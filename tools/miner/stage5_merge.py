"""Stage 5: merge Mixamo clips onto one rig, bone-parent the stage-4 timber, export GLB for Godot.
usage: blender -b --factory-startup -P stage5_merge.py
Inputs: blender/mixamo/*.fbx (first = with skin), blender/miner_v2_stage4.blend (timber objects)
Outputs: blender/miner_v2_stage5.blend, mesh/miner_rigged.glb, blender/stage5_render/*.png"""
import bpy, os, math
from mathutils import Vector, Matrix

ROOT = r"C:\Users\anjyo\Documents\MineTunnel"
MIX = os.path.join(ROOT, "blender", "mixamo")
STAGE4 = os.path.join(ROOT, "blender", os.environ.get("TIMBER_BLEND", "miner_v3_stage11.blend"))   # #45: stage 11 = TRELLIS body + head + timber (#41 was miner_v2_stage8.blend)
BODY_FROM_BLEND = os.environ.get("BODY_FROM_BLEND", "1") == "1"   # #45: Mixamo strips materials; take the textured body from STAGE4 and move the weights onto it (nearest vertex — same geometry)
OUT_BLEND = os.path.join(ROOT, "blender", "miner_v2_stage5.blend")
OUT_GLB = os.path.join(ROOT, "mesh", "miner_rigged.glb")
RENDER = os.path.join(ROOT, "blender", "stage5_render")
os.makedirs(RENDER, exist_ok=True)

CLIP_SETS = {  # file stem -> action name in Godot. #45: set B = "scarier" picks from the Scary Zombie / Creature packs (user F5 09-12: 뛰고 걷는 모션이 안 무섭다)
    "A": {"Crouch Idle": "idle_crouch", "Crouched Walking": "walk_crouch", "Zombie Crawl": "crawl", "Mutant Run": "run",
          "Mutant Swiping": "attack_swipe", "Zombie Reaction Hit": "hit", "Mutant Dying": "death", "Mutant Roaring": "roar"},
    "B": {"Crouch Idle": "idle_crouch_base", "zombie idle": "idle_crouch", "Creeping Zombie Walk": "walk_crouch", "Zombie Crawl": "crawl",
          "running crawl": "run", "zombie attack": "attack_swipe", "Zombie Reaction Hit": "hit", "Mutant Dying": "death", "zombie scream": "roar",
          "Zombie Stand Up": "prone_down",
          "zombie run": "run_stand", "Climbing Up Wall": "climb_up", "Climbing Down Wall": "climb_down",
          "Falling Idle": "fall_air", "Hard Landing": "land_hard"},   # #48 천장 크롤러: 벽타기·공중·착지 + 바닥 추격은 서서 달리기   # #47: 엎드림 -> 네 발 -> 일어섬. 고도가 뒤로 재생해서 "엎드리기"로 쓴다
}
CLIP_SET = os.environ.get("CLIP_SET", "B")
CLIPS = CLIP_SETS[CLIP_SET]
BASE_STEM = "Crouch Idle"          # the With-Skin FBX: rig + mesh come from here
TIMBER_BONE = {  # timber object -> bone it rides on
    # chest planks dropped 2026-09-11: rigid on Spine2 they float off the chest when crouched (user call)
    "Strap_Torso_0": "mixamorig:Spine1", "Strap_Torso_1": "mixamorig:Spine2", "Strap_Torso_2": "mixamorig:Spine2",
    "Plank_Forearm_L": "mixamorig:LeftForeArm", "Strap_Forearm_0": "mixamorig:LeftForeArm", "Strap_Forearm_1": "mixamorig:LeftForeArm",
    "Plank_Shin_R": "mixamorig:RightLeg", "Strap_Shin_0": "mixamorig:RightLeg", "Strap_Shin_1": "mixamorig:RightLeg",
    "Plank_Back": "mixamorig:Spine2",
    "Strap_Neck": "mixamorig:Neck",       # #41 hides the head seam
    **{f"Nail_{i}": "mixamorig:Spine2" for i in range(5)},
}

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30


def import_fbx(stem):
    before_obj = set(bpy.data.objects); before_act = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=os.path.join(MIX, stem + ".fbx"))
    new_obj = [o for o in bpy.data.objects if o not in before_obj]
    new_act = [a for a in bpy.data.actions if a not in before_act]
    return new_obj, new_act


def fcurves_of(act):
    return [fc for layer in act.layers for strip in layer.strips for cb in strip.channelbags for fc in cb.fcurves]


def hips_speed(arm_obj, act):
    """natural travel speed of a clip (m/s): Hips world position at the first vs last frame, before the root motion is removed"""
    ad = arm_obj.animation_data or arm_obj.animation_data_create()
    ad.action = act
    if hasattr(ad, "action_slot") and act.slots:
        ad.action_slot = act.slots[0]
    f0, f1 = act.frame_range
    pb = arm_obj.pose.bones["mixamorig:Hips"]
    scene.frame_set(int(f0)); p0 = (arm_obj.matrix_world @ pb.head).copy()
    scene.frame_set(int(f1)); p1 = (arm_obj.matrix_world @ pb.head).copy()
    d = p1 - p0; d.z = 0.0
    return d.length / max((f1 - f0) / scene.render.fps, 1e-6)


KEEP_Y = {"prone_down", "land_hard"}     # #48: 이 둘만 위아래 드리프트를 남긴다(일어서기·착지 — 위아래가 등속이 아니라 직선으로 못 뺀다). 나머지는 제자리로 — 벽타기·낙하·착지는 우리가 높이를 준다


def strip_root_motion(act, keep_y=False):
    """packs do not offer Mixamo's 'In Place': subtract the linear Hips drift start->end on every axis (bob stays, travel goes)"""
    n = 0
    for fc in fcurves_of(act):
        if fc.data_path.endswith('["mixamorig:Hips"].location') and not (keep_y and fc.array_index == 1) and len(fc.keyframe_points) > 1:   # #47: 본 공간 y(= 위) 드리프트는 빼지 않는다 — 일어서는 클립은 끝이 실제로 1 m 높다. 제자리 클립은 z 드리프트가 0 이라 결과가 같다
            k0, k1 = fc.keyframe_points[0], fc.keyframe_points[-1]
            slope = (k1.co.y - k0.co.y) / max(k1.co.x - k0.co.x, 1e-6)
            for k in fc.keyframe_points:
                k.co.y -= slope * (k.co.x - k0.co.x)
            fc.update(); n += 1
    return n


# ---- 1. skinned clip first: rig + mesh
objs, acts = import_fbx(BASE_STEM)
arm = next(o for o in objs if o.type == "ARMATURE"); arm.name = "Miner_Rig"
body = next(o for o in objs if o.type == "MESH"); body.name = "Miner_Body"
acts[0].name = CLIPS[BASE_STEM]; acts[0].use_fake_user = True
actions = {CLIPS[BASE_STEM]: acts[0]}
print("RIG bones", len(arm.data.bones), "body verts", len(body.data.vertices), "clip set", CLIP_SET)

# ---- 2. other clips: keep the action, drop the throwaway armature
for stem, name in CLIPS.items():
    if stem == BASE_STEM:
        continue
    objs, acts = import_fbx(stem)
    assert acts, stem
    acts[0].name = name; acts[0].use_fake_user = True
    actions[name] = acts[0]
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
if "idle_crouch_base" in actions:            # set B: the With-Skin base clip is only the rig carrier
    bpy.data.actions.remove(actions.pop("idle_crouch_base"))
speeds = {n: round(hips_speed(arm, a), 2) for n, a in actions.items()}
print("CLIP natural speed m/s (before root-motion strip):", speeds)
print("ROOT motion stripped:", {n: strip_root_motion(a, n in KEEP_Y) for n, a in actions.items()})
print("ACTIONS", {n: tuple(int(f) for f in a.frame_range) for n, a in actions.items()})


def set_action(name):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = actions[name]
    if hasattr(ad, "action_slot") and actions[name].slots:  # Blender 4.4+ slotted actions
        ad.action_slot = actions[name].slots[0]


# ---- 3. timber from stage 4, aligned to the rest pose, bone-parented
arm.data.pose_position = "REST"
bpy.context.view_layer.update()
rest_pts = [body.matrix_world @ Vector(c) for c in body.bound_box]
rest_lo = Vector([min(p[i] for p in rest_pts) for i in range(3)]); rest_hi = Vector([max(p[i] for p in rest_pts) for i in range(3)])
print("REST bbox size", tuple(round(v, 3) for v in (rest_hi - rest_lo)), "zmin", round(rest_lo.z, 3))
# stage-4 body was 2.5m tall, feet on z=0, centred on x/y. Mixamo keeps the mesh, so only a residual offset is expected.
delta = Vector(((rest_lo.x + rest_hi.x) / 2, (rest_lo.y + rest_hi.y) / 2, rest_lo.z))
print("REST offset vs stage4", tuple(round(v, 3) for v in delta))

with bpy.data.libraries.load(STAGE4, link=False) as (src, dst):
    dst.objects = [n for n in src.objects if n in TIMBER_BONE] + (["Miner_Body"] if BODY_FROM_BLEND else [])
timber = [o for o in dst.objects if o is not None and o.name.split(".")[0] != "Miner_Body"]
if BODY_FROM_BLEND:
    tex = next(o for o in dst.objects if o is not None and o.name.split(".")[0] == "Miner_Body")
    scene.collection.objects.link(tex); tex.parent = None; tex.location += delta; bpy.context.view_layer.update()
    for g in body.vertex_groups:
        tex.vertex_groups.new(name=g.name)
    bpy.ops.object.select_all(action="DESELECT"); tex.select_set(True); bpy.context.view_layer.objects.active = tex
    dt = tex.modifiers.new("xfer", "DATA_TRANSFER"); dt.object = body; dt.use_vert_data = True; dt.data_types_verts = {"VGROUP_WEIGHTS"}
    dt.vert_mapping = "NEAREST"; dt.layers_vgroup_select_src = "ALL"; dt.layers_vgroup_select_dst = "NAME"
    bpy.ops.object.modifier_apply(modifier="xfer")
    unweighted = [v.index for v in tex.data.vertices if sum(g.weight for g in v.groups) < 1e-4]
    print("BODY swap: Mixamo verts %d -> textured verts %d, unweighted %d, materials %s" % (len(body.data.vertices), len(tex.data.vertices), len(unweighted), [sl.material.name for sl in tex.material_slots if sl.material]))
    assert not unweighted, "unweighted vertices after transfer: %s" % unweighted[:10]
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    tex.parent = arm; tex.parent_type = "OBJECT"; tex.matrix_parent_inverse = arm.matrix_world.inverted(); tex.matrix_world = Matrix.Identity(4)
    tex.modifiers.new("Armature", "ARMATURE").object = arm
    bpy.data.objects.remove(body, do_unlink=True)
    body = tex; body.name = "Miner_Body"
    for m in [m for m in bpy.data.materials if m.users == 0]:   # every With-Skin FBX brought its own "살"/"살_머리" copies
        bpy.data.materials.remove(m)
    for sl in body.material_slots:
        if sl.material:
            base_name = sl.material.name.split(".")[0]
            other = bpy.data.materials.get(base_name)
            if other is not None and other is not sl.material:
                other.name = base_name + ".stale"; bpy.data.materials.remove(other)
            sl.material.name = base_name
for o in timber:
    scene.collection.objects.link(o)
    o.parent = None
    o.location += delta
    for m in list(o.modifiers):
        if m.type == "SHRINKWRAP":
            m.target = body
bpy.context.view_layer.update()
# bake straps onto the rest-pose body, then hand every piece to its bone
for o in timber:
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    bone = TIMBER_BONE[o.name]
    pb = arm.pose.bones[bone]
    o.parent = arm; o.parent_type = "BONE"; o.parent_bone = bone
    # bone-parent space sits at the bone TAIL: undo it so the piece stays where it is
    o.matrix_parent_inverse = (arm.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.length, 0))).inverted()
# drop anything the append dragged along (old body, HI copy, gauges)
for o in list(bpy.data.objects):
    if o not in timber and o not in (arm, body):
        bpy.data.objects.remove(o, do_unlink=True)
arm.data.pose_position = "POSE"
print("TIMBER parented", len(timber))

# ---- 4. renders: two clips mid-motion, to confirm the timber rides the bones
scene.render.engine = "BLENDER_EEVEE"; scene.render.resolution_x = scene.render.resolution_y = 1024
world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.12, 0.12, 1)
cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"; cam_data.ortho_scale = 4.0
cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun); sun.data.energy = 3
views = {"front": ((0, -8, 0), (math.pi / 2, 0, 0)), "left": ((8, 0, 0), (math.pi / 2, 0, math.pi / 2)),
         "iso": ((-5.6, -5.6, 2.5), (math.radians(72), 0, math.radians(-45)))}
for clip, frame in (("walk_crouch", 16), ("attack_swipe", 40), ("crawl", 60)):
    set_action(clip); scene.frame_set(frame)
    for vname, (off, rot) in views.items():
        cam.location = Vector((0, 0, 1.2)) + Vector(off); cam.rotation_euler = rot; sun.rotation_euler = rot
        scene.render.filepath = os.path.join(RENDER, f"{clip}_f{frame}_{vname}.png")
        bpy.ops.render.render(write_still=True)
    print("rendered", clip, frame)

# ---- 5. NLA: one track per clip (glTF exports each track as an animation)
set_action("idle_crouch")
ad = arm.animation_data
for name, act in actions.items():
    tr = ad.nla_tracks.new(); tr.name = name
    st = tr.strips.new(name, int(act.frame_range[0]), act)
    if hasattr(st, "action_slot") and act.slots:
        st.action_slot = act.slots[0]
ad.action = None
for o in (cam, sun):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
print("saved", OUT_BLEND)

# ---- 6. export for Godot
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True,
                          export_animations=True, export_animation_mode="NLA_TRACKS",
                          export_apply=True, export_yup=True, export_skins=True)
print("exported", OUT_GLB, round(os.path.getsize(OUT_GLB) / 1e6, 2), "MB")

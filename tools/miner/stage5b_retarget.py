"""Stage 5b (proposals #41/#42): put the stage-9 body (old body + separate head + separate hands) on the EXISTING Mixamo rig — no re-rig.
usage: blender -b --factory-startup -P blender/stage5b_retarget.py
Why it works: Mixamo kept the stage-4 mesh untouched (23734 verts, rest bbox error 0), and stage 8 only replaced the
vertices above the neck cut. So the old skinned body is a valid weight source for everything below the cut (nearest
vertex), and the head is simply the Head bone (Neck blend at the seam).
Inputs : blender/miner_v2_stage5.blend (rig + old skinned body + timber, 8 clips), blender/miner_v2_stage8.blend (new body, Strap_Neck)
Outputs: blender/miner_v2_stage5.blend (overwritten — backup miner_v2_stage5_prehead.blend), blender/stage5b_render/*.png"""
import bpy, os, math
from mathutils import Vector, Matrix

ROOT = r"C:\Users\anjyo\Documents\MineTunnel"
STAGE5 = os.path.join(ROOT, "blender", "miner_v2_stage5.blend")
STAGE8 = os.path.join(ROOT, "blender", os.environ.get("NEW_BLEND", "miner_v2_stage9.blend"))   # #42: stage 9 = stage 8 + separate hands
BACKUP = os.environ.get("BACKUP", "miner_v2_stage5_prehand.blend")                                 # the stage-5 file is overwritten: keep the previous one
RENDER = os.path.join(ROOT, "blender", "stage5b_render")
os.makedirs(RENDER, exist_ok=True)
NECK_Z = 2.04          # stage-8 cut height (log: "BODY neck z 2.040")
HEAD_ONLY_Z = 2.12     # above this every vertex is 100 % Head bone; between NECK_Z and this the transferred Neck/Head blend stays
HEAD_BONE, NECK_BONE = "mixamorig:Head", "mixamorig:Neck"
HAND_ONLY_X = 1.156    # #42: beyond this |x| every vertex is 100 % the Hand bone (Hand bone head is at 1.136; the wrist cut is ~1.02) — iron claws are rigid
HAND_BONES = {1: "mixamorig:LeftHand", -1: "mixamorig:RightHand"}
STRAPS = {"Strap_Neck": NECK_BONE, "Strap_Wrist_L": HAND_BONES[1], "Strap_Wrist_R": HAND_BONES[-1]}

import shutil
shutil.copy(STAGE5, os.path.join(ROOT, "blender", BACKUP)); print("backup", BACKUP)
bpy.ops.wm.open_mainfile(filepath=STAGE5)
scene = bpy.context.scene
arm = bpy.data.objects["Miner_Rig"]; old = bpy.data.objects["Miner_Body"]
arm.data.pose_position = "REST"; bpy.context.view_layer.update()

# ---- 1. new body + neck strap from stage 8
with bpy.data.libraries.load(STAGE8, link=False) as (src, dst):
    dst.objects = ["Miner_Body"] + list(STRAPS)
new, *straps = dst.objects
new.name = "Miner_Body_new"
for old_strap in [o for o in bpy.data.objects if o.name.split(".")[0] in STRAPS and o not in straps]:   # the previous run's straps
    bpy.data.objects.remove(old_strap, do_unlink=True)
for o in [new] + straps:
    scene.collection.objects.link(o); o.parent = None
    o.matrix_world = Matrix.Identity(4) if o is new else o.matrix_world
for o in straps:                     # appended straps arrive as "Strap_X.001" with a copied "가죽끈.00N": use the file's own names/material (stage 6 looks them up by name)
    o.name = o.name.split(".")[0]
    for slot in o.material_slots:
        dup = slot.material
        if dup is not None and dup.name != "가죽끈":
            slot.material = bpy.data.materials["가죽끈"]
            if dup.users == 0:
                bpy.data.materials.remove(dup)
bpy.context.view_layer.update()
print("old verts", len(old.data.vertices), "new verts", len(new.data.vertices), "new faces", len(new.data.polygons), "uv", [u.name for u in new.data.uv_layers])

# ---- 2. weights: nearest-vertex transfer from the old skinned body, then the head override
for g in old.vertex_groups:
    new.vertex_groups.new(name=g.name)
bpy.ops.object.select_all(action="DESELECT"); new.select_set(True); bpy.context.view_layer.objects.active = new
dt = new.modifiers.new("xfer", "DATA_TRANSFER")
dt.object = old; dt.use_vert_data = True; dt.data_types_verts = {"VGROUP_WEIGHTS"}
dt.vert_mapping = "NEAREST"; dt.layers_vgroup_select_src = "ALL"; dt.layers_vgroup_select_dst = "NAME"
bpy.ops.object.modifier_apply(modifier="xfer")
head_g = new.vertex_groups[HEAD_BONE]; neck_g = new.vertex_groups[NECK_BONE]
hand_g = {sgn: new.vertex_groups[HAND_BONES[sgn]] for sgn in (1, -1)}
n_head = 0; n_hand = 0
for v in new.data.vertices:
    only = head_g if v.co.z >= HEAD_ONLY_Z else hand_g[1] if v.co.x >= HAND_ONLY_X else hand_g[-1] if v.co.x <= -HAND_ONLY_X else None
    if only is not None:
        for g in new.vertex_groups:
            g.remove([v.index])
        only.add([v.index], 1.0, "REPLACE")
        if only is head_g:
            n_head += 1
        else:
            n_hand += 1
# sanity: every vertex has weight
unweighted = [v.index for v in new.data.vertices if sum(g.weight for g in v.groups) < 1e-4]
print("transfer done: head-only verts %d, hand-only verts %d, unweighted %d" % (n_head, n_hand, len(unweighted)))
assert not unweighted, "unweighted vertices: %s" % unweighted[:10]
bpy.ops.object.vertex_group_normalize_all(lock_active=False)

# ---- 3. swap bodies: same parenting as Mixamo left it (child of the rig, world identity), armature modifier
new.parent = arm; new.parent_type = "OBJECT"; new.matrix_parent_inverse = arm.matrix_world.inverted()
new.matrix_world = Matrix.Identity(4)
mod = new.modifiers.new("Armature", "ARMATURE"); mod.object = arm
bpy.data.objects.remove(old, do_unlink=True)
new.name = "Miner_Body"
body = new
# the appended body brought its own "살" (renamed "살.001" on collision); keep ONE material named "살" — stage 6/7 look it up by name
for slot in body.material_slots:
    if slot.material and slot.material.name.startswith("살") and slot.material.name != "살":
        stale = bpy.data.materials.get("살")
        if stale:
            bpy.data.materials.remove(stale)
        slot.material.name = "살"
print("skin material:", [sl.material.name for sl in body.material_slots])

# ---- 4. straps (neck, wrists): shrinkwrap onto the new body in rest pose, then bone-parent (stage 5 recipe)
for strap in straps:
    bone = STRAPS[strap.name.split(".")[0]]
    for m in list(strap.modifiers):
        if m.type == "SHRINKWRAP":
            m.target = body
    bpy.ops.object.select_all(action="DESELECT"); strap.select_set(True); bpy.context.view_layer.objects.active = strap
    for m in list(strap.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    pb = arm.pose.bones[bone]
    strap.parent = arm; strap.parent_type = "BONE"; strap.parent_bone = bone
    strap.matrix_parent_inverse = (arm.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.length, 0))).inverted()
    print("strap", strap.name, "parented to", bone)

# ---- 5. renders: walk_crouch f16 + roar mid — does the head ride the neck?
arm.data.pose_position = "POSE"
actions = {a.name: a for a in bpy.data.actions}
for tr in arm.animation_data.nla_tracks:
    tr.mute = True
ad = arm.animation_data


def set_action(name):
    ad.action = actions[name]
    if hasattr(ad, "action_slot") and actions[name].slots:
        ad.action_slot = actions[name].slots[0]


scene.render.engine = "BLENDER_EEVEE"; scene.render.resolution_x = scene.render.resolution_y = 1024
world = scene.world or bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.12, 0.12, 1)
cam_data = bpy.data.cameras.new("cam"); cam_data.type = "ORTHO"; cam_data.ortho_scale = 4.0
cam = bpy.data.objects.new("cam", cam_data); scene.collection.objects.link(cam); scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scene.collection.objects.link(sun); sun.data.energy = 3
views = {"front": ((0, -8, 0), (math.pi / 2, 0, 0)), "left": ((8, 0, 0), (math.pi / 2, 0, math.pi / 2)), "top": ((0, 0, 8), (0, 0, 0))}
for clip, frame in (("walk_crouch", 16), ("roar", 80), ("attack_swipe", 40)):
    set_action(clip); scene.frame_set(frame)
    for vname, (off, rot) in views.items():
        cam.location = Vector((0, 0, 1.2)) + Vector(off); cam.rotation_euler = rot; sun.rotation_euler = rot
        scene.render.filepath = os.path.join(RENDER, f"{clip}_f{frame}_{vname}.png")
        bpy.ops.render.render(write_still=True)
print("rendered walk_crouch/roar/attack_swipe")
for o in (cam, sun):
    bpy.data.objects.remove(o, do_unlink=True)
for tr in arm.animation_data.nla_tracks:
    tr.mute = False
ad.action = None
bpy.ops.wm.save_as_mainfile(filepath=STAGE5)
print("saved", STAGE5, "body faces", len(body.data.polygons), "timber", len([o for o in bpy.data.objects if o.type == "MESH"]) - 1)

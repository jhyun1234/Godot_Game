"""Motion review sheet: every candidate clip on the NEW rig, N frames across the clip, one strip per clip + one contact sheet.
usage: blender -b --factory-startup -P blender/review_clips.py -- <out_dir> <base_with_skin.fbx> <clip1.fbx> [clip2.fbx ...]
The base FBX (With Skin) gives the rig + mesh; every other FBX gives only its action (its throwaway rig is deleted).
Root motion is removed (Hips location linear drift subtracted) so the strip stays in frame. Frames are rendered from the
front-left, orthographic, same camera for every clip. Names: <out_dir>/<stem>.png, <out_dir>/sheet.png (PIL, if available)."""
import bpy, sys, os, math
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
out_dir, base = args[0], args[1]; clips = args[2:]
os.makedirs(out_dir, exist_ok=True)
N = 8                      # frames per strip
TILE = 300                 # px per frame
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene; scene.render.fps = 30


def import_fbx(path):
    before_obj = set(bpy.data.objects); before_act = set(bpy.data.actions)
    bpy.ops.import_scene.fbx(filepath=path)
    return [o for o in bpy.data.objects if o not in before_obj], [a for a in bpy.data.actions if a not in before_act]


def fcurves_of(act, slot_handle=None):
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                if slot_handle is None or cb.slot_handle == slot_handle:
                    out.extend(cb.fcurves)
    return out


def strip_root_motion(act):
    """Hips location: subtract the linear drift start->end on every axis (keeps the bob, kills the travel)"""
    for fc in fcurves_of(act):
        if fc.data_path.endswith('["mixamorig:Hips"].location') and len(fc.keyframe_points) > 1:
            k0, k1 = fc.keyframe_points[0], fc.keyframe_points[-1]
            slope = (k1.co.y - k0.co.y) / max(k1.co.x - k0.co.x, 1e-6)
            for k in fc.keyframe_points:
                k.co.y -= slope * (k.co.x - k0.co.x)
            fc.update()


objs, acts = import_fbx(base)
arm = next(o for o in objs if o.type == "ARMATURE"); body = next(o for o in objs if o.type == "MESH")
for a in acts:
    a.use_fake_user = True
base_act = acts[0]
print("BASE", os.path.basename(base), "bones", len(arm.data.bones), "verts", len(body.data.vertices))
actions = {os.path.splitext(os.path.basename(base))[0]: base_act}
for c in clips:
    o2, a2 = import_fbx(c)
    if a2:
        a2[0].use_fake_user = True; actions[os.path.splitext(os.path.basename(c))[0]] = a2[0]
    for o in o2:
        bpy.data.objects.remove(o, do_unlink=True)
print("CLIPS", {k: int(a.frame_range[1] - a.frame_range[0]) for k, a in actions.items()})

# flat grey material, front-left ortho camera framing the whole 2.5 m figure in every pose
m = bpy.data.materials.new("grey"); m.use_nodes = True
body.data.materials.clear(); body.data.materials.append(m)
scene.render.engine = "BLENDER_EEVEE"; scene.render.resolution_x = scene.render.resolution_y = TILE
w = bpy.data.worlds.new("w"); scene.world = w; w.use_nodes = True; w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.25, 0.25, 0.25, 1)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = 3.6
cam.location = (-5.5, -5.5, 1.3); cam.rotation_euler = (math.radians(84), 0, math.radians(-45))
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sun.data.energy = 3; scene.collection.objects.link(sun)
sun.rotation_euler = (math.radians(60), 0, math.radians(-30))
ad = arm.animation_data
frames_dir = os.path.join(out_dir, "frames"); os.makedirs(frames_dir, exist_ok=True)
strips = {}
for name, act in actions.items():
    strip_root_motion(act)
    ad.action = act
    if hasattr(ad, "action_slot") and act.slots:
        ad.action_slot = act.slots[0]
    f0, f1 = act.frame_range
    files = []
    for i in range(N):
        f = int(f0 + (f1 - f0) * i / (N - 1))
        scene.frame_set(f)
        p = os.path.join(frames_dir, "%s_%02d.png" % (name.replace(" ", "_"), i)); scene.render.filepath = p
        bpy.ops.render.render(write_still=True); files.append(p)
    strips[name] = (files, int(f1 - f0))
    print("STRIP", name, int(f1 - f0), "frames")
try:
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 16)
    names = list(strips)
    sheet = Image.new("RGB", (TILE * N + 230, (TILE + 6) * len(names)), (25, 25, 25)); dr = ImageDraw.Draw(sheet)
    for r, name in enumerate(names):
        files, length = strips[name]
        dr.multiline_text((8, r * (TILE + 6) + 8), "%s\n%d 프레임 (%.1f s)" % (name, length, length / 30.0), fill=(235, 235, 235), font=font)
        for i, p in enumerate(files):
            sheet.paste(Image.open(p).convert("RGB"), (230 + i * TILE, r * (TILE + 6)))
    sheet.save(os.path.join(out_dir, "sheet.png")); print("SHEET", os.path.join(out_dir, "sheet.png"), sheet.size)
except Exception as e:
    print("no sheet (PIL?)", e)

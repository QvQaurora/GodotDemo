"""Full rebuild of level-1 forest map using Kenney GLBs from D:\\Kenney."""
import bpy
import bmesh
import math
import random
import os
import json
from mathutils import Vector, Matrix, noise, Euler

NAT = r"D:\Kenney\github\3D assets\Nature Kit\Models\GLTF format"
SUB = r"D:\Kenney\github\3D assets\City Kit - Suburban\Models\GLB format"
GY = r"D:\Kenney\github\3D assets\Graveyard Kit\Models\GLB format"
OUT_DIR = r"d:\godotdemo\assets\blender_forest"
BLEND_SRC = r"d:\godotdemo_blender_src\forest_world.blend"
GLB_OUT = os.path.join(OUT_DIR, "forest_world.glb")

SIZE = 1000.0
HALF = SIZE * 0.5
RES = 160
SEED = 20261104
rng = random.Random(SEED)

TREE_FILES = [
    "tree_pineTallA.glb", "tree_pineTallB.glb", "tree_pineTallC.glb",
    "tree_pineRoundA.glb", "tree_pineRoundC.glb", "tree_pineRoundE.glb",
    "tree_oak.glb", "tree_oak_dark.glb", "tree_detailed.glb", "tree_fat.glb",
    "tree_cone.glb", "tree_default.glb", "tree_tall.glb", "tree_pineDefaultA.glb",
]
ROCK_FILES = [
    "rock_largeA.glb", "rock_largeC.glb", "rock_largeE.glb",
    "rock_tallA.glb", "rock_tallE.glb", "rock_tallI.glb",
    "rock_smallA.glb", "rock_smallFlatA.glb", "rock_smallG.glb",
]
BUSH_FILES = ["plant_bushLarge.glb", "plant_bush.glb", "plant_bushDetailed.glb", "plant_bushTriangle.glb"]
PATH_FILES = [
    "ground_pathStraight.glb", "ground_pathCorner.glb", "ground_pathCross.glb",
    "ground_pathBend.glb", "path_stone.glb", "path_stoneCircle.glb",
]
HOUSE_FILES = [f"building-type-{c}.glb" for c in "abcdefghijklmnop"]
GRAVE_FILES = [
    "altar-stone.glb", "crypt-large.glb", "crypt.glb", "pillar-obelisk.glb",
    "gravestone-cross-large.glb", "gravestone-decorative.glb", "gravestone-round.glb",
    "gravestone-broken.glb", "grave.glb", "iron-fence.glb", "iron-fence-border-gate.glb",
    "column-large.glb", "cross-column.glb",
]
EXTRA_FILES = [
    "bridge_wood.glb", "bridge_center_wood.glb", "bridge_side_wood.glb",
    "cliff_large_rock.glb", "cliff_cave_rock.glb", "log_large.glb", "stump_round.glb",
    "fence_simple.glb", "tent_detailedOpen.glb", "tent_smallOpen.glb",
    "campfire_stones.glb", "grass_large.glb",
]

PEAKS = [
    (80, 360, 55, 130),
    (-160, 390, 70, 150),
    (-360, 180, 48, 110),
    (340, 200, 42, 100),
    (-280, -300, 38, 95),
    (300, -280, 45, 105),
]
PONDS = [(210, -40, 26), (265, -70, 16), (-70, -200, 20)]
RIVER_Y = -90.0
RIVER_HALF_W = 14.0


def log(msg):
    print(msg, flush=True)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.armatures, bpy.data.actions):
        for b in list(block):
            if b.users == 0:
                block.remove(b)
    # collections except Scene Collection
    for col in list(bpy.data.collections):
        bpy.data.collections.remove(col)
    log("CLEARED")


def ensure_collection(name):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col


def mat(name, color, roughness=0.85, alpha=1.0, emission=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND"
    if emission is not None:
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = (*emission[0], 1.0)
            bsdf.inputs["Emission Strength"].default_value = emission[1]
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    m.diffuse_color = (*color, alpha)
    return m


def height_at(x, y):
    nx, ny = x / HALF, y / HALF
    r = math.sqrt(nx * nx + ny * ny)
    rim = max(0.0, r - 0.52) ** 2 * 60.0
    n1 = noise.noise(Vector((x * 0.0032, y * 0.0032, 0.15))) * 8.5
    n2 = noise.noise(Vector((x * 0.0075, y * 0.0075, 1.4))) * 3.0
    n3 = noise.noise(Vector((x * 0.018, y * 0.018, 2.8))) * 0.85
    h = 2.0 + n1 + n2 + n3 + rim
    for px, py, ph, pr in PEAKS:
        d = math.hypot(x - px, y - py)
        if d < pr:
            t = 1.0 - d / pr
            h += ph * (t * t * (3 - 2 * t))
    # village flatten
    d0 = math.hypot(x, y)
    if d0 < 85:
        t = 1.0 - d0 / 85
        h = h * (1 - t * 0.9) + 1.4 * t
    # river trench
    dy = abs(y - RIVER_Y)
    if dy < RIVER_HALF_W * 2.2 and abs(x) < 380:
        t = 1.0 - dy / (RIVER_HALF_W * 2.2)
        h -= 5.5 * t * t
    for px, py, pr in PONDS:
        d = math.hypot(x - px, y - py)
        if d < pr * 1.4:
            t = 1.0 - d / (pr * 1.4)
            h -= 4.8 * t * t
    return h


def build_terrain():
    mesh = bpy.data.meshes.new("Terrain")
    obj = bpy.data.objects.new("Terrain", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    verts = [[None] * RES for _ in range(RES)]
    for iz in range(RES):
        for ix in range(RES):
            u = ix / (RES - 1)
            v = iz / (RES - 1)
            x = -HALF + u * SIZE
            y = -HALF + v * SIZE
            verts[iz][ix] = bm.verts.new((x, y, height_at(x, y)))
    bm.verts.ensure_lookup_table()
    for iz in range(RES - 1):
        for ix in range(RES - 1):
            bm.faces.new((verts[iz][ix], verts[iz][ix + 1], verts[iz + 1][ix + 1], verts[iz + 1][ix]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    obj.data.materials.append(mat("M_Grass", (0.23, 0.40, 0.17), 0.92))
    zs = [v.co.z for v in mesh.vertices]
    log(f"TERRAIN faces={len(mesh.polygons)} z=[{min(zs):.1f},{max(zs):.1f}]")
    return obj


def import_glb(path, name):
    before = set(bpy.data.objects.keys())
    bpy.ops.import_scene.gltf(filepath=path)
    new_objs = [bpy.data.objects[k] for k in bpy.data.objects.keys() if k not in before]
    if not new_objs:
        log(f"IMPORT_EMPTY {path}")
        return None
    # GLTF often creates Empty parents outside the view layer; only keep meshes.
    meshes = [o for o in new_objs if o.type == "MESH"]
    empties = [o for o in new_objs if o.type != "MESH"]
    if not meshes:
        for o in new_objs:
            bpy.data.objects.remove(o, do_unlink=True)
        log(f"IMPORT_NO_MESH {path}")
        return None
    # Apply parent transforms into mesh, then clear parents
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in empties:
        bpy.data.objects.remove(o, do_unlink=True)
    # Ensure linked to scene collection for selection
    scene_col = bpy.context.scene.collection
    for o in meshes:
        if scene_col not in o.users_collection:
            scene_col.objects.link(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    root = bpy.context.view_layer.objects.active
    root.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    lib = ensure_collection("Library")
    for col in list(root.users_collection):
        col.objects.unlink(root)
    lib.objects.link(root)
    root.hide_viewport = True
    root.hide_render = True
    return root


def world_size(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    xs = [c.x for c in corners]
    ys = [c.y for c in corners]
    zs = [c.z for c in corners]
    return max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)


def load_library():
    lib_objs = {}
    groups = [
        (NAT, TREE_FILES, "Tree"),
        (NAT, ROCK_FILES, "Rock"),
        (NAT, BUSH_FILES, "Bush"),
        (NAT, PATH_FILES, "Path"),
        (NAT, EXTRA_FILES, "Extra"),
        (SUB, HOUSE_FILES, "House"),
        (GY, GRAVE_FILES, "Grave"),
    ]
    for folder, files, prefix in groups:
        for i, fn in enumerate(files):
            path = os.path.join(folder, fn)
            if not os.path.exists(path):
                log(f"MISS {path}")
                continue
            key = f"{prefix}_{os.path.splitext(fn)[0]}"
            obj = import_glb(path, key)
            if obj:
                lib_objs[key] = obj
                sx, sy, sz = world_size(obj)
                log(f"LIB {key} size=({sx:.2f},{sy:.2f},{sz:.2f})")
    return lib_objs


def instance_at(template, name, loc, scale=1.0, yaw=0.0, col=None):
    obj = template.copy()
    # Share prototype mesh; make_single_user runs before join
    obj.data = template.data
    obj.name = name
    obj.hide_viewport = False
    obj.hide_render = False
    obj.hide_set(False)
    obj.location = Vector(loc)
    obj.rotation_euler = Euler((0.0, 0.0, yaw))
    obj.scale = (scale, scale, scale)
    target = col or bpy.context.scene.collection
    # Copies inherit collection membership from template; clear then link once
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    target.objects.link(obj)
    return obj


def near_any(x, y, points, dist):
    d2 = dist * dist
    for px, py in points:
        if (x - px) ** 2 + (y - py) ** 2 < d2:
            return True
    return False


def place_path_tiles(lib, samples, col, scale=10.0):
    """Place path tiles along polyline samples [(x,y),...]."""
    keys = [k for k in lib if k.startswith("Path_ground_pathStraight")]
    if not keys:
        keys = [k for k in lib if k.startswith("Path_")]
    if not keys:
        return []
    tpl = lib[keys[0]]
    placed = []
    # step based on tile size * scale
    sx, sy, _ = world_size(tpl)
    step = max(sx, sy) * scale * 0.92
    if step < 1:
        step = 8.0
    acc = 0.0
    for i in range(len(samples) - 1):
        a = Vector((samples[i][0], samples[i][1], 0))
        b = Vector((samples[i + 1][0], samples[i + 1][1], 0))
        seg = b - a
        length = seg.length
        if length < 0.01:
            continue
        direction = seg.normalized()
        yaw = math.atan2(direction.y, direction.x)
        t = 0.0
        while t < length:
            p = a + direction * t
            z = height_at(p.x, p.y) + 0.05
            # sink slightly into terrain
            o = instance_at(tpl, f"RoadTile_{len(placed)}", (p.x, p.y, z), scale=scale, yaw=yaw, col=col)
            placed.append(o)
            t += step
    return placed


def make_roads():
    roads = []
    # EW through village then to bridge
    ew = []
    for t in range(0, 45):
        x = -420 + t * 20
        y = 18 * math.sin(x / 120.0)
        ew.append((x, y))
    roads.append(ew)
    # NS to graveyard
    ns = []
    for t in range(0, 42):
        y = -380 + t * 20
        x = 16 * math.sin(y / 100.0)
        ns.append((x, y))
    roads.append(ns)
    # to SE ponds / camp
    se = []
    for t in range(0, 30):
        u = t / 29
        se.append((40 + u * 250, -30 - u * 40 + 12 * math.sin(u * 5)))
    roads.append(se)
    # to west cliffs
    west = []
    for t in range(0, 26):
        u = t / 25
        west.append((-40 - u * 280, 10 + u * 30 + 10 * math.cos(u * 4)))
    roads.append(west)
    # village ring
    ring = []
    for i in range(28):
        ang = i / 28 * math.tau
        ring.append((math.cos(ang) * 48, math.sin(ang) * 48))
    ring.append(ring[0])
    roads.append(ring)
    return roads


def place_village(lib, col):
    houses = [lib[k] for k in lib if k.startswith("House_")]
    fence = lib.get("Extra_fence_simple")
    circle = lib.get("Path_path_stoneCircle") or lib.get("Path_path_stone")
    objs = []
    # plaza marker
    if circle:
        z = height_at(0, 0) + 0.08
        objs.append(instance_at(circle, "PlazaCircle", (0, 0, z), scale=14.0, col=col))
    # houses in oval
    for i, h in enumerate(houses[:12]):
        ang = i / 12 * math.tau + 0.2
        r = 58 + (i % 3) * 6
        x, y = math.cos(ang) * r, math.sin(ang) * r
        z = height_at(x, y)
        yaw = ang + math.pi
        # suburban houses ~ few meters; scale up for world
        objs.append(instance_at(h, f"House_{i}", (x, y, z), scale=8.0, yaw=yaw, col=col))
        if fence:
            fx, fy = math.cos(ang) * (r - 10), math.sin(ang) * (r - 10)
            objs.append(instance_at(fence, f"Fence_{i}", (fx, fy, height_at(fx, fy)), scale=6.0, yaw=ang + math.pi / 2, col=col))
    return objs


def place_graveyard(lib, col):
    objs = []
    cx, cy = -40, 330
    pieces = [
        ("Grave_crypt-large", 0, 8, 10.0, 0),
        ("Grave_altar-stone", 0, -6, 8.0, 0),
        ("Grave_pillar-obelisk", -14, 0, 9.0, 0.2),
        ("Grave_pillar-obelisk", 14, 0, 9.0, -0.2),
        ("Grave_cross-column", -8, -14, 7.0, 0),
        ("Grave_column-large", 8, -14, 7.0, 0),
    ]
    for key, dx, dy, sc, yaw in pieces:
        tpl = lib.get(key)
        if not tpl:
            continue
        x, y = cx + dx, cy + dy
        objs.append(instance_at(tpl, f"GY_{key}", (x, y, height_at(x, y)), scale=sc, yaw=yaw, col=col))
    graves = [k for k in lib if "gravestone" in k or k.endswith("Grave_grave")]
    for i in range(18):
        ang = i / 18 * math.tau
        x = cx + math.cos(ang) * 22
        y = cy + math.sin(ang) * 22
        key = graves[i % len(graves)] if graves else None
        if key:
            objs.append(instance_at(lib[key], f"Gravestone_{i}", (x, y, height_at(x, y)), scale=7.0, yaw=ang, col=col))
    fence = lib.get("Grave_iron-fence")
    if fence:
        for i in range(20):
            ang = i / 20 * math.tau
            x = cx + math.cos(ang) * 32
            y = cy + math.sin(ang) * 32
            objs.append(instance_at(fence, f"IronFence_{i}", (x, y, height_at(x, y)), scale=7.0, yaw=ang + math.pi / 2, col=col))
    gate = lib.get("Grave_iron-fence-border-gate")
    if gate:
        objs.append(instance_at(gate, "GraveGate", (cx, cy - 34, height_at(cx, cy - 34)), scale=8.0, yaw=0, col=col))
    return objs


def place_landmarks(lib, col):
    objs = []
    # bridge over river
    bx, by = 120.0, RIVER_Y
    for key, dx, sc in [
        ("Extra_bridge_wood", 0, 12.0),
        ("Extra_bridge_center_wood", 0, 12.0),
        ("Extra_bridge_side_wood", -8, 10.0),
        ("Extra_bridge_side_wood", 8, 10.0),
    ]:
        tpl = lib.get(key)
        if tpl:
            objs.append(instance_at(tpl, f"Bridge_{key}", (bx + dx, by, height_at(bx, by) + 1.2), scale=sc, yaw=0.0, col=col))
    # west cliffs
    for i, (x, y) in enumerate([(-340, 20), (-355, 50), (-320, -10), (-370, 80)]):
        key = "Extra_cliff_large_rock" if i % 2 == 0 else "Extra_cliff_cave_rock"
        tpl = lib.get(key)
        if tpl:
            objs.append(instance_at(tpl, f"Cliff_{i}", (x, y, height_at(x, y)), scale=14.0, yaw=rng.uniform(0, 6), col=col))
    # camp SE
    for i, (x, y) in enumerate([(230, -160), (245, -150), (220, -145)]):
        tent = lib.get("Extra_tent_detailedOpen") or lib.get("Extra_tent_smallOpen")
        if tent:
            objs.append(instance_at(tent, f"Tent_{i}", (x, y, height_at(x, y)), scale=8.0, yaw=rng.uniform(0, 6), col=col))
    fire = lib.get("Extra_campfire_stones")
    if fire:
        objs.append(instance_at(fire, "Campfire", (235, -152, height_at(235, -152)), scale=6.0, col=col))
    return objs


def place_water(col):
    m_water = mat("M_Water", (0.10, 0.28, 0.36), 0.08, alpha=0.75)
    objs = []
    # river strip
    bm = bmesh.new()
    segs = 40
    for i in range(segs):
        x0 = -380 + i * (760 / (segs - 1))
        x1 = -380 + (i + 1) * (760 / (segs - 1)) if i < segs - 1 else x0
        y0 = RIVER_Y - RIVER_HALF_W
        y1 = RIVER_Y + RIVER_HALF_W
        z = height_at(x0, RIVER_Y) + 0.55
        v0 = bm.verts.new((x0, y0, z))
        v1 = bm.verts.new((x1 if i < segs - 1 else x0 + 1, y0, z))
        v2 = bm.verts.new((x1 if i < segs - 1 else x0 + 1, y1, z))
        v3 = bm.verts.new((x0, y1, z))
        if i < segs - 1:
            try:
                bm.faces.new((v0, v1, v2, v3))
            except ValueError:
                pass
    # simpler single river plane
    bm.free()
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=24, y_segments=3, size=1.0)
    for v in bm.verts:
        v.co.x = v.co.x * 760
        v.co.y = v.co.y * (RIVER_HALF_W * 2)
        v.co.y += RIVER_Y
        v.co.z = height_at(v.co.x, RIVER_Y) + 0.5
    mesh = bpy.data.meshes.new("RiverWater")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("RiverWater", mesh)
    col.objects.link(obj)
    obj.data.materials.append(m_water)
    objs.append(obj)
    for i, (px, py, pr) in enumerate(PONDS):
        bm = bmesh.new()
        bmesh.ops.create_circle(bm, cap_ends=True, segments=24, radius=pr)
        z = height_at(px, py) + 0.45
        for v in bm.verts:
            v.co += Vector((px, py, z))
        mesh = bpy.data.meshes.new(f"PondWater_{i}")
        bm.to_mesh(mesh)
        bm.free()
        o = bpy.data.objects.new(f"PondWater_{i}", mesh)
        col.objects.link(o)
        o.data.materials.append(m_water)
        objs.append(o)
    return objs


def scatter_nature(lib, avoid_pts, col):
    trees = [lib[k] for k in lib if k.startswith("Tree_")]
    rocks = [lib[k] for k in lib if k.startswith("Rock_")]
    bushes = [lib[k] for k in lib if k.startswith("Bush_")]
    objs = []
    # trees
    n_trees = 0
    attempts = 0
    tree_pos = []
    while n_trees < 1400 and attempts < 90000:
        attempts += 1
        x = rng.uniform(-460, 460)
        y = rng.uniform(-460, 460)
        d0 = math.hypot(x, y)
        if d0 < 70:
            continue
        if near_any(x, y, avoid_pts, 14):
            continue
        # keep clear of river
        if abs(y - RIVER_Y) < 18 and abs(x) < 380:
            continue
        if near_any(x, y, tree_pos, 7.5):
            continue
        dens = 0.4 + min(1.0, d0 / 320.0)
        if rng.random() > dens:
            continue
        z = height_at(x, y)
        if z > 68 and rng.random() < 0.55:
            continue
        tpl = trees[rng.randrange(len(trees))]
        sc = rng.uniform(7.5, 12.5)
        objs.append(instance_at(tpl, f"Tree_{n_trees}", (x, y, z), scale=sc, yaw=rng.uniform(0, 6.28), col=col))
        tree_pos.append((x, y))
        n_trees += 1
    log(f"TREES {n_trees}")
    # rocks
    for i in range(220):
        x = rng.uniform(-440, 440)
        y = rng.uniform(-440, 440)
        if math.hypot(x, y) < 55 or near_any(x, y, avoid_pts, 10):
            continue
        if abs(y - RIVER_Y) < 16 and abs(x) < 380:
            continue
        tpl = rocks[rng.randrange(len(rocks))]
        sc = rng.uniform(5.0, 11.0)
        objs.append(instance_at(tpl, f"Rock_{i}", (x, y, height_at(x, y)), scale=sc, yaw=rng.uniform(0, 6), col=col))
    # bushes
    for i in range(380):
        x = rng.uniform(-430, 430)
        y = rng.uniform(-430, 430)
        if math.hypot(x, y) < 45:
            continue
        if near_any(x, y, avoid_pts, 8) and rng.random() < 0.4:
            pass
        elif near_any(x, y, avoid_pts, 8):
            continue
        tpl = bushes[rng.randrange(len(bushes))]
        sc = rng.uniform(4.5, 8.5)
        objs.append(instance_at(tpl, f"Bush_{i}", (x, y, height_at(x, y)), scale=sc, yaw=rng.uniform(0, 6), col=col))
    # stumps / logs accents
    stump = lib.get("Extra_stump_round")
    logm = lib.get("Extra_log_large")
    for i in range(40):
        x = rng.uniform(-400, 400)
        y = rng.uniform(-400, 400)
        if math.hypot(x, y) < 80 or near_any(x, y, avoid_pts, 12):
            continue
        tpl = stump if rng.random() < 0.55 else logm
        if tpl:
            objs.append(instance_at(tpl, f"Debris_{i}", (x, y, height_at(x, y)), scale=rng.uniform(5, 9), yaw=rng.uniform(0, 6), col=col))
    return objs, tree_pos


def join_objects(objs, out_name, chunk_xy=None):
    """Join list of mesh objects into one or chunked meshes. Returns created objects."""
    mesh_objs = [o for o in objs if o and o.type == "MESH" and o.name in bpy.data.objects]
    if not mesh_objs:
        return []
    created = []
    if chunk_xy is None:
        groups = {"all": mesh_objs}
    else:
        groups = {}
        for o in mesh_objs:
            cx = int((o.location.x + HALF) / SIZE * chunk_xy)
            cy = int((o.location.y + HALF) / SIZE * chunk_xy)
            cx = max(0, min(chunk_xy - 1, cx))
            cy = max(0, min(chunk_xy - 1, cy))
            groups.setdefault((cx, cy), []).append(o)
    for key, group in groups.items():
        if not group:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in group:
            o.hide_viewport = False
            o.hide_set(False)
            o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        if len(group) > 1:
            bpy.ops.object.make_single_user(type="SELECTED_OBJECTS", object=True, obdata=True)
            bpy.ops.object.join()
        active = bpy.context.view_layer.objects.active
        if isinstance(key, tuple):
            active.name = f"{out_name}_{key[0]}_{key[1]}"
        else:
            active.name = out_name
        if active.data:
            active.data.name = active.name
        created.append(active)
        log(f"JOINED {active.name} faces={len(active.data.polygons)}")
    return created


def setup_lights_camera():
    for o in list(bpy.data.objects):
        if o.type in {"LIGHT", "CAMERA"}:
            bpy.data.objects.remove(o, do_unlink=True)
    sun = bpy.data.lights.new("Sun", type="SUN")
    sun.energy = 4.5
    sun.color = (1.0, 0.96, 0.88)
    sun_o = bpy.data.objects.new("Sun", sun)
    bpy.context.scene.collection.objects.link(sun_o)
    sun_o.rotation_euler = (math.radians(48), math.radians(12), math.radians(35))
    fill = bpy.data.lights.new("Fill", type="SUN")
    fill.energy = 0.65
    fill.color = (0.55, 0.68, 0.9)
    fill_o = bpy.data.objects.new("Fill", fill)
    bpy.context.scene.collection.objects.link(fill_o)
    fill_o.rotation_euler = (math.radians(75), math.radians(-40), math.radians(170))
    cam_data = bpy.data.cameras.new("PreviewCamera")
    cam = bpy.data.objects.new("PreviewCamera", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = (0, -95, 58)
    cam.rotation_euler = (math.radians(55), 0, 0)
    bpy.context.scene.camera = cam
    mk = bpy.data.objects.new("SpawnMarker", None)
    mk.empty_display_type = "PLAIN_AXES"
    mk.empty_display_size = 10
    mk.location = (0, 0, height_at(0, 0) + 0.5)
    bpy.context.scene.collection.objects.link(mk)


def export_all():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(BLEND_SRC), exist_ok=True)
    # hide library
    lib = bpy.data.collections.get("Library")
    if lib:
        for o in lib.objects:
            o.hide_render = True
            o.hide_viewport = True
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_SRC)
    rna = bpy.ops.export_scene.gltf.get_rna_type()
    kw = dict(filepath=GLB_OUT, export_format="GLB", use_selection=False, export_apply=True)
    for key, val in [
        ("export_yup", True),
        ("export_animations", False),
        ("export_lights", False),
        ("export_cameras", False),
        ("export_extras", False),
    ]:
        if key in rna.properties.keys():
            kw[key] = val
    # exclude library objects from export by moving them to excluded collection visibility
    # Ensure only visible scene meshes export: temporarily unlink library
    unlinked = []
    if lib:
        for o in list(lib.objects):
            lib.objects.unlink(o)
            unlinked.append(o)
    res = bpy.ops.export_scene.gltf(**kw)
    for o in unlinked:
        lib.objects.link(o)
    log(f"EXPORT {res} size={os.path.getsize(GLB_OUT) if os.path.exists(GLB_OUT) else -1}")
    mesh_n = sum(1 for o in bpy.data.objects if o.type == "MESH" and not o.hide_render)
    log(f"VISIBLE_MESHES ~ check done mesh_total={sum(1 for o in bpy.data.objects if o.type=='MESH')}")


def main():
    log("=== KENNEY FOREST FULL REBUILD ===")
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    build_terrain()
    setup_lights_camera()
    log("IMPORT_LIBRARY...")
    lib = load_library()
    log(f"LIBRARY_COUNT {len(lib)}")
    world = ensure_collection("WorldProps")
    roads = make_roads()
    avoid = []
    for path in roads:
        avoid.extend(path)
    avoid.extend([(0, 0), (-40, 330), (120, RIVER_Y), (235, -152), (-340, 20)])
    log("PLACE_ROADS...")
    road_objs = []
    for path in roads:
        road_objs.extend(place_path_tiles(lib, path, world, scale=10.0))
    log(f"ROAD_TILES {len(road_objs)}")
    log("PLACE_VILLAGE...")
    village = place_village(lib, world)
    log("PLACE_GRAVEYARD...")
    grave = place_graveyard(lib, world)
    log("PLACE_LANDMARKS...")
    marks = place_landmarks(lib, world)
    log("PLACE_WATER...")
    water = place_water(world)
    log("SCATTER_NATURE...")
    nature, _ = scatter_nature(lib, avoid, world)
    # Join for performance
    log("JOIN...")
    trees = [o for o in nature if o.name.startswith("Tree_")]
    rocks = [o for o in nature if o.name.startswith("Rock_")]
    bushes = [o for o in nature if o.name.startswith("Bush_") or o.name.startswith("Debris_")]
    join_objects(trees, "KenneyTrees", chunk_xy=4)
    join_objects(rocks, "KenneyRocks", chunk_xy=2)
    join_objects(bushes, "KenneyBushes", chunk_xy=2)
    join_objects(road_objs, "KenneyRoads")
    join_objects(village, "KenneyVillage")
    join_objects(grave, "KenneyGraveyard")
    join_objects(marks, "KenneyLandmarks")
    # water already few objects
    export_all()
    log("=== DONE ===")


if __name__ == "__main__":
    main()

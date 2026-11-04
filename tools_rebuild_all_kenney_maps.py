"""Build every placeholder map as a DISTINCT Kenney-themed GLB.

Each map uses a unique layout recipe + strict asset filters so supermarket
does not look like a pirate island or parking lot.
"""
from __future__ import annotations

import bpy
import bmesh
import math
import os
import random
from mathutils import Vector, Euler

KENNEY = r"D:\Kenney\github\3D assets"
OUT_ROOT = r"d:\godotdemo\assets\blender_maps"
BLEND_ROOT = r"d:\godotdemo_blender_src\maps"

KIT = {
    "nature": os.path.join(KENNEY, r"Nature Kit\Models\GLTF format"),
    "suburban": os.path.join(KENNEY, r"City Kit - Suburban\Models\GLB format"),
    "industrial": os.path.join(KENNEY, r"City Kit - Industrial\Models\GLB format"),
    "commercial": os.path.join(KENNEY, r"City Kit - Commercial\Models\GLB format"),
    "graveyard": os.path.join(KENNEY, r"Graveyard Kit\Models\GLB format"),
    "pirate": os.path.join(KENNEY, r"Pirate Kit\Models\GLB format"),
    "space_station": os.path.join(KENNEY, r"Space Station Kit\Models\GLTF format"),
    "space": os.path.join(KENNEY, r"Space Kit\Models\GLTF format"),
    "castle": os.path.join(KENNEY, r"Castle Kit\Models\GLB format"),
    "factory": os.path.join(KENNEY, r"Factory Kit\Models\GLB format"),
    "furniture": os.path.join(KENNEY, r"Furniture Kit\Models\GLTF format"),
    "dungeon": os.path.join(KENNEY, r"Mini Dungeon\Models\GLB format"),
    "cave": os.path.join(KENNEY, r"Modular Cave Kit\Models\GLB format"),
    "train": os.path.join(KENNEY, r"Train Kit\Models\GLB format"),
    "coaster": os.path.join(KENNEY, r"Coaster Kit\Models\GLB format"),
    "fantasy": os.path.join(KENNEY, r"Fantasy Town Kit\Models\GLB format"),
    "holiday": os.path.join(KENNEY, r"Holiday Kit\Models\GLB format"),
    "survival": os.path.join(KENNEY, r"Survival Kit\Models\GLB format"),
    "market": os.path.join(KENNEY, r"Mini Market\Models\GLB format"),
    "arena": os.path.join(KENNEY, r"Mini Arena\Models\GLB format"),
    "watercraft": os.path.join(KENNEY, r"Watercraft Pack\Models\GLB format"),
    "car": os.path.join(KENNEY, r"Car Kit\Models\GLB format"),
    "food": os.path.join(KENNEY, r"Food Kit\Models\GLB format"),
    "marble": os.path.join(KENNEY, r"Marble Kit\Models\GLB format"),
    "urban": os.path.join(KENNEY, r"Retro Urban Kit\Models\GLB format"),
    "arcade": os.path.join(KENNEY, r"Mini Arcade\Models\GLB format"),
    "brick": os.path.join(KENNEY, r"Brick Kit\Models\GLB format"),
    "building": os.path.join(KENNEY, r"Building Kit\Models\GLB format"),
}

_LIB_CACHE: dict[str, object] = {}


def log(msg: str) -> None:
    print(msg, flush=True)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for b in list(block):
            if getattr(b, "users", 1) == 0:
                block.remove(b)


def mat(name: str, color, roughness=0.9, alpha=1.0):
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
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = 0.0
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    m.diffuse_color = (*color, alpha)
    return m


def ensure_collection(name: str):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col


def import_glb(path: str, name: str):
    before = set(bpy.data.objects.keys())
    try:
        bpy.ops.import_scene.gltf(filepath=path)
    except Exception as e:
        log(f"IMPORT_FAIL {path}: {e}")
        return None
    new_objs = [bpy.data.objects[k] for k in bpy.data.objects.keys() if k not in before]
    meshes = [o for o in new_objs if o.type == "MESH"]
    empties = [o for o in new_objs if o.type != "MESH"]
    if not meshes:
        for o in new_objs:
            bpy.data.objects.remove(o, do_unlink=True)
        return None
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in empties:
        bpy.data.objects.remove(o, do_unlink=True)
    scene_col = bpy.context.scene.collection
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        if scene_col not in o.users_collection:
            scene_col.objects.link(o)
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    root = bpy.context.view_layer.objects.active
    root.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # glTF imports land in QUATERNION mode ¡ª force XYZ so later euler yaw writes stick.
    root.rotation_mode = "XYZ"
    root.rotation_euler = (0.0, 0.0, 0.0)
    root.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
    lib = ensure_collection("Library")
    for col in list(root.users_collection):
        col.objects.unlink(root)
    lib.objects.link(root)
    root.hide_viewport = True
    root.hide_render = True
    return root


def world_bounds(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    xs = [c.x for c in corners]
    ys = [c.y for c in corners]
    zs = [c.z for c in corners]
    return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)


def world_size(obj):
    x0, x1, y0, y1, z0, z1 = world_bounds(obj)
    return x1 - x0, y1 - y0, z1 - z0


def list_glbs(folder: str, limit: int = 60, include=None, exclude=None):
    if not folder or not os.path.isdir(folder):
        return []
    files = [f for f in os.listdir(folder) if f.lower().endswith(".glb")]
    files.sort()
    include = [s.lower() for s in (include or [])]
    exclude = [s.lower() for s in (exclude or [])]

    def ok(name: str) -> bool:
        fl = name.lower()
        if exclude and any(x in fl for x in exclude):
            return False
        if include:
            return any(x in fl for x in include)
        return True

    ranked = []
    for f in files:
        if not ok(f):
            continue
        fl = f.lower()
        score = sum(1 for s in include if s in fl) if include else 0
        ranked.append((-score, f))
    ranked.sort()
    return [os.path.join(folder, f) for _, f in ranked[:limit]]


def load_template(path: str):
    if path in _LIB_CACHE:
        return _LIB_CACHE[path]
    name = "Lib_" + os.path.splitext(os.path.basename(path))[0][:48]
    obj = import_glb(path, name)
    if obj:
        _LIB_CACHE[path] = obj
    return obj


def seat_on_ground(obj, ground_z: float = 0.0) -> None:
    bpy.context.view_layer.update()
    _x0, _x1, _y0, _y1, z0, _z1 = world_bounds(obj)
    obj.location.z += ground_z - z0


def smart_scale(tpl, target_range, mode="foot"):
    sx, sy, sz = world_size(tpl)
    lo, hi = target_range
    if mode == "height":
        base = max(sz, 0.05)
    elif mode == "max":
        base = max(sx, sy, sz, 0.05)
    else:
        base = max(sx, sy, 0.05)
    # Tiny props stay prop-sized.
    if base < 0.4:
        target = min(hi, max(0.4, lo * 0.35))
        target = random.uniform(target * 0.7, min(1.2, target * 1.4))
    else:
        target = random.uniform(lo, hi)
    return max(0.2, min(target / base, 16.0))


def instance_at(template, name, xy, scale=1.0, yaw=0.0, ground_z=0.0):
    obj = template.copy()
    obj.data = template.data.copy()
    obj.name = name[:60]
    obj.hide_viewport = False
    obj.hide_render = False
    obj.hide_set(False)
    # Copies inherit QUATERNION from glTF templates; euler writes are ignored until XYZ.
    obj.rotation_mode = "XYZ"
    obj.location = Vector((xy[0], xy[1], 0.0))
    obj.scale = (scale, scale, scale)
    obj.rotation_euler = Euler((0.0, 0.0, yaw))
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    bpy.context.scene.collection.objects.link(obj)
    seat_on_ground(obj, ground_z)
    return obj


def pick_paths(kit_keys, include=None, exclude=None, limit=40):
    paths = []
    for k in kit_keys:
        paths.extend(list_glbs(KIT.get(k, ""), limit=limit, include=include, exclude=exclude))
    # de-dupe keep order
    seen = set()
    out = []
    for p in paths:
        if p not in seen and os.path.exists(p):
            seen.add(p)
            out.append(p)
    return out


def yaw_align_longest(tpl, along="x") -> float:
    """Align the model's longest horizontal AABB edge to world X or Y.

    Kenney cars/trains/beds/doorways are usually longer on local Y ¡ª this turns
    them to sit correctly in rows, walls, and tracks.
    """
    sx, sy, _sz = world_size(tpl)
    long_on_x = sx >= sy * 0.98
    if along == "x":
        return 0.0 if long_on_x else math.pi * 0.5
    return math.pi * 0.5 if long_on_x else 0.0


# Back-compat alias used by door helpers.
def yaw_align_width(tpl, along="x") -> float:
    return yaw_align_longest(tpl, along=along)


def yaw_face_center(x: float, y: float) -> float:
    """Yaw so local -Y (Kenney building/machine front) points toward the origin."""
    if abs(x) < 1e-6 and abs(y) < 1e-6:
        return 0.0
    return math.atan2(-x, y)


def yaw_face_dir(fx: float, fy: float) -> float:
    """Yaw so local -Y points along world (fx, fy)."""
    if abs(fx) < 1e-6 and abs(fy) < 1e-6:
        return 0.0
    # local -Y after yaw ¦È -> (sin¦È, -cos¦È) == normalize(fx,fy)
    return math.atan2(fx, -fy)


def yaw_tangent(positions, i: int) -> float:
    """Yaw so local longest-forward (approx -Y) follows the path tangent."""
    n = len(positions)
    if n < 2:
        return 0.0
    x0, y0 = positions[(i - 1) % n]
    x1, y1 = positions[(i + 1) % n]
    return yaw_face_dir(x1 - x0, y1 - y0)


def classify_asset(path: str) -> str:
    n = os.path.basename(path).lower()
    if any(
        k in n
        for k in (
            "sedan", "suv", "truck", "taxi", "police", "hatch", "van", "delivery",
            "race", "ambulance", "garbage", "tractor", "kart", "locomotive",
            "carriage", "train-", "tram", "boat", "ship", "sail", "tug", "raft",
        )
    ):
        return "vehicle"
    if any(k in n for k in ("railroad", "rail-", "spline", "track-")):
        return "rail"
    if any(k in n for k in ("doorway", "door-rotate", "wall-door", "cabin-door")):
        return "door"
    if any(k in n for k in ("building", "cabin", "house", "tower", "skyscraper", "warehouse", "shop", "crypt")):
        return "building"
    if any(k in n for k in ("bed", "sofa", "table", "bench", "desk", "shelf", "freezer", "display")):
        return "long_furn"
    if any(
        k in n
        for k in (
            "arcade", "gambling", "machine", "vending", "pinball", "claw", "console",
            "register", "ticket", "dance",
        )
    ):
        return "machine"
    if any(k in n for k in ("corridor", "conveyor", "catwalk")):
        return "segment"
    if any(k in n for k in ("wall", "fence", "barrier", "border")):
        return "wall"
    if any(k in n for k in ("tree", "palm", "rock", "bush", "grass", "flower", "mushroom", "column", "pillar", "cactus")):
        return "radial"
    return "prop"


def resolve_yaw(tpl, path: str, x: float, y: float, yaw_mode, rng, positions=None, index=0) -> float:
    """Pick a sensible yaw for every asset ¡ª never leave asymmetric meshes random by default."""
    kind = classify_asset(path)

    if yaw_mode == "face_center":
        return yaw_face_center(x, y)
    if yaw_mode == "along_x":
        return yaw_align_longest(tpl, along="x")
    if yaw_mode == "along_y":
        return yaw_align_longest(tpl, along="y")
    if yaw_mode == "tangent":
        return yaw_tangent(positions or [(x, y)], index)
    if yaw_mode == "face_south":
        return yaw_face_dir(0.0, -1.0)  # local -Y -> world -Y
    if yaw_mode == "face_north":
        return yaw_face_dir(0.0, 1.0)
    if isinstance(yaw_mode, (int, float)):
        return float(yaw_mode)

    # --- auto (default) ---
    if kind == "building":
        return yaw_face_center(x, y)
    if kind in ("vehicle", "rail", "long_furn", "segment", "door"):
        # Prefer path tangent when we have a poly-line; else longest -> X.
        if positions is not None and len(positions) >= 3:
            # If neighbors share roughly same Y ¡ú row along X
            x0, y0 = positions[max(0, index - 1)]
            x1, y1 = positions[min(len(positions) - 1, index + 1)]
            if abs(x1 - x0) >= abs(y1 - y0):
                return yaw_align_longest(tpl, along="x")
            return yaw_align_longest(tpl, along="y")
        return yaw_align_longest(tpl, along="x")
    if kind == "machine":
        # Face the south entrance / player approach inside halls.
        return yaw_face_dir(0.0, -1.0)
    if kind == "wall":
        return yaw_face_center(x, y)
    if kind == "radial":
        return rng.uniform(0, math.tau)
    # Generic props: face toward map center so they don't look randomly spun.
    if abs(x) + abs(y) > 4.0:
        return yaw_face_center(x, y)
    return yaw_face_dir(0.0, -1.0)


def place_many(paths, positions, name_prefix, scale_range, rng, mode="foot", yaw_mode="auto"):
    objs = []
    if not paths or not positions:
        return objs
    for i, (x, y) in enumerate(positions):
        path = paths[i % len(paths)]
        tpl = load_template(path)
        if tpl is None:
            continue
        scale = smart_scale(tpl, scale_range, mode=mode)
        yaw = resolve_yaw(tpl, path, x, y, yaw_mode, rng, positions=positions, index=i)
        objs.append(
            instance_at(
                tpl,
                f"{name_prefix}_{i:03d}_{os.path.splitext(os.path.basename(path))[0][:20]}",
                (x, y),
                scale=scale,
                yaw=yaw,
            )
        )
    return objs


def make_ground(size: float, color, name="Terrain", thickness=0.45):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, -thickness * 0.5))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size, size, thickness)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.clear()
    obj.data.materials.append(mat(f"M_{name}", color, 0.92))
    return obj


def make_patch(x, y, sx, sy, color, name="Patch", z=-0.02):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(x, y, z - 0.05))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (sx, sy, 0.12)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.clear()
    obj.data.materials.append(mat(f"M_{name}", color, 0.95))
    return obj


def make_water_disc(x, y, radius, z=0.08, name="PondWater"):
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=28, radius=radius)
    for v in bm.verts:
        v.co.z = z
        v.co.x += x
        v.co.y += y
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat("M_Water", (0.12, 0.34, 0.48), 0.12, alpha=0.72))
    return obj


def make_box(name, loc, scale_xyz, color, roughness=0.9):
    """Axis-aligned solid used for reliable enclosed interiors (walls/ceiling)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale_xyz
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.clear()
    obj.data.materials.append(mat(f"M_{name}", color, roughness))
    return obj


def _door_frame_paths(wide=False):
    include = ["wall-doorway-wide"] if wide else ["wall-doorway-round", "wall-doorway-square", "wall-doorway"]
    return pick_paths(
        ["building"],
        include=include,
        exclude=["barricade", "doors", "door-rotate"],
        limit=8,
    ) or pick_paths(["building"], include=["wall-doorway"], exclude=["barricade", "door-rotate"], limit=8)


def _door_leaf_paths():
    # Kenney door-rotate*: hinge at origin, panel extends mostly along -Y.
    return pick_paths(
        ["building"],
        include=["door-rotate-square", "door-rotate-round", "door-rotate"],
        exclude=["doorway", "barricade", "fence", "wall-door-rotate"],
        limit=16,
    )


def place_hinged_door_leaf(
    tpl,
    name: str,
    hinge_xy,
    wall_along: str,
    open_angle: float,
    door_h: float,
    inward_sign: float = 1.0,
):
    """Seat a Kenney door-rotate leaf on its hinge.

    Asset local: hinge ¡Ö origin, panel extends along -Y, thickness on X.
    wall_along 'x': closed door fills a south/north wall (width on world X).
    wall_along 'y': closed door fills an east/west wall (width on world Y).
    open_angle: radians past closed, positive swings toward +inward.
    inward_sign: +1 means inward is +Y (south wall) or +X (west wall).
    """
    _sx, _sy, sz = world_size(tpl)
    scale = door_h / max(sz, 0.05)
    # Closed orientation: put local -Y along the wall's +width direction.
    if wall_along == "x":
        # local -Y -> world +X  => yaw = ¦Ð/2
        closed = math.pi * 0.5
        # Swing inward (+Y for south wall): +open_angle
        yaw = closed + open_angle * inward_sign
    else:
        # local -Y -> world +Y  => yaw = ¦Ð
        closed = math.pi
        # Swing inward (+X for west-facing partition opening to +X): need local -Y -> +X after open
        # From closed (along +Y), +open toward +X is -open in Z yaw (CW).
        yaw = closed - open_angle * inward_sign
    return instance_at(tpl, name, hinge_xy, scale=scale, yaw=yaw)


def place_entrance_doors(y_wall: float, door_width: float, door_h: float, rng: random.Random):
    """Frame flush in the south gap + one leaf hinged on the left jamb, swung open inward."""
    objs = []
    wide = door_width >= 3.4
    frames = _door_frame_paths(wide=wide)
    leaves = _door_leaf_paths()

    if frames:
        tpl = load_template(frames[0])
        if tpl is not None:
            sx, sy, sz = world_size(tpl)
            # Frame local width on Y, thickness on X ¡ú yaw ¦Ð/2 puts width on world X.
            yaw = yaw_align_width(tpl, along="x")
            # Fill the wall gap exactly (width + height via uniform scale from width).
            foot_w = max(sx, sy)  # pre-yaw width axis length
            scale = door_width / max(foot_w, 0.05)
            # Keep height near door_h; if width-driven scale overshoots a lot, blend.
            h_scale = door_h / max(sz, 0.05)
            if scale > h_scale * 1.35:
                scale = h_scale * 1.15
            objs.append(instance_at(tpl, "DoorFrame", (0.0, y_wall), scale=scale, yaw=yaw))
            log(
                f"DoorFrame {os.path.basename(frames[0])} yaw={yaw:.2f} "
                f"gap={door_width:.2f} h={door_h:.2f} scale={scale:.2f} raw=({sx:.2f},{sy:.2f},{sz:.2f})"
            )

    if leaves:
        path = leaves[rng.randrange(len(leaves))]
        tpl = load_template(path)
        if tpl is not None:
            # Hinge on left jamb, slightly inset so the panel clears the frame.
            hinge = (-door_width * 0.5 + 0.06, y_wall)
            # ~80¡ã open into the room (+Y) so the passage is clear but leaf stays on the jamb.
            objs.append(
                place_hinged_door_leaf(
                    tpl,
                    "DoorLeaf_Open",
                    hinge,
                    wall_along="x",
                    open_angle=math.radians(80.0),
                    door_h=door_h * 0.96,
                    inward_sign=1.0,
                )
            )
            log(f"DoorLeaf {os.path.basename(path)} hinge={hinge} open=80deg h={door_h:.2f}")
    else:
        log("WARN no door leaf assets found ¡ª entrance stays an empty gap")
    return objs


def place_partition_door(axis: str, pos: float, mid: float, gap_w: float, door_h: float, name: str):
    """One open leaf seated in a partition doorway gap."""
    leaves = _door_leaf_paths()
    if not leaves:
        return None
    tpl = load_template(leaves[0])
    if tpl is None:
        return None
    if axis == "y":
        # Partition runs along X (wall normal ¡ÀY). Opening faces +Y into next room.
        hinge = (mid - gap_w * 0.5 + 0.06, pos)
        return place_hinged_door_leaf(
            tpl, name, hinge, wall_along="x", open_angle=math.radians(75.0), door_h=door_h, inward_sign=1.0
        )
    # Partition runs along Y (wall normal ¡ÀX). Opening faces +X.
    hinge = (pos, mid - gap_w * 0.5 + 0.06)
    return place_hinged_door_leaf(
        tpl, name, hinge, wall_along="y", open_angle=math.radians(75.0), door_h=door_h, inward_sign=1.0
    )


def make_interior_shell(
    width,
    depth,
    height=8.0,
    thick=0.7,
    floor_color=(0.55, 0.55, 0.58),
    wall_color=(0.72, 0.72, 0.74),
    ceiling_color=(0.82, 0.82, 0.84),
    door_width=2.4,
    partitions=None,
    rng=None,
):
    """Closed building: floor + walls + ceiling, human-scale south doorway with seated doors.

    Spawn just inside the south door looking toward +Y into the hall.
    door_width is the wall gap ¡ª keep it near Kenney doorway size (¡Ö2.2¨C4.0), never 6¨C10.
    """
    rng = rng or random.Random(0)
    objs = []
    hw, hd = width * 0.5, depth * 0.5
    # Human doorway: clamp so the Kenney frame can actually fill the hole.
    door_width = float(max(2.0, min(door_width, 4.0)))
    door_h = 2.7

    # Floor named Terrain => Godot layer-8 ground stick.
    objs.append(make_box("Terrain", (0.0, 0.0, -0.25), (width + thick * 2, depth + thick * 2, 0.5), floor_color, 0.95))
    objs.append(make_box("Ceiling", (0.0, 0.0, height), (width + thick * 2, depth + thick * 2, thick), ceiling_color, 0.88))

    # Full walls N/E/W
    objs.append(make_box("Wall_N", (0.0, hd, height * 0.5), (width + thick * 2, thick, height), wall_color))
    objs.append(make_box("Wall_W", (-hw, 0.0, height * 0.5), (thick, depth, height), wall_color))
    objs.append(make_box("Wall_E", (hw, 0.0, height * 0.5), (thick, depth, height), wall_color))

    # South wall with centered doorway matching the frame.
    gap = door_width * 0.5
    side_w = max(1.0, hw - gap)
    objs.append(make_box("Wall_S_L", (-gap - side_w * 0.5, -hd, height * 0.5), (side_w, thick, height), wall_color))
    objs.append(make_box("Wall_S_R", (gap + side_w * 0.5, -hd, height * 0.5), (side_w, thick, height), wall_color))
    lintel_h = max(0.35, height - door_h)
    objs.append(
        make_box(
            "Wall_S_Lintel",
            (0.0, -hd, door_h + lintel_h * 0.5),
            (door_width + 0.15, thick, lintel_h),
            wall_color,
        )
    )

    objs += place_entrance_doors(-hd, door_width, door_h, rng)

    # partitions: ("x"|"y", pos, a0, a1) wall along the other axis
    for i, part in enumerate(partitions or []):
        axis, pos, a0, a1 = part
        length = abs(a1 - a0)
        mid = (a0 + a1) * 0.5
        ph = height * 0.92
        gap_w = 2.2
        door_h_inner = min(2.5, ph * 0.85)
        if length > gap_w * 2.5:
            half_len = (length - gap_w) * 0.5
            if axis == "y":
                objs.append(
                    make_box(
                        f"Partition_{i}_A",
                        (a0 + half_len * 0.5, pos, ph * 0.5),
                        (half_len, thick * 0.75, ph),
                        wall_color,
                    )
                )
                objs.append(
                    make_box(
                        f"Partition_{i}_B",
                        (a1 - half_len * 0.5, pos, ph * 0.5),
                        (half_len, thick * 0.75, ph),
                        wall_color,
                    )
                )
                # Lintel over partition gap
                objs.append(
                    make_box(
                        f"Partition_{i}_Lintel",
                        (mid, pos, door_h_inner + (ph - door_h_inner) * 0.5),
                        (gap_w + 0.1, thick * 0.75, max(0.25, ph - door_h_inner)),
                        wall_color,
                    )
                )
            else:
                objs.append(
                    make_box(
                        f"Partition_{i}_A",
                        (pos, a0 + half_len * 0.5, ph * 0.5),
                        (thick * 0.75, half_len, ph),
                        wall_color,
                    )
                )
                objs.append(
                    make_box(
                        f"Partition_{i}_B",
                        (pos, a1 - half_len * 0.5, ph * 0.5),
                        (thick * 0.75, half_len, ph),
                        wall_color,
                    )
                )
                objs.append(
                    make_box(
                        f"Partition_{i}_Lintel",
                        (pos, mid, door_h_inner + (ph - door_h_inner) * 0.5),
                        (thick * 0.75, gap_w + 0.1, max(0.25, ph - door_h_inner)),
                        wall_color,
                    )
                )
            leaf = place_partition_door(axis, pos, mid, gap_w, door_h_inner, f"InnerDoor_{i}")
            if leaf is not None:
                objs.append(leaf)
        else:
            if axis == "y":
                objs.append(make_box(f"Partition_{i}", (mid, pos, ph * 0.5), (length, thick * 0.75, ph), wall_color))
            else:
                objs.append(make_box(f"Partition_{i}", (pos, mid, ph * 0.5), (thick * 0.75, length, ph), wall_color))
    return objs


def add_spawn_marker(x=0.0, y=6.0, z=0.0):
    empty = bpy.data.objects.new("SpawnMarker", None)
    empty.empty_display_type = "PLAIN_AXES"
    empty.location = (x, y, z)
    bpy.context.scene.collection.objects.link(empty)
    return empty


def apply_all_transforms(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        if o is None or o.name not in bpy.data.objects:
            continue
        if o.type != "MESH":
            continue
        o.hide_set(False)
        o.select_set(True)
    if bpy.context.selected_objects:
        bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def export_map(map_id: str):
    out_dir = os.path.join(OUT_ROOT, map_id)
    os.makedirs(out_dir, exist_ok=True)
    blend_dir = os.path.join(BLEND_ROOT, map_id)
    os.makedirs(blend_dir, exist_ok=True)
    glb = os.path.join(out_dir, "world.glb")
    blend = os.path.join(blend_dir, "world.blend")
    lib = bpy.data.collections.get("Library")
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.context.scene.collection.all_objects:
        if lib and o.name in [x.name for x in lib.objects]:
            continue
        if o.type in ("MESH", "EMPTY"):
            o.hide_set(False)
            o.select_set(True)
    rna = bpy.ops.export_scene.gltf.get_rna_type()
    kw = dict(filepath=glb, export_format="GLB", use_selection=True, export_apply=True)
    for key, val in (
        ("export_yup", True),
        ("export_animations", False),
        ("export_lights", False),
        ("export_cameras", False),
        ("export_extras", False),
    ):
        if key in rna.properties.keys():
            kw[key] = val
    res = bpy.ops.export_scene.gltf(**kw)
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    log(f"EXPORT {map_id} -> {glb} res={res} size={os.path.getsize(glb) if os.path.exists(glb) else 0}")
    return glb


# --- layout helpers ---------------------------------------------------------

def grid_positions(cols, rows, spacing_x, spacing_y, ox=0.0, oy=0.0):
    pts = []
    for j in range(rows):
        for i in range(cols):
            pts.append((ox + (i - (cols - 1) * 0.5) * spacing_x, oy + (j - (rows - 1) * 0.5) * spacing_y))
    return pts


def line_positions(n, start, end):
    pts = []
    for i in range(n):
        t = i / max(n - 1, 1)
        pts.append((start[0] + (end[0] - start[0]) * t, start[1] + (end[1] - start[1]) * t))
    return pts


def ring_positions(n, radius, ox=0.0, oy=0.0):
    return [
        (ox + math.cos(i / n * math.tau) * radius, oy + math.sin(i / n * math.tau) * radius)
        for i in range(n)
    ]


def ellipse_positions(n, rx, ry, ox=0.0, oy=0.0):
    return [
        (ox + math.cos(i / n * math.tau) * rx, oy + math.sin(i / n * math.tau) * ry)
        for i in range(n)
    ]


def jittered_fill(rng, count, half, min_r=8.0, spacing=4.0, avoid=None):
    avoid = avoid or []
    pts = []
    attempts = 0
    while len(pts) < count and attempts < count * 50:
        attempts += 1
        x = rng.uniform(-half, half)
        y = rng.uniform(-half, half)
        if math.hypot(x, y) < min_r:
            continue
        ok = True
        for px, py in pts + avoid:
            if (x - px) ** 2 + (y - py) ** 2 < spacing * spacing:
                ok = False
                break
        if ok:
            pts.append((x, y))
    return pts


# --- per-map builders -------------------------------------------------------

def build_supermarket(rng, size):
    # Enclosed store: outer shell + aisle partitions + shelves inside.
    w, d, h = 90.0, 70.0, 7.5
    objs = make_interior_shell(
        w,
        d,
        height=h,
        floor_color=(0.45, 0.45, 0.48),
        wall_color=(0.78, 0.8, 0.82),
        ceiling_color=(0.9, 0.9, 0.92),
        door_width=2.4,
        partitions=[
            ("x", -18, -28, 28),
            ("x", 0, -28, 28),
            ("x", 18, -28, 28),
        ],
    )
    shelves = pick_paths(["market"], include=["shelf", "freezer", "display", "freezers"], limit=20)
    carts = pick_paths(["market"], include=["cart", "basket", "register", "column"], limit=12)
    food = pick_paths(["food"], include=["bottle", "bread", "apple", "box", "can", "bag", "bowl"], exclude=["character"], limit=30)
    shelf_pts = []
    for aisle in (-27, -9, 9, 27):
        shelf_pts += line_positions(6, (aisle, -22), (aisle, 22))
    objs += place_many(shelves, shelf_pts, "Shelf", (3.0, 5.5), rng, mode="height", yaw_mode="along_y")
    objs += place_many(carts, grid_positions(3, 2, 6, 6, 0, -28), "Cart", (1.4, 2.6), rng, yaw_mode="face_south")
    objs += place_many(food, jittered_fill(rng, 35, 28, 6, 2.2), "Food", (0.45, 1.2), rng, yaw_mode="face_south")
    return objs


def build_parking(rng, size):
    # Underground garage: low ceiling, pillars, cars in rows.
    w, d, h = 100.0, 70.0, 5.2
    objs = make_interior_shell(
        w,
        d,
        height=h,
        thick=0.9,
        floor_color=(0.2, 0.2, 0.22),
        wall_color=(0.35, 0.35, 0.36),
        ceiling_color=(0.28, 0.28, 0.3),
        door_width=2.6,
    )
    # concrete pillars
    for x, y in grid_positions(4, 3, 22, 18):
        objs.append(make_box(f"Pillar_{x:.0f}_{y:.0f}", (x, y, h * 0.45), (1.4, 1.4, h * 0.9), (0.4, 0.4, 0.42)))
    cars = pick_paths(
        ["car"],
        include=["sedan", "suv", "hatchback", "taxi", "police", "truck", "delivery"],
        exclude=["debris", "kart", "cone"],
        limit=28,
    )
    props = pick_paths(["car"], include=["cone"], limit=8)
    pts = []
    for row in range(-2, 3):
        pts += line_positions(7, (-40, row * 10), (40, row * 10))
    # Rows run along +X; park nose-in along ¡ÀY so car length fills the stall.
    objs += place_many(cars, pts, "Car", (4.0, 5.2), rng, mode="foot", yaw_mode="along_y")
    objs += place_many(props, jittered_fill(rng, 14, 30, 6, 3.0), "Cone", (0.5, 1.0), rng, yaw_mode="auto")
    return objs


def build_cruise(rng, size):
    # Ship interior lounge: enclosed cabin hall with windows of props.
    w, d, h = 80.0, 36.0, 6.5
    objs = make_interior_shell(
        w,
        d,
        height=h,
        floor_color=(0.42, 0.32, 0.24),
        wall_color=(0.7, 0.68, 0.62),
        ceiling_color=(0.85, 0.82, 0.78),
        door_width=2.4,
        partitions=[("y", 0, -30, -8), ("y", 0, 8, 30)],
    )
    furn = pick_paths(["furniture"], include=["chair", "table", "bench", "sofa", "cabinet"], limit=24)
    pirate = pick_paths(["pirate"], include=["barrel", "crate", "chest", "flag"], limit=16)
    objs += place_many(furn, grid_positions(6, 3, 8, 8, 0, 0), "Lounge", (1.2, 2.4), rng, yaw_mode="face_south")
    objs += place_many(pirate, jittered_fill(rng, 18, 28, 6, 3.0), "Cargo", (1.2, 2.8), rng, yaw_mode="face_south")
    return objs


def build_nuclear(rng, size):
    # Reactor control hall ¡ª enclosed industrial interior.
    w, d, h = 85.0, 60.0, 10.0
    objs = make_interior_shell(
        w,
        d,
        height=h,
        floor_color=(0.28, 0.3, 0.28),
        wall_color=(0.45, 0.5, 0.42),
        ceiling_color=(0.35, 0.38, 0.34),
        door_width=2.5,
    )
    machines = pick_paths(["factory"], include=["conveyor", "tank", "cog", "machine", "catwalk", "box"], limit=36)
    chimneys = pick_paths(["industrial", "factory"], include=["tank", "chimney"], limit=10)
    objs += place_many(machines, grid_positions(5, 4, 12, 10), "Mach", (3, 7), rng, mode="max", yaw_mode="face_south")
    objs += place_many(chimneys, [(-20, 15), (20, 15), (0, 18)], "Core", (6, 12), rng, mode="height", yaw_mode="auto")
    return objs


def build_museum(rng, size):
    # One big museum building: shell + gallery rooms + exhibits inside.
    w, d, h = 70.0, 55.0, 9.0
    objs = make_interior_shell(
        w,
        d,
        height=h,
        floor_color=(0.78, 0.74, 0.68),
        wall_color=(0.88, 0.86, 0.82),
        ceiling_color=(0.93, 0.92, 0.9),
        door_width=2.4,
        partitions=[
            ("x", -12, -8, 22),
            ("x", 12, -8, 22),
            ("y", 8, -28, -14),
            ("y", 8, 14, 28),
        ],
    )
    cols = pick_paths(["marble", "dungeon", "castle"], include=["column", "pillar", "statue"], limit=20)
    exhibits = pick_paths(
        ["furniture", "marble", "dungeon"],
        include=["bench", "cabinet", "chest", "statue", "bookcase", "vase", "display"],
        limit=28,
    )
    banners = pick_paths(["marble", "castle"], include=["banner"], limit=10)
    objs += place_many(cols, grid_positions(3, 2, 16, 14, 0, 5), "Col", (2.2, 3.8), rng, mode="height", yaw_mode="auto")
    objs += place_many(exhibits, jittered_fill(rng, 32, 24, 8, 3.5), "Exhibit", (1.2, 3.2), rng, yaw_mode="face_south")
    objs += place_many(banners, [(-28, 0), (28, 0), (0, 22)], "Banner", (2, 4), rng, mode="height", yaw_mode="face_center")
    return objs


def build_casino(rng, size):
    w, d, h = 75.0, 55.0, 7.0
    objs = make_interior_shell(
        w,
        d,
        height=h,
        floor_color=(0.25, 0.08, 0.12),
        wall_color=(0.35, 0.12, 0.2),
        ceiling_color=(0.15, 0.08, 0.12),
        door_width=2.4,
    )
    machines = pick_paths(
        ["arcade"],
        include=["machine", "arcade", "gambling", "pinball", "claw", "dance", "vending", "ticket", "wheel"],
        limit=20,
    )
    chairs = pick_paths(["furniture"], include=["chair", "table"], limit=16)
    objs += place_many(machines, grid_positions(5, 4, 10, 9), "Slot", (1.8, 3.0), rng, mode="height", yaw_mode="face_south")
    objs += place_many(chairs, jittered_fill(rng, 22, 26, 6, 2.5), "Seat", (0.9, 1.8), rng, yaw_mode="face_south")
    return objs


def build_egypt(rng, size):
    objs = [make_ground(size, (0.78, 0.68, 0.42))]
    towers = pick_paths(["castle"], include=["tower", "gate", "wall", "stairs"], limit=24)
    ruins = pick_paths(["castle", "dungeon", "brick"], include=["statue", "column", "rocks", "wall", "banner", "stones"], limit=30)
    props = pick_paths(["dungeon"], include=["chest", "pot", "barrel", "torch", "weapon"], limit=20)
    objs += place_many(towers, ring_positions(8, size * 0.36), "Ruin", (14, 24), rng, mode="height", yaw_mode="face_center")
    objs += place_many(ruins, ring_positions(12, 28), "Stone", (4, 10), rng, mode="max", yaw_mode="face_center")
    objs += place_many(props, jittered_fill(rng, 30, size * 0.3, 10, 3.5), "Relic", (1.0, 2.8), rng, yaw_mode="face_center")
    return objs


def build_shrine(rng, size):
    objs = [make_ground(size, (0.28, 0.40, 0.26))]
    objs.append(make_water_disc(45, -25, 12))
    houses = pick_paths(["fantasy"], include=["house", "building", "tower", "chimney", "overhang", "roof"], limit=20)
    trees = pick_paths(["nature"], include=["tree_", "pine", "oak", "detailed"], exclude=["stump", "fall"], limit=30)
    decor = pick_paths(["fantasy", "nature"], include=["lantern", "fence", "hedge", "fountain", "banner", "path", "rock", "flower", "bush"], limit=40)
    objs += place_many(houses, ring_positions(7, 32), "Shrine", (10, 16), rng, mode="foot", yaw_mode="face_center")
    path = line_positions(12, (0, -55), (0, 40))
    objs += place_many(decor[:8] or decor, path, "Path", (2, 4), rng, mode="foot", yaw_mode="along_y")
    objs += place_many(trees, jittered_fill(rng, 45, size * 0.4, 12, 5.0), "Tree", (5, 12), rng, mode="height", yaw_mode="auto")
    objs += place_many(decor, jittered_fill(rng, 35, size * 0.35, 8, 3.0), "Decor", (1.2, 3.5), rng, yaw_mode="face_center")
    return objs


def build_pirate_island(rng, size):
    objs = [make_ground(size, (0.80, 0.72, 0.48))]
    objs.append(make_water_disc(0, -62, 28))
    objs.append(make_water_disc(50, 35, 14))
    palms = pick_paths(["pirate", "nature"], include=["palm", "tree_pine", "tree_oak", "tree_default", "tree_tall"], limit=30)
    boats = pick_paths(["pirate", "watercraft"], include=["boat", "ship", "row", "sail"], limit=16)
    loot = pick_paths(["pirate"], include=["chest", "barrel", "crate", "cannon", "flag", "rocks", "grass", "patch"], limit=30)
    structures = pick_paths(["pirate"], include=["castle", "platform", "mast", "tower"], limit=12)
    objs += place_many(structures, ring_positions(5, 30), "Fort", (8, 14), rng, mode="foot", yaw_mode="face_center")
    objs += place_many(boats, line_positions(5, (-40, -58), (40, -58)), "Boat", (7, 14), rng, mode="foot", yaw_mode="along_x")
    objs += place_many(palms, jittered_fill(rng, 40, size * 0.4, 10, 5.0), "Palm", (5, 11), rng, mode="height", yaw_mode="auto")
    objs += place_many(loot, jittered_fill(rng, 40, size * 0.35, 8, 3.0), "Loot", (1.2, 3.5), rng, yaw_mode="face_center")
    return objs


def build_space_station(rng, size):
    # Pressurized station interior ¡ª metal shell + corridor props.
    w, d, h = 70.0, 50.0, 7.0
    objs = make_interior_shell(
        w,
        d,
        height=h,
        floor_color=(0.18, 0.2, 0.24),
        wall_color=(0.45, 0.5, 0.58),
        ceiling_color=(0.25, 0.28, 0.34),
        door_width=2.4,
        partitions=[("x", 0, -8, 20), ("y", 10, -28, -8), ("y", 10, 8, 28)],
    )
    modules = pick_paths(["space"], include=["corridor", "desk", "chair", "barrel", "crate", "craft"], limit=36)
    objs += place_many(modules, jittered_fill(rng, 40, 24, 6, 3.0), "Mod", (2.5, 6.0), rng, mode="max", yaw_mode="face_south")
    return objs


def build_cyberpunk(rng, size):
    objs = [make_ground(size, (0.10, 0.10, 0.12))]
    objs.append(make_patch(0, 0, 18, size * 0.8, (0.16, 0.16, 0.18), "Road"))
    objs.append(make_patch(0, 0, size * 0.8, 18, (0.16, 0.16, 0.18), "Road2"))
    towers = pick_paths(["commercial", "urban"], include=["skyscraper", "building"], limit=30)
    street = pick_paths(["urban", "car"], include=["dumpster", "barrier", "awning", "light", "car", "sedan", "taxi", "sign", "pallet", "cable"], limit=40)
    objs += place_many(towers, ring_positions(12, size * 0.36), "Tower", (14, 26), rng, mode="height", yaw_mode="face_center")
    objs += place_many(street, jittered_fill(rng, 50, size * 0.35, 10, 3.5), "Street", (1.5, 5.0), rng, yaw_mode="auto")
    return objs


def build_bio_lab(rng, size):
    w, d, h = 70.0, 50.0, 7.5
    objs = make_interior_shell(
        w,
        d,
        height=h,
        floor_color=(0.3, 0.38, 0.34),
        wall_color=(0.55, 0.7, 0.62),
        ceiling_color=(0.7, 0.82, 0.75),
        door_width=2.4,
        partitions=[("x", -14, -18, 18), ("x", 14, -18, 18)],
    )
    gear = pick_paths(["factory"], include=["tank", "conveyor", "machine", "box", "cog", "catwalk"], limit=36)
    tables = pick_paths(["furniture"], include=["table", "chair", "cabinet", "desk"], limit=20)
    objs += place_many(gear, grid_positions(4, 3, 12, 10, 0, 4), "Gear", (2.5, 6.0), rng, mode="max", yaw_mode="face_south")
    objs += place_many(tables, jittered_fill(rng, 20, 22, 6, 2.8), "Bench", (1.1, 2.5), rng, yaw_mode="face_south")
    return objs


def build_time_rift(rng, size):
    objs = [make_ground(size, (0.26, 0.18, 0.34))]
    a = pick_paths(["castle"], include=["tower", "ruins", "wall", "siege"], limit=16)
    b = pick_paths(["space"], include=["craft", "corridor", "rocket", "crater"], limit=16)
    c = pick_paths(["nature"], include=["tree_", "rock", "cliff"], limit=20)
    objs += place_many(a, ring_positions(6, 40), "Past", (10, 18), rng, mode="max", yaw_mode="face_center")
    objs += place_many(b, ring_positions(6, 22), "Future", (8, 14), rng, mode="max", yaw_mode="face_center")
    objs += place_many(c, jittered_fill(rng, 35, size * 0.38, 8, 4.0), "Wild", (3, 10), rng, mode="height", yaw_mode="auto")
    return objs


def build_hospital(rng, size):
    w, d, h = 80.0, 55.0, 6.5
    objs = make_interior_shell(
        w,
        d,
        height=h,
        floor_color=(0.82, 0.82, 0.84),
        wall_color=(0.9, 0.92, 0.94),
        ceiling_color=(0.95, 0.95, 0.96),
        door_width=2.4,
        partitions=[
            ("y", -8, -32, -6),
            ("y", -8, 6, 32),
            ("y", 12, -32, -6),
            ("y", 12, 6, 32),
            ("x", 0, -20, 20),
        ],
    )
    beds = pick_paths(["furniture"], include=["bed", "cabinet", "chair", "bench", "table", "sink"], limit=36)
    medical = pick_paths(["survival", "furniture"], include=["barrel", "box", "bottle", "cabinet"], limit=18)
    pts = []
    for row in (-18, -2, 14):
        pts += line_positions(5, (-28, row), (28, row))
    objs += place_many(beds, pts, "Bed", (2.0, 3.2), rng, mode="foot", yaw_mode="along_x")
    objs += place_many(medical, jittered_fill(rng, 18, 24, 6, 2.8), "Med", (0.8, 2.0), rng, yaw_mode="face_south")
    return objs


def build_amusement(rng, size):
    objs = [make_ground(size, (0.20, 0.18, 0.22))]
    track = pick_paths(["coaster"], include=["coaster-flume-straight", "coaster-flume-corner", "coaster-flume-curve", "coaster-hanging-straight", "bench"], limit=40)
    haunt = pick_paths(["graveyard"], include=["crypt", "gravestone", "fence", "coffin", "cross", "candle", "ghost", "skeleton"], limit=30)
    booth = pick_paths(["fantasy", "coaster"], include=["cart", "booth", "fence", "banner"], limit=16)
    objs += place_many(track, ellipse_positions(24, 55, 40), "Track", (6, 10), rng, mode="foot", yaw_mode="tangent")
    objs += place_many(haunt, jittered_fill(rng, 35, size * 0.35, 12, 4.0), "Haunt", (2, 6), rng, mode="max", yaw_mode="face_center")
    objs += place_many(booth, ring_positions(8, 25), "Booth", (4, 8), rng, mode="foot", yaw_mode="face_center")
    return objs


def build_deep_sea(rng, size):
    # Submerged wreck interior: sealed dark hall.
    w, d, h = 75.0, 45.0, 6.0
    objs = make_interior_shell(
        w,
        d,
        height=h,
        floor_color=(0.12, 0.18, 0.2),
        wall_color=(0.2, 0.28, 0.32),
        ceiling_color=(0.08, 0.14, 0.18),
        door_width=2.4,
    )
    wreck = pick_paths(["pirate", "watercraft", "cave"], include=["chest", "barrel", "crate", "rocks", "cargo", "boat", "room"], limit=36)
    objs += place_many(wreck, jittered_fill(rng, 40, 24, 6, 3.2), "Wreck", (2, 8), rng, mode="max", yaw_mode="auto")
    return objs


def build_jungle(rng, size):
    objs = [make_ground(size, (0.22, 0.38, 0.16))]
    objs.append(make_water_disc(-35, 40, 14))
    trees = pick_paths(["nature"], include=["tree_", "pine", "oak", "detailed", "fat", "tall", "cone"], exclude=["fall"], limit=40)
    ruins = pick_paths(["castle"], include=["statue", "tower", "wall", "rocks", "stairs", "gate"], limit=20)
    under = pick_paths(["nature"], include=["bush", "rock", "flower", "grass", "plant", "fern", "mushroom"], limit=40)
    objs += place_many(ruins, ring_positions(7, 30), "Ruin", (10, 18), rng, mode="max", yaw_mode="face_center")
    objs += place_many(trees, jittered_fill(rng, 70, size * 0.42, 10, 4.5), "Tree", (6, 14), rng, mode="height", yaw_mode="auto")
    objs += place_many(under, jittered_fill(rng, 50, size * 0.4, 6, 2.5), "Under", (1.0, 3.0), rng, yaw_mode="face_center")
    return objs


def build_snow(rng, size):
    objs = [make_ground(size, (0.86, 0.90, 0.94))]
    cabins = pick_paths(["holiday"], include=["cabin"], limit=30)
    trees = pick_paths(["nature", "holiday"], include=["tree_", "pine", "snow"], limit=30)
    decor = pick_paths(["holiday", "survival"], include=["bench", "candy", "fence", "campfire", "sled", "barrel", "box"], limit=30)
    objs += place_many(cabins, ring_positions(7, 34), "Cabin", (10, 16), rng, mode="foot", yaw_mode="face_center")
    objs += place_many(trees, jittered_fill(rng, 45, size * 0.4, 12, 5.0), "Pine", (5, 12), rng, mode="height", yaw_mode="auto")
    objs += place_many(decor, jittered_fill(rng, 30, size * 0.32, 8, 3.0), "Camp", (1.0, 3.0), rng, yaw_mode="face_center")
    return objs


def build_volcano(rng, size):
    # Mine tunnel hall ¡ª enclosed rock chamber.
    w, d, h = 80.0, 55.0, 8.0
    objs = make_interior_shell(
        w,
        d,
        height=h,
        floor_color=(0.28, 0.16, 0.12),
        wall_color=(0.38, 0.22, 0.16),
        ceiling_color=(0.22, 0.12, 0.1),
        door_width=2.4,
    )
    objs.append(make_patch(0, 12, 16, 16, (0.55, 0.18, 0.08), "LavaGlow", z=0.02))
    mine = pick_paths(["factory", "industrial", "cave"], include=["box", "conveyor", "tank", "machine", "room", "cart"], limit=36)
    rocks = pick_paths(["nature", "cave", "castle"], include=["rock", "cliff", "stone"], limit=20)
    objs += place_many(mine, grid_positions(4, 3, 12, 10, 0, -4), "Mine", (3, 7), rng, mode="max", yaw_mode="face_south")
    objs += place_many(rocks, jittered_fill(rng, 24, 26, 8, 3.5), "Rock", (2.5, 7), rng, mode="max", yaw_mode="auto")
    return objs


def build_spirit(rng, size):
    objs = [make_ground(size, (0.16, 0.30, 0.20))]
    trees = pick_paths(["nature"], include=["tree_", "detailed", "oak", "pine", "fat"], limit=35)
    magic = pick_paths(["fantasy", "nature"], include=["mushroom", "lantern", "flower", "hedge", "fountain", "banner", "house", "treehouse"], limit=40)
    houses = pick_paths(["fantasy"], include=["house", "tower", "balcony"], limit=12)
    objs += place_many(houses, ring_positions(6, 32), "Treehouse", (8, 14), rng, mode="foot", yaw_mode="face_center")
    objs += place_many(trees, jittered_fill(rng, 55, size * 0.42, 10, 5.0), "SpiritTree", (6, 13), rng, mode="height", yaw_mode="auto")
    objs += place_many(magic, jittered_fill(rng, 45, size * 0.38, 6, 2.8), "Glow", (1.0, 3.5), rng, yaw_mode="face_center")
    return objs


def build_inverted(rng, size):
    objs = [make_ground(size, (0.34, 0.28, 0.42))]
    # "upside-down" feel: houses on ring + floating-looking tall props clustered oddly
    houses = pick_paths(["suburban"], include=["building-type"], limit=20)
    trees = pick_paths(["nature"], include=["tree_"], limit=20)
    furn = pick_paths(["furniture"], include=["chair", "table", "lamp", "sofa", "bed"], limit=30)
    objs += place_many(houses, ring_positions(8, 36), "House", (10, 16), rng, mode="foot", yaw_mode="face_center")
    objs += place_many(trees, ring_positions(10, 20), "Tree", (6, 12), rng, mode="height", yaw_mode="auto")
    objs += place_many(furn, jittered_fill(rng, 40, size * 0.35, 8, 2.5), "Odd", (1.0, 2.5), rng, yaw_mode="face_south")
    return objs


def build_mirror(rng, size):
    objs = [make_ground(size, (0.34, 0.38, 0.42))]
    houses = pick_paths(["suburban"], include=["building-type"], limit=20)
    cars = pick_paths(["car"], include=["sedan", "suv", "hatchback"], exclude=["debris"], limit=12)
    trees = pick_paths(["nature"], include=["tree_", "bush"], limit=20)
    # Perfect mirrored left/right placements
    left = [(-30, y) for y in (-40, -20, 0, 20, 40)] + [(-50, y) for y in (-30, -10, 10, 30)]
    right = [(-x, y) for x, y in left]
    objs += place_many(houses, left + right, "Twin", (10, 16), rng, mode="foot", yaw_mode="face_center")
    objs += place_many(cars, [(-15, 0), (15, 0), (-15, 25), (15, 25)], "Car", (4, 5.5), rng, yaw_mode="along_x")
    objs += place_many(trees, jittered_fill(rng, 30, size * 0.35, 10, 4.0), "Tree", (4, 10), rng, mode="height", yaw_mode="auto")
    return objs


def build_maze_casino(rng, size):
    w, d, h = 70.0, 70.0, 6.5
    # Dense interior partitions form a real indoor maze.
    parts = []
    for i in range(-3, 4):
        if i == 0:
            continue
        parts.append(("x", i * 9, -28, 28))
        parts.append(("y", i * 9, -28, 28))
    objs = make_interior_shell(
        w,
        d,
        height=h,
        floor_color=(0.16, 0.08, 0.14),
        wall_color=(0.32, 0.12, 0.22),
        ceiling_color=(0.12, 0.06, 0.1),
        door_width=2.4,
        partitions=parts,
    )
    machines = pick_paths(["arcade"], include=["machine", "arcade", "gambling", "pinball", "claw"], limit=16)
    objs += place_many(machines, jittered_fill(rng, 36, 26, 5, 3.0), "Slot", (1.5, 2.8), rng, mode="height", yaw_mode="face_south")
    return objs


def build_ghost_train(rng, size):
    objs = [make_ground(size, (0.24, 0.24, 0.26))]
    objs.append(make_patch(0, 0, size * 0.9, 16, (0.18, 0.18, 0.18), "Railbed"))
    rails = pick_paths(["train"], include=["railroad-straight", "railroad-rail-straight", "railroad-curve", "railroad-corner"], exclude=["damaged"], limit=30)
    cars = pick_paths(["train"], include=["locomotive", "wagon", "carriage", "cargo", "train"], limit=24)
    station = pick_paths(["train", "industrial"], include=["station", "building", "signal", "platform"], limit=16)
    objs += place_many(rails, line_positions(16, (-80, 0), (80, 0)), "Rail", (8, 12), rng, mode="foot", yaw_mode="along_x")
    objs += place_many(cars, line_positions(8, (-60, 0), (60, 0)), "Car", (10, 16), rng, mode="foot", yaw_mode="along_x")
    objs += place_many(station, [(-70, 22), (70, 22), (-70, -22), (70, -22)], "Station", (12, 20), rng, mode="foot", yaw_mode="face_center")
    return objs


def build_arena(rng, size):
    objs = [make_ground(size, (0.45, 0.32, 0.22))]
    objs.append(make_patch(0, 0, 50, 50, (0.55, 0.40, 0.28), "Sand"))
    walls = pick_paths(["arena", "castle", "marble"], include=["wall", "border", "gate", "column", "stairs"], limit=30)
    props = pick_paths(["arena", "dungeon"], include=["statue", "banner", "weapon", "trophy", "barrel", "chest"], limit=24)
    objs += place_many(walls, ellipse_positions(20, 48, 42), "ArenaWall", (8, 14), rng, mode="height", yaw_mode="face_center")
    objs += place_many(props, ring_positions(12, 20), "ArenaProp", (2, 5), rng, mode="max", yaw_mode="face_center")
    objs += place_many(props, jittered_fill(rng, 16, 18, 4, 3.0), "Center", (1.5, 4.0), rng, yaw_mode="face_center")
    return objs


BUILDERS = {
    "abandoned_supermarket": (build_supermarket, 150, (0.35, 0.40, 0.48)),
    "underground_parking": (build_parking, 160, (0.12, 0.12, 0.14)),
    "abandoned_cruise": (build_cruise, 170, (0.45, 0.62, 0.78)),
    "nuclear_plant": (build_nuclear, 180, (0.35, 0.42, 0.28)),
    "museum": (build_museum, 150, (0.55, 0.55, 0.58)),
    "casino_ruins": (build_casino, 150, (0.08, 0.05, 0.14)),
    "egypt_pyramid": (build_egypt, 180, (0.72, 0.58, 0.32)),
    "japanese_shrine": (build_shrine, 160, (0.45, 0.62, 0.75)),
    "pirate_island": (build_pirate_island, 180, (0.45, 0.70, 0.85)),
    "space_station": (build_space_station, 150, (0.05, 0.05, 0.08)),
    "cyberpunk_district": (build_cyberpunk, 180, (0.08, 0.10, 0.18)),
    "bio_lab": (build_bio_lab, 150, (0.20, 0.35, 0.28)),
    "time_rift": (build_time_rift, 160, (0.25, 0.12, 0.35)),
    "abandoned_hospital": (build_hospital, 150, (0.45, 0.48, 0.50)),
    "haunted_amusement": (build_amusement, 180, (0.10, 0.08, 0.12)),
    "deep_sea_wreck": (build_deep_sea, 170, (0.04, 0.10, 0.18)),
    "jungle_ruins": (build_jungle, 180, (0.25, 0.45, 0.55)),
    "snow_camp": (build_snow, 160, (0.70, 0.80, 0.90)),
    "volcano_mine": (build_volcano, 170, (0.25, 0.12, 0.08)),
    "spirit_forest": (build_spirit, 180, (0.15, 0.25, 0.35)),
    "inverted_world": (build_inverted, 150, (0.40, 0.25, 0.55)),
    "mirror_level": (build_mirror, 150, (0.50, 0.55, 0.60)),
    "maze_casino": (build_maze_casino, 150, (0.10, 0.05, 0.12)),
    "ghost_train": (build_ghost_train, 200, (0.18, 0.18, 0.20)),
    "gamble_arena": (build_arena, 150, (0.45, 0.35, 0.22)),
}


INDOOR_MAPS = {
    "abandoned_supermarket",
    "underground_parking",
    "abandoned_cruise",
    "nuclear_plant",
    "museum",
    "casino_ruins",
    "space_station",
    "bio_lab",
    "abandoned_hospital",
    "deep_sea_wreck",
    "volcano_mine",
    "maze_casino",
}


def build_map(map_id: str) -> str:
    builder, size, _sky = BUILDERS[map_id]
    seed = 20261104 + abs(hash(map_id)) % 9000
    rng = random.Random(seed)
    clear_scene()
    ensure_collection("Library")
    log(f"=== BUILD {map_id} layout={builder.__name__} size={size} ===")
    objs = builder(rng, size)
    # Indoor: spawn just inside the south doorway, looking into the hall (+Y).
    if map_id in INDOOR_MAPS:
        add_spawn_marker(0.0, -22.0, 0.0)
    else:
        add_spawn_marker(0.0, 8.0, 0.0)
    mesh_objs = [o for o in objs if o is not None and getattr(o, "type", "") == "MESH"]
    apply_all_transforms(mesh_objs)
    return export_map(map_id)


def main(only_ids=None):
    os.makedirs(OUT_ROOT, exist_ok=True)
    os.makedirs(BLEND_ROOT, exist_ok=True)
    done, failed = [], []
    for map_id in BUILDERS:
        if only_ids and map_id not in only_ids:
            continue
        try:
            path = build_map(map_id)
            done.append((map_id, path))
        except Exception as e:
            log(f"FAIL {map_id}: {e}")
            import traceback

            traceback.print_exc()
            failed.append(map_id)
    log(f"DONE maps={len(done)} failed={failed}")
    for mid, path in done:
        log(f"OK {mid} {path}")


if __name__ == "__main__":
    import sys

    ids = []
    if "--" in sys.argv:
        ids = [a for a in sys.argv[sys.argv.index("--") + 1 :] if a and not a.startswith("-")]
    ids = [a for a in ids if not a.lower().endswith(".py")]
    main(ids or None)

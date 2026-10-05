"""Build a continuous skinned hand from MakeHuman's CC0 base graphical mesh.

Run with Blender 4.5 in background mode. Source OBJ and provenance live under
tools/source_assets/makehuman. The generated GLB is project-authored adaptation.
"""
import bpy
import bmesh
import json
from math import exp
from collections import defaultdict, deque
from mathutils import Vector
from pathlib import Path

ROOT = Path("/home/gc/workspace/paper_war")
SOURCE = ROOT / "tools/source_assets/makehuman/base.obj"
OUT = ROOT / "assets/creator_hand"
OUT.mkdir(parents=True, exist_ok=True)
SOURCE_OUTPUT = ROOT / "tools/source_assets/creator_hand_source.blend"


def source_geometry():
    vertices = []
    faces = []
    helper_vertices = defaultdict(set)
    group = ""
    with SOURCE.open("r", encoding="utf-8") as stream:
        for line in stream:
            if line.startswith("v "):
                vertices.append(Vector(tuple(float(v) for v in line.split()[1:4])))
            elif line.startswith("g "):
                group = line.split()[1]
            elif line.startswith("f "):
                ids = [int(word.split("/")[0]) - 1 for word in line.split()[1:]]
                if group == "body":
                    if any(vertices[index].x > 3.5 for index in ids):
                        faces.append(ids)
                elif group.startswith("joint-l-"):
                    helper_vertices[group].update(ids)
    helpers = {
        name: sum((vertices[index] for index in indices), Vector()) / len(indices)
        for name, indices in helper_vertices.items() if indices
    }
    return vertices, faces, helpers


def hand_frame(helpers):
    wrist = helpers["joint-l-hand"]
    elbow = helpers["joint-l-elbow"]
    index = helpers["joint-l-finger-2-4"]
    middle = helpers["joint-l-finger-3-4"]
    thumb = helpers["joint-l-finger-1-2"]
    little = helpers["joint-l-finger-5-2"]
    axis = (wrist - elbow).normalized()
    forward = ((index + middle) * 0.5 - wrist).normalized()
    thumb_side = (thumb - little)
    thumb_side = (thumb_side - forward * thumb_side.dot(forward)).normalized()
    dorsal = thumb_side.cross(forward).normalized()
    thumb_side = forward.cross(dorsal).normalized()
    return wrist, axis, forward, dorsal, thumb_side


def round_wrist_cap(bm, boundaries, axis):
    # Build a compact elliptical heel from the open wrist loop. A flat filled
    # disc would read as a severed forearm in side view; four shrinking rings
    # close the hand without extending an arm beyond the wrist.
    if not boundaries:
        return
    start = boundaries[0].verts[0]
    ring = [start]
    prior = None
    current = start
    while True:
        candidates = [edge for edge in current.link_edges
                      if edge.is_boundary and edge != prior]
        if not candidates:
            raise RuntimeError("Wrist boundary is not a loop")
        edge = candidates[0]
        following = edge.other_vert(current)
        if following == start:
            break
        ring.append(following)
        prior, current = edge, following
        if len(ring) > len(boundaries):
            raise RuntimeError("Wrist boundary traversed twice")
    if len(ring) != len(boundaries):
        raise RuntimeError("Unexpected extra hand boundary")
    center = sum((vertex.co for vertex in ring), Vector()) / len(ring)
    previous = ring
    for retreat, width in [(0.035, 0.94), (0.090, 0.73),
                           (0.145, 0.42), (0.180, 0.13)]:
        next_ring = [bm.verts.new(center + (vertex.co - center) * width
                                  - axis * retreat) for vertex in ring]
        for i in range(len(ring)):
            j = (i + 1) % len(ring)
            bm.faces.new((previous[i], previous[j], next_ring[j], next_ring[i]))
        previous = next_ring
    pole = bm.verts.new(center - axis * 0.195)
    for i in range(len(ring)):
        bm.faces.new((previous[i], previous[(i + 1) % len(ring)], pole))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)


def create_hand_mesh(vertices, faces, helpers, scale=4.0):
    used = sorted({i for face in faces for i in face})
    remap = {old: index for index, old in enumerate(used)}
    mesh = bpy.data.meshes.new("AnatomicalHandSkin")
    mesh.from_pydata([vertices[i] for i in used], [], [[remap[i] for i in face] for face in faces])
    mesh.update()
    obj = bpy.data.objects.new("CreatorHandSkin", mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    wrist, axis, forward, dorsal, thumb_side = hand_frame(helpers)
    bmesh.ops.bisect_plane(
        bm,
        geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
        dist=0.00001,
        plane_co=wrist + axis * 0.20,
        plane_no=axis,
        clear_inner=True,
        clear_outer=False,
    )
    bm.verts.ensure_lookup_table()
    tip = helpers["joint-l-finger-2-4"]
    seed = min(bm.verts, key=lambda v: (v.co - tip).length_squared)
    keep = {seed}
    queue = deque([seed])
    while queue:
        current = queue.popleft()
        for edge in current.link_edges:
            other = edge.other_vert(current)
            if other not in keep:
                keep.add(other)
                queue.append(other)
    outside = [v for v in bm.verts if v not in keep]
    if outside:
        bmesh.ops.delete(bm, geom=outside, context="VERTS")
    boundaries = [edge for edge in bm.edges if edge.is_boundary]
    print("HAND_CROP", "precap_verts", len(bm.verts), "faces", len(bm.faces), "boundary_edges", len(boundaries))
    round_wrist_cap(bm, boundaries, axis)
    print("HAND_MANIFOLD", "remaining_boundary_edges", sum(edge.is_boundary for edge in bm.edges))
    # Blender is Z-up, while glTF/Godot is Y-up. These Blender coordinates
    # export as Godot +X to fingertips, +Y dorsal, +Z toward the thumb.
    for vert in bm.verts:
        delta = vert.co - wrist
        vert.co = Vector((delta.dot(forward), -delta.dot(thumb_side), delta.dot(dorsal))) * scale
        x = vert.co.x
        if 0.8 < x < 4.3 and vert.co.z > 0.0:
            spread = smoothstep(0.8, 3.8, x)
            end_fade = 1.0 - smoothstep(3.65, 4.3, x)
            surface = smoothstep(0.0, 0.45, vert.co.z)
            ridge = 0.0
            # Four broad, low dorsal metacarpal ridges blend into actual
            # anatomical knuckles. The skin remains one continuous surface.
            for lateral, height in [(-0.58, 0.10), (0.36, 0.11),
                                    (1.08, 0.08), (1.74, 0.05)]:
                path = lateral * (0.22 + 0.78 * spread)
                ridge += height * exp(-((vert.co.y - path) / 0.24) ** 2)
            vert.co.z += ridge * surface * end_fade * spread
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj.location = (0, 0, 0)
    transformed_helpers = {
        name: Vector(((point - wrist).dot(forward),
                      -(point - wrist).dot(thumb_side),
                      (point - wrist).dot(dorsal))) * scale
        for name, point in helpers.items()
    }
    return obj, transformed_helpers


FINGERS = {
    1: "Thumb", 2: "Index", 3: "Middle", 4: "Ring", 5: "Little",
}


def make_armature(helpers):
    armature = bpy.data.armatures.new("CreatorHandBones")
    rig = bpy.data.objects.new("CreatorHandRig", armature)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    palm = armature.edit_bones.new("Palm")
    palm.head = Vector((0, 0, 0))
    palm.tail = Vector((2.3, 0, 0))
    palm.align_roll(Vector((0, -1, 0)))
    for number, label in FINGERS.items():
        points = [helpers[f"joint-l-finger-{number}-{part}"] for part in range(1, 5)]
        parent = palm
        for index in range(3):
            bone = armature.edit_bones.new(f"{label}{['Proximal','Middle','Distal'][index]}")
            bone.head = points[index]
            bone.tail = points[index + 1]
            bone.parent = parent
            bone.use_connect = False
            bone.align_roll(Vector((0, -1, 0)))
            parent = bone
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    return rig


def nearest_polyline(point, points):
    cumulative = 0.0
    best = (float("inf"), 0.0)
    for index in range(3):
        start, end = points[index], points[index + 1]
        span = end - start
        length = span.length
        t = max(0.0, min(1.0, (point - start).dot(span) / (length * length)))
        nearest = start + span * t
        squared = (point - nearest).length_squared
        if squared < best[0]:
            best = (squared, cumulative + t * length)
        cumulative += length
    first_direction = (points[1] - points[0]).normalized()
    raw_root = (point - points[0]).dot(first_direction)
    return best[0], best[1], raw_root


def smoothstep(edge0, edge1, value):
    x = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return x * x * (3.0 - 2.0 * x)


def rig_weights(hand, rig, helpers):
    groups = {"Palm": hand.vertex_groups.new(name="Palm")}
    for label in FINGERS.values():
        for suffix in ("Proximal", "Middle", "Distal"):
            name = label + suffix
            groups[name] = hand.vertex_groups.new(name=name)
    points_by_finger = {
        number: [helpers[f"joint-l-finger-{number}-{part}"] for part in range(1, 5)]
        for number in FINGERS
    }
    for vertex in hand.data.vertices:
        candidate = min(
            FINGERS,
            key=lambda digit: nearest_polyline(vertex.co, points_by_finger[digit])[0],
        )
        points = points_by_finger[candidate]
        squared, distance, raw_root = nearest_polyline(vertex.co, points)
        root_width = 0.48 if candidate == 1 else 0.29
        strength = smoothstep(-root_width, root_width * 0.85, raw_root)
        # Keep palm webbing and thenar volume tied to the palm, while the
        # distal phalanges remain fully articulated.
        radius = 0.58 if candidate == 1 else 0.34
        if squared > radius ** 2:
            strength *= max(0.0, 1.0 - (squared ** 0.5 - radius) / (0.28 if candidate == 1 else 0.22))
        if strength < 0.001:
            groups["Palm"].add([vertex.index], 1.0, "REPLACE")
            continue
        groups["Palm"].add([vertex.index], 1.0 - strength, "REPLACE")
        lengths = [(points[i + 1] - points[i]).length for i in range(3)]
        first = lengths[0]
        second = first + lengths[1]
        blend = 0.22 if candidate == 1 else 0.14
        if distance < first - blend:
            segment_weights = (1.0, 0.0, 0.0)
        elif distance < first + blend:
            t = smoothstep(first - blend, first + blend, distance)
            segment_weights = (1.0 - t, t, 0.0)
        elif distance < second - blend:
            segment_weights = (0.0, 1.0, 0.0)
        elif distance < second + blend:
            t = smoothstep(second - blend, second + blend, distance)
            segment_weights = (0.0, 1.0 - t, t)
        else:
            segment_weights = (0.0, 0.0, 1.0)
        label = FINGERS[candidate]
        for suffix, weight in zip(("Proximal", "Middle", "Distal"), segment_weights):
            if weight > 0.0001:
                groups[label + suffix].add([vertex.index], strength * weight, "REPLACE")
    hand.parent = rig
    modifier = hand.modifiers.new("SkeletonSkin", "ARMATURE")
    modifier.object = rig


def make_materials(hand):
    skin = bpy.data.materials.new("CreatorSkin")
    skin.use_nodes = True
    shader = skin.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.50, 0.26, 0.19, 1.0)
    shader.inputs["Roughness"].default_value = 0.87
    shader.inputs["Subsurface Weight"].default_value = 0.10
    hand.data.materials.append(skin)
    nail = bpy.data.materials.new("CreatorNail")
    nail.use_nodes = True
    shader = nail.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (0.65, 0.43, 0.37, 1.0)
    shader.inputs["Roughness"].default_value = 0.73
    hand.data.materials.append(nail)


def finish_mesh(hand, helpers):
    bpy.context.view_layer.objects.active = hand
    hand.select_set(True)
    subdivision = hand.modifiers.new("AnatomicalSubdivision", "SUBSURF")
    subdivision.levels = 1
    subdivision.render_levels = 1
    hand.modifiers.move(len(hand.modifiers) - 1, 0)
    # Apply subdivision before export so the GLB carries a genuinely round
    # surface and interpolated skin weights, independent of runtime modifiers.
    bpy.ops.object.modifier_apply(modifier=subdivision.name)
    for polygon in hand.data.polygons:
        polygon.use_smooth = True
    # Paint the nail plate on the continuous distal surface. It follows skin
    # topology and adds no protruding oval mesh or free floating edge.
    for polygon in hand.data.polygons:
        point = polygon.center
        if polygon.normal.z < 0.32:
            continue
        for number in FINGERS:
            middle = helpers[f"joint-l-finger-{number}-3"]
            tip = helpers[f"joint-l-finger-{number}-4"]
            direction = (tip - middle).normalized()
            projected = (point - middle).dot(direction)
            cross = ((point - middle) - direction * projected).length
            span = (tip - middle).length
            if span * 0.42 <= projected <= span * 0.90 and cross < (0.18 if number == 1 else 0.16):
                polygon.material_index = 1
                break
    hand.select_set(False)


def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    vertices, faces, helpers = source_geometry()
    hand, transformed = create_hand_mesh(vertices, faces, helpers)
    make_materials(hand)
    rig = make_armature(transformed)
    rig_weights(hand, rig, transformed)
    finish_mesh(hand, transformed)
    stats = {
        "verts": len(hand.data.vertices),
        "faces": len(hand.data.polygons),
        "bounds": [[round(min(v.co[i] for v in hand.data.vertices), 3),
                    round(max(v.co[i] for v in hand.data.vertices), 3)] for i in range(3)],
    }
    print("HAND_MESH", stats)
    for finger in range(1, 6):
        print("FINGER_HELPERS", finger,
              [tuple(round(v, 3) for v in transformed[f"joint-l-finger-{finger}-{part}"])
               for part in range(1, 5)])
    # glTF converts Blender (X,Y,Z) to Godot (X,Z,-Y).
    godot_points = {
        label: [[round(float(point[0]), 6), round(float(point[2]), 6), round(float(-point[1]), 6)]
                for point in [transformed[f"joint-l-finger-{number}-{part}"] for part in range(1, 5)]]
        for number, label in FINGERS.items()
    }
    (OUT / "rig.json").write_text(json.dumps({
        "schema": 1,
        "source": "MakeHuman Community CC0 graphical basemesh",
        "source_commit": "a8bc2d54ff0ac92e78ff71431b1023eda42bf482",
        "bone_names": ["Palm"] + [label + suffix for label in FINGERS.values()
                                  for suffix in ("Proximal", "Middle", "Distal")],
        "finger_joints_godot": godot_points,
        "foot_digits": ["Index", "Middle"],
        "mesh_vertices": len(hand.data.vertices),
        "mesh_faces": len(hand.data.polygons),
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_OUTPUT))
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    hand.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / "creator_hand.glb"),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_skins=True,
        export_animations=False,
    )


if __name__ == "__main__":
    main()

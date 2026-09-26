"""Deposit asset pipeline for Blender: build meshes, bake colour + mask, export OBJ.

Blender is Z-up; export writes Godot's Y-up. Cluster units: ~1 across, feet
a little below 0.
"""
import bpy
import bmesh
import math
import random
import os
import numpy as np
from mathutils import Vector, Matrix, noise

OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "models", "deposits"))
WORK = "WORK"


# ---------------------------------------------------------------- scene -----

def work_collection():
    col = bpy.data.collections.get(WORK)
    if col is None:
        col = bpy.data.collections.new(WORK)
        bpy.context.scene.collection.children.link(col)
    return col


def clear():
    col = work_collection()
    for ob in list(col.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        if me.users == 0:
            bpy.data.meshes.remove(me)


SLOTS = 8


def _slotted_mesh(name):
    """A mesh with empty material slots, so material indices survive
    to_mesh / from_mesh (Blender clamps them to the slots there are)."""
    me = bpy.data.meshes.new(name)
    for _ in range(SLOTS):
        me.materials.append(None)
    return me


def to_object(name, bm, x_offset=0.0):
    me = _slotted_mesh(name)
    # Every part facing outward (tubes and rings come out inside-out).
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    work_collection().objects.link(ob)
    ob.location.x = x_offset
    return ob


# ---------------------------------------------------------------- parts -----
# Every part adds geometry to `bm` with material index `mat` and smooth flag.

def _faces_set(faces, mat, smooth):
    for f in faces:
        f.material_index = mat
        f.smooth = smooth


def ring_grid(bm, rings, mat, smooth=True, cap_start=False, cap_end=False):
    """rings: list of lists of Vector (open rings, closed round)."""
    verts = [[bm.verts.new(p) for p in ring] for ring in rings]
    faces = []
    n = len(rings[0])
    for i in range(len(verts) - 1):
        for k in range(n):
            a, b = verts[i][k], verts[i][(k + 1) % n]
            c, d = verts[i + 1][(k + 1) % n], verts[i + 1][k]
            faces.append(bm.faces.new((a, b, c, d)))
    if cap_start:
        faces.append(bm.faces.new(list(reversed(verts[0]))))
    if cap_end:
        faces.append(bm.faces.new(verts[-1]))
    _faces_set(faces, mat, smooth)
    return verts, faces


def frame_for(axis):
    axis = axis.normalized()
    helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    side = axis.cross(helper).normalized()
    other = axis.cross(side)
    return side, other


def crystal(bm, base, axis, width, length, twist, mat, sides=6, shoulder=0.72, top_scale=1.0):
    axis = axis.normalized()
    side, other = frame_for(axis)
    bottom, top = [], []
    for k in range(sides):
        a = twist + math.tau * k / sides
        spoke = (side * math.cos(a) + other * math.sin(a)) * width
        bottom.append(base + spoke)
        top.append(base + axis * (length * shoulder) + spoke * top_scale)
    tip = base + axis * length
    vb = [bm.verts.new(p) for p in bottom]
    vt = [bm.verts.new(p) for p in top]
    vtip = bm.verts.new(tip)
    faces = []
    for k in range(sides):
        n = (k + 1) % sides
        faces.append(bm.faces.new((vb[k], vb[n], vt[n], vt[k])))
        faces.append(bm.faces.new((vt[k], vt[n], vtip)))
    faces.append(bm.faces.new(list(reversed(vb))))
    _faces_set(faces, mat, False)


def tube(bm, path, radii, sides, mat, smooth=True, cap=True):
    rings = []
    normal = None
    for i, p in enumerate(path):
        t = (path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]).normalized()
        if normal is None:
            normal = t.cross(Vector((1, 0, 0)) if abs(t.x) < 0.9 else Vector((0, 1, 0))).normalized()
        else:
            normal = (normal - t * normal.dot(t)).normalized()
        bi = t.cross(normal)
        ring = []
        for k in range(sides):
            a = math.tau * k / sides
            ring.append(p + (normal * math.cos(a) + bi * math.sin(a)) * radii[i])
        rings.append(ring)
    return ring_grid(bm, rings, mat, smooth, cap_start=cap, cap_end=cap)


def curve(start, heading, length, axis, bend, steps=24):
    pts = [start.copy()]
    at = start.copy()
    way = heading.normalized()
    step = length / steps
    for i in range(steps):
        t = i / steps
        way = (Matrix.Rotation(bend(t) * step, 3, axis) @ way).normalized()
        at = at + way * step
        pts.append(at.copy())
    return pts


def blob(bm, centre, size, mat, seed, subdiv=3, rough=0.25, freq=1.6, smooth=True, flat_bottom=None, rot=None):
    """Noisy ico sphere: a rock. size is a Vector of half-extents."""
    tmp = bmesh.new()
    bmesh.ops.create_icosphere(tmp, subdivisions=subdiv, radius=1.0)
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    for v in tmp.verts:
        n = v.co.normalized()
        d = noise.fractal(n * freq + off, 0.6, 2.2, 5, noise_basis='PERLIN_ORIGINAL')
        ridge = noise.ridged_multi_fractal(n * freq * 1.7 + off, 0.8, 2.0, 3, 1.0, 2.0, noise_basis='PERLIN_ORIGINAL')
        r = 1.0 + rough * d + rough * 0.25 * (ridge - 1.0)
        p = Vector((n.x * size.x, n.y * size.y, n.z * size.z)) * r
        if rot is not None:
            p = rot @ p
        if flat_bottom is not None and p.z < flat_bottom:
            p.z = flat_bottom + (p.z - flat_bottom) * 0.15
        v.co = centre + p
    for f in tmp.faces:
        f.material_index = mat
        f.smooth = smooth
    _merge(bm, tmp)


def ball(bm, centre, radius, mat, segments=16, rings=10, scale=Vector((1, 1, 1)), rot=None):
    tmp = bmesh.new()
    bmesh.ops.create_uvsphere(tmp, u_segments=segments, v_segments=rings, radius=radius)
    for v in tmp.verts:
        p = Vector((v.co.x * scale.x, v.co.y * scale.y, v.co.z * scale.z))
        if rot is not None:
            p = rot @ p
        v.co = centre + p
    for f in tmp.faces:
        f.material_index = mat
        f.smooth = True
    _merge(bm, tmp)


def prism(bm, xform, corners, height, top_scale, mat, top_shift=(0.0, 0.0), smooth=False, bevel=0.0):
    cx = sum(c[0] for c in corners) / len(corners)
    cy = sum(c[1] for c in corners) / len(corners)
    tmp = bmesh.new()
    bot = [tmp.verts.new(xform @ Vector((c[0], c[1], 0.0))) for c in corners]
    top = []
    for c in corners:
        sx = cx + (c[0] - cx) * top_scale
        sy = cy + (c[1] - cy) * top_scale
        lift = height + (top_shift[0] * c[0] + top_shift[1] * c[1]) * height
        top.append(tmp.verts.new(xform @ Vector((sx, sy, lift))))
    n = len(corners)
    faces = [tmp.faces.new((bot[k], bot[(k + 1) % n], top[(k + 1) % n], top[k])) for k in range(n)]
    faces.append(tmp.faces.new(top))
    faces.append(tmp.faces.new(list(reversed(bot))))
    bmesh.ops.recalc_face_normals(tmp, faces=tmp.faces)
    if bevel > 0:
        bmesh.ops.bevel(tmp, geom=list(tmp.edges), offset=bevel, segments=1, affect='EDGES', profile=0.5)
    for f in tmp.faces:
        f.material_index = mat
        f.smooth = smooth
    _merge(bm, tmp)


def box(bm, xform, size, mat, bevel=0.0):
    hx, hy = size[0] * 0.5, size[1] * 0.5
    corners = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    prism(bm, xform @ Matrix.Translation((0, 0, -size[2] * 0.5)), corners, size[2], 1.0, mat, bevel=bevel)


def _merge(bm, tmp):
    me = _slotted_mesh("_tmp")
    tmp.to_mesh(me)
    tmp.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)


def displace_verts(bm, amount, freq, seed, mat=None):
    off = Vector((seed * 5.3, seed * 2.1, seed * 9.7))
    for v in bm.verts:
        if mat is not None and not any(f.material_index == mat for f in v.link_faces):
            continue
        n = v.normal
        d = noise.fractal(v.co * freq + off, 0.6, 2.0, 4, noise_basis='PERLIN_ORIGINAL')
        v.co += n * d * amount


# ------------------------------------------------------------- materials -----

class Nodes:
    """A bake material: `color` and `mask` sockets feed an emission shader."""

    def __init__(self, name):
        mat = bpy.data.materials.get(name)
        if mat is None:
            mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        self.mat = mat
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.x = 0
        out = self.new("ShaderNodeOutputMaterial")
        self.emit = self.new("ShaderNodeEmission")
        self.link(self.emit.outputs[0], out.inputs["Surface"])
        tc = self.new("ShaderNodeTexCoord")
        self.obj = tc.outputs["Object"]
        self.gen = tc.outputs["Generated"]

    def new(self, kind, **props):
        n = self.nt.nodes.new(kind)
        n.location = (self.x, 0)
        self.x -= 200
        for k, v in props.items():
            setattr(n, k, v)
        return n

    def link(self, a, b):
        self.nt.links.new(a, b)

    def image(self, name, scale=1.0, blend=0.35, offset=(0, 0, 0), vector=None, rot=(0, 0, 0)):
        tex = self.new("ShaderNodeTexImage", projection='BOX', projection_blend=blend)
        tex.image = bpy.data.images[name]
        mp = self.new("ShaderNodeMapping")
        mp.inputs["Scale"].default_value = (scale, scale, scale)
        mp.inputs["Location"].default_value = offset
        mp.inputs["Rotation"].default_value = rot
        self.link(vector if vector is not None else self.obj, mp.inputs["Vector"])
        self.link(mp.outputs[0], tex.inputs["Vector"])
        return tex

    def color(self, name, scale=1.0, **kw):
        return self.image(name + "_Diffuse", scale, **kw).outputs["Color"]

    def gray(self, name, scale=1.0, **kw):
        return self.image(name, scale, **kw).outputs["Color"]

    def noise(self, scale=4.0, detail=6.0, rough=0.6, dist=0.0, vector=None):
        n = self.new("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        n.inputs["Distortion"].default_value = dist
        self.link(vector if vector is not None else self.obj, n.inputs["Vector"])
        return n.outputs["Fac"]

    def voronoi(self, scale=5.0, feature='F1', dist_out="Distance", vector=None):
        n = self.new("ShaderNodeTexVoronoi", feature=feature)
        n.inputs["Scale"].default_value = scale
        self.link(vector if vector is not None else self.obj, n.inputs["Vector"])
        return n.outputs[dist_out]

    def ramp(self, fac, stops):
        r = self.new("ShaderNodeValToRGB")
        els = r.color_ramp.elements
        while len(els) > 1:
            els.remove(els[-1])
        for i, (pos, col) in enumerate(stops):
            e = els[0] if i == 0 else els.new(pos)
            e.position = pos
            e.color = col if len(col) == 4 else (*col, 1.0)
        self.link(fac, r.inputs["Fac"])
        return r.outputs["Color"]

    def mix(self, a, b, fac, blend='MIX'):
        m = self.new("ShaderNodeMix", data_type='RGBA', blend_type=blend)
        self._set(m.inputs[0], fac)
        self._set(m.inputs[6], a)
        self._set(m.inputs[7], b)
        return m.outputs[2]

    def math(self, op, a, b=0.0, clamp=True):
        m = self.new("ShaderNodeMath", operation=op, use_clamp=clamp)
        self._set(m.inputs[0], a)
        self._set(m.inputs[1], b)
        return m.outputs[0]

    def hsv(self, col, h=0.5, s=1.0, v=1.0):
        n = self.new("ShaderNodeHueSaturation")
        n.inputs["Hue"].default_value = h
        n.inputs["Saturation"].default_value = s
        n.inputs["Value"].default_value = v
        self.link(col, n.inputs["Color"])
        return n.outputs[0]

    def bw(self, col):
        n = self.new("ShaderNodeRGBToBW")
        self.link(col, n.inputs[0])
        return n.outputs[0]

    def ao(self, distance=0.25, low=0.4, power=1.0):
        n = self.new("ShaderNodeAmbientOcclusion", samples=16, only_local=True)
        n.inputs["Distance"].default_value = distance
        f = n.outputs["AO"]
        if power != 1.0:
            f = self.math('POWER', f, power)
        return self.math('MULTIPLY_ADD', f, 1.0 - low, clamp=False) if False else self._lerp(low, 1.0, f)

    def _lerp(self, a, b, f):
        m = self.new("ShaderNodeMapRange")
        self.link(f, m.inputs["Value"])
        m.inputs["To Min"].default_value = a
        m.inputs["To Max"].default_value = b
        return m.outputs[0]

    def pointiness(self, low=0.45, high=0.55):
        g = self.new("ShaderNodeNewGeometry")
        m = self.new("ShaderNodeMapRange")
        self.link(g.outputs["Pointiness"], m.inputs["Value"])
        m.inputs["From Min"].default_value = low
        m.inputs["From Max"].default_value = high
        return m.outputs[0]

    def rgb(self, col):
        n = self.new("ShaderNodeRGB")
        n.outputs[0].default_value = (*col, 1.0)
        return n.outputs[0]

    def shade(self, col, ao):
        return self.mix(col, ao, 1.0, 'MULTIPLY')

    def finish(self, color, mask=1.0):
        c = self.new("NodeReroute")
        c.label = "COLOR"
        self.link(color, c.inputs[0])
        m = self.new("NodeReroute")
        m.label = "MASK"
        if isinstance(mask, (int, float)):
            v = self.new("ShaderNodeValue")
            v.outputs[0].default_value = mask
            mask = v.outputs[0]
        self.link(mask, m.inputs[0])
        return self.mat

    def _set(self, sock, val):
        if isinstance(val, bpy.types.NodeSocket):
            self.link(val, sock)
        elif isinstance(val, (int, float)):
            sock.default_value = val if sock.type == 'VALUE' else (val, val, val, 1.0)
        else:
            sock.default_value = val if len(val) == 4 else (*val, 1.0)


def assign(ob, mats):
    """Materials into the existing slots, in place - clearing the slots
    would drop the faces' material indices."""
    me = ob.data
    for i, m in enumerate(mats):
        if i < len(me.materials):
            me.materials[i] = m
        else:
            me.materials.append(m)
    while len(me.materials) > max(len(mats), 1):
        me.materials.pop()


# ------------------------------------------------------------------ bake -----

def _select(objs):
    bpy.ops.object.mode_set(mode='OBJECT') if bpy.context.object and bpy.context.object.mode != 'OBJECT' else None
    for ob in bpy.context.view_layer.objects:
        ob.select_set(False)
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def unwrap(objs, margin=0.006):
    _select(objs)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=margin, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=margin, rotate=True)
    bpy.ops.object.mode_set(mode='OBJECT')


def _bake_pass(objs, img, which):
    for ob in objs:
        for mat in ob.data.materials:
            nt = mat.node_tree
            src = next(n for n in nt.nodes if n.type == 'REROUTE' and n.label == which)
            emit = next(n for n in nt.nodes if n.type == 'EMISSION')
            nt.links.new(src.outputs[0], emit.inputs["Color"])
            tgt = nt.nodes.get("BAKE_TARGET")
            if tgt is None:
                tgt = nt.nodes.new("ShaderNodeTexImage")
                tgt.name = "BAKE_TARGET"
                tgt.location = (400, 300)
            tgt.image = img
            nt.nodes.active = tgt
    _select(objs)
    bpy.ops.object.bake(type='EMIT', margin=16, use_clear=True)


def bake(objs, name, size=1024, samples=24):
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = samples
    scene.cycles.use_denoising = False
    try:
        scene.cycles.device = 'GPU'
    except Exception:
        pass
    imgs = {}
    for which in ("COLOR", "MASK"):
        iname = f"{name}_{which}"
        old = bpy.data.images.get(iname)
        if old:
            bpy.data.images.remove(old)
        img = bpy.data.images.new(iname, size, size, alpha=False, float_buffer=(which == "MASK"))
        img.colorspace_settings.name = 'sRGB' if which == "COLOR" else 'Non-Color'
        _bake_pass(objs, img, which)
        imgs[which] = img
    # Colour in RGB, mask in alpha.
    col = np.array(imgs["COLOR"].pixels[:], dtype=np.float32).reshape(size, size, 4)
    msk = np.array(imgs["MASK"].pixels[:], dtype=np.float32).reshape(size, size, 4)
    col[:, :, 3] = np.clip(msk[:, :, 0], 0.0, 1.0)
    iname = f"{name}_albedo"
    old = bpy.data.images.get(iname)
    if old:
        bpy.data.images.remove(old)
    out = bpy.data.images.new(iname, size, size, alpha=True)
    out.alpha_mode = 'STRAIGHT'
    out.pixels[:] = col.ravel()
    os.makedirs(OUT, exist_ok=True)
    out.filepath_raw = os.path.join(OUT, f"{name}_albedo.png")
    out.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.compression = 90
    out.save()
    return out


def export(objs, name):
    paths = []
    for i, ob in enumerate(objs):
        _select([ob])
        loc = ob.location.copy()
        ob.location = (0, 0, 0)
        bpy.context.view_layer.update()
        path = os.path.join(OUT, f"{name}_{i + 1}.obj")
        bpy.ops.wm.obj_export(
            filepath=path, export_selected_objects=True, export_materials=False,
            export_uv=True, export_normals=True, export_colors=False,
            forward_axis='NEGATIVE_Z', up_axis='Y', apply_modifiers=True,
            export_triangulated_mesh=True,
        )
        ob.location = loc
        paths.append(path)
    return paths


def preview(objs, name):
    """Show the bake on the objects for a viewport check."""
    img = bpy.data.images.get(f"{name}_albedo")
    pm = bpy.data.materials.get(f"PREVIEW_{name}") or bpy.data.materials.new(f"PREVIEW_{name}")
    pm.use_nodes = True
    nt = pm.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    for ob in objs:
        for i in range(len(ob.data.materials)):
            ob.data.materials[i] = pm
    return pm


def stats(objs):
    res = []
    for ob in objs:
        me = ob.data
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
        mn = [min(v[i] for v in bb) - ob.location[i] for i in range(3)]
        mx = [max(v[i] for v in bb) - ob.location[i] for i in range(3)]
        res.append(f"{ob.name}: {tris} tris, x {mn[0]:.2f}..{mx[0]:.2f} y {mn[1]:.2f}..{mx[1]:.2f} z {mn[2]:.2f}..{mx[2]:.2f}")
    return "\n".join(res)


def produce(name, builder, mats, variants=3, size=1024, spacing=2.2):
    """builder(bm, rng, variant) -> fills bm. mats: list of materials by index."""
    clear()
    objs = []
    for i in range(variants):
        rng = random.Random(hash((name, i)) & 0xFFFFFFFF)
        bm = bmesh.new()
        builder(bm, rng, i)
        ob = to_object(f"{name}_{i + 1}", bm, x_offset=i * spacing)
        assign(ob, mats)
        objs.append(ob)
    unwrap(objs)
    bake(objs, name, size)
    export(objs, name)
    preview(objs, name)
    return stats(objs)

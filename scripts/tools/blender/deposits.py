"""Per-type deposit looks: materials and builders for respipe.produce()."""
import math
import random
from mathutils import Vector, Matrix
import respipe as R

# ---------------------------------------------------------------- materials --


def rock_mat(name, tex="rock_surface", scale=1.6, hue=0.5, sat=0.6, val=0.85,
             vein=None, vein_scale=4.0, vein_width=0.06, mask=0.08):
    n = R.Nodes(name)
    col = n.hsv(n.color(tex, scale), 0.5 + (hue - 0.5), sat, val)
    # Large-scale mottling so it does not read as one flat photo.
    mott = n.ramp(n.noise(2.5, 4.0, 0.5), [(0.3, (0.8, 0.8, 0.8)), (0.7, (1.1, 1.1, 1.1))])
    col = n.mix(col, mott, 1.0, 'MULTIPLY')
    m = mask
    if vein is not None:
        d = n.voronoi(vein_scale, 'DISTANCE_TO_EDGE')
        # Distorted a little so the veins wander.
        v = n.math('LESS_THAN', d, vein_width)
        wob = n.math('GREATER_THAN', n.noise(3.0, 3.0, 0.6), 0.55)
        v = n.math('MULTIPLY', v, wob)
        col = n.mix(col, n.rgb(vein), v)
        m = n.math('MAXIMUM', v, mask)
    col = n.shade(col, n.ao(0.35, 0.35))
    return n.finish(col, m)


def metal_mat(name, dark, light, scratch_scale=3.0, noise_scale=6.0, mask=1.0, scratch=0.35):
    n = R.Nodes(name)
    base = n.ramp(n.noise(noise_scale, 6.0, 0.55, 0.4), [(0.35, dark), (0.7, light)])
    hi = 1.0 + scratch * 0.43
    lo = 1.0 - scratch * 0.57
    scratches = n.ramp(n.bw(n.gray("metal_plate_02_Rough", scratch_scale)), [(0.2, (hi, hi, hi)), (0.8, (lo, lo, lo))])
    col = n.mix(base, scratches, 1.0, 'MULTIPLY')
    edge = n.pointiness(0.48, 0.56)
    col = n.mix(col, n.hsv(col, 0.5, 0.95, 1.3), edge)
    col = n.shade(col, n.ao(0.2, 0.45))
    return n.finish(col, mask)


def crystal_mat(name, deep, bright, streak=(1.0, 1.0, 1.0), mask=1.0):
    n = R.Nodes(name)
    # Deep at the foot, bright toward the tips.
    sep = n.new("ShaderNodeSeparateXYZ")
    n.link(n.obj, sep.inputs[0])
    h = n.new("ShaderNodeMapRange")
    n.link(sep.outputs[2], h.inputs["Value"])
    h.inputs["From Min"].default_value = -0.1
    h.inputs["From Max"].default_value = 1.1
    col = n.ramp(h.outputs[0], [(0.0, deep), (1.0, bright)])
    # Milky streaks inside the crystal.
    veins = n.bw(n.color("marble_01", 2.5))
    streaks = n.ramp(veins, [(0.55, (0.0, 0.0, 0.0)), (0.85, (1.0, 1.0, 1.0))])
    col = n.mix(col, n.rgb(streak), n.math('MULTIPLY', n.bw(streaks), 0.55))
    col = n.mix(col, n.hsv(col, 0.5, 0.7, 1.4), n.pointiness(0.5, 0.58))
    col = n.shade(col, n.ao(0.18, 0.55))
    return n.finish(col, mask)


def tex_mat(name, tex, scale=2.0, hue=0.5, sat=1.0, val=1.0, mask=0.1, ao_low=0.4):
    n = R.Nodes(name)
    col = n.hsv(n.color(tex, scale), hue, sat, val)
    col = n.shade(col, n.ao(0.3, ao_low))
    return n.finish(col, mask)


def flat_mat(name, colour, noise=0.15, mask=1.0, ao_low=0.55):
    n = R.Nodes(name)
    col = n.ramp(n.noise(5.0, 4.0, 0.5), [(0.3, tuple(c * (1 - noise) for c in colour)), (0.7, tuple(min(c * (1 + noise), 1.0) for c in colour))])
    col = n.shade(col, n.ao(0.25, ao_low))
    return n.finish(col, mask)


# ---------------------------------------------------------------- helpers ----


def _on_blob(rng, size, centre, up_min=0.25):
    """A point on the upper part of an ellipsoid and its outward normal."""
    while True:
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(up_min, 1)))
        if d.length > 0.2:
            break
    d.normalize()
    p = Vector((d.x * size.x, d.y * size.y, d.z * size.z))
    nrm = Vector((d.x / size.x, d.y / size.y, d.z / size.z)).normalized()
    return centre + p, nrm


def _rock_base(bm, rng, size, seed, mat=0, z=0.1):
    centre = Vector((0, 0, z))
    R.blob(bm, centre, size, mat, seed, subdiv=5, rough=0.22, freq=1.4, flat_bottom=-(z + 0.05))
    return centre


def _crystal_cluster(bm, rng, origin, count, height, width, spread, mat, sides=6, lean=0.9):
    for i in range(count):
        a = rng.uniform(0, math.tau)
        out = Vector((math.cos(a), math.sin(a), 0))
        r = 0 if i == 0 else rng.uniform(0.25, 1.0) * spread
        foot = origin + out * r
        h = height * (1.0 if i == 0 else rng.uniform(0.35, 0.8))
        w = width * (1.25 if i == 0 else rng.uniform(0.7, 1.0))
        axis = (Vector((0, 0, 1)) + out * (0 if i == 0 else rng.uniform(0.3, lean))).normalized()
        R.crystal(bm, foot - axis * 0.2, axis, w, h + 0.2, rng.uniform(0, math.tau), mat, sides=sides,
                  shoulder=rng.uniform(0.65, 0.8), top_scale=rng.uniform(0.85, 1.0))


# ---------------------------------------------------------------- builders ---


def gold_ore(bm, rng, v):
    size = Vector((rng.uniform(0.45, 0.55), rng.uniform(0.38, 0.48), rng.uniform(0.24, 0.32)))
    centre = _rock_base(bm, rng, size, v * 7 + 3)
    for i in range(rng.randint(6, 9)):
        p, nrm = _on_blob(rng, size * 0.92, centre)
        s = rng.uniform(0.07, 0.15)
        rot = Matrix.Rotation(rng.uniform(0, 3), 3, Vector((rng.random(), rng.random(), rng.random())).normalized())
        R.blob(bm, p + nrm * s * 0.25, Vector((s, s * rng.uniform(0.6, 0.9), s * rng.uniform(0.5, 0.8))), 1,
               v * 31 + i, subdiv=3, rough=0.2, freq=1.5, rot=rot)


def silver_ore(bm, rng, v):
    size = Vector((rng.uniform(0.4, 0.5), rng.uniform(0.35, 0.45), rng.uniform(0.18, 0.24)))
    centre = _rock_base(bm, rng, size, v * 11 + 5)
    top = centre + Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), size.z * 0.7))
    _crystal_cluster(bm, rng, top, rng.randint(5, 8), rng.uniform(0.75, 0.95), 0.1, 0.3, 1)
    # A few small crystals poking out of the flanks.
    for i in range(rng.randint(2, 4)):
        p, nrm = _on_blob(rng, size * 0.9, centre, 0.0)
        R.crystal(bm, p - nrm * 0.05, (nrm + Vector((0, 0, 0.8))).normalized(), 0.05, rng.uniform(0.2, 0.35),
                  rng.uniform(0, 6), 1)


def pink_crystal(bm, rng, v):
    size = Vector((rng.uniform(0.32, 0.4), rng.uniform(0.3, 0.36), rng.uniform(0.12, 0.16)))
    centre = _rock_base(bm, rng, size, v * 13 + 9, z=0.03)
    top = centre + Vector((0, 0, size.z * 0.4))
    _crystal_cluster(bm, rng, top, rng.randint(6, 9), rng.uniform(0.95, 1.15), 0.13, 0.32, 1, lean=1.1)


def stone_mat(name, deep, light, scale=2.2, mask=1.0):
    n = R.Nodes(name)
    veins = n.bw(n.color("marble_01", scale))
    col = n.ramp(veins, [(0.35, deep), (0.8, light)])
    col = n.mix(col, n.hsv(col, 0.5, 0.8, 1.3), n.pointiness(0.5, 0.56))
    col = n.shade(col, n.ao(0.2, 0.5))
    return n.finish(col, mask)


def _xf(at, yaw=0.0, tilt=0.0, tilt_axis='X'):
    return Matrix.Translation(at) @ Matrix.Rotation(yaw, 4, 'Z') @ Matrix.Rotation(tilt, 4, tilt_axis)


def scrap(bm, rng, v):
    # An I-beam girder, one end dug in.
    g = _xf(Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 0.06)), rng.uniform(0, 6.3), rng.uniform(0.15, 0.35), 'Y')
    length = rng.uniform(1.0, 1.25)
    R.box(bm, g, (length, 0.03, 0.16), 0)
    R.box(bm, g @ Matrix.Translation((0, 0, 0.075)), (length, 0.15, 0.025), 0)
    R.box(bm, g @ Matrix.Translation((0, 0, -0.075)), (length, 0.15, 0.025), 0)
    # A pipe lying on its side.
    yaw = rng.uniform(0, 6.3)
    d = Vector((math.cos(yaw), math.sin(yaw), 0))
    start = Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0.07))
    plen = rng.uniform(0.55, 0.8)
    R.tube(bm, [start + d * (plen * t / 6) for t in range(7)], [0.075] * 7, 12, 1)
    R.tube(bm, [start + d * plen, start + d * (plen + 0.04)], [0.095, 0.095], 12, 1)
    # A plate bent in two.
    pyaw = rng.uniform(0, 6.3)
    at = Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0.01))
    R.box(bm, _xf(at, pyaw, -0.12), (0.45, 0.36, 0.035), 2)
    R.box(bm, _xf(at, pyaw) @ Matrix.Translation((0, -0.28, 0.1)) @ Matrix.Rotation(0.9, 4, 'X'), (0.45, 0.28, 0.035), 2)
    # A dented crate.
    if rng.random() < 0.75:
        s = rng.uniform(0.26, 0.34)
        R.box(bm, _xf(Vector((rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), s * 0.4)), rng.uniform(0, 6.3), rng.uniform(-0.15, 0.15)),
              (s, s, s), 3, bevel=0.015)


def gold_pillar(bm, rng, v):
    for i in range(rng.randint(3, 6)):
        a = rng.uniform(0, math.tau)
        reach = 0 if i == 0 else rng.uniform(0.2, 0.45)
        at = Vector((math.cos(a) * reach, math.sin(a) * reach, -0.4))
        radius = rng.uniform(0.12, 0.19) * (1.3 if i == 0 else 1.0)
        height = (rng.uniform(1.3, 1.9) if i == 0 else rng.uniform(0.6, 1.3)) + 0.4
        sides = 6 if rng.random() < 0.7 else 8
        twist = rng.uniform(0, 6.3)
        corners = [(math.cos(twist + math.tau * k / sides) * radius, math.sin(twist + math.tau * k / sides) * radius) for k in range(sides)]
        lean = Matrix.Rotation(rng.uniform(0, 0.12), 4, Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized())
        xf = Matrix.Translation(at) @ lean
        R.prism(bm, xf, corners, height, 0.92, 0, (rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25)), bevel=0.012)
        # Raised bands round the column.
        for b in range(rng.randint(1, 3)):
            h = 0.4 + (height - 0.5) * rng.uniform(0.15, 0.8)
            ring = [(x * 1.08, y * 1.08) for x, y in corners]
            R.prism(bm, xf @ Matrix.Translation((0, 0, h)), ring, 0.05, 1.0, 1, bevel=0.008)


def egg(bm, rng, v):
    import bmesh
    tmp = bmesh.new()
    bmesh.ops.create_uvsphere(tmp, u_segments=28, v_segments=18, radius=1.0)
    tilt = Matrix.Rotation(rng.uniform(0.05, 0.3), 3, Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized())
    for vert in tmp.verts:
        p = vert.co.copy()
        p.x *= 0.42 * (1.0 - 0.16 * p.z)
        p.y *= 0.42 * (1.0 - 0.16 * p.z)
        p.z *= 0.58
        vert.co = tilt @ p + Vector((0, 0, 0.46))
    for f in tmp.faces:
        f.smooth = True
        f.material_index = 0
    R._merge(bm, tmp)


def sky_stone(bm, rng, v):
    for i in range(rng.randint(2, 4)):
        a = rng.uniform(0, math.tau)
        at = Vector((math.cos(a), math.sin(a), 0)) * (0 if i == 0 else rng.uniform(0.25, 0.42))
        s = rng.uniform(0.22, 0.32) * (1.25 if i == 0 else 1.0)
        at.z = s * 0.3
        R.blob(bm, at, Vector((s, s * rng.uniform(0.8, 1.0), s * 0.62)), 0, v * 17 + i, subdiv=4, rough=0.08, freq=1.0)


def bone(bm, rng, v):
    spikes = rng.randint(3, 6)
    start = rng.uniform(0, math.tau)
    for i in range(spikes):
        a = start + math.tau * i / spikes + rng.uniform(-0.3, 0.3)
        out = Vector((math.cos(a), math.sin(a), 0))
        foot = out * rng.uniform(0.05, 0.22) + Vector((0, 0, -0.25))
        length = rng.uniform(1.1, 1.8)
        heading = (Vector((0, 0, 2.0)) + out * rng.uniform(0.2, 0.6)).normalized()
        axis = out.cross(Vector((0, 0, 1))).normalized()
        bend = rng.uniform(0.5, 1.1)
        path = R.curve(foot, heading, length, -axis, lambda t, b=bend: b * (0.6 + t))
        radii = [0.1 * (1 - (k / (len(path) - 1)) ** 0.8) + 0.008 for k in range(len(path))]
        # Knuckles along it.
        radii = [r * (1.0 + 0.08 * math.sin(k * 1.3)) for k, r in enumerate(radii)]
        R.tube(bm, path, radii, 10, 0)
    R.blob(bm, Vector((0, 0, -0.02)), Vector((0.3, 0.3, 0.17)), 0, v * 5 + 2, subdiv=4, rough=0.2, freq=2.0)


def toxic_ore(bm, rng, v):
    z = -0.1
    count = rng.randint(3, 5)
    for i in range(count):
        radius = (0.5 - 0.3 * i / count) * rng.uniform(0.85, 1.1)
        sides = rng.randint(6, 8)
        corners = []
        for k in range(sides):
            a = math.tau * k / sides + rng.uniform(-0.2, 0.2)
            corners.append((math.cos(a) * radius * rng.uniform(0.75, 1.15), math.sin(a) * radius * rng.uniform(0.75, 1.15)))
        th = rng.uniform(0.1, 0.16)
        tilt = Matrix.Rotation(rng.uniform(0, 0.15), 4, Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized())
        R.prism(bm, Matrix.Translation((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), z)) @ tilt, corners, th,
                rng.uniform(0.78, 0.9), 0, bevel=0.01)
        z += th * 0.85
    # Glowing green shards between the slabs.
    for i in range(rng.randint(3, 6)):
        a = rng.uniform(0, math.tau)
        out = Vector((math.cos(a), math.sin(a), 0))
        R.crystal(bm, out * rng.uniform(0.15, 0.35) + Vector((0, 0, rng.uniform(0.0, z * 0.6))),
                  (out + Vector((0, 0, 1.2))).normalized(), rng.uniform(0.04, 0.07), rng.uniform(0.25, 0.45), rng.uniform(0, 6), 1)


def ice_crystal(bm, rng, v):
    R.blob(bm, Vector((0, 0, -0.02)), Vector((0.4, 0.38, 0.12)), 0, v * 3 + 1, subdiv=4, rough=0.25, freq=1.8, flat_bottom=-0.08)
    for i in range(rng.randint(5, 8)):
        a = rng.uniform(0, math.tau)
        out = Vector((math.cos(a), math.sin(a), 0))
        axis = (Vector((0, 0, 2.5)) + out * (0 if i == 0 else rng.uniform(0.5, 1.4))).normalized()
        length = rng.uniform(1.3, 1.8) if i == 0 else rng.uniform(0.7, 1.3)
        R.crystal(bm, out * rng.uniform(0, 0.15) - axis * 0.2, axis, rng.uniform(0.06, 0.1), length + 0.2,
                  rng.uniform(0, 6), 1, sides=4, shoulder=0.18)


def slime_jelly(bm, rng, v):
    R.blob(bm, Vector((0, 0, 0.0)), Vector((0.47, 0.47, 0.52)), 0, v * 9 + 4, subdiv=4, rough=0.05, freq=1.2, flat_bottom=-0.05)
    for i in range(rng.randint(2, 4)):
        a = rng.uniform(0, math.tau)
        R.ball(bm, Vector((math.cos(a) * 0.22, math.sin(a) * 0.22, 0.34 + rng.uniform(0, 0.1))), rng.uniform(0.06, 0.1), 1)


def tumbleweed(bm, rng, v):
    centre = Vector((0, 0, 0.42))
    for i in range(rng.randint(14, 18)):
        axis = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
        helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
        startv = axis.cross(helper).normalized()
        radius = rng.uniform(0.32, 0.46)
        arc = rng.uniform(1.5, 3.5)
        frm = rng.uniform(0, math.tau)
        path = [centre + (Matrix.Rotation(frm + arc * k / 10, 3, axis) @ startv) * radius for k in range(11)]
        R.tube(bm, path, [rng.uniform(0.018, 0.026)] * 11, 5, 0)


def geyser(bm, rng, v):
    corners = [(math.cos(math.tau * k / 10) * 0.42 * rng.uniform(0.85, 1.1), math.sin(math.tau * k / 10) * 0.42 * rng.uniform(0.85, 1.1)) for k in range(10)]
    R.prism(bm, Matrix.Translation((0, 0, -0.2)), corners, 0.35, 0.45, 0, bevel=0.03, smooth=True)
    height = rng.uniform(2.5, 3.8)
    lean = Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 0))
    path, radii = [], []
    for k in range(17):
        t = k / 16
        path.append(Vector((0, 0, 0.1 + t * height)) + lean * t * t * height)
        radii.append((0.1 + 0.28 * t ** 0.7) * (1 - 0.7 * max(0.0, (t - 0.85) / 0.15)) * (1 + 0.1 * math.sin(k * 2.1)))
    R.tube(bm, path, radii, 12, 1)


def ice_wurm(bm, rng, v):
    # A segmented body arching out of the ice, head turned down and forward.
    foot = Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), -0.25))
    yaw = rng.uniform(0, math.tau)
    fwd = Vector((math.cos(yaw), math.sin(yaw), 0))
    axis = fwd.cross(Vector((0, 0, 1))).normalized()
    path = R.curve(foot, (Vector((0, 0, 1)) + fwd * 0.2).normalized(), rng.uniform(1.4, 1.8), axis,
                   lambda t: 1.9 * t, steps=32)
    radii = []
    for k in range(len(path)):
        t = k / (len(path) - 1)
        radii.append(0.15 * (1.0 - 0.25 * t) * (1.0 + 0.12 * math.cos(k * 1.2)))
    R.tube(bm, path, radii, 12, 0)
    head_dir = (path[-1] - path[-2]).normalized()
    R.ball(bm, path[-1] + head_dir * 0.04, 0.15, 0, scale=Vector((1.1, 1.1, 1.0)))
    # Mouth: a dark ring at the tip.
    R.tube(bm, [path[-1] + head_dir * 0.1, path[-1] + head_dir * 0.16], [0.1, 0.06], 12, 1)
    # Ice spines along its back.
    for k in range(4, len(path) - 4, 4):
        d = (path[k + 1] - path[k]).normalized()
        up = d.cross(axis).normalized()
        if up.z < 0:
            up = -up
        R.crystal(bm, path[k] + up * radii[k] * 0.6, (up + d * 0.3).normalized(), 0.03, 0.14, 0.0, 2, sides=4, shoulder=0.2)


def hel(bm, rng, v):
    for i in range(rng.randint(4, 7)):
        a = rng.uniform(0, math.tau)
        reach = 0 if i == 0 else rng.uniform(0.15, 0.4)
        radius = rng.uniform(0.22, 0.32) if i == 0 else rng.uniform(0.08, 0.2)
        R.ball(bm, Vector((math.cos(a) * reach, math.sin(a) * reach, rng.uniform(0.3, 0.9))), radius, 0, segments=20, rings=12)


def silver_spheres(bm, rng, v):
    turn = Matrix.Rotation(rng.uniform(0, 6.3), 3, 'Z')
    radius = rng.uniform(0.38, 0.48)
    path = [turn @ Vector((math.cos(math.pi * k / 24) * radius, 0, math.sin(math.pi * k / 24) * radius * 1.1 - 0.08)) for k in range(25)]
    R.tube(bm, path, [0.024] * 25, 8, 1)
    count = rng.randint(5, 7)
    for i in range(count):
        a = math.pi * (0.12 + 0.76 * (i + rng.uniform(-0.2, 0.2)) / (count - 1))
        at = turn @ Vector((math.cos(a) * radius, 0, math.sin(a) * radius * 1.1 - 0.08))
        R.ball(bm, at, rng.uniform(0.07, 0.11), 0, segments=20, rings=12)


TYPES = {}


def register():
    TYPES["scrap"] = (scrap, lambda: [
        tex_mat("scrap_girder", "rusty_metal_02", 2.0, mask=0.25),
        tex_mat("scrap_pipe", "metal_plate_02", 2.5, sat=0.6, mask=0.5),
        tex_mat("scrap_plate", "metal_plate_02", 1.5, mask=0.4),
        tex_mat("scrap_crate", "green_metal_rust", 2.0, mask=0.3),
    ])
    TYPES["gold_pillar"] = (gold_pillar, lambda: [
        metal_mat("pillar_gold", (0.75, 0.42, 0.06), (1.0, 0.7, 0.2), scratch_scale=3.0, noise_scale=3.0, scratch=0.1),
        metal_mat("pillar_band", (0.3, 0.12, 0.01), (0.6, 0.3, 0.04), scratch_scale=4.0, noise_scale=3.0, scratch=0.1),
    ])
    TYPES["egg"] = (egg, lambda: [flat_mat("egg_shell", (0.95, 0.88, 0.72), 0.06, mask=0.5, ao_low=0.8)])
    TYPES["sky_stone"] = (sky_stone, lambda: [stone_mat("sky_stone_mat", (0.02, 0.15, 0.5), (0.45, 0.85, 1.0))])
    TYPES["bone"] = (bone, lambda: [tex_mat("bone_mat", "white_stucco", 2.5, 0.5, 0.5, 1.05, mask=0.4, ao_low=0.5)])
    TYPES["toxic_ore"] = (toxic_ore, lambda: [
        rock_mat("toxic_rock", "dark_rock", 1.6, 0.5, 0.4, 0.55, vein=(0.35, 1.0, 0.3), vein_scale=2.5, vein_width=0.03, mask=0.0),
        crystal_mat("toxic_shard", (0.02, 0.2, 0.01), (0.25, 1.0, 0.15), (0.7, 1.0, 0.6)),
    ])
    TYPES["ice_crystal"] = (ice_crystal, lambda: [
        tex_mat("ice_snow", "snow_02", 1.5, 0.5, 0.5, 1.05, mask=0.2),
        crystal_mat("ice_spike", (0.08, 0.28, 0.6), (0.6, 0.85, 1.0), (1.0, 1.0, 1.0)),
    ])
    TYPES["slime_jelly"] = (slime_jelly, lambda: [
        flat_mat("jelly_body", (0.92, 1.0, 0.92), 0.12, ao_low=0.7),
        flat_mat("jelly_bubble", (1.0, 1.0, 1.0), 0.05, ao_low=0.8),
    ])
    TYPES["tumbleweed"] = (tumbleweed, lambda: [tex_mat("tumble_twig", "bark_willow_02", 3.0, 0.52, 0.7, 2.6, mask=0.0, ao_low=0.55)])
    TYPES["geyser"] = (geyser, lambda: [
        tex_mat("geyser_vent", "rock_08", 1.5, 0.5, 0.3, 1.2, mask=0.1),
        flat_mat("geyser_steam", (0.95, 0.97, 1.0), 0.08, mask=0.6, ao_low=0.85),
    ])
    TYPES["ice_wurm"] = (ice_wurm, lambda: [
        tex_mat("wurm_body", "snow_02", 2.0, 0.55, 0.6, 1.0, mask=0.5, ao_low=0.5),
        flat_mat("wurm_mouth", (0.25, 0.1, 0.2), 0.1, mask=0.0),
        crystal_mat("wurm_spine", (0.45, 0.65, 0.9), (0.95, 0.98, 1.0)),
    ])
    TYPES["hel"] = (hel, lambda: [flat_mat("hel_gas", (0.9, 0.5, 1.0), 0.2, ao_low=0.75)])
    TYPES["silver_spheres"] = (silver_spheres, lambda: [
        metal_mat("spheres_silver", (0.55, 0.58, 0.63), (0.97, 0.98, 1.0), scratch_scale=5.0),
        metal_mat("spheres_rod", (0.3, 0.32, 0.36), (0.6, 0.62, 0.66), scratch_scale=5.0),
    ])
    TYPES["gold_ore"] = (gold_ore, lambda: [
        rock_mat("gold_rock", "rock_surface", 1.8, 0.5, 0.55, 0.8, vein=(1.0, 0.6, 0.1), vein_scale=2.2, vein_width=0.018),
        metal_mat("gold_metal", (0.3, 0.12, 0.01), (1.0, 0.6, 0.1)),
    ])
    TYPES["silver_ore"] = (silver_ore, lambda: [
        rock_mat("silver_rock", "dark_rock", 1.6, 0.5, 0.35, 0.95, vein=(0.8, 0.83, 0.88), vein_scale=2.2, vein_width=0.015),
        crystal_mat("silver_crystal", (0.16, 0.18, 0.22), (0.78, 0.82, 0.9), (1.0, 1.0, 1.0)),
    ])
    TYPES["pink_crystal"] = (pink_crystal, lambda: [
        rock_mat("pink_rock", "dark_rock", 1.6, 0.5, 0.4, 0.7),
        crystal_mat("pink_crystal_mat", (0.3, 0.015, 0.12), (1.0, 0.3, 0.6), (1.0, 0.75, 0.88)),
    ])


register()


def make(name, variants=3, size=1024):
    builder, mats = TYPES[name]
    return R.produce(name, builder, mats(), variants, size)

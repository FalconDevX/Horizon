shader_type spatial;
render_mode unshaded, cull_back;

// Heightmap planet. The mesh is a unit cube-sphere whose object-space
// direction is the planet-space direction; the heightmap (six cube faces in a
// mipmapped texture array, baked on the GPU by PlanetTerrain.bake()) pushes
// each vertex out and picks the colour. Close up, the map is read bicubically
// and a procedural fractal carries the terrain on below its texels, faded out
// by the pixel footprint so nothing shimmers from afar. Liquid is flat:
// anything under sea_level is drawn at sea level with its own shallow-to-deep
// colour, gloss and optional glow (lava). Lit by hand from the sun, like
// planet_surface_3d.gdshader.

uniform sampler2DArray height_faces : filter_linear_mipmap, repeat_disable;
uniform float face_size = 1024.0;

// Highest ground above the sea (or above the lowest point on a dry world), as
// a fraction of the radius. Exaggerated on purpose.
uniform float relief : hint_range(0.0, 0.3) = 0.07;
// Extra steepness used only for shading, so relief that is small on the
// silhouette still reads as mountains in the light.
uniform float bump : hint_range(0.0, 30.0) = 5.0;

uniform bool has_liquid = true;
uniform float sea_level : hint_range(0.0, 1.0) = 0.5;
uniform bool is_gas = false;

// Height gradient: land_colors[i] (linear) at land_stops[i], 0 = shoreline.
uniform vec4 land_colors[6];
uniform float land_stops[6];

uniform vec3 liquid_shallow : source_color = vec3(0.1, 0.5, 0.6);
uniform vec3 liquid_deep : source_color = vec3(0.0, 0.05, 0.2);
uniform float liquid_emission : hint_range(0.0, 4.0) = 0.0;
// How much of a glowing liquid is crusted over (lava's cooling skin, acid
// scum). 0 leaves the glow bare.
uniform float liquid_crust : hint_range(0.0, 1.0) = 1.0;
// What the crust is made of: cooled rock on lava, crystals on acid.
uniform vec3 crust_color : source_color = vec3(0.2, 0.19, 0.18);
// Bubbles swelling and popping all over the liquid. 0 = none.
uniform float boil : hint_range(0.0, 1.0) = 0.0;
uniform vec3 boil_color : source_color = vec3(0.6, 1.0, 0.4);
// Cells per unit of planet-space direction - higher means smaller bubbles.
uniform float boil_scale = 60.0;
// Land that gives off light of its own, below `land_glow_band` (0..1 land
// height) - glowing lily pads. 0 = none.
uniform float land_glow : hint_range(0.0, 2.0) = 0.0;
uniform float land_glow_band : hint_range(0.0, 1.0) = 0.2;
uniform float liquid_gloss : hint_range(0.0, 1.0) = 0.8;

uniform vec3 rock_color : source_color = vec3(0.4);
uniform float slope_rock : hint_range(0.0, 1.0) = 0.5;
uniform float rock_patches : hint_range(0.0, 1.0) = 0.0;
// Sediment bands across exposed rock; 0 = plain rock.
uniform float strata : hint_range(0.0, 1.0) = 0.0;

// Arid biome laid over the lowlands where a moisture noise runs dry, favouring
// the subtropics like real deserts do.
uniform vec3 dry_color : source_color = vec3(0.6, 0.5, 0.35);
uniform float dry_amount : hint_range(0.0, 1.0) = 0.0;

// Polar caps start at this |latitude| (sine of it, 0..1); above 1 disables.
uniform vec3 cap_color : source_color = vec3(1.0);
uniform float cap_latitude = 2.0;
// The spin axis in planet space - where the poles and the giants' bands sit.
uniform vec3 pole_axis = vec3(0.0, 1.0, 0.0);

uniform vec3 atmo_color : source_color = vec3(0.4, 0.6, 1.0);
uniform float atmo_strength : hint_range(0.0, 3.0) = 0.6;
uniform float atmo_haze : hint_range(0.0, 1.0) = 0.0;

// Strength of the sub-texel fractal, 1 = continuing the baked one's falloff.
uniform float detail_strength : hint_range(0.0, 3.0) = 1.0;
uniform float seed_offset = 0.0;

uniform float ambient : hint_range(0.0, 1.0) = 0.04;
// Tips the sunlight up toward the camera - see planet_surface_3d.gdshader.
uniform float light_lift : hint_range(0.0, 2.0) = 0.35;
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.9);
// Lighting character. `light_wrap` lets light creep past a slope's own
// shadow edge, `terminator_softness` scales how gradually day turns to night
// (1 = default), `shade_contrast` steepens the diffuse falloff. Hard,
// theatrical worlds run 0 / ~0.15 / ~2.
uniform float light_wrap : hint_range(0.0, 1.0) = 0.15;
uniform float terminator_softness : hint_range(0.05, 2.0) = 1.0;
uniform float shade_contrast : hint_range(0.5, 4.0) = 1.0;

// Aurora uniforms live in planet_aurora.gdshaderinc (shared with the air).

// Glowing cracks drawn over the ground (not carved, so they can glow and need
// no match in the heightmap). 0 = none.
uniform float crack_strength : hint_range(0.0, 4.0) = 0.0;
uniform vec3 crack_color : source_color = vec3(1.0, 0.75, 0.3);
uniform float crack_scale = 6.0;
uniform float crack_width = 0.03;
// Threshold on a slow noise: -1 cracks everywhere, 1 almost nowhere.
uniform float crack_coverage = 0.0;
// A second, finer network in its own colour, laid through the first. 0 = none.
uniform float crack_twin : hint_range(0.0, 1.0) = 0.0;
uniform vec3 crack_color_b : source_color = vec3(0.8, 0.05, 0.1);
uniform float crack_scale_b = 10.0;

// Placed features the bake carved (see PlanetTerrain.sigil_arrays()), coloured
// here. `sigil_mode` mirrors PlanetTerrain.FeatureMode: 0 Occult eyes, 1 Swirl
// spirals, 2 Rings, 3 nothing to colour (Fractal, Lotus), 4 Terran snow humps.
// Array sizes mirror
// PlanetTerrain.MAX_SIGILS.
const int MAX_SIGILS = 24;
uniform int sigil_count = 0;
uniform int sigil_mode = 0;
// xyz planet-space centre, w angular radius.
uniform vec4 sigils[24];
// Eyes: x rotation, y pupil (0 round, 1 slit, 2 diamond; <0 tentacle nest,
// no eye), z drip count, w crater depth (bake only). Other modes: see the
// kind's roll in planet_terrain.gd.
uniform vec4 sigil_styles[24];
// Eyes: x tentacle count, y curl, z reach (sigil radii), w width.
uniform vec4 sigil_extra[24];
uniform vec3 sigil_color : source_color = vec3(0.9, 0.05, 0.05);
uniform vec3 sigil_color_b : source_color = vec3(0.0);
uniform float sigil_glow : hint_range(0.0, 4.0) = 0.0;

// Quake scars: small silver jagged rings with spokes, scattered by cell. 0 = none.
// Rings volcanoes (the bake's volcano_cones): scorched ground round each cone,
// lava in the caldera and down the flanks. 0 = none.
uniform float volcano_strength : hint_range(0.0, 1.0) = 0.0;
uniform float volcano_scale = 5.0;
uniform float volcano_density : hint_range(0.0, 1.0) = 0.2;
uniform float volcano_shift = 0.0;
uniform vec3 volcano_ground : source_color = vec3(0.35, 0.22, 0.13);
uniform vec3 lava_color : source_color = vec3(1.0, 0.42, 0.08);
uniform float volcano_glow : hint_range(0.0, 4.0) = 1.8;

uniform float quake_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 quake_color : source_color = vec3(0.85, 0.87, 0.9);
uniform float quake_scale = 16.0;
uniform float quake_density : hint_range(0.0, 1.0) = 0.4;
// Scar radius as a share of a cell, rings per scar, spokes per scar.
uniform float quake_size : hint_range(0.1, 0.5) = 0.38;
uniform float quake_rings = 2.0;
uniform float quake_spokes = 6.0;
// Offset of the scar lattice, shared with the bake, which carves a hole under
// every scar.
uniform float quake_shift = 7.0;
// Light the scars give off (an active world's run hot).
uniform float quake_glow : hint_range(0.0, 3.0) = 0.12;

// Buds: small spiky green dots scattered over dry ground, thickest just above
// the waterline and never in it. 0 = none.
uniform float bud_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 bud_color : source_color = vec3(0.35, 0.6, 0.25);
// Cells per unit of planet-space direction - higher means smaller, more buds.
uniform float bud_scale = 100.0;
// Radius as a share of a cell, how spiky the outline is, and how many cells
// hold a bud where the ground is wettest.
uniform float bud_size : hint_range(0.05, 0.45) = 0.25;
uniform float bud_spike : hint_range(0.0, 0.4) = 0.12;
uniform float bud_density : hint_range(0.0, 1.0) = 0.5;
// How high above the waterline (in 0..1 height) the wet band reaches.
uniform float bud_reach : hint_range(0.0, 0.5) = 0.08;
// 1: grow in patches round the placed features (Rings' ring sets) instead of
// along the waterline.
uniform float bud_near_features : hint_range(0.0, 1.0) = 0.0;

// Mist pooling in the low ground and drifting. 0 = none.
uniform float mist_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 mist_color : source_color = vec3(0.8, 0.7, 1.0);
uniform float mist_height : hint_range(0.01, 1.0) = 0.25;

global uniform vec3 sun_position;

const int DETAIL_OCTAVES = 5;

varying vec3 v_dir;

// ---- heightmap ------------------------------------------------------------

// Mirror of PlanetTerrain.face_uv(): which face, and (u, v) on it.
vec3 face_uv(vec3 d) {
	vec3 a = abs(d);
	vec3 f;
	vec3 r;
	vec3 u;
	float face;

	if (a.x >= a.y && a.x >= a.z) {
		if (d.x > 0.0) { face = 0.0; f = vec3(1.0, 0.0, 0.0); r = vec3(0.0, 0.0, -1.0); u = vec3(0.0, 1.0, 0.0); }
		else { face = 1.0; f = vec3(-1.0, 0.0, 0.0); r = vec3(0.0, 0.0, 1.0); u = vec3(0.0, 1.0, 0.0); }
	} else if (a.y >= a.z) {
		if (d.y > 0.0) { face = 2.0; f = vec3(0.0, 1.0, 0.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 0.0, -1.0); }
		else { face = 3.0; f = vec3(0.0, -1.0, 0.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 0.0, 1.0); }
	} else {
		if (d.z > 0.0) { face = 4.0; f = vec3(0.0, 0.0, 1.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 1.0, 0.0); }
		else { face = 5.0; f = vec3(0.0, 0.0, -1.0); r = vec3(-1.0, 0.0, 0.0); u = vec3(0.0, 1.0, 0.0); }
	}

	float forward = dot(d, f);
	return vec3(dot(d, r) / forward, dot(d, u) / forward, face);
}

// Texel centres sit on the cube edges: u = -1 is the middle of the first one.
vec3 face_texcoord(vec3 d) {
	vec3 fuv = face_uv(d);
	vec2 uv = (fuv.xy * 0.5 + 0.5) * ((face_size - 1.0) / face_size) + 0.5 / face_size;
	return vec3(uv, fuv.z);
}

float height_lod(vec3 d, float lod) {
	return textureLod(height_faces, face_texcoord(d), lod).r;
}

// Cubic B-spline in four bilinear taps: smooth slopes, no bilinear creases.
float height_bicubic(vec3 d) {
	vec3 tc = face_texcoord(d);
	vec2 p = tc.xy * face_size - 0.5;
	vec2 i = floor(p);
	vec2 f = p - i;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;

	vec2 w0 = (-f3 + 3.0 * f2 - 3.0 * f + 1.0) / 6.0;
	vec2 w1 = (3.0 * f3 - 6.0 * f2 + 4.0) / 6.0;
	vec2 w2 = (-3.0 * f3 + 3.0 * f2 + 3.0 * f + 1.0) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 t0 = (i - 0.5 + w1 / g0) / face_size;
	vec2 t1 = (i + 1.5 + w3 / g1) / face_size;

	float s00 = textureLod(height_faces, vec3(t0.x, t0.y, tc.z), 0.0).r;
	float s10 = textureLod(height_faces, vec3(t1.x, t0.y, tc.z), 0.0).r;
	float s01 = textureLod(height_faces, vec3(t0.x, t1.y, tc.z), 0.0).r;
	float s11 = textureLod(height_faces, vec3(t1.x, t1.y, tc.z), 0.0).r;

	return g0.y * (g0.x * s00 + g1.x * s10) + g1.y * (g0.x * s01 + g1.x * s11);
}

// Bicubic up close, plain mipmapped once a texel is smaller than a pixel.
// The B-spline would read past a face's edge (clamped), so over the last few
// texels it hands over to bilinear, which the two faces share exactly.
float height_filtered(vec3 d, float lod) {
	if (lod >= 1.0) {
		return height_lod(d, lod);
	}
	vec3 fuv = face_uv(d);
	float to_edge = (1.0 - max(abs(fuv.x), abs(fuv.y))) * face_size * 0.5;
	float cubic = smoothstep(1.0, 3.0, to_edge);
	float bilinear = height_lod(d, 0.0);
	return cubic > 0.0 ? mix(bilinear, height_bicubic(d), cubic) : bilinear;
}

float ground(float h) {
	return has_liquid ? max(h - sea_level, 0.0) : h;
}

// ---- procedural noise (shading only; gameplay never sees it) ---------------

#include "res://planet_noise.gdshaderinc"
#include "res://planet_clouds.gdshaderinc"
#include "res://planet_aurora.gdshaderinc"
#include "res://planet_rings.gdshaderinc"

// The terrain below heightmap resolution: eroded fBm (octaves damped where
// the ones before are steep) with its gradient in planet space. xyz is the
// gradient, w the height.
vec4 detail(vec3 d, float frequency, float footprint) {
	float sum = 0.0;
	vec3 gradient = vec3(0.0);
	vec3 slope = vec3(0.0);
	float amplitude = 0.5;
	mat3 m = mat3(1.0);

	for (int i = 0; i < DETAIL_OCTAVES; i++) {
		float fade = octave_fade(frequency, footprint);
		if (fade <= 0.0) {
			break;
		}
		vec4 n = noised(m * d * frequency + seed_offset);
		// Back from the octave's twisted frame into planet space.
		vec3 g = transpose(m) * n.yzw * frequency;
		slope += n.yzw;
		float damp = 1.0 / (1.0 + dot(slope, slope) * 0.6);
		sum += amplitude * n.x * damp * fade;
		gradient += amplitude * g * damp * fade;
		m = ROT * m;
		frequency *= 2.03;
		amplitude *= 0.5;
	}

	return vec4(gradient, sum);
}

// Cheap value noise for colour grain.
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(
			mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x),
			f.y
		),
		mix(
			mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x),
			f.y
		),
		f.z
	);
}

vec3 land_gradient(float x) {
	vec3 c = land_colors[0].rgb;
	for (int i = 1; i < 6; i++) {
		c = mix(c, land_colors[i].rgb, smoothstep(land_stops[i - 1], land_stops[i], x));
	}
	return c;
}

// ---- drawn-on effects -------------------------------------------------------

float sd_segment(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

// Occult eye craters. The bake carves them (planet_terrain_bake.glsl); these
// mirror its sigil_frame(), eye_lens() and eye_parts() so the red staining
// and glow land exactly on the carved shapes.

// A sigil's own frame: radius-1 units, upright relative to the pole.
vec2 sigil_frame(vec3 d, vec4 s, float angle) {
	vec3 up = abs(dot(pole_axis, s.xyz)) < 0.95 ? pole_axis : vec3(1.0, 0.0, 0.0);
	vec3 east = normalize(cross(up, s.xyz));
	vec3 north = cross(s.xyz, east);
	// Azimuthal equidistant: |q| is the true angle from the centre, so big
	// features keep their shape out to the rim.
	vec2 flat_q = vec2(dot(d, east), dot(d, north));
	float across = length(flat_q);
	float arc = acos(clamp(dot(d, s.xyz), -1.0, 1.0));
	vec2 q = (across > 1e-6 ? flat_q * (arc / across) : flat_q) / s.w;
	return mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * q;
}

float eye_lens(vec2 q) {
	return max(length(q - vec2(0.0, -0.675)) - 1.125, length(q - vec2(0.0, 0.675)) - 1.125);
}

// x = how far inside the almond, y = pupil, z = drips, w = iris ring.
vec4 eye_parts(vec2 q, vec4 style) {
	float inside = 1.0 - smoothstep(-0.3, 0.0, eye_lens(q));

	float pupil_d;
	if (style.y < 0.5) {
		pupil_d = length(q) - 0.13;
	} else if (style.y < 1.5) {
		pupil_d = max(abs(q.x) - 0.05, abs(q.y) - 0.3);
	} else {
		pupil_d = abs(q.x) + abs(q.y) * 0.6 - 0.16;
	}
	float pupil = 1.0 - smoothstep(-0.03, 0.04, pupil_d);

	float drips_d = 1e3;
	int count = int(style.z);
	for (int i = 0; i < 5; i++) {
		if (i >= count) {
			break;
		}
		float x = (float(i) - float(count - 1) * 0.5) * 0.28;
		float length_i = 0.35 + 0.3 * fract(sin(float(i) * 12.9898 + style.x * 7.0) * 43758.5453);
		vec2 top = vec2(x, -0.3);
		vec2 end = vec2(x, -0.3 - length_i);
		drips_d = min(drips_d, min(sd_segment(q, top, end) - 0.04, length(q - end) - 0.08));
	}
	float drips = 1.0 - smoothstep(-0.02, 0.05, drips_d);

	float iris = exp(-pow((length(q) - 0.3) / 0.05, 2.0));
	if (style.y > 2.5) {
		// Closed (Occult's blind worlds): no pupil or iris, only the lid's
		// seam, drawn where the pupil would be.
		float seam = abs(q.y + 0.06 * (1.0 - q.x * q.x * 1.2));
		pupil = (1.0 - smoothstep(0.015, 0.045, seam)) * (1.0 - step(0.85, abs(q.x)));
		iris = 0.0;
	}
	return vec4(inside, pupil, drips, iris);
}

// Mirror of tentacle_ridges() in the bake: 0..1 across each tentacle.
float tentacle_ridges(vec2 q, vec4 t, float start, float phase) {
	float r = length(q);
	if (r < start || r > t.z) {
		return 0.0;
	}
	float theta = atan(q.y, q.x);
	float along = (r - start) / max(t.z - start, 1e-3);
	float height = 0.0;

	int count = int(t.x);
	for (int k = 0; k < 8; k++) {
		if (k >= count) {
			break;
		}
		float fk = float(k);
		float base = phase + fk * 6.2831853 / float(count) + 0.35 * sin(fk * 5.1 + phase);
		float path = base + t.y * along * along + 0.25 * sin(along * 7.0 + fk * 2.3);
		float off_path = abs(mod(theta - path + 3.14159265, 6.2831853) - 3.14159265) * r;
		float width = t.w * (1.0 - along) + 0.015;
		float across = clamp(off_path / width, 0.0, 1.0);
		float ridge = sqrt(1.0 - across * across);
		float suckers = 0.88 + 0.12 * sin(along * 55.0 + fk);
		height = max(height, ridge * sqrt(1.0 - along) * suckers);
	}
	return height;
}

// Every eye crater and tentacle at d: x = red stain (the bowl and the
// drips), y = glow (the iris only), z = the dark pupil, w = tentacle.
vec4 eyes_at(vec3 d) {
	vec4 total = vec4(0.0);
	for (int i = 0; i < MAX_SIGILS; i++) {
		if (i >= sigil_count) {
			break;
		}
		vec4 s = sigils[i];
		vec4 style = sigil_styles[i];
		vec4 t = sigil_extra[i];
		if (dot(d, s.xyz) < cos(min(s.w * (t.z + 0.3), 3.0))) {
			continue;
		}
		vec2 q = sigil_frame(d, s, style.x);
		bool has_eye = style.y > -0.5;
		float tentacle = tentacle_ridges(q, t, has_eye ? 0.95 : 0.2, style.x * 3.0 + float(i) * 1.7);
		if (has_eye) {
			vec4 e = eye_parts(q, style);
			total = max(total, vec4(max(e.x, e.z), e.w, e.y, tentacle));
		} else {
			total.w = max(total.w, max(tentacle, exp(-dot(q, q) / 0.09)));
		}
	}
	return total;
}

// Mirror of swirl_parts() in the bake: x = inside, y = arm (0 / 1),
// z = groove between arms, w = dome across an arm.
vec4 swirl_parts(vec2 q, vec4 style) {
	float r = length(q);
	float inside = 1.0 - smoothstep(0.85, 1.0, r);
	if (inside <= 0.0) {
		return vec4(0.0);
	}
	float theta = atan(q.y, q.x) * style.w;
	float u = r * style.y + style.z * theta / 6.2831853;
	float f = fract(u);
	float groove = 1.0 - smoothstep(0.0, 0.08, min(f, 1.0 - f));
	return vec4(inside, mod(floor(u), 2.0), groove, sin(f * 3.14159265));
}

// Mirror of ring_parts() in the bake: x = on a ring, y = ring index,
// z = inside the set.
vec3 ring_parts(vec2 q, vec4 style, vec4 extra) {
	float r = length(q);
	if (r > 1.0) {
		return vec3(0.0);
	}
	float x = r * style.y;
	float index = floor(x);
	float band = 1.0 - smoothstep(style.z * 0.5 - 0.06, style.z * 0.5, abs(fract(x) - 0.5));
	float phase = fract(sin((index + 1.0) * 12.9898 + style.x * 7.0) * 43758.5453);
	float along = fract(atan(q.y, q.x) / 6.2831853 * style.w + phase);
	band *= smoothstep(extra.x, extra.x + 0.04, along);
	return vec3(band, index, 1.0 - smoothstep(0.95, 1.0, r));
}

// The nearest placed feature's colour at d, for Swirl and Rings: rgb, and
// how much of it covers the ground in a.
// Terran snow humps (sigil_mode 4): 0..1 snow cover, with a ragged edge.
float snow_at(vec3 d) {
	float cover = 0.0;
	for (int i = 0; i < MAX_SIGILS; i++) {
		if (i >= sigil_count) {
			break;
		}
		vec4 s = sigils[i];
		if (dot(d, s.xyz) < cos(min(s.w * 1.3, 3.0))) {
			continue;
		}
		float r = length(sigil_frame(d, s, sigil_styles[i].x));
		r *= 1.0 + (value_noise(d * 60.0 + float(i) * 13.0) - 0.5) * 0.35;
		cover = max(cover, 1.0 - smoothstep(0.8, 1.0, r));
	}
	return cover;
}

vec4 feature_color_at(vec3 d) {
	vec4 best = vec4(0.0);
	for (int i = 0; i < MAX_SIGILS; i++) {
		if (i >= sigil_count) {
			break;
		}
		vec4 s = sigils[i];
		if (dot(d, s.xyz) < cos(min(s.w * 1.4, 3.0))) {
			continue;
		}
		vec4 style = sigil_styles[i];
		vec2 q = sigil_frame(d, s, style.x);
		if (sigil_mode == 1) {
			// The raised arm orange, brighter along its crest; the sunken one
			// only shaded toward `sigil_color_b`, deepest down its middle.
			vec4 w = swirl_parts(q, style);
			vec3 arm = mix(sigil_color * (0.75 + 0.35 * w.w), sigil_color_b, w.y);
			float cover = w.x * mix(0.92, 0.6 * w.w, w.y);
			if (cover > best.a) {
				best = vec4(arm, cover);
			}
		} else if (sigil_mode == 2) {
			// Rings alternate dark red and near black.
			vec3 ring = ring_parts(q, style, sigil_extra[i]);
			float cover = ring.x * ring.z;
			if (cover > best.a) {
				best = vec4(mix(sigil_color, sigil_color_b, mod(ring.y, 2.0)), cover);
			}
		}
	}
	return best;
}

// The nearest Rings volcano to d, on the bake's lattice (volcano_cones): x =
// distance from its centre in its own radii, y = its height share.
vec2 volcano_at(vec3 d) {
	vec3 p = d * volcano_scale + vec3(volcano_shift);
	vec3 cell = floor(p);
	vec3 local = p - cell;
	vec2 best = vec2(99.0, 0.0);
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 roll = hash3(cell + o + vec3(0.0, 0.0, 6143.0));
				if (roll.x > volcano_density) {
					continue;
				}
				vec3 r = o + 0.5 + (hash3(cell + o + vec3(0.0, 31.0, 0.0)) - 0.5) * 0.8 - local;
				float radius = mix(0.35, 0.6, roll.x / max(volcano_density, 1e-3));
				float dist = length(r) / radius;
				if (dist < best.x) {
					best = vec2(dist, mix(0.6, 1.0, roll.y));
				}
			}
		}
	}
	return best;
}

// Quake scars at d, tangent frame (t, b): at most one per 3D cell, each a few
// jagged rings with spokes running out. 0..1 line. Lines never go thinner
// than about a pixel, and the scars fade out once too small to read.
float quakes_at(vec3 d, vec3 t, vec3 b, float footprint) {
	float fade = 1.0 - smoothstep(0.2, 0.6, footprint * quake_scale);
	if (fade <= 0.0) {
		return 0.0;
	}
	vec3 shift = vec3(quake_shift);
	vec3 p = d * quake_scale + shift;
	vec3 cell = floor(p);
	vec3 local = p - cell;
	float width = max(0.018, footprint * quake_scale * 0.8);
	float line = 0.0;

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 h = hash3(cell + o + vec3(0.0, 0.0, 577.0));
				if (h.x > quake_density) {
					continue;
				}
				vec3 off = o + 0.5 + (hash3(cell + o + vec3(0.0, 57.0, 0.0)) - 0.5) * 0.7 - local;
				float r = length(off);
				float size = quake_size * mix(0.7, 1.2, h.y);
				if (r > size * 1.1) {
					continue;
				}
				float angle = atan(dot(off, b), dot(off, t));
				float jag = noised(vec3(angle * 3.0, h.z * 10.0, 0.5)).x * 0.08;
				float rr = r + jag * size;
				for (int k = 1; k <= 3; k++) {
					if (float(k) > quake_rings) {
						break;
					}
					float ring_radius = size * float(k) / quake_rings;
					line = max(line, 1.0 - smoothstep(width * 0.5, width, abs(rr - ring_radius)));
				}
				float spoke = abs(sin((angle + h.z * 6.2831853 + jag * 3.0) * quake_spokes * 0.5)) * r;
				line = max(line, (1.0 - smoothstep(width * 0.5, width, spoke)) * (1.0 - smoothstep(size * 0.8, size, r)));
			}
		}
	}
	return line * fade;
}

// Glowing cracks: the zero lines of warped noise, like the bake's ice
// fractures but drawn. Never thinner than about a pixel, so they do not
// break up at a distance. x = the line, y = its halo.
vec2 cracks_at(vec3 d, float footprint, float scale, float shift) {
	vec3 p = d * scale + seed_offset * 0.21 + shift;
	vec3 w = vec3(noised(p * 0.5 + 5.0).x, noised(p * 0.5 + 9.0).x, noised(p * 0.5 + 13.0).x) * 1.2;
	float a = abs(noised(p + w).x);
	float b = abs(noised(p * 2.3 + w * 1.7 + 31.0).x);
	float width = max(crack_width, footprint * scale * 0.6);
	float line = max(1.0 - smoothstep(0.0, width, a), (1.0 - smoothstep(0.0, width * 0.6, b)) * 0.4);
	float halo = max(1.0 - smoothstep(0.0, width * 4.0, a), (1.0 - smoothstep(0.0, width * 2.5, b)) * 0.25);
	float region = smoothstep(crack_coverage - 0.1, crack_coverage + 0.1, noised(d * 1.3 + 71.0 + seed_offset + shift).x);
	return vec2(line, halo) * region;
}

// Bubbles in a boiling liquid: one per cell at most, each swelling on its own
// clock and popping at full size - a bright rim over a paler cap. 0..1.
float bubbles_at(vec3 d, float footprint) {
	float fade = 1.0 - smoothstep(0.2, 0.5, footprint * boil_scale);
	if (fade <= 0.0) {
		return 0.0;
	}
	vec3 p = d * boil_scale + seed_offset * 0.37;
	vec3 cell = floor(p);
	vec3 local = p - cell;
	float best = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 h = hash3(cell + o + vec3(401.0, 0.0, 0.0));
				if (h.x > 0.45) {
					continue;
				}
				vec3 off = o + 0.5 + (hash3(cell + o + vec3(0.0, 0.0, 97.0)) - 0.5) * 0.6 - local;
				float life = fract(planet_time * (0.15 + 0.2 * h.y) + h.z);
				float radius = mix(0.15, 0.42, h.y) * sqrt(life);
				float dist = length(off);
				float rim = exp(-pow((dist - radius) / (0.25 * radius + 0.02), 2.0));
				float cap = (1.0 - smoothstep(radius * 0.7, radius, dist)) * 0.5;
				best = max(best, max(rim, cap) * (1.0 - smoothstep(0.85, 1.0, life)));
			}
		}
	}
	return best * fade;
}

// Buds at d, tangent frame (t, b): x = cover, y = how far toward the bud's
// centre (0 at the rim, 1 in the middle). One bud per 3D cell at most, jittered;
// each checks the height under its own centre, so a bud is either whole or
// absent rather than clipped by the waterline. Fades out once a bud would be
// under a pixel.
// How much `d` lies just outside a placed feature - a band from its rim out
// to about 1.8 of its radii - broken into patches. 0..1.
float feature_surroundings(vec3 d) {
	float near = 0.0;
	for (int i = 0; i < MAX_SIGILS; i++) {
		if (i >= sigil_count) {
			break;
		}
		vec4 s = sigils[i];
		float r = acos(clamp(dot(d, s.xyz), -1.0, 1.0)) / max(s.w, 1e-3);
		near = max(near, smoothstep(0.92, 1.05, r) * (1.0 - smoothstep(1.4, 1.9, r)));
	}
	return near * smoothstep(-0.2, 0.1, noised(d * 7.0 + seed_offset).x);
}

vec2 buds_at(vec3 d, vec3 t, vec3 b, float footprint) {
	float fade = 1.0 - smoothstep(0.15, 0.45, footprint * bud_scale);
	if (fade <= 0.0) {
		return vec2(0.0);
	}

	vec3 shift = vec3(seed_offset * 0.19);
	vec3 p = d * bud_scale + shift;
	vec3 cell = floor(p);
	vec3 local = p - cell;
	float sea = has_liquid ? sea_level : 0.0;
	vec2 best = vec2(0.0);

	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 h = hash3(cell + o + vec3(0.0, 0.0, 911.0));
				if (h.x > bud_density) {
					continue;
				}
				vec3 centre = o + 0.5 + (hash3(cell + o) - 0.5) * 0.8;

				// Wettest just above the water, thinning with height; none in it.
				// Or, round the features, in patches.
				vec3 at = normalize(cell + centre - shift);
				float height = height_lod(at, 2.0);
				float wet = 1.0 - smoothstep(0.0, bud_reach, height - sea);
				float chance = bud_near_features > 0.5 ? feature_surroundings(at) : mix(0.3, 1.0, wet);
				if (height < sea || h.x > bud_density * chance) {
					continue;
				}

				vec3 offset = centre - local;
				float radius = bud_size * mix(0.6, 1.2, h.y);
				float angle = atan(dot(offset, b), dot(offset, t));
				float spikes = 1.0 + bud_spike * sin(angle * (7.0 + floor(h.z * 6.0)) + h.y * 6.2832);
				float reach = length(offset) / (radius * spikes);
				if (reach < 1.0) {
					best = max(best, vec2(1.0 - smoothstep(0.8, 1.0, reach), 1.0 - reach));
				}
			}
		}
	}

	return best * fade;
}

// ---------------------------------------------------------------------------

void vertex() {
	vec3 dir = normalize(VERTEX);
	// Full resolution: only there do two faces agree on their shared edge, so
	// any blurrier level would open cracks along the seams.
	VERTEX = dir * (1.0 + relief * ground(height_lod(dir, 0.0)));
	v_dir = dir;
}

void fragment() {
	vec3 d = normalize(v_dir);
	vec3 helper = abs(d.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t = normalize(cross(helper, d));
	vec3 b = cross(d, t);

	// One pixel's width on the unit sphere, and in heightmap texels.
	float footprint = max(length(fwidth(v_dir)), 1e-6);
	float texel = 2.0 / face_size;
	float lod = log2(max(footprint / texel, 1.0));
	float eps = max(texel, footprint);

	float h = height_filtered(d, lod);
	float h_t1 = height_filtered(normalize(d + t * eps), lod);
	float h_t0 = height_filtered(normalize(d - t * eps), lod);
	float h_b1 = height_filtered(normalize(d + b * eps), lod);
	float h_b0 = height_filtered(normalize(d - b * eps), lod);

	float grain = 0.5 + fbm(d + seed_offset, 3, 45.0, footprint);
	float latitude = dot(d, pole_axis);

	// Planet-space sun, for cloud shadows.
	vec3 to_sun = normalize(sun_position - NODE_POSITION_WORLD);
	vec3 L = normalize(to_sun + vec3(0.0, light_lift, 0.0));
	vec3 L_planet = normalize(transpose(mat3(MODEL_MATRIX)) * L);

	vec3 col;
	vec3 n = d;
	float gloss = 0.0;
	float glow = 0.0;
	// Light the surface gives off by itself, added after lighting.
	vec3 emit = vec3(0.0);
	bool liquid = false;
	float ground_h = 0.0;

	if (is_gas) {
		// Bands dragged sideways by stretched turbulence: eddies along the
		// band edges, far finer than the map itself.
		float drag = fbm(vec3(d.x * 3.0, latitude * 14.0, d.z * 3.0) + seed_offset, 4, 2.0, footprint * 6.0);
		float gh = height_filtered(normalize(rotate_about(d, pole_axis, drag * 0.06)), lod);
		float streak = fbm(vec3(d.x * 5.0, latitude * 60.0, d.z * 5.0) + seed_offset, 4, 1.5, footprint * 20.0);
		col = land_gradient(clamp(gh + streak * 0.12, 0.0, 1.0));
	} else {
		float detail_frequency = face_size * 0.25;
		vec4 fine = detail(d, detail_frequency, footprint);
		// Match the baked fractal's falloff, a little rougher on high ground.
		float land_guess = has_liquid ? (h - sea_level) / max(1.0 - sea_level, 1e-3) : h;
		float rough = mix(0.5, 1.6, smoothstep(0.05, 0.6, land_guess));
		float amplitude = detail_strength * 1.2 / detail_frequency * rough;
		float h_fine = h + fine.w * amplitude;

		liquid = has_liquid && h_fine < sea_level;
		ground_h = ground(h_fine);

		// Normal of the displaced surface: macro slope from the map, fine
		// slope from the fractal, both exaggerated by `bump`.
		float k = relief * bump;
		vec3 macro = (t * (ground(h_t1) - ground(h_t0)) + b * (ground(h_b1) - ground(h_b0))) / (2.0 * eps);
		vec3 micro = fine.xyz * amplitude * (liquid ? 0.0 : 1.0);
		micro -= d * dot(micro, d);
		vec3 n_macro = normalize(d - k * macro);
		n = normalize(n_macro * dot(n_macro, d) - k * 0.6 * micro + (n_macro - d * dot(n_macro, d)));
		// Rock follows the big slopes; the fine ones only fray its edges, or
		// every bump would flip between rock and grass and read as spots.
		float slope = 1.0 - dot(n_macro, d) + (1.0 - dot(n, n_macro)) * 0.25;

		// Second difference a few texels wide, off a blurrier mip so it finds
		// valleys and crests rather than every texel's grain: > 0 in hollows.
		float cavity_eps = max(texel * 6.0, footprint * 2.0);
		float cavity_lod = log2(cavity_eps / texel) - 1.0;
		float h_c = height_lod(d, cavity_lod);
		float curvature = height_lod(normalize(d + t * cavity_eps), cavity_lod)
			+ height_lod(normalize(d - t * cavity_eps), cavity_lod)
			+ height_lod(normalize(d + b * cavity_eps), cavity_lod)
			+ height_lod(normalize(d - b * cavity_eps), cavity_lod) - 4.0 * h_c;
		float cavity = clamp(curvature * 60.0, -1.0, 1.0);

		if (liquid) {
			float depth = clamp((sea_level - h_fine) / max(sea_level, 1e-3), 0.0, 1.0);
			col = mix(liquid_shallow, liquid_deep, smoothstep(0.0, 0.45, depth));
			gloss = liquid_gloss;

			if (liquid_emission > 0.0) {
				// Lava: a cooling crust drifting over the glow.
				float crust = smoothstep(-0.05, 0.15,
					fbm(d + vec3(0.0, planet_time * 0.002, 0.0), 4, 60.0, footprint)) * liquid_crust;
				col = mix(col, crust_color, crust * 0.85);
				glow = liquid_emission * (1.0 - crust * 0.9) * mix(1.0, 0.55, depth);
				gloss *= 1.0 - crust;
			} else {
				// Surf where the sea is shallowest.
				float surf = (1.0 - smoothstep(0.0, 0.012, depth))
					* smoothstep(0.35, 0.75, value_noise(d * 700.0 + planet_time * 0.6));
				col = mix(col, vec3(0.9), surf * 0.55);
				col = mix(col, liquid_shallow * 1.3, (1.0 - smoothstep(0.0, 0.03, depth)) * 0.4);
			}

			if (boil > 0.0) {
				float bubble = bubbles_at(d, footprint) * boil;
				col = mix(col, boil_color, bubble);
				emit += boil_color * bubble * 0.5;
			}

			// Swell - two octaves of moving waves, gone once sub-pixel.
			vec3 wave = vec3(0.0);
			for (int i = 0; i < 2; i++) {
				float f = 180.0 * pow(2.7, float(i));
				vec4 w = noised(d * f + vec3(planet_time * 0.15, -planet_time * 0.11, planet_time * 0.07) * float(i + 1));
				wave += w.yzw * octave_fade(f, footprint) * (0.03 / float(i + 1));
			}
			wave -= d * dot(wave, d);
			n = normalize(d + wave);
		} else {
			float land = has_liquid ? (h_fine - sea_level) / max(1.0 - sea_level, 1e-3) : h_fine;
			land = clamp(land + (grain - 0.5) * 0.03, 0.0, 1.0);
			col = land_gradient(land);

			// Dry biome over the lowlands, most likely around the subtropics.
			float subtropic = exp(-pow((abs(latitude) - 0.42) / 0.16, 2.0));
			float moisture = fbm(d + seed_offset * 0.13, 4, 2.2, footprint);
			float dryness = smoothstep(-0.05, 0.2, moisture + subtropic * 0.2 - 0.05);
			float lowland = 1.0 - smoothstep(0.35, 0.65, land);
			vec3 dry = dry_color * (0.85 + 0.3 * value_noise(d * 9.0 + 7.0));
			col = mix(col, dry, dryness * dry_amount * lowland);

			// Exposed rock on the steep parts, banded into strata.
			vec3 rock = rock_color * (0.8 + 0.4 * grain);
			if (strata > 0.0) {
				float warp = fbm(d, 2, 30.0, footprint) * 2.0;
				float band = 0.5 + 0.5 * sin((h_fine * 90.0 + warp) * 6.2832);
				band += (value_noise(vec3(h_fine * 400.0, 0.0, 0.0)) - 0.5) * 0.6;
				rock *= mix(1.0, 0.7 + 0.55 * band, strata);
			}
			float rocky_ground = smoothstep(0.08, 0.35, slope) * slope_rock;
			if (rock_patches > 0.0) {
				float outcrop = fbm(d + seed_offset * 0.13 + 31.0, 3, 8.0, footprint);
				rocky_ground = max(rocky_ground, smoothstep(0.05, 0.28, outcrop) * rock_patches);
			}
			col = mix(col, rock, rocky_ground);
			col *= 0.92 + 0.16 * grain;

			// Hollows darker, crests a touch brighter.
			col *= 1.0 - 0.3 * max(cavity, 0.0);
			col *= 1.0 + 0.15 * max(-cavity, 0.0);

			if (bud_strength > 0.0) {
				// A dab of paint: pigment pooled darker at the rim, lighter in
				// the middle.
				vec2 bud = buds_at(d, t, b, footprint);
				vec3 bud_col = bud_color * mix(0.55, 1.15, bud.y) * (0.9 + 0.2 * grain);
				col = mix(col, bud_col, bud.x * bud_strength);
			}

			if (crack_strength > 0.0) {
				vec2 crack = cracks_at(d, footprint, crack_scale, 0.0);
				col = mix(col, crack_color, crack.x);
				emit += crack_color * crack_strength * (crack.x + crack.y * 0.12);
				if (crack_twin > 0.0) {
					vec2 twin = cracks_at(d, footprint, crack_scale_b, 37.0) * crack_twin;
					col = mix(col, crack_color_b, twin.x);
					emit += crack_color_b * crack_strength * (twin.x + twin.y * 0.12);
				}
			}

			if (land_glow > 0.0) {
				emit += col * land_glow * (1.0 - smoothstep(land_glow_band * 0.6, land_glow_band, land));
			}

			if (sigil_count > 0 && sigil_mode == 4) {
				// Terran snow humps - on land only; one under the sea stays
				// hidden, one that breaks the surface is a snowy island.
				col = mix(col, sigil_color * (0.92 + 0.1 * grain), snow_at(d));
			}

			if (volcano_strength > 0.0) {
				// Scorched brown ground round each cone, lava pooled in the
				// caldera and running down the flanks in glowing rivulets.
				vec2 volcano = volcano_at(d);
				float scorched = 1.0 - smoothstep(1.05, 1.6, volcano.x);
				col = mix(col, volcano_ground * (0.8 + 0.4 * grain), scorched * volcano_strength);
				float caldera = 1.0 - smoothstep(0.1, 0.16, volcano.x);
				float streak = 1.0 - smoothstep(0.0, 0.06, abs(noised(d * 60.0 + 29.0).x));
				float rivulet = streak * (1.0 - smoothstep(0.35, 0.95, volcano.x)) * step(volcano.x, 0.95);
				float lava = max(caldera, rivulet * 0.85) * volcano_strength;
				float flicker = 0.85 + 0.15 * sin(planet_time * 1.7 + volcano.y * 40.0);
				col = mix(col, lava_color, lava);
				emit += lava_color * lava * volcano_glow * flicker;
			}

			if (quake_strength > 0.0) {
				// Silver with a little shine of its own, so the scars catch the
				// eye even on shaded slopes.
				float scar = quakes_at(d, t, b, footprint) * quake_strength;
				col = mix(col, quake_color * (0.9 + 0.2 * grain), scar);
				emit += quake_color * scar * quake_glow;
			}
		}

		if (sigil_count > 0 && sigil_mode == 0) {
			// Stain the carved crater red but keep the ground's own texture and
			// lighting, so it reads as part of the terrain; only the iris and
			// the drips give off a faint, slow-pulsing light.
			vec4 eye = eyes_at(d);
			float pulse = 0.75 + 0.25 * sin(planet_time * 1.1 + seed_offset);
			// Tentacles darkened toward dried blood, eye bowls stained solid red.
			col = mix(col, sigil_color * 0.12 + col * 0.4, smoothstep(0.0, 0.4, eye.w) * 0.8);
			col = mix(col, sigil_color * (0.35 + 0.15 * grain), eye.x * 0.9);
			col = mix(col, vec3(0.005), eye.z);
			emit += sigil_color * sigil_glow * pulse * eye.y * (1.0 - eye.z);
		} else if (sigil_count > 0 && (sigil_mode == 1 || sigil_mode == 2)) {
			vec4 feature = feature_color_at(d);
			col = mix(col, feature.rgb * (0.9 + 0.2 * grain), feature.a);

		}
	}

	if (cap_latitude <= 1.0 && !is_gas) {
		float edge = abs(latitude) + fbm(d, 4, 7.0, footprint) * 0.2;
		// Ice reaches further toward the equator on high ground.
		edge += liquid ? 0.0 : ground_h * 0.25;
		float cap = smoothstep(cap_latitude, cap_latitude + 0.025, edge);
		col = mix(col, cap_color * (0.92 + 0.08 * grain), cap);
		gloss = mix(gloss, 0.25, cap);
		glow *= 1.0 - cap;
		n = normalize(mix(n, d, cap * 0.5));
	}

	// ---- lighting (world space) ----
	vec3 V = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 nw = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	vec3 sw = normalize((MODEL_MATRIX * vec4(d, 0.0)).xyz);

	float sphere_light = dot(sw, L);
	// Terrain slopes cannot light up the night side past the terminator.
	float day = smoothstep(-0.12 * terminator_softness, 0.2 * terminator_softness, sphere_light);
	// Some wrap, as scattered light would give: shadowed slopes on the day
	// side go dim, not pitch black - unless the planet is meant to be harsh.
	float diffuse = clamp(dot(nw, L) * (1.0 - light_wrap) + light_wrap, 0.0, 1.0);
	diffuse = pow(diffuse, shade_contrast) * day;
	float sky_fill = atmo_strength * 0.06 * day * (0.5 + 0.5 * dot(nw, sw));

	// Shadows of the cloud shell (planet_clouds.gdshader) cast along the
	// light onto the ground below it.
	float shadow = 1.0;
	if (cloud_coverage > 0.0) {
		vec3 shadow_dir = normalize(d + L_planet * 0.015);
		shadow = 1.0 - 0.6 * cloud_field(shadow_dir, footprint, 1).y;
	}
	// Shadow of the rings (planet_rings.gdshaderinc), which lie in the plane
	// perpendicular to the pole.
	shadow *= mix(1.0, ring_transmission(d, L_planet, pole_axis), 0.85);

	vec3 lit = col * (ambient + (1.0 - ambient) * diffuse * shadow * sun_color + atmo_color * sky_fill);

	if (gloss > 0.0) {
		vec3 halfway = normalize(L + V);
		float spec = pow(max(dot(nw, halfway), 0.0), mix(16.0, 220.0, gloss));
		lit += sun_color * spec * gloss * day * shadow * mix(0.6, 2.5, gloss);
		// The sky mirrored in the sea, strongest at grazing angles.
		float fresnel = 0.02 + 0.98 * pow(1.0 - max(dot(nw, V), 0.0), 5.0);
		lit = mix(lit, atmo_color * 0.6 * day, fresnel * gloss * 0.6);
	}

	lit += col * glow + emit;

	// Mist pooling in the low ground, drifting and thinning as it goes.
	if (mist_strength > 0.0 && !liquid) {
		float t = planet_time * 0.02;
		float drift = fbm(d + vec3(t, -t * 0.7, t * 0.4) + seed_offset * 0.3, 4, 6.0, footprint);
		float low = 1.0 - smoothstep(0.0, mist_height, ground_h);
		// Never fully opaque - the ground always shows through.
		float mist = clamp(low * smoothstep(-0.1, 0.25, drift) * mist_strength, 0.0, 0.55);
		vec3 mist_lit = mist_color * (0.15 + 0.85 * max(sphere_light, 0.0) * day);
		lit = mix(lit, mist_lit, mist);
	}

	float facing = clamp(dot(sw, V), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.0);
	float atmo_light = smoothstep(-0.25, 0.6, sphere_light);
	lit = mix(lit, atmo_color * (0.1 + 0.9 * atmo_light), atmo_haze * (0.5 + 0.5 * rim));
	lit += atmo_color * rim * atmo_strength * atmo_light;

	// Aurora last, over the haze (the cloud shell is drawn on top of this
	// surface separately), strongest on the night side where nothing drowns it.
	if (aurora_strength > 0.0 && !is_gas) {
		lit += aurora_ground(d, latitude) * aurora_strength * (1.0 - 0.7 * day);
	}

	ALBEDO = lit;
}

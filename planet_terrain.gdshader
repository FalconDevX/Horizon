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
uniform float liquid_gloss : hint_range(0.0, 1.0) = 0.8;

uniform vec3 rock_color : source_color = vec3(0.4);
uniform float slope_rock : hint_range(0.0, 1.0) = 0.5;
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

// Aurora: glowing curtains around the poles, drawn as light. 0 = none.
uniform float aurora_strength : hint_range(0.0, 3.0) = 0.0;
uniform float aurora_latitude : hint_range(0.0, 1.0) = 0.75;
uniform float aurora_width : hint_range(0.01, 0.3) = 0.1;
uniform float aurora_speed = 0.03;
uniform vec3 aurora_color_a : source_color = vec3(0.2, 1.0, 0.5);
uniform vec3 aurora_color_b : source_color = vec3(0.2, 0.8, 1.0);
uniform vec3 aurora_color_c : source_color = vec3(0.9, 0.3, 0.9);

// Glowing cracks drawn over the ground (not carved, so they can glow and need
// no match in the heightmap). 0 = none.
uniform float crack_strength : hint_range(0.0, 4.0) = 0.0;
uniform vec3 crack_color : source_color = vec3(1.0, 0.75, 0.3);
uniform float crack_scale = 6.0;
uniform float crack_width = 0.03;
// Threshold on a slow noise: -1 cracks everywhere, 1 almost nowhere.
uniform float crack_coverage = 0.0;

// Sigils: glowing eye symbols painted on the ground.
// Array sizes mirror PlanetTerrain.MAX_SIGILS.
const int MAX_SIGILS = 8;
uniform int sigil_count = 0;
// xyz planet-space centre, w angular radius.
uniform vec4 sigils[8];
// x rotation, y pupil (0 round, 1 slit, 2 diamond; <0 tentacle nest, no eye),
// z drip count, w crater depth (bake only).
uniform vec4 sigil_styles[8];
// x count, y curl, z reach (sigil radii), w width.
uniform vec4 sigil_tentacles[8];
uniform vec3 sigil_color : source_color = vec3(0.9, 0.05, 0.05);
uniform float sigil_glow : hint_range(0.0, 4.0) = 0.0;

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
	vec2 q = vec2(dot(d, east), dot(d, north)) / s.w;
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
		vec4 t = sigil_tentacles[i];
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

// Glowing cracks: the zero lines of warped noise, like the bake's ice
// fractures but drawn. Never thinner than about a pixel, so they do not
// break up at a distance. x = the line, y = its halo.
vec2 cracks_at(vec3 d, float footprint) {
	vec3 p = d * crack_scale + seed_offset * 0.21;
	vec3 w = vec3(noised(p * 0.5 + 5.0).x, noised(p * 0.5 + 9.0).x, noised(p * 0.5 + 13.0).x) * 1.2;
	float a = abs(noised(p + w).x);
	float b = abs(noised(p * 2.3 + w * 1.7 + 31.0).x);
	float width = max(crack_width, footprint * crack_scale * 0.6);
	float line = max(1.0 - smoothstep(0.0, width, a), (1.0 - smoothstep(0.0, width * 0.6, b)) * 0.4);
	float halo = max(1.0 - smoothstep(0.0, width * 4.0, a), (1.0 - smoothstep(0.0, width * 2.5, b)) * 0.25);
	float region = smoothstep(crack_coverage - 0.1, crack_coverage + 0.1, noised(d * 1.3 + 71.0 + seed_offset).x);
	return vec2(line, halo) * region;
}

// Buds at d, tangent frame (t, b): x = cover, y = how far toward the bud's
// centre (0 at the rim, 1 in the middle). One bud per 3D cell at most, jittered;
// each checks the height under its own centre, so a bud is either whole or
// absent rather than clipped by the waterline. Fades out once a bud would be
// under a pixel.
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
				float height = height_lod(normalize(cell + centre - shift), 2.0);
				float wet = 1.0 - smoothstep(0.0, bud_reach, height - sea);
				if (height < sea || h.x > bud_density * mix(0.3, 1.0, wet)) {
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

// Aurora light at d: curtains streaked along the auroral oval, drifting, their
// colour sliding between the three stops and going violet at the poleward edge.
vec3 aurora_at(vec3 d, float latitude) {
	float offset = abs(latitude) - aurora_latitude;
	float oval = exp(-pow(offset / aurora_width, 2.0));
	if (oval < 0.01) {
		return vec3(0.0);
	}

	vec3 helper = abs(pole_axis.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 e1 = normalize(cross(pole_axis, helper));
	vec3 e2 = cross(pole_axis, e1);
	float lon = atan(dot(d, e2), dot(d, e1));
	vec2 ring = vec2(cos(lon), sin(lon));
	float t = planet_time * aurora_speed;

	float body = clamp(0.5 + noised(vec3(ring * 6.0, t) + seed_offset).x * 1.4, 0.0, 1.0);
	float streak = pow(0.5 + 0.5 * sin(lon * 40.0 + noised(vec3(ring * 3.0, t * 0.7)).x * 8.0), 3.0);
	float curtain = oval * body * mix(1.0, streak, 0.6);

	float mixer = clamp(0.5 + noised(vec3(ring * 2.0, t * 0.5) + 17.0).x * 1.4, 0.0, 1.0);
	vec3 color = mix(
		mix(aurora_color_a, aurora_color_b, clamp(mixer * 2.0, 0.0, 1.0)),
		aurora_color_c,
		clamp(mixer * 2.0 - 1.0, 0.0, 1.0)
	);
	color = mix(color, aurora_color_c, smoothstep(0.0, aurora_width, offset) * 0.6);
	return color * curtain;
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
				col = mix(col, rock_color * 0.5, crust * 0.85);
				glow = liquid_emission * (1.0 - crust * 0.9) * mix(1.0, 0.55, depth);
				gloss *= 1.0 - crust;
			} else {
				// Surf where the sea is shallowest.
				float surf = (1.0 - smoothstep(0.0, 0.012, depth))
					* smoothstep(0.35, 0.75, value_noise(d * 700.0 + planet_time * 0.6));
				col = mix(col, vec3(0.9), surf * 0.55);
				col = mix(col, liquid_shallow * 1.3, (1.0 - smoothstep(0.0, 0.03, depth)) * 0.4);
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
			col = mix(col, rock, smoothstep(0.08, 0.35, slope) * slope_rock);
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
				vec2 crack = cracks_at(d, footprint);
				col = mix(col, crack_color, crack.x);
				emit += crack_color * crack_strength * (crack.x + crack.y * 0.12);
			}
		}

		if (sigil_count > 0) {
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
		lit += aurora_at(d, latitude) * aurora_strength * (1.0 - 0.7 * day);
	}

	ALBEDO = lit;
}

shader_type spatial;
// Lit by hand like the planets: the scene has no 3D lights, only the
// `sun_position` global solar_system.gd sets.
render_mode unshaded, cull_back;

// A resource deposit (resource_deposits.gd, shapes from deposit_meshes.gd).
// The mesh's vertex colours shade within it; `base_color` tints the lot.

uniform vec3 base_color : source_color = vec3(1.0);
// Same lift as the terrain, so deposit and ground share a terminator.
uniform float light_lift : hint_range(0.0, 2.0) = 0.35;
// Light of its own, so deposits can still be found on the night side.
uniform float glow : hint_range(0.0, 2.0) = 0.15;
// 0 = matte, 1 = polished metal.
uniform float shine : hint_range(0.0, 1.0) = 0.3;
// Sway, in cluster units at one unit up, growing with height (0 = none).
uniform float wiggle = 0.0;
// Per deposit, so neighbours do not sway in step.
uniform float phase = 0.0;
// Spots scattered over the surface (0 = none), in two colours.
uniform float spots = 0.0;
uniform vec3 spot_color_a : source_color = vec3(0.3, 0.5, 1.0);
uniform vec3 spot_color_b : source_color = vec3(1.0, 0.5, 0.7);

global uniform vec3 sun_position;
// Game time: stops on pause, like every other planet animation.
global uniform float planet_time;

varying vec3 v_local;

vec3 hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Round spots, one per cell at most: x = on a spot, y = which colour.
vec2 spots_at(vec3 p) {
	vec3 cell = floor(p);
	vec2 best = vec2(0.0);
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 c = cell + vec3(float(x), float(y), float(z));
				vec3 h = hash3(c);
				if (h.x > 0.55) {
					continue;
				}
				float d = length(p - c - hash3(c + 17.0));
				float r = mix(0.18, 0.34, h.y);
				float on = 1.0 - smoothstep(r - 0.04, r, d);
				if (on > best.x) {
					best = vec2(on, step(0.5, h.z));
				}
			}
		}
	}
	return best;
}

void vertex() {
	v_local = VERTEX;
	if (wiggle > 0.0) {
		// Bend, not tilt: the higher up, the further it swings.
		float up = max(VERTEX.y, 0.0);
		float t = planet_time;
		VERTEX.x += wiggle * up * up * sin(t * 1.7 + phase + up * 0.6);
		VERTEX.z += wiggle * up * up * 0.6 * sin(t * 1.3 + phase * 1.7 + up * 0.4);
	}
}

void fragment() {
	vec3 albedo = base_color * COLOR.rgb;
	if (spots > 0.0) {
		vec2 s = spots_at(v_local * 7.0);
		albedo = mix(albedo, mix(spot_color_a, spot_color_b, s.y), s.x * spots);
	}

	vec3 to_sun = normalize(sun_position - NODE_POSITION_WORLD);
	vec3 L = normalize(to_sun + vec3(0.0, light_lift, 0.0));
	vec3 V = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Night on the ground below is night on the deposit too: its own up axis
	// points straight out of the planet.
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	float day = smoothstep(-0.12, 0.2, dot(up, L));

	float diffuse = clamp(dot(nw, L) * 0.8 + 0.2, 0.0, 1.0) * day;
	float spec = pow(max(dot(nw, normalize(L + V)), 0.0), mix(12.0, 90.0, shine)) * day;
	// Metal tints its highlight; stone and plants keep it white.
	vec3 highlight = mix(vec3(1.0), albedo, shine * 0.6) * spec * mix(0.15, 1.3, shine);

	ALBEDO = albedo * (0.08 + 0.92 * diffuse * mix(1.0, 0.75, shine) + glow) + highlight;
}

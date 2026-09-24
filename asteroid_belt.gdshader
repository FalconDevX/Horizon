shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform, shadows_disabled;

// Asteroid belt rocks (asteroid_belts.gd). Each MultiMesh instance is one rock:
// its transform holds only the rock's shape (orientation and size, origin at
// zero), INSTANCE_CUSTOM holds the orbit - (radius, phase, size, spin). The
// orbit is advanced here on the GPU from the sim time, circular round the sun
// at the Kepler rate, so no instance is ever touched from the CPU again.
// Faceted, lit by hand from the sun like the planets.

global uniform vec3 sun_position;
global uniform float planet_time;

uniform float mu = 3000000.0;
uniform vec2 sun_center = vec2(0.0);
// Sim time split in two: a float32 cannot hold hours of seconds precisely
// enough to move a rock smoothly, but each half on its own can.
uniform float time_hi = 0.0;
uniform float time_lo = 0.0;
// World size a rock is grown to at least, so zoomed out a belt is still a
// band of specks rather than nothing.
uniform float min_size = 0.0;
uniform float light_lift = 0.35;
uniform float ambient = 0.16;

varying vec3 v_rel;
varying vec3 v_local;
varying vec3 v_light;
varying vec3 v_color;
varying float v_seed;

vec3 rotate_about(vec3 v, vec3 axis, float a) {
	float c = cos(a);
	return v * c + cross(axis, v) * sin(a) + axis * dot(axis, v) * (1.0 - c);
}

void vertex() {
	vec4 orbit = INSTANCE_CUSTOM;
	float r = orbit.x;
	float omega = sqrt(mu / (r * r * r));
	float angle = orbit.y + mod(omega * time_hi, 6.28318530718) + omega * time_lo;
	vec3 center = vec3(sun_center.x + cos(angle) * r, 0.0, sun_center.y + sin(angle) * r);

	vec3 axis = normalize(vec3(sin(orbit.y * 7.1), cos(orbit.y * 3.3), sin(orbit.y * 5.7) + 0.3));
	vec3 local = rotate_about(VERTEX, axis, planet_time * orbit.w);
	float grow = max(1.0, min_size / orbit.z);
	v_rel = mat3(MODEL_MATRIX) * local * grow;
	v_local = VERTEX;
	v_seed = orbit.y;

	VERTEX = (VIEW_MATRIX * vec4(center + v_rel, 1.0)).xyz;
	v_light = normalize(normalize(sun_position - center) + vec3(0.0, light_lift, 0.0));
	v_color = COLOR.rgb;
}

float hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

// Pits: 1 at the centre of a crater, 0 outside, with a bright raised rim.
float craters(vec3 p) {
	vec3 cell = floor(p);
	float best = 1e9;
	float best_r = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 c = cell + vec3(float(x), float(y), float(z));
				vec3 centre = c + vec3(hash3(c), hash3(c + 17.1), hash3(c + 31.7));
				float d = length(p - centre);
				if (d < best) {
					best = d;
					best_r = 0.25 + 0.3 * hash3(c + 5.3);
				}
			}
		}
	}
	float q = best / best_r;
	return (1.0 - smoothstep(0.55, 0.85, q)) - 0.6 * smoothstep(0.8, 0.95, q) * (1.0 - smoothstep(0.95, 1.15, q));
}

void fragment() {
	// Flat facets: the triangle's own plane, from screen-space derivatives.
	vec3 n = normalize(cross(dFdx(v_rel), dFdy(v_rel)));
	vec3 to_camera = INV_VIEW_MATRIX[2].xyz;
	if (dot(n, to_camera) < 0.0) {
		n = -n;
	}
	float diffuse = max(dot(n, v_light), 0.0);

	// Surface detail in the rock's own space, so it turns with the rock: mottled
	// regolith plus craters. Faded out once the rock is only a few pixels wide.
	vec3 p = v_local * 2.2 + vec3(v_seed * 13.1, v_seed * 7.3, v_seed * 3.7);
	float detail_fade = 1.0 - smoothstep(0.12, 0.35, length(fwidth(v_local)));
	float mottle = noise3(p * 1.7) * 0.6 + noise3(p * 4.3) * 0.4;
	float pit = craters(p * 1.4);
	float shade = 1.0 + detail_fade * ((mottle - 0.5) * 0.45 - pit * 0.35);
	// Rims catch the light a little.
	shade += detail_fade * max(-pit, 0.0) * 0.4 * diffuse;
	vec3 albedo = v_color * max(shade, 0.2);

	ALBEDO = albedo * (ambient + (1.0 - ambient) * diffuse);
}

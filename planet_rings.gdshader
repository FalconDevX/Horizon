shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Planetary rings: a flat quad in the planet's equatorial plane, a child of the
// planet sphere, so its local space is planet space (radius 1 = the planet's
// surface, +Y = the pole). The profile lives in planet_rings.gdshaderinc and is
// shared with the terrain shader, which darkens the planet under the rings.
// Lit by hand from the sun like the planets; the planet's own shadow falls
// across the rings on the night side.

#include "res://planet_rings.gdshaderinc"

global uniform vec3 sun_position;

uniform vec3 ring_color_inner : source_color = vec3(0.45, 0.4, 0.34);
uniform vec3 ring_color_outer : source_color = vec3(0.86, 0.8, 0.68);
uniform vec3 ring_color_accent : source_color = vec3(0.7, 0.58, 0.44);
// Same lift the planets use, so ring and globe agree on where the light is.
uniform float light_lift = 0.35;
uniform float ambient = 0.18;

varying vec3 v_pos;

void vertex() {
	v_pos = VERTEX;
}

void fragment() {
	float r = length(v_pos.xz);
	float x = ring_coord(r);
	float blur = fwidth(x);
	float density = ring_density(x, blur);
	if (density <= 0.002) {
		discard;
	}

	vec3 col = mix(ring_color_inner, ring_color_outer, smoothstep(0.1, 0.75, x));
	col = mix(col, ring_color_accent, 0.55 * ring_noise(x * 23.0 + 7.0));
	// Dense parts are brighter - more ice catching the light.
	col *= 0.75 + 0.35 * density / max(ring_opacity, 0.001);

	vec3 to_sun = normalize(sun_position - NODE_POSITION_WORLD);
	vec3 L = normalize(to_sun + vec3(0.0, light_lift, 0.0));
	// Planet space, where the planet is the unit sphere at the origin.
	vec3 L_local = normalize(transpose(mat3(MODEL_MATRIX)) * L);

	// The planet's shadow: does the ray to the sun pass through the globe?
	float lit = 1.0;
	float b = dot(v_pos, L_local);
	if (b < 0.0) {
		float miss = sqrt(max(dot(v_pos, v_pos) - b * b, 0.0));
		lit = smoothstep(0.97, 1.03, miss);
	}

	float face = 0.4 + 0.6 * sqrt(abs(L_local.y));
	ALBEDO = col * (ambient + (1.0 - ambient) * face * lit);
	ALPHA = density;
}

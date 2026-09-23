shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// A star's corona, on the flat plane that sits behind its sphere facing the
// camera. Added on top of whatever is behind: a hot inner rim, streamers that
// reach out and slowly writhe, and a broad faint halo. The disc itself hides
// the middle.

uniform vec3 star_color : source_color = vec3(1.0, 0.85, 0.3);
uniform float intensity : hint_range(0.0, 8.0) = 1.0;
// The plane's half-width over the star's radius (see celestial_body.gd).
uniform float extent = 5.0;
uniform float seed_offset = 0.0;

uvec2 pcg2d(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	return v;
}

float hash12(vec2 cell) {
	return float(pcg2d(uvec2(ivec2(cell))).x) * (1.0 / 4294967295.0);
}

// Value noise that wraps around every `period` cells along x - so it can run
// round the circle without a seam.
float wrapped_noise(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = p - i;
	f = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period);
	float x1 = mod(i.x + 1.0, period);

	return mix(
		mix(hash12(vec2(x0, i.y)), hash12(vec2(x1, i.y)), f.x),
		mix(hash12(vec2(x0, i.y + 1.0)), hash12(vec2(x1, i.y + 1.0)), f.x),
		f.y
	);
}

float streamers(float angle, float r, float time) {
	float a = angle / 6.2832;
	float sum = 0.0;
	float amplitude = 0.5;
	float period = 24.0;
	for (int i = 0; i < 4; i++) {
		// Radius on the second axis, slowly: streamers run straight out and
		// only drift and bend a little along their length.
		sum += amplitude * wrapped_noise(vec2(a * period, r * 0.35 - time * 0.05 + float(i) * 7.3 + seed_offset), period);
		period *= 2.0;
		amplitude *= 0.5;
	}
	return sum;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * extent;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float time = TIME;

	// Distance above the surface, in stellar radii.
	float height = max(r - 1.0, 0.0);

	float rays = streamers(angle, height, time);
	float ray_boost = pow(smoothstep(0.35, 0.85, rays), 1.5);

	// Bright thin inner corona.
	float inner = exp(-height * 12.0) * 0.7;
	// Streamers: long, fading roughly as a power of height.
	float outer = exp(-height * 1.8) * (0.12 + 0.9 * ray_boost);
	// Broad halo, so the star lights up the space around it.
	float halo = 0.28 / (1.0 + height * height * 8.0);

	// Soft fade to nothing well before the plane's edge.
	float edge = 1.0 - smoothstep(extent * 0.6, extent * 0.98, r);
	float glow = (inner + outer + halo) * edge;

	vec3 hot = mix(star_color, vec3(1.0), 0.5);
	vec3 col = mix(star_color * vec3(1.0, 0.7, 0.45), hot, exp(-height * 3.0));

	ALBEDO = col * glow * intensity;
}

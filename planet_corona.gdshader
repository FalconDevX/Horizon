shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// A star's corona, on the flat plane that sits behind its sphere facing the
// camera. Added on top of whatever is behind: prominences - red, torn, flame-
// like tongues of plasma standing on the limb - over a deep red chromosphere
// glow, streamers that reach out and slowly writhe, plasma puffs pulsing
// outward along them, and a broad faint halo. The disc hides the middle.

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

// Plasma puffs: coarse blobs whose noise scrolls outward in radius, so they
// are born at the surface and drift away, fading as they go.
float ejecta(float angle, float height, float time) {
	float a = angle / 6.2832;
	float sum = 0.0;
	float amplitude = 0.5;
	float period = 9.0;
	for (int i = 0; i < 3; i++) {
		sum += amplitude * wrapped_noise(
			vec2(a * period, height * 1.3 - time * 0.3 + float(i) * 3.1 + seed_offset), period
		);
		period *= 2.0;
		amplitude *= 0.5;
	}
	return sum;
}

// Prominences: where the limb is active, turbulent filaments licking up off
// the surface. Domain-warped noise in (angle, height), folded into ridges so
// it reads as strands rather than blobs, and scrolled upward as it churns.
float prominences(float angle, float height, float time) {
	float a = angle / 6.2832;
	// Active sites along the limb, drifting slowly.
	float site = smoothstep(0.35, 0.65, wrapped_noise(vec2(a * 14.0 + time * 0.01, seed_offset), 14.0));

	vec2 q = vec2(a * 64.0, height * 14.0);
	vec2 warp = vec2(
		wrapped_noise(vec2(a * 32.0, height * 6.0 - time * 0.25 + 3.0), 32.0),
		wrapped_noise(vec2(a * 32.0 + 11.0, height * 6.0 - time * 0.2 + 7.0), 32.0)
	) - 0.5;
	float strands = 0.0;
	float amplitude = 0.55;
	float period = 64.0;
	for (int i = 0; i < 3; i++) {
		float n = wrapped_noise(vec2(q.x * period / 64.0, q.y * period / 64.0 - time * 0.5) + warp * 5.0 + float(i) * 13.0, period);
		strands += amplitude * pow(1.0 - abs(n * 2.0 - 1.0), 4.0);
		amplitude *= 0.5;
		period *= 2.0;
	}

	// Tall where the site is strong, low elsewhere; ragged at the top.
	float reach = mix(0.04, 0.45, site) * (0.7 + 0.6 * warp.x);
	float body = 1.0 - smoothstep(reach * 0.35, reach, height);
	return strands * body * (0.25 + 0.75 * site);
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

	// Chromosphere: a thin deep-red glow hugging the limb, swelling and
	// ebbing unevenly round it. Red, not white - a white rim would read as a
	// hard outline round the disc.
	float breath = 0.8 + 0.2 * sin(time * 0.9 + angle * 3.0 + sin(time * 0.37 + angle * 5.0) * 2.0);
	float inner = exp(-height * 7.0) * 0.55 * breath;
	float flames = prominences(angle, height, time) * 1.6;
	// Streamers: long, fading roughly as a power of height.
	float outer = exp(-height * 1.8) * (0.12 + 0.9 * ray_boost);
	// Broad halo, so the star lights up the space around it.
	float halo = 0.28 / (1.0 + height * height * 8.0);
	// Puffs ride the streamers: brightest where both agree.
	float puffs = pow(smoothstep(0.38, 0.75, ejecta(angle, height, time)), 1.5);
	float flow = puffs * exp(-height * 0.9) * (0.6 + 0.6 * ray_boost) * 1.3;

	// Soft fade to nothing well before the plane's edge.
	float edge = 1.0 - smoothstep(extent * 0.6, extent * 0.98, r);
	float glow = (outer + halo + flow) * edge;

	vec3 red = star_color * vec3(1.0, 0.32, 0.1);
	vec3 col = mix(star_color * vec3(1.0, 0.62, 0.35), mix(star_color, vec3(1.0), 0.25), exp(-height * 3.0));

	// Prominences glow red-orange, hotter at their roots.
	vec3 flame = mix(red, star_color * vec3(1.0, 0.6, 0.25), exp(-height * 25.0));

	ALBEDO = (col * glow + red * inner + flame * flames) * intensity;
}

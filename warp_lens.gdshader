shader_type canvas_item;
// Warp jump (scripts/ui/WarpFX.gd): space bends round the ship. Drawn full
// screen between the world and the HUD, it re-samples what is behind it:
//   lens   - gravitational lensing round `center`: a dark core ringed by a
//            bright violet photon ring, the view around it pulled and mirrored
//   streak - zoom blur toward the centre, stars and planets stretched into
//            lines rushing past
//   ring   - a shockwave ripple running outward on arrival (< 0 = off)
//   flash  - white-out at the moment of arrival

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 center = vec2(0.5);
uniform float aspect = 1.7778;
uniform float lens = 0.0;
uniform float streak = 0.0;
uniform float ring = -1.0;
uniform float flash = 0.0;
uniform vec4 tint : source_color = vec4(0.62, 0.55, 1.0, 1.0);

const int SAMPLES = 14;

void fragment() {
	vec2 d = SCREEN_UV - center;
	d.x *= aspect;
	float r = length(d);
	vec2 n = r > 1e-5 ? d / r : vec2(0.0);

	// Einstein-ring bending: the closer to the centre, the harder the view
	// is pulled across it.
	float rs = 0.075 * lens;
	vec2 bend = n * (rs * rs / max(r, 0.004));
	// Arrival shockwave.
	if (ring > 0.0) {
		float x = (r - ring) / 0.05;
		bend -= n * 0.035 * exp(-x * x) * clamp(1.4 - ring, 0.0, 1.0);
	}
	bend.x /= aspect;
	vec2 uv = SCREEN_UV - bend;

	// Zoom blur with a little chromatic split, stronger as the jump builds.
	vec3 col = vec3(0.0);
	float spread = 0.22 * streak;
	for (int i = 0; i < SAMPLES; i++) {
		float t = float(i) / float(SAMPLES - 1);
		vec2 base = center + (uv - center) * (1.0 - spread * t);
		vec2 split = (base - center) * 0.012 * (lens + streak);
		col.r += textureLod(screen_tex, base + split, 0.0).r;
		col.g += textureLod(screen_tex, base, 0.0).g;
		col.b += textureLod(screen_tex, base - split, 0.0).b;
	}
	col /= float(SAMPLES);

	// Dark core and the glowing photon ring round it.
	float core = (1.0 - smoothstep(rs * 0.35, rs * 0.75, r)) * lens;
	col *= 1.0 - core;
	float glow = exp(-pow((r - rs) / (rs * 0.22 + 1e-4), 2.0)) * lens;
	col += tint.rgb * glow * 0.9;
	// Violet haze over the whole view while streaking.
	col = mix(col, col * tint.rgb * 1.3 + tint.rgb * 0.05, streak * 0.35);
	col = mix(col, vec3(1.0), clamp(flash, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}

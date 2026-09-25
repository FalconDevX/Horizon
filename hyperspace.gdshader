// Hyperspace jump, drawn full screen over everything (HyperspaceJump.gd).
// Stars stretch into streaks rushing out from the centre (`stretch`), then
// the view drops into a swirling blue tunnel (`tunnel`), and a white `flash`
// pops on the way out. `travel` is distance flown, integrated by the script so
// a change of speed never makes the pattern jump. `darken` blacks out what is
// behind (the old system on the way in, the new one on the way out).
// Hashes are integer PCG: a float sine hash breaks into blocks on the GPU.
shader_type canvas_item;
render_mode unshaded;

uniform vec2 rect_size = vec2(1920.0, 1080.0);
uniform float travel = 0.0;
uniform float stretch : hint_range(0.0, 1.0) = 0.0;
uniform float tunnel : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float darken : hint_range(0.0, 1.0) = 0.0;
uniform float star_alpha : hint_range(0.0, 1.0) = 0.0;

const float LANES = 540.0;
const int LAYERS = 3;
const int TUNNEL_PERIOD = 18;

uint pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

float hash1(uint v) {
	return float(pcg(v)) / 4294967295.0;
}

float hash2(ivec2 p) {
	return hash1(uint(p.x) + pcg(uint(p.y)));
}

// Value noise that wraps every `period` cells in x (round the tunnel).
float wrap_noise(vec2 p, int period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	// Float mod: an int % of a negative number is undefined in GLSL.
	int x0 = int(mod(i.x, float(period)));
	int x1 = int(mod(i.x + 1.0, float(period)));
	int y0 = int(i.y);
	float a = hash2(ivec2(x0, y0));
	float b = hash2(ivec2(x1, y0));
	float c = hash2(ivec2(x0, y0 + 1));
	float d = hash2(ivec2(x1, y0 + 1));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// One star per lane per layer, flying at the viewer: screen radius K / depth.
// The streak runs from where it is now back to where it was `trail` ago.
// Neighbouring lanes are checked too, so a streak near a lane edge is not cut.
float streaks(float u, float r) {
	float light = 0.0;
	for (int cell = 0; cell < LAYERS * 3; cell++) {
		int layer = cell / 3;
		float lane = floor(u * LANES) + float(cell % 3 - 1);
		float wrapped = mod(lane, LANES);
		uint id = uint(wrapped) + uint(layer) * 7919u;
		if (hash1(id) > 0.6) {
			continue;
		}
		float offset = 0.2 + 0.6 * hash1(id + 101u);
		float centre = (lane + offset) / LANES;
		float rate = 0.5 + hash1(id + 202u);
		float z = fract(hash1(id + 303u) - travel * 0.18 * rate);
		float k = 0.035;
		float head = k / max(z, 0.002);
		float trail = mix(0.004, 0.45, stretch);
		float tail = k / (z + trail);
		if (r > head || r < tail) {
			continue;
		}
		float width = mix(0.0012, 0.0022, stretch) + 0.004 * r * (1.0 - stretch);
		float across = abs(u - centre) * TAU * r;
		float along = (r - tail) / max(head - tail, 1e-4);
		float core = smoothstep(width, 0.0, across);
		float fade_in = smoothstep(1.0, 0.7, z);
		light += core * mix(0.35, 1.0, along) * fade_in * (0.6 + 0.8 * hash1(id + 404u));
	}
	return light;
}

void fragment() {
	vec2 p = (UV - 0.5) * rect_size / rect_size.y;
	float r = length(p);
	float u = atan(p.y, p.x) / TAU + 0.5;

	float star = streaks(u, r) * star_alpha;
	vec3 star_col = mix(vec3(0.75, 0.88, 1.0), vec3(1.0), clamp(star - 0.5, 0.0, 1.0)) * star;

	vec3 tunnel_col = vec3(0.0);
	if (tunnel > 0.001) {
		float depth = 0.22 / max(r, 0.003);
		float v = depth + travel * 1.4;
		float twist = depth * 0.08;
		float n = wrap_noise(vec2((u + twist) * float(TUNNEL_PERIOD), v * 0.9), TUNNEL_PERIOD) * 0.6
			+ wrap_noise(vec2((u - twist) * float(TUNNEL_PERIOD * 2), v * 2.3 + 17.0), TUNNEL_PERIOD * 2) * 0.4;
		float bands = pow(n, 3.0) * 2.4;
		vec3 deep = vec3(0.02, 0.06, 0.22);
		vec3 mid = vec3(0.18, 0.5, 1.0);
		vec3 hot = vec3(0.85, 0.95, 1.0);
		tunnel_col = mix(deep, mid, clamp(bands, 0.0, 1.0));
		tunnel_col = mix(tunnel_col, hot, clamp(bands - 1.0, 0.0, 1.0));
		// Dark near the far end, brightest at mid radius, a glow at the centre.
		tunnel_col *= smoothstep(0.02, 0.25, r) * (0.6 + 0.6 * smoothstep(0.9, 0.3, r));
		tunnel_col += vec3(0.55, 0.75, 1.0) * exp(-r * 14.0) * 0.9;
		tunnel_col *= tunnel;
	}

	vec3 col = star_col * (1.0 - 0.5 * tunnel) + tunnel_col + vec3(flash);
	float glow = max(col.r, max(col.g, col.b));
	COLOR = vec4(col, clamp(max(darken, glow), 0.0, 1.0));
}

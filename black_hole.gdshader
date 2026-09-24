shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Black hole, ray traced per pixel on a flat quad (celestial_body.gd, the
// body's glow plane). Everything is in units of the Schwarzschild radius
// Rs = 1 (the event horizon), with GM = 0.5 and c = 1.
//
// Each pixel is a light ray traced backwards from the top-down orthographic
// camera. The ray bends as a photon does round a Schwarzschild mass
// (d2x/dl2 = -1.5 h^2 x / r^5, h = |x cross v|): rays inside ~2.6 Rs fall
// through the horizon and give the shadow; the rest are deflected.
//  - A thin accretion disk, tilted to the view, is picked up wherever a ray
//    crosses its plane - including rays that swing round the back, which is
//    why the far side of the disk shows up arched over and under the shadow.
//    Its light gets relativistic Doppler beaming (the side coming toward the
//    camera is brighter and bluer) and gravitational redshift.
//  - Rays that escape look at the background (stars, orbit lines - whatever
//    the 3D view has behind it, via the screen texture) along their bent
//    direction, which gives the lensed, ring-shaped starfield.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
global uniform float planet_time;

// Quad half-size in Rs (matches BLACK_HOLE_EXTENT in celestial_body.gd).
uniform float extent = 16.0;
// Disk tilt away from face-on (radians) and its turn about the view axis.
uniform float inclination = 1.47;
uniform float disk_turn = 0.55;
uniform float disk_inner = 3.0; // innermost stable circular orbit, 6 GM
uniform float disk_outer = 12.0;
uniform float disk_brightness = 1.4;
uniform vec3 disk_hot : source_color = vec3(1.0, 0.93, 0.82);
uniform vec3 disk_warm : source_color = vec3(1.0, 0.55, 0.16);
uniform vec3 disk_cool : source_color = vec3(0.55, 0.12, 0.03);
// How far behind the hole the background is imagined to be, in Rs - sets
// how strongly a bent ray shifts the stars it lands on.
uniform float lens_distance = 26.0;
uniform float disk_spin_speed = 0.35;
uniform int max_steps = 180;

varying vec2 v_local;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

// Value noise that repeats every `period` cells along x, so a pattern laid
// round the disk (x = angle) closes on itself with no seam.
float vnoise_wrap(vec2 p, float period) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, period);
	float x1 = mod(i.x + 1.0, period);
	return mix(
		mix(hash21(vec2(x0, i.y)), hash21(vec2(x1, i.y)), f.x),
		mix(hash21(vec2(x0, i.y + 1.0)), hash21(vec2(x1, i.y + 1.0)), f.x),
		f.y
	);
}

// fbm over (angle turns, radius); each octave doubles the angular period.
float fbm_wrap(vec2 p, float period) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise_wrap(p, period);
		p *= 2.0;
		period *= 2.0;
		a *= 0.5;
	}
	return v;
}

vec3 disk_normal() {
	// Face-on is +Y (toward the camera); tip it by `inclination` about X,
	// then turn it about the view axis.
	vec3 n = vec3(0.0, cos(inclination), -sin(inclination));
	float c = cos(disk_turn);
	float s = sin(disk_turn);
	return vec3(c * n.x - s * n.z, n.y, s * n.x + c * n.z);
}

// Light of the disk at `hit` for a photon leaving along `to_camera`.
// Returns rgb and, in .a, how opaque the disk is there.
vec4 disk_emission(vec3 hit, vec3 to_camera, vec3 n) {
	float r = length(hit);
	if (r < disk_inner || r > disk_outer) {
		return vec4(0.0);
	}

	// Polar coordinates in the disk plane, spun at the local Kepler rate.
	vec3 e1 = normalize(cross(n, abs(n.x) < 0.9 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 0.0, 1.0)));
	vec3 e2 = cross(n, e1);
	float phi = atan(dot(hit, e2), dot(hit, e1));
	float omega = pow(r, -1.5);
	// Angle in turns (0..1), spun at the local orbital rate, plus a gentle
	// spiral so the streaks trail like sheared gas.
	float turns = fract(phi / TAU - planet_time * disk_spin_speed * omega * 1.3 + r * 0.035);
	float streaks = fbm_wrap(vec2(turns * 24.0, r * 3.5), 24.0);
	float clumps = fbm_wrap(vec2(turns * 10.0, r * 1.4 + 7.0), 10.0);
	float texture_mod = 0.45 + 0.75 * streaks * (0.6 + 0.4 * clumps);

	// Novikov-Thorne-like temperature: rises from the inner edge, falls off
	// as r^-3/4 further out.
	float x = disk_inner / r;
	float temperature = pow(x, 0.75) * pow(max(1.0 - sqrt(x), 0.0), 0.25) * 2.4;

	// Orbital velocity (prograde about n), Doppler and gravitational shifts.
	vec3 v_dir = normalize(cross(n, hit));
	float beta = clamp(sqrt(0.5 / r), 0.0, 0.95);
	float gamma = inversesqrt(1.0 - beta * beta);
	float cos_theta = dot(v_dir, to_camera);
	float doppler = 1.0 / (gamma * (1.0 - beta * cos_theta));
	float g = doppler * sqrt(max(1.0 - 1.0 / r, 0.02));

	float shifted = temperature * g;
	vec3 col = mix(disk_cool, disk_warm, smoothstep(0.1, 0.55, shifted));
	col = mix(col, disk_hot, smoothstep(0.55, 1.05, shifted));
	// Blue-white where beaming pushes it past white.
	col = mix(col, vec3(0.8, 0.88, 1.0), smoothstep(1.05, 1.6, shifted) * 0.6);

	float intensity = disk_brightness * pow(temperature, 1.6) * pow(g, 3.0) * texture_mod;
	float edge = smoothstep(disk_inner, disk_inner + 0.6, r) * (1.0 - smoothstep(disk_outer - 4.0, disk_outer, r));
	float opacity = clamp(edge * (0.55 + 0.45 * clumps), 0.0, 0.95);
	return vec4(col * intensity, opacity);
}

void vertex() {
	// PlaneMesh of size 1: VERTEX.xz spans -0.5..0.5 across the quad.
	v_local = VERTEX.xz * extent * 2.0;
}

void fragment() {
	vec3 n = disk_normal();

	// Start high above the hole and trace downward, as the camera looks.
	vec3 pos = vec3(v_local.x, extent * 2.5, v_local.y);
	vec3 vel = vec3(0.0, -1.0, 0.0);
	vec3 hc = cross(pos, vel);
	float h2 = dot(hc, hc);

	vec3 light = vec3(0.0);
	float through = 1.0;
	bool captured = false;
	float start_r = length(pos);

	for (int i = 0; i < max_steps; i++) {
		float r = length(pos);
		if (r < 1.0) {
			captured = true;
			break;
		}
		// Short steps near the hole, long ones far out.
		float dt = clamp(0.06 * r * r / max(r, 1.5), 0.02, 2.5);
		vec3 acc = -1.5 * h2 * pos / pow(r, 5.0);
		vec3 next_vel = vel + acc * dt;
		vec3 next_pos = pos + (vel + next_vel) * 0.5 * dt;

		// Crossing the disk plane between the two points?
		float s0 = dot(pos, n);
		float s1 = dot(next_pos, n);
		if (s0 * s1 < 0.0) {
			vec3 hit = mix(pos, next_pos, s0 / (s0 - s1));
			vec4 e = disk_emission(hit, -normalize(vel), n);
			light += through * e.rgb * e.a;
			through *= 1.0 - e.a;
			if (through < 0.02) {
				break;
			}
		}

		pos = next_pos;
		vel = next_vel;
		// Well clear and heading away: this ray has escaped.
		if (length(pos) > start_r + 2.0 && dot(pos, vel) > 0.0) {
			break;
		}
	}

	vec3 background = vec3(0.0);
	if (!captured && through > 0.02) {
		vec3 d = normalize(vel);
		if (d.y < -0.05) {
			// Where the bent ray meets the far background, back in world space.
			vec2 lensed = v_local + d.xz / -d.y * lens_distance;
			float rs_world = length(MODEL_MATRIX[0].xyz) / (2.0 * extent);
			vec3 world = NODE_POSITION_WORLD + vec3(lensed.x, 0.0, lensed.y) * rs_world;
			vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
			vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
			uv.y = 1.0 - uv.y;
			if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
				background = textureLod(screen_tex, uv, 0.0).rgb;
			}
		}
		// Light near the shadow is strongly magnified but also dimmed as the
		// ray grazes the photon sphere; keep the rim from blowing out.
	}

	// Soft shoulder: bright parts roll off instead of clipping to flat white,
	// but still pass 1.0 so the scene's glow blooms them.
	light = light / (1.0 + 0.3 * light);
	vec3 color = light + through * background;

	// Blend into the untouched view toward the quad's edge, where lensing is
	// negligible anyway.
	float edge_fade = 1.0 - smoothstep(extent * 0.72, extent * 0.98, length(v_local));
	ALBEDO = color;
	ALPHA = edge_fade;
}

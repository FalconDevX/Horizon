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
//  - Rays that escape look up the starfield along their bent direction, which
//    gives the lensed, ring-shaped sky. Only the star image itself is bent
//    (`starfield`, the same texture and screen fit as the Background layer):
//    orbit lines, SOI rings and other map overlays are not physical and stay
//    straight - near the hole the quad covers them, and further out the
//    lensing and the quad fade out together so they reappear untouched.

uniform sampler2D starfield : source_color, filter_linear_mipmap;
// The Background layer's dimming (BackgroundMask alpha, 1 - star brightness).
uniform float starfield_dim = 0.5;
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

// Wormhole mode (celestial_body.gd is_wormhole): same lensing, no disk. Rays
// that fall into the throat come out somewhere else: they show another patch
// of sky, tinted `far_tint`, with a faint nebula, and the throat's edge glows.
uniform bool wormhole = false;
uniform vec3 far_tint : source_color = vec3(0.6, 0.8, 1.0);
uniform vec2 far_offset = vec2(0.3, 0.7);
// Radius of the shadow (the photon capture edge), 3*sqrt(3)/2 Rs.
const float SHADOW_R = 2.598;

varying vec2 v_local;

// Integer hash (PCG) of a lattice corner. A float hash like the old
// fract(p * k) one is chaotic, so the GPU rounding the same corner slightly
// differently from two neighbouring cells (fused multiply-adds) gave it two
// values and the noise broke into visible squares. Integers hash exactly.
uint pcg(uint v) {
	uint s = v * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (w >> 22u) ^ w;
}

float hash21(vec2 p) {
	ivec2 c = ivec2(floor(p + 0.5));
	return float(pcg(uint(c.x) ^ pcg(uint(c.y)))) / 4294967295.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = p - i;
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

// Each octave is turned as well as scaled, so the value-noise grid doesn't
// line up from octave to octave and show as square blobs.
float fbm(vec2 p) {
	const mat2 octave_turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = octave_turn * p * 2.03 + vec2(17.1, 9.4);
		a *= 0.5;
	}
	return v;
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
		if (!wormhole && s0 * s1 < 0.0) {
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

	vec2 sky_size = vec2(textureSize(starfield, 0));
	vec3 background = vec3(0.0);
	float rr = length(v_local);
	// One pixel's width in Rs, for anti-aliasing the throat's edge.
	float px = max(fwidth(rr), 0.01);
	// Whether a ray falls into the throat is set by its impact parameter alone
	// (the ray starts straight down, so that is rr). Deciding it here instead
	// of from the traced `captured` gives a clean round edge, anti-aliased over
	// a pixel, where the stepped trace leaves it ragged and stair-stepped.
	float inside = wormhole ? 1.0 - smoothstep(SHADOW_R - px, SHADOW_R + px, rr) : 0.0;
	vec3 far_side = vec3(0.0);
	if (inside > 0.0) {
		// The other side: a fisheye of a far patch of sky, squeezed toward
		// the throat's edge and turning slowly.
		vec2 q = v_local / SHADOW_R;
		float k = min(length(q), 1.0);
		float turn = planet_time * 0.02;
		mat2 rot = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn)));
		vec2 fq = rot * (q * (1.0 + 2.2 * k * k));
		vec2 far_uv = far_offset + fq * 0.16;
		// Wrap by hand (the sampler clamps), but take the mip level from the
		// unwrapped coordinates so the wrap doesn't draw a seam.
		vec3 stars = textureGrad(starfield, fract(far_uv), dFdx(far_uv), dFdy(far_uv)).rgb;
		float cloud = fbm(fq * 2.2 + far_offset * 17.0 + vec2(turn * 3.0, 0.0));
		vec3 nebula = far_tint * smoothstep(0.35, 0.9, cloud) * 0.45;
		far_side = stars * mix(vec3(1.0), far_tint, 0.5) * 1.8 + nebula;
		// Darker toward the edge, where the view grazes the throat.
		far_side *= 1.0 - 0.6 * smoothstep(0.6, 1.0, k);
	}
	if (!captured && through > 0.02) {
		vec3 d = normalize(vel);
		if (d.y < -0.05) {
			// Where the bent ray meets the far background, back in world space.
			// The bend is eased to nothing toward the quad's edge, so the star
			// image there matches the untouched sky it fades into.
			float lens_fade = 1.0 - smoothstep(extent * 0.4, extent * 0.85, length(v_local));
			vec2 lensed = v_local + d.xz / -d.y * lens_distance * lens_fade;
			float rs_world = length(MODEL_MATRIX[0].xyz) / (2.0 * extent);
			vec3 world = NODE_POSITION_WORLD + vec3(lensed.x, 0.0, lensed.y) * rs_world;
			vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
			vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
			uv.y = 1.0 - uv.y;
			// Same fit as the Background TextureRect: keep aspect, cover.
			float cover = max(VIEWPORT_SIZE.x / sky_size.x, VIEWPORT_SIZE.y / sky_size.y);
			vec2 sky_uv = (uv - 0.5) * VIEWPORT_SIZE / (sky_size * cover) + 0.5;
			background = texture(starfield, sky_uv).rgb * (1.0 - starfield_dim);
		}
		// Light near the shadow is strongly magnified but also dimmed as the
		// ray grazes the photon sphere; keep the rim from blowing out.
	}

	// Soft shoulder: bright parts roll off instead of clipping to flat white,
	// but still pass 1.0 so the scene's glow blooms them.
	if (wormhole) {
		background = mix(background, far_side, inside);
		// Glowing lip of the throat, streaked as it turns. The noise cells
		// are long along the ring and wider than the lip across it, with a
		// slight spiral, so they read as smooth streaks rather than blocks.
		float ang = atan(v_local.y, v_local.x) / TAU;
		float swirl = fract(ang - planet_time * 0.03 + rr * 0.04);
		float streak = fbm_wrap(vec2(swirl * 48.0, rr * 0.7), 48.0);
		float rim = exp(-pow((rr - SHADOW_R) / 0.28, 2.0)) * (0.6 + 0.8 * streak);
		float halo = exp(-max(rr - SHADOW_R, 0.0) * 0.9) * (1.0 - inside) * 0.12;
		light += mix(far_tint, vec3(1.0), 0.45) * (rim * 1.3 + halo);
	}
	light = light / (1.0 + 0.3 * light);
	vec3 color = light + through * background;

	// Blend into the untouched view (with its map lines) toward the edge.
	float edge_fade = 1.0 - smoothstep(extent * 0.55, extent * 0.95, length(v_local));
	ALBEDO = color;
	ALPHA = edge_fade;
}

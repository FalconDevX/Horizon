shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled;

// The atmosphere as a shell round the planet, added on top: a soft halo
// beyond the limb and a thin haze over the disc, both lit by the sun, blue
// (or whatever the air is) on the day side and reddened along the
// terminator. Density falls off exponentially with height, and the glow at
// any pixel follows how much air its line of sight grazes - measured by the
// impact parameter: how close that line passes to the planet's centre.

// Outer edge of the shell and the density scale height, in planet radii
// (the unit sphere is the planet's surface).
uniform float shell_radius = 1.15;
uniform float scale_height = 0.03;
// Where the air starts: the sea, or the cloud tops on a giant.
uniform float base_radius = 1.0;
uniform vec3 atmo_color : source_color = vec3(0.4, 0.6, 1.0);
uniform float strength : hint_range(0.0, 4.0) = 1.0;
// Tips the sunlight up toward the camera - see planet_surface_3d.gdshader.
uniform float light_lift : hint_range(0.0, 2.0) = 0.35;

global uniform vec3 sun_position;

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
	VERTEX = v_dir * shell_radius;
}

void fragment() {
	// Everything in planet space, where the planet is the unit sphere.
	mat3 to_planet = transpose(mat3(MODEL_MATRIX));
	vec3 V = normalize(to_planet * INV_VIEW_MATRIX[2].xyz);
	vec3 to_sun = normalize(sun_position - NODE_POSITION_WORLD);
	vec3 L = normalize(to_planet * normalize(to_sun + vec3(0.0, light_lift, 0.0)));

	vec3 p = v_dir * shell_radius;
	// Closest approach of the view ray to the centre.
	vec3 closest = p - V * dot(p, V);
	float impact = length(closest);

	float glow;
	vec3 lit_dir;
	float beyond_limb = 1.0;
	if (impact > base_radius) {
		// Beyond the limb: the ray grazes the air, densest at the bottom.
		float altitude = impact - base_radius;
		glow = exp(-altitude / scale_height);
		lit_dir = closest / impact;
	} else {
		// Over the disc: a thin veil, thickening toward the limb where the
		// line of sight runs through more of it.
		float mu = sqrt(max(1.0 - impact * impact / (base_radius * base_radius), 0.0));
		glow = 0.1 + 0.9 * pow(1.0 - mu, 3.0);
		lit_dir = normalize(p);
		beyond_limb = 0.0;
	}

	// Fade the shell's own hard edge away.
	glow *= 1.0 - smoothstep(shell_radius * 0.92, shell_radius, impact);

	float sun = dot(lit_dir, L);
	float day = smoothstep(-0.25, 0.35, sun);
	// Twilight: the light that reaches the terminator has crossed the most air
	// and lost its blue.
	float twilight = exp(-pow(sun / 0.18, 2.0));
	// Only seen edge-on: over the disc it would tint the whole night side.
	vec3 col = atmo_color * day + vec3(1.0, 0.45, 0.2) * twilight * 0.55 * beyond_limb;

	ALBEDO = col * glow * strength;
}

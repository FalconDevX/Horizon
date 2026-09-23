shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

// The cloud deck of a planet: a shell a little above its highest ground,
// sharing the planet's mesh and transform, so clouds pass over mountains,
// stand proud of the limb and slide over the terrain with parallax. The
// weather itself is planet_clouds.gdshaderinc, which the terrain also reads
// for the shadows these clouds cast.
//
// Lighting fakes volume: the thickness field is sampled a step toward the
// sun, and wherever the cloud gets thicker that way, this spot is in the
// shade of its own billows. Thin edges let light through and glow; the
// terminator tints them with sunset.

// Shell height over the unit sphere, just above the lowlands.
uniform float shell_height = 0.1;
uniform vec3 pole_axis = vec3(0.0, 1.0, 0.0);
uniform float seed_offset = 0.0;
uniform vec3 atmo_color : source_color = vec3(0.4, 0.6, 1.0);
uniform float atmo_strength : hint_range(0.0, 3.0) = 0.6;
uniform float ambient : hint_range(0.0, 1.0) = 0.04;
// Tips the sunlight up toward the camera - see planet_surface_3d.gdshader.
uniform float light_lift : hint_range(0.0, 2.0) = 0.35;
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.9);

global uniform vec3 sun_position;

const int CLOUD_OCTAVES = 5;

varying vec3 v_dir;

#include "res://planet_noise.gdshaderinc"
#include "res://planet_clouds.gdshaderinc"

void vertex() {
	v_dir = normalize(VERTEX);
	VERTEX = v_dir * (1.0 + shell_height);
}

void fragment() {
	vec3 d = normalize(v_dir);
	float footprint = max(length(fwidth(v_dir)), 1e-6);

	vec2 here = cloud_field(d, footprint, CLOUD_OCTAVES);
	if (here.x <= 0.002) {
		discard;
	}

	vec3 to_sun = normalize(sun_position - NODE_POSITION_WORLD);
	vec3 L = normalize(to_sun + vec3(0.0, light_lift, 0.0));
	vec3 L_planet = normalize(transpose(mat3(MODEL_MATRIX)) * L);
	vec3 V = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 sw = normalize((MODEL_MATRIX * vec4(d, 0.0)).xyz);

	// Self-shadow: how much more cloud lies a step toward the sun.
	vec3 toward_sun = L_planet - d * dot(L_planet, d);
	float step_size = max(0.012, footprint * 3.0);
	vec2 sunward = cloud_field(normalize(d + toward_sun * step_size / max(length(toward_sun), 1e-4)), footprint, 2);
	float occlusion = clamp((sunward.y - here.y) * 2.2, -0.4, 1.0);
	float self_light = clamp(1.0 - occlusion * 0.55, 0.35, 1.25);

	float sphere_light = dot(sw, L);
	float day = smoothstep(-0.12, 0.18, sphere_light);
	float sun = clamp(sphere_light * 0.9 + 0.1, 0.0, 1.0) * day;

	// Thick cores go dense and bright-topped; thin veils stay translucent and
	// catch the light at their edges.
	float edge_glow = (1.0 - here.y) * here.x * 0.25;
	vec3 base = mix(cloud_color * vec3(0.78, 0.82, 0.9), cloud_color, here.y);

	// Sunset along the terminator.
	vec3 sunlight = sun_color * mix(vec3(1.0, 0.6, 0.38), vec3(1.0), smoothstep(-0.04, 0.14, sphere_light));

	vec3 lit = base * (ambient + (1.0 - ambient) * sun * self_light * sunlight);
	lit += sunlight * edge_glow * day;

	// Blue sky light filling the shaded sides, and haze toward the limb.
	float facing = clamp(dot(sw, V), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.0);
	lit += atmo_color * 0.06 * atmo_strength * day;
	lit = mix(lit, atmo_color * day, rim * 0.35 * min(atmo_strength, 1.0));

	// Seen edge-on, a veil is a longer path through cloud: denser at the limb.
	float alpha = here.x * mix(0.55, 1.0, here.y);
	alpha = clamp(alpha * (1.0 + rim * 0.8), 0.0, 0.97);

	ALBEDO = lit;
	ALPHA = alpha;
}

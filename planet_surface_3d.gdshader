shader_type spatial;
render_mode unshaded, cull_back;

// A planet as a real sphere. The mesh is a unit sphere; its object-space
// direction IS the planet-space direction the surface lookup wants, because
// the node's rotation (not a uniform) turns the planet. Terrain is pushed out
// along that direction in vertex(), and lit by hand in fragment() so the light
// always comes from the sun whatever the scale of the system.

#include "res://planet_surface_common.gdshaderinc"

const int RIDGE_OCTAVES = 4;

// Step along the surface used to measure the slope for the normal. Small next
// to a vertex spacing on the high-detail mesh.
const float NORMAL_STEP = 0.01;

// How far the highest ground rises, as a fraction of the radius. Exaggerated
// on purpose: true-scale mountains would be invisible from orbit.
uniform float relief : hint_range(0.0, 0.2) = 0.06;

// Blend width for terrain height between neighbouring blobs, in the same
// dot-difference units as edge_softness but far wider, so ground slopes up
// across a cell instead of stepping at the coastline. Set per planet from its
// blob count - see PlanetSurface.height_blend_for().
uniform float height_blend = 0.1;

// Frequency of the ridge noise laid over the terrain.
uniform float ridge_frequency : hint_range(1.0, 16.0) = 5.0;

// Night-side floor, so the dark half still reads.
uniform float ambient : hint_range(0.0, 1.0) = 0.14;

// Tips the sunlight up toward the camera. The sun sits in the orbital plane,
// so a camera looking straight down would otherwise see every planet exactly
// half dark.
uniform float light_lift : hint_range(0.0, 2.0) = 0.35;

global uniform vec3 sun_position;

varying vec3 v_planet_dir;
varying vec3 v_world_normal;

// Ground height of a palette slot. Slot 0 is the dominant colour (60% of the
// surface) and becomes the lowlands, slot 1 the uplands, every accent a
// mountain range. Mirrored by PlanetSurface.slot_height().
float slot_height(int color_index) {
	return min(float(color_index), 2.0) * 0.5;
}

// Ridged sine noise in 0..1. Sines rather than a hash for the same reason as
// surface_warp(): the CPU mirror in PlanetSurface.ridge_field() has to agree.
float ridge_field(vec3 position, float base_frequency) {
	vec3 p = position;
	float sum = 0.0;
	float amplitude = 0.5;
	float frequency = base_frequency;

	for (int i = 0; i < RIDGE_OCTAVES; i++) {
		float n = sin(p.x * frequency + 0.7)
			* sin(p.y * frequency * 1.17 + 2.9)
			* sin(p.z * frequency * 0.93 + 4.3);
		sum += amplitude * (1.0 - abs(n));
		amplitude *= 0.5;
		frequency *= 2.03;
		p = p.yzx;
	}

	// Amplitudes sum to 0.5 + 0.25 + 0.125 + 0.0625.
	return sum / 0.9375;
}

// Terrain height in 0..1 at a planet-space direction. Mirrored by
// PlanetSurface.elevation_at() - keep the two identical.
float surface_elevation(vec3 dir) {
	int best = 0;
	int second = 0;
	float best_dot = -2.0;
	float second_dot = -2.0;
	nearest_blobs(warp_direction(dir), best, second, best_dot, second_dot);

	float near_height = slot_height(int(blobs[best].w));
	float far_height = slot_height(int(blobs[second].w));
	float weight = 0.5 + 0.5 * smoothstep(0.0, max(height_blend, 1e-5), best_dot - second_dot);
	float base = mix(far_height, near_height, weight);

	float ridge = ridge_field(dir, ridge_frequency);
	return (base * (0.6 + 0.4 * ridge) + 0.1 * ridge) / 1.1;
}

vec3 displaced(vec3 dir) {
	return dir * (1.0 + relief * surface_elevation(dir));
}

void vertex() {
	vec3 dir = normalize(VERTEX);

	// Normal from the displaced surface itself: sample two nearby points along
	// the tangent plane and cross the slopes. The sphere's own normal would
	// light the mountains as if they were flat.
	vec3 helper = abs(dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(helper, dir));
	vec3 bitangent = cross(dir, tangent);

	vec3 here = displaced(dir);
	vec3 along_tangent = displaced(normalize(dir + tangent * NORMAL_STEP));
	vec3 along_bitangent = displaced(normalize(dir + bitangent * NORMAL_STEP));

	VERTEX = here;
	NORMAL = normalize(cross(along_tangent - here, along_bitangent - here));

	v_planet_dir = dir;
	v_world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 base = surface_color(normalize(v_planet_dir));

	vec3 to_sun = normalize(sun_position - NODE_POSITION_WORLD);
	vec3 sun_dir = normalize(to_sun + vec3(0.0, light_lift, 0.0));
	float lambert = max(dot(normalize(v_world_normal), sun_dir), 0.0);

	ALBEDO = base * mix(ambient, 1.0, lambert);
}

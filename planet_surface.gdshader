shader_type canvas_item;

// Draws a sphere onto a flat quad. For each pixel we work out which point of
// the unit sphere is under it, rotate that point out of view space and into
// the planet's own frame, then ask which blob is nearest. No mesh, no 3D node
// - the circle never changes shape, only the colours inside it.

const int MAX_BLOBS = 256;
const int MAX_COLORS = 8;
const int WARP_OCTAVES = 3;

// xyz = blob direction on the unit sphere, w = index into palette.
uniform vec4 blobs[MAX_BLOBS];
uniform vec4 palette[MAX_COLORS];
uniform int blob_count = 0;

// Planet orientation as a quaternion (x, y, z, w), mapping planet space into
// view space. Advanced on the CPU by composing rotations.
uniform vec4 planet_rotation = vec4(0.0, 0.0, 0.0, 1.0);

// Bends the lookup direction before the nearest-blob test, so the straight
// edges a Voronoi diagram produces come out ragged. PlanetSurface.gd runs the
// identical function, so CPU queries still agree with what is drawn.
uniform float warp_strength : hint_range(0.0, 0.5) = 0.12;
uniform float warp_frequency : hint_range(0.5, 12.0) = 3.0;

// Width of the blend between the nearest and second-nearest blob, measured in
// dot-product difference. 0.0 gives the old hard step.
uniform float edge_softness : hint_range(0.0, 0.2) = 0.02;

// Purely geometric shading so the disc reads as a ball. Set to 0.0 for flat.
uniform float limb_darkening : hint_range(0.0, 1.0) = 0.45;

// Grayscale material textures, one array layer per terrain type (ocean, sand,
// mountains). Array layers rather than separate samplers, because GLSL will
// not index an array of samplers with a value only known at run time.
//
// The gray is data, not colour: it says how far along the slot's colour ramp a
// pixel sits. That is why there is no source_color hint - that hint would
// treat the values as sRGB colour and bend them.
uniform sampler2DArray surface_textures : filter_linear_mipmap, repeat_enable;
uniform bool use_textures = false;

// Per palette slot: which terrain layer it reads, and the dark and light ends
// of its colour ramp. The palette colour is the middle of the ramp.
uniform float slot_terrain[MAX_COLORS];
uniform vec4 ramp_low[MAX_COLORS];
uniform vec4 ramp_high[MAX_COLORS];

// How many times a texture repeats across the planet.
uniform float texture_scale : hint_range(0.5, 32.0) = 4.0;

// 0.0 shows flat palette colours, 1.0 the full colour ramp.
uniform float texture_strength : hint_range(0.0, 1.0) = 1.0;

// Procedural height, sampled in planet space so the relief turns with the
// planet. It picks where on the slot's colour ramp a pixel sits, and the
// tiled texture is layered on top as fine grain. Rendering only: it is
// hash-based, so unlike the warp it has no CPU mirror and gameplay lookups
// know nothing about it.
uniform bool use_elevation = false;
uniform vec3 elevation_offset = vec3(0.0);
uniform float elevation_frequency : hint_range(0.5, 8.0) = 2.0;
uniform int elevation_octaves : hint_range(1, 8) = 5;
uniform float texture_detail : hint_range(0.0, 1.0) = 0.6;

// Sunlight in view space (x right, y up, z towards the camera), unit length.
// When lit, this replaces limb darkening: the falloff towards the terminator
// is what makes the disc read as a ball.
uniform bool use_lighting = false;
uniform vec3 light_direction = vec3(-0.6, 0.5, 0.6);
uniform float ambient_light : hint_range(0.0, 1.0) = 0.15;

// How far relief tilts the lighting normal. 0.0 is flat.
uniform float bump_strength : hint_range(0.0, 0.5) = 0.12;

// How far out from the coast water reaches full depth, in the same
// dot-product units as edge_softness. Shallows sit at the light end of the
// ocean ramp, deep water at the dark end.
uniform float ocean_shelf_width : hint_range(0.01, 0.3) = 0.06;
uniform float ocean_glint : hint_range(0.0, 1.0) = 0.5;

// Cold biomes. pole_axis is the spin axis in planet space. polar_cap is the
// share of the sphere iced over at sea level: a cap's area is proportional to
// its height along the axis, so a threshold on |latitude| of 1 - polar_cap
// covers exactly that share across both poles.
uniform bool use_biomes = false;
uniform vec3 pole_axis = vec3(0.0, 1.0, 0.0);
uniform float polar_cap : hint_range(0.0, 1.0) = 0.12;

// Mirror PlanetSurface.Terrain.
const int TERRAIN_OCEAN = 0;
const int TERRAIN_SAND = 1;
const int TERRAIN_MOUNTAINS = 2;

// Stretch on layered noise (std ~0.12). Kept to the middle of the ramp:
// pushed to the ends, broad height reads as smoke and swamps the texture grain.
const float SAND_CONTRAST = 1.1;

// Physical relief per terrain. Sand is dunes, not peaks.
const float MOUNTAIN_RELIEF = 1.0;
const float SAND_RELIEF = 0.35;

// Slope sampling distance in radians, set to about one pixel. Relief finer
// than a pixel then averages out instead of sparkling.
const float MIN_BUMP_STEP = 0.0005;
const float MAX_BUMP_STEP = 0.05;

// Ocean ramp positions at the shore and in open water.
const float SHALLOW_GRAY = 0.85;
const float DEEP_GRAY = 0.15;
const float SEAFLOOR_ROUGHNESS = 3.0;
const float GLINT_SHININESS = 120.0;

const vec3 ICE_COLOR = vec3(0.90, 0.94, 0.98);
// How much of the colour underneath shows through the ice, so abstract
// worlds get tinted ice rather than all the same white.
const float ICE_TINT = 0.15;
const float ICE_EDGE = 0.03;
const float TUNDRA_WIDTH = 0.15;
const float TUNDRA_FADE = 0.45;
// Coldness added per unit of relief - how fast the snow line drops.
const float SNOW_LAPSE = 1.2;
const float BIOME_WOBBLE = 0.8;
const float BIOME_WOBBLE_FREQUENCY = 1.5;

// Sharpening applied before the ridge fold. At 1.6 the ridged sum averages
// about 0.5, so it only needs squeezing towards the middle - at full spread
// the ridges read as bright veins rather than peaks.
const float RIDGE_SHARPNESS = 1.6;
const float RIDGE_WEIGHT_GAIN = 1.5;
const float RIDGE_CONTRAST = 0.7;

// Decorrelates octaves, which would otherwise all share a lattice origin.
const vec3 OCTAVE_SHIFT = vec3(19.1, 7.7, 13.3);

vec3 quat_rotate(vec4 q, vec3 v) {
	vec3 t = 2.0 * cross(q.xyz, v);
	return v + q.w * t + cross(q.xyz, t);
}

// Triplanar sampling: read the texture down each of the three axes and blend
// by how much the surface faces that way. A sphere has no sensible UVs - wrap
// a flat image round one and it pinches at the poles and seams at the join -
// and this sidesteps the problem by never needing them.
float triplanar_gray(vec3 dir, float layer) {
	vec3 blend = abs(dir);
	blend /= max(blend.x + blend.y + blend.z, 1e-5);

	float down_x = texture(surface_textures, vec3(dir.yz * texture_scale, layer)).r;
	float down_y = texture(surface_textures, vec3(dir.zx * texture_scale, layer)).r;
	float down_z = texture(surface_textures, vec3(dir.xy * texture_scale, layer)).r;

	return down_x * blend.x + down_y * blend.y + down_z * blend.z;
}

// Three-stop ramp: gray 0 is the dark end, 0.5 the palette colour, 1 the light end.
vec3 ramp(int slot, float gray) {
	vec3 middle = palette[slot].rgb;
	if (gray < 0.5) {
		return mix(ramp_low[slot].rgb, middle, gray * 2.0);
	}
	return mix(middle, ramp_high[slot].rgb, gray * 2.0 - 1.0);
}

// PCG3D integer hash (Jarzynski & Olano), -1..1 per component. Integer on
// purpose: a float hash is chaotic, and the compiler fuses multiply-adds
// differently depending on which neighbouring cell asks about a shared
// corner, so the same corner hashed to different gradients from either side
// and the noise tore along lattice planes. Integer maths is exact.
vec3 hash33(ivec3 cell) {
	uvec3 v = uvec3(cell) * 1664525u + 1013904223u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	v ^= v >> 16u;
	v.x += v.y * v.z;
	v.y += v.z * v.x;
	v.z += v.x * v.y;
	return vec3(v) * (2.0 / 4294967295.0) - 1.0;
}

float lattice_corner(ivec3 cell, vec3 local, ivec3 corner) {
	return dot(hash33(cell + corner), local - vec3(corner));
}

// 3D gradient noise, std ~0.2 around 0. Quintic fade, so the slope is
// continuous as well as the value.
float gradient_noise(vec3 p) {
	vec3 floored = floor(p);
	ivec3 cell = ivec3(floored);
	vec3 local = p - floored;
	vec3 u = local * local * local * (local * (local * 6.0 - 15.0) + 10.0);

	float x00 = mix(
		lattice_corner(cell, local, ivec3(0, 0, 0)),
		lattice_corner(cell, local, ivec3(1, 0, 0)),
		u.x
	);
	float x10 = mix(
		lattice_corner(cell, local, ivec3(0, 1, 0)),
		lattice_corner(cell, local, ivec3(1, 1, 0)),
		u.x
	);
	float x01 = mix(
		lattice_corner(cell, local, ivec3(0, 0, 1)),
		lattice_corner(cell, local, ivec3(1, 0, 1)),
		u.x
	);
	float x11 = mix(
		lattice_corner(cell, local, ivec3(0, 1, 1)),
		lattice_corner(cell, local, ivec3(1, 1, 1)),
		u.x
	);

	return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z);
}

// Layered noise: each octave doubles the frequency and halves the amplitude,
// so broad shapes carry progressively finer detail. Std ~0.12 around 0.
float layered_noise(vec3 p) {
	float sum = 0.0;
	float total = 0.0;
	float amplitude = 1.0;
	float frequency = 1.0;

	for (int i = 0; i < elevation_octaves; i++) {
		sum += amplitude * gradient_noise(p * frequency + OCTAVE_SHIFT * float(i));
		total += amplitude;
		amplitude *= 0.5;
		frequency *= 2.0;
	}

	return sum / total;
}

// Ridged layered noise. 1 - |n| folds each octave into a sharp crease, and
// squaring narrows the crease into a ridge line. Each octave is weighted by
// the one before, so fine detail clusters along ridges instead of filling the
// valleys evenly. Roughly 0..1, averaging about 0.5.
float ridged_noise(vec3 p) {
	float sum = 0.0;
	float total = 0.0;
	float amplitude = 1.0;
	float frequency = 1.0;
	float weight = 1.0;

	for (int i = 0; i < elevation_octaves; i++) {
		float n = 1.0 - abs(
			gradient_noise(p * frequency + OCTAVE_SHIFT * float(i)) * RIDGE_SHARPNESS
		);
		n *= n * weight;
		weight = clamp(n * RIDGE_WEIGHT_GAIN, 0.0, 1.0);
		sum += amplitude * n;
		total += amplitude;
		amplitude *= 0.5;
		frequency *= 2.0;
	}

	return sum / total;
}

// The noise behind a terrain, before shaping: ridged 0..1 for mountains,
// layered and centred on 0 otherwise. For ocean it is only seafloor roughness.
float terrain_noise(vec3 dir, int terrain) {
	vec3 p = dir * elevation_frequency + elevation_offset;

	if (terrain == TERRAIN_MOUNTAINS) {
		return ridged_noise(p);
	}

	if (terrain == TERRAIN_SAND) {
		return layered_noise(p * 2.0);
	}

	return layered_noise(p);
}

// Position on a land slot's colour ramp. Centred on 0.5, the palette colour,
// so a planet's overall colour stays what the palette generator picked.
float land_gray(float noise, int terrain) {
	if (terrain == TERRAIN_MOUNTAINS) {
		return 0.5 + (noise - 0.5) * RIDGE_CONTRAST;
	}

	return 0.5 + noise * SAND_CONTRAST;
}

// Physical height, in the units bump_strength scales. Drives slope shading
// and the snow line.
float relief(float noise, int terrain) {
	if (terrain == TERRAIN_MOUNTAINS) {
		return (noise - 0.5) * MOUNTAIN_RELIEF;
	}

	return noise * SAND_RELIEF;
}

// Light at the shore, dark in open water. The seafloor noise stretches the
// shelf in some places and pulls it in at others, so the shallows are not a
// uniform band hugging every coast.
float ocean_gray(float noise, float coast_gap) {
	float depth = clamp(
		coast_gap / ocean_shelf_width * (1.0 + noise * SEAFLOOR_ROUGHNESS), 0.0, 1.0
	);
	return mix(SHALLOW_GRAY, DEEP_GRAY, smoothstep(0.0, 1.0, depth));
}

// What one palette slot looks like at a point: colour, planet-space normal and
// height. The colour is a position on the slot's ramp, from the height field,
// the terrain texture, or both. Gradient mapping - only the ramps differ
// between planets.
//
// The normal is slope shading. Height is sampled one bump_step along each
// tangent and the normal tilted down the slope, so relief catches the light
// while the silhouette stays a circle. Water is left flat.
void slot_surface(
	int slot,
	vec3 dir,
	vec3 tangent,
	vec3 bitangent,
	float bump_step,
	float coast_gap,
	out vec3 color,
	out vec3 normal,
	out float height
) {
	int terrain = int(slot_terrain[slot]);
	color = palette[slot].rgb;
	normal = dir;
	height = 0.0;

	float gray = use_textures ? triplanar_gray(dir, slot_terrain[slot]) : 0.5;

	if (use_elevation) {
		float noise = terrain_noise(dir, terrain);
		float grain = use_textures ? (gray - 0.5) * texture_detail : 0.0;

		if (terrain == TERRAIN_OCEAN) {
			gray = ocean_gray(noise, coast_gap) + grain;
		} else {
			gray = land_gray(noise, terrain) + grain;
			height = relief(noise, terrain);

			if (bump_strength > 0.0) {
				float along_tangent = relief(
					terrain_noise(normalize(dir + tangent * bump_step), terrain), terrain
				);
				float along_bitangent = relief(
					terrain_noise(normalize(dir + bitangent * bump_step), terrain), terrain
				);
				vec3 slope = (
					tangent * (along_tangent - height)
					+ bitangent * (along_bitangent - height)
				) / bump_step;
				normal = normalize(dir - slope * bump_strength);
			}
		}

		gray = clamp(gray, 0.0, 1.0);
	}

	if ((use_textures || use_elevation) && texture_strength > 0.0) {
		color = mix(color, ramp(slot, gray), texture_strength);
	}
}

// Ice caps, sea ice, snowy peaks, and a paler tundra band leading up to them.
// Coldness is latitude, wobbled by noise so the cap edge is not a perfect
// circle, and raised by altitude so peaks freeze further from the poles.
vec3 apply_cold(vec3 color, vec3 dir, float height, float water, out float ice) {
	float latitude = abs(dot(dir, pole_axis));
	float wobble = layered_noise(
		dir * elevation_frequency * BIOME_WOBBLE_FREQUENCY + elevation_offset.zxy
	) * BIOME_WOBBLE;
	float coldness = latitude + wobble + max(height, 0.0) * SNOW_LAPSE;
	float threshold = 1.0 - polar_cap;

	ice = smoothstep(threshold - ICE_EDGE, threshold + ICE_EDGE, coldness);

	float tundra = smoothstep(threshold - TUNDRA_WIDTH, threshold, coldness) * (1.0 - water);
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(color, vec3(luma), tundra * TUNDRA_FADE);

	return mix(color, mix(ICE_COLOR, color, ICE_TINT), ice);
}

// Smooth, well-conditioned displacement field. Deliberately built from sines
// rather than a hash: a hash is chaotic, so 32-bit GPU floats and 64-bit CPU
// floats would produce completely different fields and the CPU lookup would
// stop matching the picture. Sines are smooth, so the two agree to well under
// a pixel. Octave frequencies are incommensurate to hide the repetition.
vec3 surface_warp(vec3 p, float base_frequency) {
	vec3 sum = vec3(0.0);
	float amplitude = 1.0;
	float frequency = base_frequency;

	for (int i = 0; i < WARP_OCTAVES; i++) {
		sum += amplitude * vec3(
			sin(p.y * frequency + 1.7) * cos(p.z * frequency * 1.31 + 0.3),
			sin(p.z * frequency + 3.1) * cos(p.x * frequency * 1.27 + 1.9),
			sin(p.x * frequency + 5.3) * cos(p.y * frequency * 1.19 + 4.1)
		);
		amplitude *= 0.5;
		frequency *= 2.17;
	}

	return sum;
}

void fragment() {
	// UV 0..1 across the quad -> -1..1 centred, with y flipped because 2D
	// screen space points down while our view space points up.
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y;

	// Front hemisphere. view_dir is unit length inside the disc: r2 + (1 - r2) = 1.
	float r2 = dot(p, p);
	float z = sqrt(max(1.0 - r2, 0.0));
	vec3 view_dir = vec3(p, z);

	// Inverse of a unit quaternion is its conjugate.
	vec4 inverse_rotation = vec4(-planet_rotation.xyz, planet_rotation.w);
	vec3 planet_dir = quat_rotate(inverse_rotation, view_dir);

	// Screen-space derivatives come before the discard: they are unreliable in
	// a pixel quad that some of its pixels have already left.
	float edge = fwidth(r2);
	float bump_step = clamp(length(fwidth(planet_dir)), MIN_BUMP_STEP, MAX_BUMP_STEP);

	if (r2 > 1.0) {
		discard;
	}

	// Textures sample the unwarped direction. Warping it too would make the
	// material swim about as the warp wobbles, rather than sitting on the
	// surface; only the region boundaries should be ragged.
	vec3 surface_dir = planet_dir;

	if (warp_strength > 0.0) {
		planet_dir = normalize(
			planet_dir + surface_warp(planet_dir, warp_frequency) * warp_strength
		);
	}

	// The slope is basis-independent, so the switch of helper axis near the
	// poles does not show.
	vec3 helper = abs(surface_dir.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 tangent = normalize(cross(helper, surface_dir));
	vec3 bitangent = cross(surface_dir, tangent);

	// Nearest and second-nearest, so the boundary can be blended instead of
	// stepping. Tracking the runner-up costs one extra compare per blob.
	int best = 0;
	int second = 0;
	float best_dot = -2.0;
	float second_dot = -2.0;

	// Nearest water and nearest land. The coastline is exactly where the two
	// are equidistant, so their difference is 0 on the coast and grows
	// offshore - a distance to shore that comes free with the lookup.
	float best_water = -2.0;
	float best_land = -2.0;

	for (int i = 0; i < blob_count; i++) {
		float towards = dot(planet_dir, blobs[i].xyz);

		if (int(slot_terrain[int(blobs[i].w)]) == TERRAIN_OCEAN) {
			best_water = max(best_water, towards);
		} else {
			best_land = max(best_land, towards);
		}

		if (towards > best_dot) {
			second_dot = best_dot;
			second = best;
			best_dot = towards;
			best = i;
		} else if (towards > second_dot) {
			second_dot = towards;
			second = i;
		}
	}

	float coast_gap = best_water - best_land;
	int near_slot = int(blobs[best].w);
	int far_slot = int(blobs[second].w);

	vec3 near_color = vec3(0.0);
	vec3 near_normal = surface_dir;
	float near_height = 0.0;
	slot_surface(
		near_slot, surface_dir, tangent, bitangent, bump_step, coast_gap,
		near_color, near_normal, near_height
	);

	// Neighbours sharing a colour are the common case - that is what merges
	// cells into continents - so reuse the result instead of sampling twice.
	vec3 far_color = near_color;
	vec3 far_normal = near_normal;
	float far_height = near_height;

	if (far_slot != near_slot) {
		slot_surface(
			far_slot, surface_dir, tangent, bitangent, bump_step, coast_gap,
			far_color, far_normal, far_height
		);
	}

	// At a boundary the two distances are equal, so mix 50/50 and ramp to the
	// winner as we move inland. Neighbours sharing a colour blend invisibly,
	// which is what merges cells into continents.
	float lead = best_dot - second_dot;
	float weight = 0.5 + 0.5 * smoothstep(0.0, max(edge_softness, 1e-5), lead);
	vec3 base = mix(far_color, near_color, weight);
	vec3 normal = normalize(mix(far_normal, near_normal, weight));
	float height = mix(far_height, near_height, weight);
	float water = mix(
		float(int(slot_terrain[far_slot]) == TERRAIN_OCEAN),
		float(int(slot_terrain[near_slot]) == TERRAIN_OCEAN),
		weight
	);

	float ice = 0.0;

	if (use_biomes && polar_cap > 0.0) {
		base = apply_cold(base, surface_dir, height, water, ice);
	}

	vec3 color = base * mix(1.0 - limb_darkening, 1.0, z);

	if (use_lighting) {
		// view_dir is the exact normal of the smooth sphere, since the sphere is
		// analytic rather than a mesh. The bumped normal lights the terrain, but
		// is faded out past the terminator, where real relief would sit in its
		// own shadow rather than catch light it cannot see.
		float facing = dot(view_dir, light_direction);
		vec3 lit_normal = quat_rotate(planet_rotation, normal);
		float diffuse = max(dot(lit_normal, light_direction), 0.0)
			* smoothstep(-0.2, 0.05, facing);

		// Sun glint on open water, off the flat sphere normal. The camera looks
		// straight down view-space -z, so the view vector is +z everywhere.
		vec3 halfway = normalize(light_direction + vec3(0.0, 0.0, 1.0));
		float glint = pow(max(dot(view_dir, halfway), 0.0), GLINT_SHININESS)
			* ocean_glint * water * (1.0 - ice);

		color = base * (ambient_light + (1.0 - ambient_light) * diffuse) + vec3(glint);
	}

	// Soften the rim by roughly a pixel so the silhouette is not stair-stepped.
	float alpha = 1.0 - smoothstep(1.0 - edge * 2.0, 1.0, r2);

	COLOR = vec4(color, alpha);
}

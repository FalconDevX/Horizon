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

// One texture per palette slot, as array layers rather than separate samplers:
// GLSL will not let you index an array of samplers with a value it cannot work
// out at compile time, and the layer here is exactly that kind of value.
// Nothing happens until use_textures is set, so an unset array cannot break
// the flat look.
uniform sampler2DArray surface_textures : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_textures = false;
uniform int texture_layers = 1;

// Shifts which layer each palette slot reads, so two planets that both rolled
// three colours do not wear the same three materials.
uniform int texture_offset = 0;

// How many times a texture repeats across the planet.
uniform float texture_scale : hint_range(0.5, 32.0) = 4.0;

// 1.0 multiplies the texture by the planet's generated colour, 0.0 leaves the
// texture's own colours alone.
uniform float texture_tint : hint_range(0.0, 1.0) = 1.0;

vec3 quat_rotate(vec4 q, vec3 v) {
	vec3 t = 2.0 * cross(q.xyz, v);
	return v + q.w * t + cross(q.xyz, t);
}

// Triplanar sampling: read the texture down each of the three axes and blend
// by how much the surface faces that way. A sphere has no sensible UVs - wrap
// a flat image round one and it pinches at the poles and seams at the join -
// and this sidesteps the problem by never needing them.
vec3 triplanar(vec3 dir, int layer) {
	vec3 blend = abs(dir);
	blend /= max(blend.x + blend.y + blend.z, 1e-5);
	float slice = float(layer);

	vec3 down_x = texture(surface_textures, vec3(dir.yz * texture_scale, slice)).rgb;
	vec3 down_y = texture(surface_textures, vec3(dir.zx * texture_scale, slice)).rgb;
	vec3 down_z = texture(surface_textures, vec3(dir.xy * texture_scale, slice)).rgb;

	return down_x * blend.x + down_y * blend.y + down_z * blend.z;
}

// What a palette slot actually looks like: its generated colour, optionally
// carrying a texture.
vec3 material(int color_index, vec3 dir) {
	vec3 tint = palette[color_index].rgb;

	if (!use_textures) {
		return tint;
	}

	int layer = (color_index + texture_offset) % max(texture_layers, 1);
	return triplanar(dir, layer) * mix(vec3(1.0), tint, texture_tint);
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

	float r2 = dot(p, p);
	if (r2 > 1.0) {
		discard;
	}

	// Front hemisphere. view_dir is already unit length: r2 + (1 - r2) = 1.
	float z = sqrt(1.0 - r2);
	vec3 view_dir = vec3(p, z);

	// Inverse of a unit quaternion is its conjugate.
	vec4 inverse_rotation = vec4(-planet_rotation.xyz, planet_rotation.w);
	vec3 planet_dir = quat_rotate(inverse_rotation, view_dir);

	// Textures sample the unwarped direction. Warping it too would make the
	// material swim about as the warp wobbles, rather than sitting on the
	// surface; only the region boundaries should be ragged.
	vec3 surface_dir = planet_dir;

	if (warp_strength > 0.0) {
		planet_dir = normalize(
			planet_dir + surface_warp(planet_dir, warp_frequency) * warp_strength
		);
	}

	// Nearest and second-nearest, so the boundary can be blended instead of
	// stepping. Tracking the runner-up costs one extra compare per blob.
	int best = 0;
	int second = 0;
	float best_dot = -2.0;
	float second_dot = -2.0;

	for (int i = 0; i < blob_count; i++) {
		float towards = dot(planet_dir, blobs[i].xyz);
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

	int near_index = int(blobs[best].w);
	int far_index = int(blobs[second].w);
	vec3 near_color = material(near_index, surface_dir);

	// Neighbours sharing a colour are the common case - that is what merges
	// cells into continents - so reuse the result instead of sampling twice.
	vec3 far_color = near_index == far_index
		? near_color
		: material(far_index, surface_dir);

	// At a boundary the two distances are equal, so mix 50/50 and ramp to the
	// winner as we move inland. Neighbours sharing a colour blend invisibly,
	// which is what merges cells into continents.
	float lead = best_dot - second_dot;
	float weight = 0.5 + 0.5 * smoothstep(0.0, max(edge_softness, 1e-5), lead);
	vec3 base = mix(far_color, near_color, weight);

	float shade = mix(1.0 - limb_darkening, 1.0, z);

	// Soften the rim by roughly a pixel so the silhouette is not stair-stepped.
	float edge = fwidth(r2);
	float alpha = 1.0 - smoothstep(1.0 - edge * 2.0, 1.0, r2);

	COLOR = vec4(base * shade, alpha);
}

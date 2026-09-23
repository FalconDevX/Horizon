shader_type canvas_item;

// Draws a sphere onto a flat quad. For each pixel we work out which point of
// the unit sphere is under it, rotate that point out of view space and into
// the planet's own frame, then ask which blob is nearest. No mesh, no 3D node
// - the circle never changes shape, only the colours inside it.
//
// Only the 2D editor preview uses this now; the running game draws planets as
// real spheres with planet_surface_3d.gdshader. Both share the lookup below.

#include "res://planet_surface_common.gdshaderinc"

// Planet orientation as a quaternion (x, y, z, w), mapping planet space into
// view space. Advanced on the CPU by composing rotations.
uniform vec4 planet_rotation = vec4(0.0, 0.0, 0.0, 1.0);

// Purely geometric shading so the disc reads as a ball. Set to 0.0 for flat.
uniform float limb_darkening : hint_range(0.0, 1.0) = 0.45;

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

	vec3 base = surface_color(planet_dir);

	float shade = mix(1.0 - limb_darkening, 1.0, z);

	// Soften the rim by roughly a pixel so the silhouette is not stair-stepped.
	float edge = fwidth(r2);
	float alpha = 1.0 - smoothstep(1.0 - edge * 2.0, 1.0, r2);

	COLOR = vec4(base * shade, alpha);
}

shader_type canvas_item;
render_mode unshaded;

uniform mat3 inverse_view_rotation;
uniform vec4 deep_color : source_color = vec4(0.05, 0.14, 0.2, 1.0);
uniform vec4 low_color : source_color = vec4(0.16, 0.3, 0.2, 1.0);
uniform vec4 mid_color : source_color = vec4(0.36, 0.52, 0.28, 1.0);
uniform vec4 high_color : source_color = vec4(0.78, 0.74, 0.58, 1.0);
uniform vec4 ice_color : source_color = vec4(0.88, 0.94, 0.98, 1.0);
uniform float seed = 1.0;
uniform float ocean_level = 0.46;

const mat3 NOISE_ROTATION = mat3(
	vec3(0.00, 0.80, 0.60),
	vec3(-0.80, 0.36, -0.48),
	vec3(-0.60, -0.48, 0.64)
);

float wave_noise(vec3 p) {
	float a = sin(dot(p, vec3(1.17, 1.91, 2.47)));
	float b = sin(dot(p, vec3(-2.03, 1.33, 0.91)) + a * 0.72);
	float c = sin(dot(p, vec3(0.73, -2.21, 1.61)) - b * 0.58);
	return (a + b * 0.62 + c * 0.38) / 2.0;
}

float noise3d(vec3 p) {
	float value = 0.0;
	float amplitude = 0.54;
	float amplitude_sum = 0.0;
	vec3 seed_offset = vec3(seed * 0.071, -seed * 0.053, seed * 0.097);
	for (int octave = 0; octave < 4; octave++) {
		value += wave_noise(p + seed_offset) * amplitude;
		amplitude_sum += amplitude;
		p = NOISE_ROTATION * p * 2.03 + vec3(0.37, -0.19, 0.43);
		amplitude *= 0.5;
	}
	return value / max(amplitude_sum, 0.001) * 0.5 + 0.5;
}

float terrain_height(vec3 sphere_point) {
	float continents = noise3d(sphere_point * 2.35);
	float detail = noise3d(sphere_point * 10.5 + vec3(4.7, -2.1, 1.3));
	float ridges = 1.0 - abs(detail * 2.0 - 1.0);
	return clamp(continents * 0.76 + detail * 0.17 + ridges * 0.07, 0.0, 1.0);
}

void fragment() {
	vec2 disk = UV * 2.0 - 1.0;
	float radius_squared = dot(disk, disk);
	if (radius_squared > 1.0) {
		discard;
	}

	float z = sqrt(max(1.0 - radius_squared, 0.0));
	vec3 view_normal = normalize(vec3(disk.x, -disk.y, z));
	vec3 planet_normal = normalize(inverse_view_rotation * view_normal);

	float terrain = terrain_height(planet_normal);
	float moisture = noise3d(planet_normal * 5.3 + vec3(-3.1, 5.7, 2.6));
	float detail = wave_noise(
		planet_normal * 22.0 + vec3(8.2, -4.6, 3.9) + seed * 0.031
	) * 0.5 + 0.5;
	float land_mask = smoothstep(ocean_level - 0.045, ocean_level + 0.045, terrain);
	float beach_mask = smoothstep(ocean_level, ocean_level + 0.035, terrain)
		* (1.0 - smoothstep(ocean_level + 0.035, ocean_level + 0.09, terrain));
	vec3 dry_land = mix(low_color.rgb, high_color.rgb, smoothstep(0.38, 0.76, terrain));
	vec3 wet_land = mix(low_color.rgb, mid_color.rgb, smoothstep(0.3, 0.72, terrain));
	vec3 land = mix(dry_land, wet_land, smoothstep(0.32, 0.72, moisture));
	land = mix(land, high_color.rgb, smoothstep(0.72, 0.93, terrain + detail * 0.08));
	land = mix(land, high_color.rgb, beach_mask * 0.42);
	vec3 color = mix(deep_color.rgb, land, land_mask);

	float polar = smoothstep(0.76, 0.96, abs(planet_normal.y));
	color = mix(color, ice_color.rgb, polar * 0.82);

	vec3 light = normalize(vec3(-0.55, 0.42, 0.72));
	vec3 displaced_position = view_normal * (1.0 + terrain * 0.055);
	vec3 displaced_view_normal = normalize(cross(dFdy(displaced_position), dFdx(displaced_position)));
	if (dot(displaced_view_normal, view_normal) < 0.0) {
		displaced_view_normal = -displaced_view_normal;
	}
	vec3 lighting_normal = normalize(mix(view_normal, displaced_view_normal, land_mask * 0.86));
	float diffuse = clamp(dot(lighting_normal, light) * 0.46 + 0.54, 0.16, 1.0);
	float ocean_specular = pow(max(dot(reflect(-light, view_normal), vec3(0.0, 0.0, 1.0)), 0.0), 28.0);
	float rim = pow(1.0 - z, 2.4);
	color *= diffuse;
	color += deep_color.rgb * ocean_specular * (1.0 - land_mask) * 0.55;
	color += vec3(0.12, 0.28, 0.42) * rim * 0.36;

	COLOR = vec4(color, 1.0);
}

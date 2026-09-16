shader_type canvas_item;
render_mode unshaded;

uniform mat3 inverse_view_rotation;
uniform vec4 deep_color : source_color = vec4(0.05, 0.14, 0.2, 1.0);
uniform vec4 low_color : source_color = vec4(0.16, 0.3, 0.2, 1.0);
uniform vec4 mid_color : source_color = vec4(0.36, 0.52, 0.28, 1.0);
uniform vec4 high_color : source_color = vec4(0.78, 0.74, 0.58, 1.0);
uniform vec4 ice_color : source_color = vec4(0.88, 0.94, 0.98, 1.0);
uniform vec4 glow_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 atmosphere_color : source_color = vec4(0.45, 0.7, 0.9, 0.18);
uniform vec2 light_direction = vec2(-0.7, -0.45);
// Default values render the normal world-space planet quad.  Surface mode
// supplies a screen-space disk, avoiding any scaled texture/mask.
uniform vec2 disk_center_uv = vec2(0.5, 0.5);
uniform vec2 disk_radius_uv = vec2(0.5, 0.5);
uniform float seed = 1.0;
uniform float ocean_level = 0.46;
uniform float cloud_time = 0.0;
uniform float lod = 1.0;
uniform float surface_detail_scale = 1.0;
uniform int planet_kind = 0;
uniform int quality = 1;
uniform int has_clouds = 0;

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

int octave_count() {
	if (quality <= 0 || lod < 0.35) {
		return 3;
	}
	if (quality == 1 || lod < 0.7) {
		return 5;
	}
	return 6;
}

float noise3d(vec3 p) {
	float value = 0.0;
	float amplitude = 0.54;
	float amplitude_sum = 0.0;
	vec3 seed_offset = vec3(seed * 0.071, -seed * 0.053, seed * 0.097);
	int octaves = octave_count();
	for (int octave = 0; octave < 6; octave++) {
		if (octave >= octaves) {
			break;
		}
		value += wave_noise(p + seed_offset) * amplitude;
		amplitude_sum += amplitude;
		p = NOISE_ROTATION * p * 2.03 + vec3(0.37, -0.19, 0.43);
		amplitude *= 0.5;
	}
	float raw = value / max(amplitude_sum, 0.001);
	return clamp(raw * 1.35 * 0.5 + 0.5, 0.0, 1.0);
}

float ridge_noise(vec3 p) {
	float n = noise3d(p);
	return clamp(1.0 - abs(n * 2.0 - 1.0) * 1.5, 0.0, 1.0);
}

float terrain_height(vec3 sphere_point) {
	float detail_scale = clamp(surface_detail_scale, 1.0, 3.0);
	float continents = noise3d(sphere_point * 2.2);
	float mountains = ridge_noise(sphere_point * 5.8 + vec3(2.1, -1.4, 0.8));
	float detail = 0.5;
	if (quality >= 1 && lod > 0.3) {
		// Closer orbital views (higher surface_detail_scale) pull in denser relief
		// so the space disk matches the surface-mode ground texture.
		detail = noise3d(sphere_point * (13.0 * mix(1.0, detail_scale, 0.65)) + vec3(4.7, -2.1, 1.3));
	}
	float base = smoothstep(0.32, 0.68, continents);
	float height = base * 0.55 + mountains * 0.32 + detail * 0.13;
	if (planet_kind == 4) {
		height = 0.5 + sin(sphere_point.y * 22.0 + seed) * 0.14 + continents * 0.12;
	}
	return clamp(height, 0.0, 1.0);
}

vec3 shade_surface(vec3 planet_normal, float terrain, float moisture) {
	float land_mask = smoothstep(ocean_level - 0.04, ocean_level + 0.04, terrain);
	vec3 color = deep_color.rgb;
	float polar = smoothstep(0.72, 0.94, abs(planet_normal.y));

	if (planet_kind == 1) {
		// Ocean Planet: deep abyss, turquoise coastal shelves, sand beaches, lush plains, mountains, snow caps
		float abyss_mask = smoothstep(ocean_level - 0.16, ocean_level - 0.04, terrain);
		vec3 ocean = mix(deep_color.rgb, mix(deep_color.rgb, vec3(0.08, 0.48, 0.55), 0.7), abyss_mask);
		vec3 beach = mix(high_color.rgb, low_color.rgb, 0.25);
		vec3 low_plains = mix(low_color.rgb, mid_color.rgb, smoothstep(0.35, 0.7, moisture));
		vec3 highlands = mix(mid_color.rgb, high_color.rgb, smoothstep(0.65, 0.82, terrain));
		vec3 snow_peaks = mix(highlands, ice_color.rgb, smoothstep(0.82, 0.94, terrain));
		vec3 land = mix(beach, low_plains, smoothstep(ocean_level, ocean_level + 0.06, terrain));
		land = mix(land, snow_peaks, smoothstep(0.65, 0.88, terrain));
		color = mix(ocean, land, land_mask);
		color = mix(color, ice_color.rgb, polar * 0.95);
	} else if (planet_kind == 0) {
		// Arid / Desert / Rocky Planet: deep basalt basins, rich dune seas, rocky canyons, and bright crater highlands
		float craters = ridge_noise(planet_normal * 8.5 + vec3(seed * 0.3, 1.2, -0.8));
		float dunes = ridge_noise(planet_normal * 20.0);
		float highlands = smoothstep(0.55, 0.85, terrain);
		float lowlands = smoothstep(0.42, 0.22, terrain);
		vec3 basin_color = mix(deep_color.rgb, low_color.rgb * 0.72, 0.35);
		vec3 plateau_color = mix(low_color.rgb, mid_color.rgb, smoothstep(0.32, 0.68, terrain));
		vec3 mountain_color = mix(mid_color.rgb, high_color.rgb, craters * 0.7 + dunes * 0.3);
		color = mix(plateau_color, basin_color, lowlands * 0.82);
		color = mix(color, mountain_color, highlands);
		color = mix(color, high_color.rgb * 1.12, smoothstep(0.82, 0.95, terrain));
		color = mix(color, ice_color.rgb, polar * 0.85);
	} else if (planet_kind == 2) {
		// Ice Planet: frozen seas, glacial rifts, blue subsurface ice
		float rifts = smoothstep(0.52, 0.85, ridge_noise(planet_normal * 16.0 + seed));
		float crags = ridge_noise(planet_normal * 26.0);
		vec3 ice_plains = mix(low_color.rgb, ice_color.rgb, smoothstep(0.3, 0.7, terrain));
		vec3 rift_color = mix(deep_color.rgb, vec3(0.12, 0.35, 0.55), 0.5);
		color = mix(ice_plains, rift_color, rifts * 0.65);
		color = mix(color, high_color.rgb, crags * 0.35);
		color = mix(color, ice_color.rgb * 1.15, polar * 0.8);
	} else if (planet_kind == 3) {
		// Lava Planet: obsidian basalt crust, glowing volcanic fissures, molten magma seas
		float fissures = smoothstep(0.55, 0.88, ridge_noise(planet_normal * 18.0 + seed * 2.0));
		float caldera = smoothstep(0.6, 0.85, noise3d(planet_normal * 7.0));
		vec3 crust = mix(low_color.rgb, mid_color.rgb, smoothstep(0.3, 0.7, terrain));
		vec3 magma = mix(deep_color.rgb, glow_color.rgb, 0.65);
		color = mix(magma, crust, land_mask);
		color += glow_color.rgb * (fissures * 0.9 + caldera * 0.4);
	} else if (planet_kind == 4) {
		// Gas Giant: layered atmospheric bands and swirling cyclonic storms
		float band_coord = planet_normal.y * 26.0 + noise3d(planet_normal * 3.5) * 4.2;
		float bands = sin(band_coord) * 0.5 + 0.5;
		float storm = smoothstep(0.72, 0.92, noise3d(planet_normal * 6.0 + vec3(seed, 2.5, -1.5)));
		color = mix(low_color.rgb, mid_color.rgb, bands);
		color = mix(color, high_color.rgb, smoothstep(0.55, 0.85, bands));
		color = mix(color, mix(deep_color.rgb, high_color.rgb, 0.7), storm * 0.65);
	} else if (planet_kind == 5) {
		// Toxic Planet: corrosive smog oceans, acid plateaus, virulent green canyons
		float ridges = ridge_noise(planet_normal * 14.0);
		vec3 sludge = deep_color.rgb;
		vec3 acid_land = mix(low_color.rgb, mid_color.rgb, smoothstep(0.35, 0.7, terrain));
		acid_land = mix(acid_land, high_color.rgb, ridges * 0.5);
		color = mix(sludge, acid_land, land_mask);
		color = mix(color, high_color.rgb, polar * 0.4);
	} else {
		// Carbon / Barren / Cratered Moon: stark impact basins, crater rims, ray networks
		float craters = ridge_noise(planet_normal * 10.0 + seed);
		float fine_craters = ridge_noise(planet_normal * 24.0);
		float highlands = smoothstep(0.48, 0.85, terrain);
		vec3 maria = deep_color.rgb;
		vec3 regolith = mix(low_color.rgb, mid_color.rgb, terrain);
		color = mix(maria, regolith, land_mask);
		color = mix(color, high_color.rgb, highlands * (craters * 0.7 + fine_craters * 0.3));
	}
	// Fine-grain albedo only appears at the high-detail level.  It makes a
	// close surface read as terrain rather than a smooth colour gradient while
	// preserving the same world-space pattern after launch.
	if (quality >= 2 && lod > 0.65 && planet_kind != 4) {
		// Keep fine terrain below the pixel sampling limit, but do not crush
		// orbital close-ups: a full-hemisphere disk has large dFdx and the old
		// 0.42 nyquist wiped almost all rock albedo (flat single colour).
		float pixel_span = max(length(dFdx(planet_normal)) + length(dFdy(planet_normal)), 0.00001);
		float requested_frequency = 26.0 * clamp(surface_detail_scale, 1.0, 3.0);
		float nyquist = 0.95 / pixel_span;
		float detail_frequency = min(requested_frequency, max(nyquist, requested_frequency * 0.45));
		float rock = wave_noise(planet_normal * detail_frequency + vec3(seed * 0.12, -seed * 0.08, seed * 0.05));
		float strata = wave_noise(planet_normal * detail_frequency * 0.43 + vec3(1.4, -2.2, seed * 0.03));
		float ridge = 1.0 - abs(rock);
		float land = smoothstep(ocean_level - 0.01, ocean_level + 0.05, terrain);
		float material_detail = mix(0.94 + strata * 0.045, 0.91 + ridge * 0.13 + strata * 0.05, land);
		color *= material_detail;
	}
	return color;
}

void fragment() {
	vec2 disk = (UV - disk_center_uv) / max(disk_radius_uv, vec2(0.00001));
	float radius_squared = dot(disk, disk);
	if (radius_squared > 1.0) {
		discard;
	}

	float z = sqrt(max(1.0 - radius_squared, 0.0));
	vec3 view_normal = normalize(vec3(disk.x, -disk.y, z));
	vec3 planet_normal = normalize(inverse_view_rotation * view_normal);

	float terrain = terrain_height(planet_normal);
	float moisture = noise3d(planet_normal * 5.1 + vec3(-3.1, 5.7, 2.6));
	vec3 color = shade_surface(planet_normal, terrain, moisture);

	// Directional 3D sun lighting with 3D terrain normal relief
	vec3 light = normalize(vec3(light_direction.x, -light_direction.y, 0.35));
	vec3 lighting_normal = view_normal;
	if (quality >= 1 && planet_kind != 4) {
		vec3 displaced = view_normal * (1.0 + terrain * 0.08);
		vec3 slope = normalize(cross(dFdx(displaced), dFdy(displaced)));
		if (dot(slope, view_normal) < 0.0) {
			slope = -slope;
		}
		lighting_normal = normalize(mix(view_normal, slope, 0.65));
	}
	float sun_dot = dot(lighting_normal, light);
	// Mocniejszy terminator: smoothstep zamiast liniowego clamp — wyraźna granica dnia i nocy
	float diffuse = smoothstep(-0.22, 0.9, sun_dot) * 0.88 + 0.12;
	color *= diffuse;

	if (planet_kind == 1 && quality >= 1) {
		float spec = pow(max(dot(reflect(-light, view_normal), vec3(0.0, 0.0, 1.0)), 0.0), 26.0);
		color += deep_color.rgb * spec * (1.0 - smoothstep(ocean_level - 0.04, ocean_level + 0.05, terrain)) * 0.5;
	}
	if (planet_kind == 3) {
		color += glow_color.rgb * (1.0 - clamp(sun_dot * 0.5 + 0.5, 0.0, 1.0)) * 0.45;
	}

	if (has_clouds == 1 && quality >= 1 && lod > 0.25 && (planet_kind == 1 || planet_kind == 5)) {
		float clouds = noise3d(planet_normal * 3.4 + vec3(cloud_time * 0.15, seed * 0.02, -cloud_time * 0.08));
		float cover = smoothstep(0.48, 0.78, clouds);
		vec3 cloud_col = planet_kind == 5 ? vec3(0.72, 0.84, 0.28) : vec3(0.92, 0.95, 0.98);
		color = mix(color, cloud_col, cover * 0.55);
	}

	float rim = pow(1.0 - z, 2.0);
	float sun_facing = clamp(dot(view_normal, light) * 0.5 + 0.5, 0.0, 1.0);
	// Atmosfera: jaśniejsza od strony słońca, słabsza w cieniu — realistyczny half-arc glow
	float atmo_strength = atmosphere_color.a * 3.2;
	color += atmosphere_color.rgb * rim * atmo_strength * (sun_facing * 0.75 + 0.25);
	// Dodaj blask limb przy zachodzie słońca (krawędź terminator)
	float terminator_rim = pow(clamp(1.0 - abs(dot(view_normal, light) * 1.8), 0.0, 1.0), 3.0);
	color += atmosphere_color.rgb * terminator_rim * atmosphere_color.a * 1.8;

	COLOR = vec4(color, 1.0);
}

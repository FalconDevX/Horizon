shader_type spatial;
render_mode unshaded, cull_back;

// Heightmap planet. The mesh is a unit sphere whose object-space direction is
// the planet-space direction; the heightmap (six cube faces in a texture
// array, baked by PlanetTerrain.bake()) pushes each vertex out and picks the
// colour. Liquid is flat: anything under sea_level is drawn at sea level with
// its own shallow-to-deep colour, gloss and optional glow (lava). Lit by hand
// from the sun, like planet_surface_3d.gdshader.

uniform sampler2DArray height_faces : filter_linear, repeat_disable;
uniform float face_size = 192.0;

// Highest ground above the sea (or above the lowest point on a dry world), as
// a fraction of the radius. Exaggerated on purpose.
uniform float relief : hint_range(0.0, 0.2) = 0.04;
// Extra steepness used only for shading, so relief that is small on the
// silhouette still reads as mountains in the light.
uniform float bump : hint_range(0.0, 30.0) = 8.0;

uniform bool has_liquid = true;
uniform float sea_level : hint_range(0.0, 1.0) = 0.5;
uniform bool is_gas = false;

// Height gradient: land_colors[i] (linear) at land_stops[i], 0 = shoreline.
uniform vec4 land_colors[6];
uniform float land_stops[6];

uniform vec3 liquid_shallow : source_color = vec3(0.1, 0.5, 0.6);
uniform vec3 liquid_deep : source_color = vec3(0.0, 0.05, 0.2);
uniform float liquid_emission : hint_range(0.0, 4.0) = 0.0;
uniform float liquid_gloss : hint_range(0.0, 1.0) = 0.8;

uniform vec3 rock_color : source_color = vec3(0.4);
uniform float slope_rock : hint_range(0.0, 1.0) = 0.5;

// Polar caps start at this |latitude| (sine of it, 0..1); above 1 disables.
uniform vec3 cap_color : source_color = vec3(1.0);
uniform float cap_latitude = 2.0;
// The spin axis in planet space - where the poles and the giants' bands sit.
uniform vec3 pole_axis = vec3(0.0, 1.0, 0.0);

uniform vec3 atmo_color : source_color = vec3(0.4, 0.6, 1.0);
uniform float atmo_strength : hint_range(0.0, 3.0) = 0.6;
uniform float atmo_haze : hint_range(0.0, 1.0) = 0.0;

uniform vec3 cloud_color : source_color = vec3(1.0);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_scale = 3.5;
uniform float cloud_speed = 0.01;

// Per-pixel grain on top of the heightmap, so close-ups are not bilinear mush.
uniform float detail_strength : hint_range(0.0, 1.0) = 0.25;
uniform float seed_offset = 0.0;

uniform float ambient : hint_range(0.0, 1.0) = 0.05;
// Tips the sunlight up toward the camera - see planet_surface_3d.gdshader.
uniform float light_lift : hint_range(0.0, 2.0) = 0.35;

global uniform vec3 sun_position;

varying vec3 v_dir;

// Mirror of PlanetTerrain.face_uv(): which face, and (u, v) on it.
vec3 face_uv(vec3 d) {
	vec3 a = abs(d);
	vec3 f;
	vec3 r;
	vec3 u;
	float face;

	if (a.x >= a.y && a.x >= a.z) {
		if (d.x > 0.0) { face = 0.0; f = vec3(1.0, 0.0, 0.0); r = vec3(0.0, 0.0, -1.0); u = vec3(0.0, 1.0, 0.0); }
		else { face = 1.0; f = vec3(-1.0, 0.0, 0.0); r = vec3(0.0, 0.0, 1.0); u = vec3(0.0, 1.0, 0.0); }
	} else if (a.y >= a.z) {
		if (d.y > 0.0) { face = 2.0; f = vec3(0.0, 1.0, 0.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 0.0, -1.0); }
		else { face = 3.0; f = vec3(0.0, -1.0, 0.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 0.0, 1.0); }
	} else {
		if (d.z > 0.0) { face = 4.0; f = vec3(0.0, 0.0, 1.0); r = vec3(1.0, 0.0, 0.0); u = vec3(0.0, 1.0, 0.0); }
		else { face = 5.0; f = vec3(0.0, 0.0, -1.0); r = vec3(-1.0, 0.0, 0.0); u = vec3(0.0, 1.0, 0.0); }
	}

	float forward = dot(d, f);
	return vec3(dot(d, r) / forward, dot(d, u) / forward, face);
}

float height_at(vec3 d) {
	vec3 fuv = face_uv(d);
	// Texel centres at the cube edges: u = -1 is the middle of the first texel.
	vec2 uv = (fuv.xy * 0.5 + 0.5) * ((face_size - 1.0) / face_size) + 0.5 / face_size;
	return textureLod(height_faces, vec3(uv, fuv.z), 0.0).r;
}

float ground(float h) {
	return has_liquid ? max(h - sea_level, 0.0) : h;
}

// ---- small procedural noise, shading only (no CPU mirror needed) ----------

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	return mix(
		mix(
			mix(hash13(i), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x),
			f.y
		),
		mix(
			mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x),
			f.y
		),
		f.z
	);
}

float fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amplitude * value_noise(p);
		p = p * 2.03 + vec3(17.1, 5.3, 11.7);
		amplitude *= 0.5;
	}
	return sum;
}

vec3 land_gradient(float x) {
	vec3 c = land_colors[0].rgb;
	for (int i = 1; i < 6; i++) {
		c = mix(c, land_colors[i].rgb, smoothstep(land_stops[i - 1], land_stops[i], x));
	}
	return c;
}

vec3 rotate_about(vec3 v, vec3 axis, float angle) {
	return v * cos(angle) + cross(axis, v) * sin(angle) + axis * dot(axis, v) * (1.0 - cos(angle));
}

// ---------------------------------------------------------------------------

void vertex() {
	vec3 dir = normalize(VERTEX);
	VERTEX = dir * (1.0 + relief * ground(height_at(dir)));
	v_dir = dir;
}

void fragment() {
	vec3 d = normalize(v_dir);
	vec3 helper = abs(d.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 t = normalize(cross(helper, d));
	vec3 b = cross(d, t);

	float eps = 1.5 / face_size;
	vec3 dt = normalize(d + t * eps);
	vec3 db = normalize(d + b * eps);
	float h = height_at(d);
	float h_t = height_at(dt);
	float h_b = height_at(db);

	vec3 grain_p = d * 90.0 + seed_offset;
	float grain = fbm(grain_p, 3);

	bool liquid = has_liquid && h < sea_level;

	// Terrain normal from the slope of the (bump-exaggerated) heightmap.
	float k = relief * bump;
	vec3 p0 = d * (1.0 + k * ground(h));
	vec3 pt = dt * (1.0 + k * ground(h_t));
	vec3 pb = db * (1.0 + k * ground(h_b));
	vec3 n = normalize(cross(pt - p0, pb - p0));
	float slope = 1.0 - dot(n, d);

	float latitude = dot(d, pole_axis);
	vec3 col;
	float gloss = 0.0;
	float glow = 0.0;

	if (is_gas) {
		// Fine streaks along the bands, stretched by squashing latitude.
		float streak = fbm(vec3(d.x * 6.0, latitude * 40.0, d.z * 6.0) + seed_offset, 3);
		col = land_gradient(clamp(h + (streak - 0.5) * 0.12, 0.0, 1.0));
		n = d;
	} else if (liquid) {
		float depth = clamp((sea_level - h) / max(sea_level, 1e-3), 0.0, 1.0);
		col = mix(liquid_shallow, liquid_deep, smoothstep(0.0, 0.45, depth));
		// Foam-less shoreline brightening where the sea is shallowest.
		col = mix(col, liquid_shallow * 1.3, (1.0 - smoothstep(0.0, 0.03, depth)) * 0.5);
		gloss = liquid_gloss;
		glow = liquid_emission * (0.6 + 0.8 * grain) * mix(1.0, 0.5, depth);
		// Gentle swell - just enough to break up the highlight.
		vec3 ripple = vec3(
			value_noise(d * 60.0 + TIME * 0.2),
			value_noise(d * 60.0 + 7.0 - TIME * 0.2),
			value_noise(d * 60.0 + 13.0)
		) - 0.5;
		n = normalize(d + (ripple - d * dot(ripple, d)) * 0.04);
	} else {
		float land = has_liquid ? (h - sea_level) / max(1.0 - sea_level, 1e-3) : h;
		land = clamp(land + (grain - 0.5) * 0.08, 0.0, 1.0);
		col = land_gradient(land);
		col = mix(col, rock_color, smoothstep(0.03, 0.18, slope) * slope_rock);
		col *= 0.85 + 0.3 * grain;

		// Pebbly per-pixel detail on the normal.
		vec3 jitter = vec3(
			value_noise(grain_p * 2.0),
			value_noise(grain_p * 2.0 + 31.0),
			value_noise(grain_p * 2.0 + 57.0)
		) - 0.5;
		n = normalize(n + (jitter - n * dot(jitter, n)) * detail_strength);
	}

	if (cap_latitude <= 1.0 && !is_gas) {
		float edge = abs(latitude) + (fbm(d * 7.0 + seed_offset, 3) - 0.5) * 0.12;
		// Ice reaches further toward the equator on high ground.
		edge += liquid ? 0.0 : ground(h) * 0.15;
		float cap = smoothstep(cap_latitude, cap_latitude + 0.025, edge);
		col = mix(col, cap_color, cap);
		gloss *= 1.0 - cap;
		glow *= 1.0 - cap;
		n = normalize(mix(n, d, cap * 0.6));
	}

	// ---- lighting (world space) ----
	vec3 to_sun = normalize(sun_position - NODE_POSITION_WORLD);
	vec3 L = normalize(to_sun + vec3(0.0, light_lift, 0.0));
	vec3 V = normalize(INV_VIEW_MATRIX[2].xyz);
	vec3 nw = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	vec3 sw = normalize((MODEL_MATRIX * vec4(d, 0.0)).xyz);

	float sphere_light = dot(sw, L);
	// Terrain slopes cannot light up the night side past the terminator.
	float day = smoothstep(-0.12, 0.2, sphere_light);
	float diffuse = max(dot(nw, L), 0.0) * day;
	vec3 lit = col * (ambient + (1.0 - ambient) * diffuse);

	if (gloss > 0.0) {
		vec3 halfway = normalize(L + V);
		float spec = pow(max(dot(nw, halfway), 0.0), mix(12.0, 90.0, gloss)) * gloss * day;
		lit += vec3(1.0, 0.97, 0.9) * spec * 0.8;
	}

	lit += col * glow;

	if (cloud_coverage > 0.0) {
		vec3 cd = rotate_about(d, pole_axis, TIME * cloud_speed);
		float c = fbm(cd * cloud_scale + seed_offset * 0.37, 5);
		// Stretch along latitude so clouds streak like weather bands.
		c += (fbm(vec3(cd.x, latitude * 3.0, cd.z) * cloud_scale * 0.5 + 3.0, 2) - 0.5) * 0.25;
		// Value-noise fbm sits around 0.3..0.7, so this threshold maps coverage
		// roughly onto the share of sky that ends up clouded.
		float threshold = 0.7 - 0.4 * cloud_coverage;
		float cover = smoothstep(threshold, threshold + 0.12, c);
		vec3 cloud_lit = cloud_color * (ambient + (1.0 - ambient) * max(sphere_light, 0.0) * day);
		lit = mix(lit, cloud_lit, cover * 0.92);
	}

	float facing = clamp(dot(sw, V), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.0);
	float atmo_light = smoothstep(-0.25, 0.6, sphere_light);
	lit = mix(lit, atmo_color * (0.1 + 0.9 * atmo_light), atmo_haze * (0.5 + 0.5 * rim));
	lit += atmo_color * rim * atmo_strength * atmo_light;

	ALBEDO = lit;
}

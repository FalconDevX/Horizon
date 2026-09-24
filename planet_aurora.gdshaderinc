// Aurora, shared by planet_terrain.gdshader (seen from above, over the
// ground) and planet_atmosphere.gdshader (curtains standing up past the limb),
// so the two line up. Include after planet_noise.gdshaderinc; expects the
// including shader to declare `pole_axis` and `seed_offset`.
//
// A real aurora is a curtain hanging along the auroral oval: a thin ribbon
// that folds and ripples, sharp and green at its lower edge, fading upward
// into red and violet, and combed into fine vertical rays that flicker.

uniform float aurora_strength : hint_range(0.0, 3.0) = 0.0;
// |sin(latitude)| of the oval and its half-width.
uniform float aurora_latitude : hint_range(0.0, 1.0) = 0.75;
uniform float aurora_width : hint_range(0.01, 0.3) = 0.1;
uniform float aurora_speed = 0.03;
// Lower edge, body, upper fringe.
uniform vec3 aurora_color_a : source_color = vec3(0.2, 1.0, 0.5);
uniform vec3 aurora_color_b : source_color = vec3(0.2, 0.8, 1.0);
uniform vec3 aurora_color_c : source_color = vec3(0.9, 0.3, 0.9);

// Longitude round the spin axis, -PI..PI.
float aurora_longitude(vec3 d) {
	vec3 helper = abs(pole_axis.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 e1 = normalize(cross(pole_axis, helper));
	vec3 e2 = cross(pole_axis, e1);
	return atan(dot(d, e2), dot(d, e1));
}

// Where the curtain's lower edge runs at this longitude, as |sin latitude|:
// the oval, folded by slow waves and a quicker ripple.
float aurora_edge(float lon, float t) {
	vec2 ring = vec2(cos(lon), sin(lon));
	float fold = noised(vec3(ring * 2.5, t * 0.6) + seed_offset).x * 1.6
		+ noised(vec3(ring * 7.0, t * 1.4) + seed_offset + 5.0).x * 0.5;
	return aurora_latitude + fold * aurora_width;
}

// Brightness along the curtain at this longitude: bright and dim stretches,
// fine flickering rays, and gaps where the curtain breaks.
float aurora_rays(float lon, float t) {
	vec2 ring = vec2(cos(lon), sin(lon));
	float body = smoothstep(-0.25, 0.35, noised(vec3(ring * 4.0, t * 0.8) + seed_offset + 11.0).x);
	float rays = 0.55 + 0.45 * noised(vec3(ring * 60.0, t * 3.0) + seed_offset + 23.0).x * 1.6;
	rays *= 0.7 + 0.3 * noised(vec3(ring * 150.0, t * 5.0) + seed_offset + 31.0).x * 1.6;
	float pulse = 0.8 + 0.2 * sin(planet_time * 1.7 + lon * 3.0);
	return body * clamp(rays, 0.0, 1.4) * pulse;
}

// Colour up the curtain: `rise` 0 at the lower edge, 1 at the top.
vec3 aurora_color(float rise) {
	vec3 low = mix(aurora_color_a, aurora_color_b, smoothstep(0.0, 0.5, rise) * 0.4);
	return mix(low, aurora_color_c, smoothstep(0.35, 1.0, rise));
}

// Seen from above: at a ground direction `d`, the curtain's foot is a bright
// line and the rest of it leans poleward as a fading glow.
vec3 aurora_ground(vec3 d, float latitude) {
	float t = planet_time * aurora_speed;
	float lon = aurora_longitude(d);
	float edge = aurora_edge(lon, t);
	// Poleward of the edge is positive.
	float along = abs(latitude) - edge;
	if (along < -aurora_width * 0.6 || along > aurora_width * 2.5) {
		return vec3(0.0);
	}
	float foot = exp(-pow(along / (aurora_width * 0.18), 2.0));
	float drape = along > 0.0 ? exp(-along / (aurora_width * 0.9)) : 0.0;
	float glow = max(foot, drape * 0.75);
	float rise = clamp(along / (aurora_width * 2.0), 0.0, 1.0);
	return aurora_color(rise) * glow * aurora_rays(lon, t);
}

// Seen edge-on past the limb: a curtain standing `altitude` above the ground
// (in planet radii) over the ground direction `d`.
vec3 aurora_limb(vec3 d, float altitude, float curtain_height) {
	float t = planet_time * aurora_speed;
	float lon = aurora_longitude(d);
	float edge = aurora_edge(lon, t);
	float offset = abs(dot(d, pole_axis)) - edge;
	// Only where the limb passes over the oval.
	float over = exp(-pow(offset / (aurora_width * 0.8), 2.0));
	if (over < 0.01) {
		return vec3(0.0);
	}
	float rise = clamp(altitude / curtain_height, 0.0, 1.0);
	float body = smoothstep(0.0, 0.08, rise) * (1.0 - smoothstep(0.55, 1.0, rise));
	return aurora_color(rise) * body * over * aurora_rays(lon, t);
}

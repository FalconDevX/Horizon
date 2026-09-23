// A planet's weather, shared by planet_clouds.gdshader (which draws it on its
// own shell) and planet_terrain.gdshader (which only needs its shadows), so
// the two always agree. Include after planet_noise.gdshaderinc; expects the
// including shader to declare `pole_axis` and `seed_offset`.

uniform vec3 cloud_color : source_color = vec3(1.0);
// Share of the sky clouded, roughly; 0 = no weather at all.
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.0;
// Size of the big weather systems: fronts per radian, give or take.
uniform float cloud_scale = 3.5;
// Drift eastward, radians per second.
uniform float cloud_speed = 0.01;
// Up to four cyclones: xyz its centre on the unit sphere (planet space), w its
// spin - signed by hemisphere, magnitude = how tightly the arms wind. 0 = none.
uniform vec4 cyclones[4];
// Chord radius of a cyclone's reach.
uniform float cyclone_radius = 0.28;

// The sky moves as one: winds carry everything east around the pole.
vec3 cloud_space(vec3 d) {
	return rotate_about(d, pole_axis, planet_time * cloud_speed);
}

// Coverage and thickness of the clouds over a planet-space direction.
// x = opacity 0..1 (sharp-ish edges), y = thickness 0..1 (soft, for shading).
// `octaves` trades detail for cost - shadows get away with far fewer.
vec2 cloud_field(vec3 d, float footprint, int octaves) {
	vec3 p = cloud_space(d);
	float eyes = 0.0;
	float storms = 0.0;

	// Cyclones: the sky twisted round each centre, harder toward the middle,
	// so fronts wrap into spiral arms. A small clear eye sits dead centre.
	for (int i = 0; i < 4; i++) {
		float spin = cyclones[i].w;
		if (spin == 0.0) {
			continue;
		}
		vec3 centre = cyclones[i].xyz;
		float reach = 1.0 - length(p - centre) / cyclone_radius;
		if (reach > 0.0) {
			p = normalize(rotate_about(p, centre, spin * reach * reach * reach));
			storms = max(storms, reach);
			eyes = max(eyes, smoothstep(0.9, 0.97, reach));
		}
	}

	float latitude = dot(p, pole_axis);
	vec3 q = p + seed_offset * 0.37;

	// Weather systems: domain-warped fBm, stretched along the latitude lines
	// the way the winds shear them.
	vec3 warp = vec3(
		noised(q * cloud_scale * 0.6).x,
		noised(q * cloud_scale * 0.6 + 5.2).x,
		noised(q * cloud_scale * 0.6 + 9.7).x
	);
	vec3 sheared = q + warp * (0.7 / cloud_scale);
	sheared += pole_axis * dot(sheared, pole_axis) * 0.45;
	float systems = fbm(sheared, 4, cloud_scale, footprint);

	// Climate bands: cloudy at the equator and the storm tracks near 60
	// degrees, clear over the subtropics.
	float bands = cos(latitude * 3.14159 * 3.0) * 0.1;

	// Cumulus: billowy detail, carved as inverted ridges so it clumps.
	float billow = 0.0;
	float amplitude = 0.5;
	float frequency = cloud_scale * 5.0;
	for (int i = 0; i < octaves; i++) {
		float n = 1.0 - abs(noised(ROT * sheared * frequency + float(i) * 3.7).x * 1.6);
		billow += amplitude * (n - 0.5) * octave_fade(frequency, footprint);
		amplitude *= 0.5;
		frequency *= 2.1;
	}

	// Cirrus: thin streaks, torn out along the wind at high latitude.
	float streak_frequency = cloud_scale * 2.5;
	float streaks = fbm(vec3(q.x * 2.0, latitude * 18.0, q.z * 2.0), 3, streak_frequency, footprint * 9.0);
	streaks *= smoothstep(0.25, 0.7, abs(latitude));

	float raw = systems + bands + billow * 0.35 + streaks * 0.3 + storms * 0.35;

	float threshold = 0.22 - 0.5 * cloud_coverage;
	float opacity = smoothstep(threshold, threshold + 0.12, raw) * (1.0 - eyes);
	float thickness = smoothstep(threshold, threshold + 0.45, raw) * (1.0 - eyes);
	return vec2(opacity, thickness);
}

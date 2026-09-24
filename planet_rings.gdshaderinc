// Ring profile shared by planet_rings.gdshader (the rings themselves) and
// planet_terrain.gdshader (the shadow they cast on the planet). Both must read
// the same density, or the shadow bands slide off the rings.
//
// Radii are in planet radii, in the ring plane, which is the plane
// perpendicular to the planet's pole. ring_opacity 0 means "no rings".

uniform float ring_inner = 1.35;
uniform float ring_outer = 2.35;
uniform float ring_opacity = 0.0;
uniform float ring_seed = 0.0;

float ring_hash(float x) {
	return fract(sin(x * 127.1 + ring_seed * 3.17) * 43758.5453);
}

// Smooth 1D value noise.
float ring_noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(ring_hash(i), ring_hash(i + 1.0), f);
}

// 0..1 across the ring system, or outside that range off the rings.
float ring_coord(float r) {
	return (r - ring_inner) / (ring_outer - ring_inner);
}

// Opacity at normalised radius x (0 inner edge, 1 outer edge). `blur` is how
// much of x one pixel covers: fine ringlets fade out once they are smaller than
// a pixel, so the rings never shimmer from afar.
float ring_density(float x, float blur) {
	if (x <= 0.0 || x >= 1.0) {
		return 0.0;
	}
	// Broad structure: a faint inner ring, a dense middle one, a medium outer one.
	float broad = mix(0.3, 1.0, smoothstep(0.12, 0.3, x));
	broad *= mix(1.0, 0.7, smoothstep(0.66, 0.7, x));
	broad *= 0.65 + 0.35 * ring_noise(x * 9.0);
	// Ringlets at two scales, faded by pixel size.
	float mid = ring_noise(x * 60.0);
	float fine = ring_noise(x * 260.0);
	float mid_w = 1.0 - smoothstep(0.004, 0.02, blur);
	float fine_w = 1.0 - smoothstep(0.001, 0.005, blur);
	float d = broad * mix(1.0, 0.55 + 0.7 * mid, 0.6 * mid_w);
	d *= mix(1.0, 0.7 + 0.5 * fine, 0.5 * fine_w);
	// A wide division (Cassini-like) and a thin gap near the outer edge.
	float gap_w = max(blur, 0.004);
	d *= 1.0 - 0.92 * (1.0 - smoothstep(0.0, 0.035 + gap_w, abs(x - 0.64)));
	d *= 1.0 - 0.85 * (1.0 - smoothstep(0.0, 0.006 + gap_w, abs(x - 0.9)));
	// Soft inner and outer edges.
	d *= smoothstep(0.0, 0.04, x) * (1.0 - smoothstep(0.96, 1.0, x));
	return clamp(d, 0.0, 1.0) * ring_opacity;
}

// How much light a ring lets through between point p (planet space) and the
// sun along L (planet space, unit). `pole` is the ring plane's normal.
float ring_transmission(vec3 p, vec3 L, vec3 pole) {
	if (ring_opacity <= 0.0) {
		return 1.0;
	}
	float denom = dot(L, pole);
	if (abs(denom) < 1e-4) {
		return 1.0;
	}
	float t = -dot(p, pole) / denom;
	if (t <= 0.0) {
		return 1.0;
	}
	vec3 hit = p + L * t;
	return 1.0 - ring_density(ring_coord(length(hit)), 0.003);
}

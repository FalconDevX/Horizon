shader_type canvas_item;
render_mode unshaded;

uniform vec4 base_color : source_color = vec4(0.35, 0.55, 0.75, 1.0);
uniform vec2 light_direction = vec2(-0.7, -0.45);
uniform float atmosphere = 0.18;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius_squared = dot(p, p);
	if (radius_squared > 1.0) {
		discard;
	}
	float z = sqrt(max(1.0 - radius_squared, 0.0));
	vec3 normal = normalize(vec3(p.x, -p.y, z));
	vec3 light = normalize(vec3(light_direction.x, -light_direction.y, 0.72));
	float diffuse = clamp(dot(normal, light) * 0.52 + 0.48, 0.16, 1.0);
	float rim = pow(1.0 - z, 2.2);
	vec3 color = base_color.rgb * diffuse;
	color += vec3(0.2, 0.42, 0.62) * rim * atmosphere;
	COLOR = vec4(color, base_color.a);
}

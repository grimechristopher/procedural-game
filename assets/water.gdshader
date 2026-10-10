// Pixel-art water from assets/water.png (left half: surface, right half:
// falling water), mapped in world space so it flows across cells: surfaces
// drift south, vertical faces fall.
shader_type spatial;
render_mode unshaded;

uniform sampler2D water : source_color, filter_nearest;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv;
	float shade = 1.0;
	if (world_normal.y > 0.5) {
		vec2 cell = fract(vec2(world_pos.x, world_pos.z - TIME * 0.4));
		uv = vec2(cell.x * 0.5, cell.y);
	} else {
		float along = abs(world_normal.x) > 0.5 ? world_pos.z : world_pos.x;
		vec2 cell = fract(vec2(along, -world_pos.y - TIME * 1.5));
		uv = vec2(0.5 + cell.x * 0.5, cell.y);
		shade = 0.9;
	}
	ALBEDO = texture(water, uv).rgb * shade;
}

// Unlit pixel-art blocks with a fixed brightness per face direction, lit
// from the south-west the way HGSS shades its cliffs: tops brightest, faces
// toward the camera next, east/west a bit darker, faces turned away darkest.
shader_type spatial;
render_mode unshaded;

uniform sampler2D tileset : source_color, filter_nearest;

varying vec3 world_normal;

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = world_normal;
	float shade;
	if (n.y > 0.99) {
		shade = 1.0;
	} else if (n.y > 0.1) {
		shade = 0.9 + 0.1 * n.z - 0.03 * n.x;
	} else if (n.y < -0.5) {
		shade = 0.5;
	} else {
		shade = 0.8 + 0.08 * n.z - 0.04 * n.x;
	}
	ALBEDO = texture(tileset, UV).rgb * shade;
}

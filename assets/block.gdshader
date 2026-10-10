// Unlit pixel-art blocks with a fixed brightness per face direction, lit
// from the south-west the way HGSS shades its cliffs: tops brightest, faces
// toward the camera next, east/west a bit darker, faces turned away darkest.
//
// UV holds the tile's (column, row) in the atlas; UV2 holds the position
// within the tile in tile units. Faces bigger than one tile (buildings)
// repeat the tile across themselves.
shader_type spatial;
render_mode unshaded;

uniform sampler2D tileset : source_color, filter_nearest;
uniform vec2 tiles = vec2(4.0, 5.0);

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
		shade = 0.86 + 0.16 * n.z - 0.08 * n.x;
	} else if (n.y < -0.5) {
		shade = 0.5;
	} else {
		shade = 0.8 + 0.08 * n.z - 0.04 * n.x;
	}
	vec2 local = UV2;
	if (any(greaterThan(abs(local - 0.5), vec2(0.5)))) {
		local = fract(local);
	}
	// Half a texel in from the edges so nearest sampling never bleeds.
	float inset = 0.5 / 16.0;
	local = clamp(local, vec2(inset), vec2(1.0 - inset));
	vec4 texel = texture(tileset, (UV + local) / tiles);
	// Overlays (Edges' grass pieces) are see-through where the tile is.
	if (texel.a < 0.5) {
		discard;
	}
	ALBEDO = texel.rgb * shade;
}

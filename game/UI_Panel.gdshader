shader_type spatial;
render_mode unshaded, cull_back;
uniform vec2 size = vec2(1.0);
uniform float highlight = 0.0;

void fragment() {
	float left_border = 1.0 / (128.0 * size.x);
	float top_border = 1.0 / (128.0 * size.y);
	float right_border = 1.0 - left_border;
	float bottom_border = 1.0 - top_border;
	if (UV.x < left_border || UV.x > right_border || UV.y < top_border || UV.y > bottom_border) {
		ALBEDO = vec3(1.0);
	} else {
		ALBEDO = vec3(0.015625 * highlight);
	}
}

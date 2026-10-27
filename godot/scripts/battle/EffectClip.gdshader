shader_type canvas_item;
// 426451 clips the original 320x200 ANM to the current battlefield window.
uniform vec4 clip_bounds = vec4(0.0, 0.0, 1.0, 1.0);
void fragment() {
	if (SCREEN_UV.x < clip_bounds.x || SCREEN_UV.y < clip_bounds.y ||
		SCREEN_UV.x >= clip_bounds.z || SCREEN_UV.y >= clip_bounds.w) {
		discard;
	}
}

shader_type canvas_item;
render_mode unshaded;
uniform float amount = 0.0;
uniform bool entering = false;
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(entering ? min(source.rgb, vec3(amount)) : max(source.rgb-vec3(amount), vec3(0.0)), source.a);
}

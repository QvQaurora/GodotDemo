shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float blur_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec2 blur_direction = vec2(1.0, 0.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 color = texture(screen_texture, uv);
	if (blur_amount > 0.001) {
		vec2 dir = normalize(blur_direction + vec2(0.0001, 0.0)) * blur_amount * 0.018;
		color += texture(screen_texture, uv + dir);
		color += texture(screen_texture, uv - dir);
		color += texture(screen_texture, uv + dir * 0.5);
		color += texture(screen_texture, uv - dir * 0.5);
		color *= 0.2;
	}
	COLOR = color;
}

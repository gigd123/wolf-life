// 假景深（tilt-shift）：鏡頭角度固定，畫面上下越遠離中間的對焦帶越模糊。
// 專案用 Compatibility 渲染器，沒有內建景深，所以在 2D 畫面上做；也負責把小畫布放大成像素。
shader_type canvas_item;

uniform bool enabled = true;
uniform float focus = 0.55;
uniform float band = 0.16;
uniform float max_blur = 2.6; // 最模糊時的取樣半徑（畫布像素）
uniform vec2 canvas_size = vec2(640.0, 360.0);
uniform float vignette = 0.28;
uniform float warm = 0.04;

void fragment() {
	vec2 uv = UV;
	vec3 col = texture(TEXTURE, uv).rgb;
	if (enabled) {
		float d = max(0.0, abs(uv.y - focus) - band) / max(0.001, 1.0 - band);
		float r = clamp(d * 1.6, 0.0, 1.0) * max_blur;
		if (r > 0.05) {
			vec2 px = r / canvas_size;
			vec3 acc = col;
			float n = 1.0;
			for (int i = 0; i < 8; i++) {
				float a = float(i) * 0.785398;
				vec2 o = vec2(cos(a), sin(a));
				acc += texture(TEXTURE, uv + o * px).rgb;
				acc += texture(TEXTURE, uv + o * px * 0.5).rgb;
				n += 2.0;
			}
			col = acc / n;
		}
		// 暗角與一點暖色（HD-2D 的後製感）
		vec2 c = uv - 0.5;
		col *= 1.0 - vignette * dot(c, c) * 2.0;
		col += vec3(warm, warm * 0.5, -warm * 0.3) * (1.0 - uv.y);
	}
	COLOR = vec4(col, 1.0);
}

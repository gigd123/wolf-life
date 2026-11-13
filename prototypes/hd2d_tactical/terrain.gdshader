// 地形方塊：上面與側面用不同的像素材質，UV 照世界座標（相鄰格子的材質接得起來），可以疊格線。
shader_type spatial;
render_mode cull_back;

uniform sampler2D top_tex : source_color, filter_nearest, repeat_enable;
uniform sampler2D side_tex : source_color, filter_nearest, repeat_enable;
// 只用 48 一套、拉遠縮小時的比較：同一張材質用平滑縮小（mipmap）取樣
uniform sampler2D top_tex_s : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D side_tex_s : source_color, filter_linear_mipmap, repeat_enable;
uniform bool smooth_min = false;
uniform float texels_per_unit = 32.0; // 一格（世界 1 單位）幾個材質像素 = tile_px
uniform float top_size = 64.0;
uniform float side_size = 64.0;
uniform bool show_grid = true;
uniform vec4 grid_color : source_color = vec4(0.08, 0.08, 0.1, 0.35);
uniform float side_shade = 0.82;
uniform vec3 tint = vec3(1.0); // 上面的顏色乘上這個（戰鬥原型的密林畫深一點，2026-11-05）
// 草皮邊緣（2026-11-08）：上面是草地或雪地時，側面最上緣畫一條上面的材質，往下垂 lip_texels～lip_texels+lip_jag 個材質像素（每一欄不同，邊緣參差），
// 下面一個像素畫暗一點當陰影。lip_texels 0 時不畫。離頂面多遠（from_top）在 vertex 算：方塊（BoxMesh，沒有細分）的頂點只有上下兩層，
// 上面那層是 0、下面那層是方塊的高度，側面內插後就是每一點離頂面的距離（instance uniform 每格一個會超過上限）
uniform float lip_texels = 0.0;
uniform float lip_jag = 3.0;
// 每一格的狀態（2026-11-13，Phase 2n 大火）：use_state 開著時照 state_tex（一格一個像素）改顏色；沒開時（狩獵、戰鬥）不影響
//   r 燒焦的程度（0 沒燒、1 焦土）、g 火光（燃燒、剛燒過的餘燼發光）、b 看不看得到（1 看得到、約 0.45 看過但被煙遮住、0 沒看過）
uniform bool use_state = false;
uniform sampler2D state_tex : filter_nearest;
uniform vec2 state_size = vec2(1.0);
uniform float glow_pulse = 1.0;

varying vec3 wpos;
varying vec3 wnorm;
varying float from_top;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	from_top = VERTEX.y > 0.0 ? 0.0 : -2.0 * VERTEX.y;
}

void fragment() {
	vec3 col;
	if (wnorm.y > 0.5) {
		// 對齊材質像素：先換成材質像素座標再取整，避免縮小時的接縫
		vec2 t = floor(wpos.xz * texels_per_unit) + 0.5;
		col = smooth_min ? texture(top_tex_s, wpos.xz * texels_per_unit / top_size).rgb : texture(top_tex, t / top_size).rgb;
		if (show_grid) {
			vec2 f = fract(wpos.xz);
			float px = 1.0 / texels_per_unit;
			if (f.x < px || f.y < px) {
				col = mix(col, grid_color.rgb, grid_color.a);
			}
		}
	} else {
		vec2 uv = abs(wnorm.x) > 0.5 ? vec2(wpos.z, -wpos.y) : vec2(wpos.x, -wpos.y);
		vec2 t = floor(uv * texels_per_unit) + 0.5;
		col = (smooth_min ? texture(side_tex_s, uv * texels_per_unit / side_size).rgb : texture(side_tex, t / side_size).rgb) * side_shade;
		if (lip_texels > 0.0) {
			float d = from_top * texels_per_unit;
			float h = fract(sin(t.x * 12.9898 + floor(uv.x) * 78.233) * 43758.5453);
			float edge = lip_texels + floor(h * (lip_jag + 1.0));
			if (d < edge) {
				col = texture(top_tex, t / top_size).rgb * tint * 0.9;
			} else if (d < edge + 1.0) {
				col *= 0.62;
			}
		}
	}
	if (wnorm.y > 0.5) {
		col *= tint;
	}
	vec3 emit = vec3(0.0);
	if (use_state) {
		vec2 cell = floor(wpos.xz - wnorm.xz * 0.01);
		if (cell.x >= 0.0 && cell.y >= 0.0 && cell.x < state_size.x && cell.y < state_size.y) {
			vec4 st = texture(state_tex, (cell + 0.5) / state_size);
			// 焦土：偏暖的黑灰，夾雜一點灰白的灰燼
			vec2 tp = floor(wpos.xz * texels_per_unit);
			float n = fract(sin(dot(tp, vec2(12.9898, 78.233))) * 43758.5453);
			vec3 ash = vec3(0.12, 0.11, 0.10) + (n > 0.93 ? vec3(0.22) : vec3(n * 0.05));
			col = mix(col, ash, st.r * 0.92);
			// 火光：一點一點的亮紅（餘燼），燃燒中的整格偏橘
			float speck = n > 0.8 ? 1.0 : (n > 0.6 ? 0.3 : 0.04);
			emit = vec3(1.0, 0.36, 0.08) * st.g * speck * glow_pulse;
			col *= mix(0.1, 1.0, st.b);
			emit *= st.b > 0.01 ? 1.0 : 0.6;
		}
	}
	ALBEDO = col;
	EMISSION = emit;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

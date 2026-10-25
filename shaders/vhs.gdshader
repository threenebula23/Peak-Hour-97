shader_type canvas_item;
render_mode unshaded;

// Нативный VHS/CRT-слой главного меню.
//
// Считается в ФИЗИЧЕСКИХ пикселях окна: скан-линии идут по FRAGCOORD,
// поэтому при 1920×1080 шаг ровно 2 px, без блоков и banding. Экранная
// текстура читается с линейной фильтрацией 1:1 — буквы не размываются.
// Хроматическая аберрация минимальна (0.0003 UV ≈ 0.6 px на краю кадра)
// и не сдвигает зелёный канал, поэтому форма букв остаётся резкой.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float intensity : hint_range(0.0, 0.55) = 0.40;

// Скан-линии: 2 физических px, затемнение до 6%.
uniform float scanline_strength : hint_range(0.0, 0.12) = 0.06;
uniform float scanline_step : hint_range(2.0, 3.0) = 2.0;

// Хроматика: очень мягкая, чтобы не двоить текст.
uniform float aberration : hint_range(0.0, 0.0006) = 0.0003;

// Зерно: ±0.025, обновление 2 Гц.
uniform float grain : hint_range(0.0, 0.04) = 0.025;

// Виньетка по краям кадра.
uniform float vignette : hint_range(0.0, 0.18) = 0.11;

// Медленная полоса прокрутки: только яркость, без сдвига картинки.
uniform float band_strength : hint_range(0.0, 0.05) = 0.04;
uniform float band_speed : hint_range(0.01, 0.3) = 0.055;

const vec3 BAND_TINT = vec3(0.85, 1.0, 1.0);


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}


void fragment() {
	vec2 res = 1.0 / max(SCREEN_PIXEL_SIZE, vec2(1e-6));
	vec2 uv = SCREEN_UV;

	// Хроматика: R/B расходятся к краям, G сэмплится ровно по UV.
	float edge = 0.35 + abs(uv.x - 0.5) * 1.3;
	vec2 shift = vec2(aberration * edge, 0.0);
	vec3 col;
	col.r = texture(screen_texture, uv + shift).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - shift).b;

	// Скан-линии по физическим строкам. FRAGCOORD — центр пикселя (n+0.5),
	// поэтому фазу берём от floor(y)+1, иначе cos((n+0.5)·PI) == 0.
	float row = floor(FRAGCOORD.y);
	float line = 0.5 + 0.5 * cos((row + 1.0) * (6.2831853 / scanline_step));
	col *= 1.0 - scanline_strength * line;

	// Зерно: пиксельный шум, обновляется 2 раза в секунду.
	float gt = floor(TIME * 2.0);
	float n = hash21(floor(FRAGCOORD.xy) + vec2(gt * 31.7, gt * 17.3));
	col += (n - 0.5) * grain;

	// Виньетка с поправкой на соотношение сторон.
	vec2 q = uv - 0.5;
	q.x *= res.x / max(res.y, 1.0);
	col *= 1.0 - vignette * smoothstep(0.35, 0.95, length(q));

	// Полоса: медленно идёт сверху вниз. Меняет только яркость и не двигает
	// картинку, поэтому текст под ней не «плывёт».
	float band_y = fract(TIME * band_speed + 0.15);
	float d1 = abs(fract(uv.y - band_y + 0.5) - 0.5);
	float d2 = abs(fract(uv.y - band_y - 0.5 + 0.5) - 0.5);
	float band = exp(-pow(d1 / 0.045, 2.0))
		+ 0.45 * exp(-pow(d2 / 0.035, 2.0));
	col += band * band_strength * BAND_TINT;

	vec3 base = texture(screen_texture, uv).rgb;
	COLOR = vec4(mix(base, col, intensity), 1.0);
}

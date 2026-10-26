shader_type canvas_item;
render_mode blend_mix, unshaded;

// «ЖАРА»: процедурный слой нагрева поверх игры.
// Без hint_screen_texture — кадр не читается, только аддитивная тонировка
// по краям. Центр почти прозрачен (alpha ≤ 0.045), край ≤ 0.24.

uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float level : hint_range(0.0, 3.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float reduced : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint_warm : source_color = vec4(0.772549, 0.541176, 0.180392, 1.0);
uniform vec4 tint_hot : source_color = vec4(0.760784, 0.356863, 0.290196, 1.0);
uniform vec4 tint_crit : source_color = vec4(0.532549, 0.249804, 0.203137, 1.0);

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	vec2 q = UV - 0.5;
	float radius = length(q * vec2(1.15, 1.0));
	// Маска края: именно она ограничивает основной тон и скан-линии.
	float edge_mask = smoothstep(0.55, 0.98, radius);

	float edge_alpha = 0.16 * smoothstep(0.35, 0.95, heat);
	float vignette = 0.20 * smoothstep(0.10, 1.0, heat)
		* smoothstep(0.55, 1.05, radius);

	// Скан-линии: 1 тёмная полоса на 2 физических пикселя.
	float scan_phase = 0.5 + 0.5 * cos(FRAGCOORD.y * PI);
	float scanline = (0.010 + 0.028 * heat) * edge_mask * scan_phase;

	// Зерно: 6 + 6·heat Гц, центр подавлен.
	float grain_hz = 6.0 + 6.0 * heat;
	float grain_tick = floor(TIME * grain_hz);
	float grain = hash21(FRAGCOORD.xy + vec2(grain_tick * 17.0, grain_tick * 31.0));
	float grain_alpha = (0.008 + 0.016 * heat) * grain
		* (0.35 + 0.65 * edge_mask);

	// Медленная полоса: 0.05 + 0.10·heat UV/с.
	float band_y = fract(UV.y + TIME * (0.05 + 0.10 * heat));
	float band = smoothstep(0.0, 0.10, band_y) * (1.0 - smoothstep(0.10, 0.24, band_y));
	float band_alpha = 0.020 * heat * band * (0.20 + 0.80 * edge_mask);

	// Сердцебиение только на уровне ≥ 2 (period 1.10 → 0.55 с).
	float beat_on = step(1.5, level);
	float period = mix(1.10, 0.55, step(2.5, level));
	float beat = beat_on * pow(max(0.0, sin(TAU * TIME / period)), 8.0);
	float beat_alpha = beat * 0.08 * edge_mask;

	// Вспышка: слабее в центре, заметнее к краю.
	float flash_alpha = 0.12 * flash * (0.20 + 0.80 * edge_mask);

	float amount = edge_alpha * edge_mask
		+ vignette
		+ scanline
		+ grain_alpha
		+ band_alpha
		+ beat_alpha
		+ flash_alpha;

	// «Снизить эффекты»: шум, полоса, пульс и вспышка выключаются,
	// остаются только статичные тон и виньетка.
	float motion = 1.0 - clamp(reduced, 0.0, 1.0);
	amount = (edge_alpha * edge_mask + vignette)
		+ motion * (scanline + grain_alpha + band_alpha + beat_alpha + flash_alpha);

	vec3 tint = mix(tint_warm.rgb, tint_hot.rgb, smoothstep(0.35, 0.95, heat));
	tint = mix(tint, tint_crit.rgb, smoothstep(0.78, 1.0, heat));

	COLOR = vec4(tint, clamp(amount, 0.0, 0.24));
}

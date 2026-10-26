class_name UiMotion
extends RefCounted
## Единые тайминги и кривые UI-анимаций PEAK HOUR 97.
## Только константы и чистые функции; цвета и шрифты — в Theme90.
## reduced=true отключает движение: тряску, наклон, сердцебиение, пульсы.

const DUR_MICRO := 0.08
const DUR_FAST := 0.12
const DUR_UI := 0.18
const DUR_BASE := 0.22
const DUR_SLOW := 0.34

const EASE_OUT_POS_TRANS := Tween.TRANS_QUAD
const EASE_OUT_POS_EASE := Tween.EASE_OUT
const EASE_OUT_SCALE_TRANS := Tween.TRANS_CUBIC
const EASE_OUT_SCALE_EASE := Tween.EASE_OUT
const EASE_IN_POS_TRANS := Tween.TRANS_QUAD
const EASE_IN_POS_EASE := Tween.EASE_IN
const EASE_LOOP_TRANS := Tween.TRANS_SINE
const EASE_LOOP_EASE := Tween.EASE_IN_OUT
const OVERSHOOT_TRANS := Tween.TRANS_BACK
const OVERSHOOT_EASE := Tween.EASE_OUT
const OVERSHOOT_MAX := 1.06

const RISE := 8.0
const RISE_SMALL := 2.0
const SHAKE := 3.0
const KICK := 1.0
const DRAG_TILT := 0.045
const STAGGER := 0.03
const STAGGER_MAX := 0.09

## Глобальный переключатель «Снизить эффекты» (настройки).
static var reduced: bool = false


## Доля пути экспоненциального сглаживания за dt при постоянной tau.
static func k(dt: float, tau: float) -> float:
	return 1.0 - exp(-maxf(dt, 0.0) / maxf(tau, 0.0001))


static func clamp01(value: float) -> float:
	return clampf(value, 0.0, 1.0)

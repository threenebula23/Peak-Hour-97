#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Генератор звуков PEAK HOUR 97 (короткие 90s-style SFX + фоновый гул).

Все ассеты синтезируются программно, без внешних файлов и без сторонних
библиотек (только стандартная библиотека Python 3) — значит, нет проблем
с лицензиями и генерация воспроизводима на любой машине.

Запуск:
    python3 audio/generate_sfx.py

Результат:
    audio/sfx/*.wav   — 18 одноразовых эффектов, 30..800 мс
    audio/music/hum.wav — гул серверной, 3 с, loop-friendly

Формат WAV: 22050 Гц, 16 бит, моно, пик нормируется ровно к −6 dBFS
(без клиппинга: 10^(-6/20) ≈ 0.501 < 1.0).
"""

from __future__ import annotations

import math
import os
import random
import struct
import wave

SR = 22050                 # частота дискретизации
PEAK_DB = -6.0             # целевой пик, dBFS
PEAK = 10.0 ** (PEAK_DB / 20.0)   # ≈ 0.50119
TWO_PI = 2.0 * math.pi

HERE = os.path.dirname(os.path.abspath(__file__))
SFX_DIR = os.path.join(HERE, "sfx")
MUSIC_DIR = os.path.join(HERE, "music")

# Длительности в секундах (SFX обязаны попадать в 30..800 мс).
DUR = {
    "click": 0.045,
    "drag": 0.380,
    "drop": 0.140,
    "drop_error": 0.240,
    "recv": 0.330,
    "request_ready": 0.450,
    "minigame_win": 0.500,
    "minigame_fail": 0.500,
    "modem": 0.800,
    "connect_fail": 0.420,
    "tick": 0.040,
    "packet_loss": 0.190,
    "attack": 0.650,
    "attack_blocked": 0.320,
    "money_up": 0.430,
    "money_down": 0.320,
    "hour_end": 0.720,
    "run_end": 0.800,
}
HUM_DUR = 3.0


# ---------------------------------------------------------------- базовые ОСЦИЛЛЯТОРЫ

def nsamp(dur: float) -> int:
    """Количество отсчётов для длительности в секундах."""
    return max(1, int(round(SR * dur)))


def silence(dur: float) -> list:
    return [0.0] * nsamp(dur)


def noise(dur: float, rng: random.Random, amp: float = 1.0) -> list:
    n = nsamp(dur)
    return [rng.uniform(-amp, amp) for _ in range(n)]


def tone(dur: float, freq, amp: float = 1.0, phase: float = 0.0) -> list:
    """Синус. freq — число либо функция t (для свипов/глиссандо)."""
    n = nsamp(dur)
    out = [0.0] * n
    ph = phase
    dt = TWO_PI / SR
    for i in range(n):
        f = freq(i / SR) if callable(freq) else freq
        out[i] = amp * math.sin(ph)
        ph += dt * f
        if ph >= TWO_PI:
            ph -= TWO_PI
    return out


def _wave_shape(dur: float, freq, kind: str, amp: float) -> list:
    n = nsamp(dur)
    out = [0.0] * n
    ph = 0.0
    dt = TWO_PI / SR
    for i in range(n):
        f = freq(i / SR) if callable(freq) else freq
        ph += dt * f
        if ph >= TWO_PI:
            ph -= TWO_PI
        s = math.sin(ph)
        if kind == "square":
            out[i] = amp * (1.0 if s >= 0.0 else -1.0)
        elif kind == "saw":
            out[i] = amp * (2.0 * (ph / TWO_PI) - 1.0)
        else:  # triangle
            p = ph / TWO_PI
            out[i] = amp * (4.0 * abs(p - 0.5) - 1.0)
    return out


def square(dur: float, freq, amp: float = 1.0) -> list:
    return _wave_shape(dur, freq, "square", amp)


def saw(dur: float, freq, amp: float = 1.0) -> list:
    return _wave_shape(dur, freq, "saw", amp)


def tri(dur: float, freq, amp: float = 1.0) -> list:
    return _wave_shape(dur, freq, "tri", amp)


def rich(dur: float, freq: float, weights, bend=None, amp: float = 1.0) -> list:
    """Аддитивный тон: weights = [(множитель гармоники, вес), ...].

    bend(t) — множитель частоты (для нисходящего изгиба ноты).
    """
    n = nsamp(dur)
    out = [0.0] * n
    dt = TWO_PI / SR
    total = sum(abs(w) for _, w in weights) or 1.0
    for mult, w in weights:
        ph = 0.0
        for i in range(n):
            t = i / SR
            f = freq * mult * (bend(t) if bend else 1.0)
            ph += dt * f
            if ph >= TWO_PI:
                ph -= TWO_PI
            out[i] += w * math.sin(ph)
    return [v * (amp / total) for v in out]


# ---------------------------------------------------------------- ФИЛЬТРЫ (RBJ biquad)

def biquad(x: list, kind: float, fc: float, q: float = 0.707) -> list:
    """Прямо-циклический биквад: 'lp' | 'hp' | 'bp'."""
    w0 = TWO_PI * fc / SR
    c = math.cos(w0)
    s = math.sin(w0)
    alpha = s / (2.0 * q)
    if kind == "lp":
        b0, b1, b2 = (1.0 - c) / 2.0, 1.0 - c, (1.0 - c) / 2.0
    elif kind == "hp":
        b0, b1, b2 = (1.0 + c) / 2.0, -(1.0 + c), (1.0 + c) / 2.0
    else:  # bp (constant peak gain)
        b0, b1, b2 = alpha, 0.0, -alpha
    a0 = 1.0 + alpha
    a1 = -2.0 * c
    a2 = 1.0 - alpha
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    x1 = x2 = y1 = y2 = 0.0
    out = [0.0] * len(x)
    for i, xi in enumerate(x):
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, xi
        y2, y1 = y1, yi
        out[i] = yi
    return out


def periodic_filter(x: list, kind: str, fc: float, q: float = 0.707) -> list:
    """Фильтрация «по кругу»: сигнал считается периодическим.

    Прогоняем биквад по 4 копиям подряд и берём последнюю — состояние фильтра
    к её началу уже сошлось к периодическому режиму, поэтому первые и последние
    отсчёты совпадают по статистике и шум зациклевается без щелчка.
    """
    reps = 4
    y = biquad(list(x) * reps, kind, fc, q)
    return y[-len(x):]


# ---------------------------------------------------------------- МИКШЕРОВАНИЕ / ОФОРМЛЕНИЕ

def place(dst: list, src: list, at: float = 0.0, gain: float = 1.0) -> None:
    """Наложить src в dst со сдвигом at (сек). dst расширяется при необходимости."""
    off = nsamp(at)
    need = off + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, v in enumerate(src):
        dst[off + i] += gain * v


def apply_env(x: list, env: list) -> list:
    m = min(len(x), len(env))
    return [x[i] * env[i] for i in range(m)] + x[m:]


def env_exp(dur: float, tau: float) -> list:
    return [math.exp(-(i / SR) / tau) for i in range(nsamp(dur))]


def env_ar(dur: float, attack: float, release: float) -> list:
    """Атака линейно, затем отпускание в конце."""
    n = nsamp(dur)
    na = max(1, nsamp(attack))
    nr = max(1, nsamp(release))
    out = [1.0] * n
    for i in range(min(na, n)):
        out[i] = i / na
    for i in range(min(nr, n)):
        out[n - 1 - i] = min(out[n - 1 - i], i / nr)
    return out


def fade(x: list, fin: float, fout: float) -> list:
    """Гарантированное «обнуление» краёв — без щелчка в конце SFX."""
    n = len(x)
    ni = min(nsamp(fin), n)
    no = min(nsamp(fout), n)
    for i in range(ni):
        x[i] *= i / max(1, ni)
    for i in range(no):
        idx = n - 1 - i
        x[idx] *= i / max(1, no)
    return x


def shape_random(dur: float, rng: random.Random, seg: float = 0.02,
                 lo: float = 0.4, hi: float = 1.0) -> list:
    """Случайная «дыхательная» огибающая: линейная интерполяция случайных точек."""
    n = nsamp(dur)
    step = max(2, nsamp(seg))
    pts = [rng.uniform(lo, hi)]
    while len(pts) * step < n + step:
        pts.append(rng.uniform(lo, hi))
    out = [0.0] * n
    for i in range(n):
        k = i // step
        frac = (i % step) / step
        a = pts[k]
        b = pts[min(k + 1, len(pts) - 1)]
        out[i] = a + (b - a) * frac
    return out


def remove_dc(x: list) -> list:
    if not x:
        return x
    mean = sum(x) / len(x)
    return [v - mean for v in x]


def normalize(x: list, peak: float = PEAK) -> list:
    m = 0.0
    for v in x:
        a = abs(v)
        if a > m:
            m = a
    if m <= 1e-12:
        return x
    g = peak / m
    return [v * g for v in x]


def write_wav(path: str, x: list) -> None:
    """16-битный моно WAV без клиппинга (клип гарантируется нормировкой)."""
    frames = bytearray()
    for v in x:
        s = int(round(v * 32767.0))
        if s > 32767:
            s = 32767
        elif s < -32768:
            s = -32768
        frames += struct.pack("<h", s)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))


def finish(x: list, fin: float = 0.001, fout: float = 0.010) -> list:
    x = remove_dc(x)
    x = fade(x, fin, fout)
    return normalize(x)


# ---------------------------------------------------------------- ЗВУКИ

def s_click(rng: random.Random) -> list:
    """Сухой щелчок: короткий шумовой транзиент + звонкий пик + тело."""
    out = silence(DUR["click"])
    tr = apply_env(biquad(noise(0.004, rng), "hp", 1400.0, 0.8), env_exp(0.004, 0.0012))
    place(out, tr, 0.0, 1.0)
    ping = apply_env(tone(0.020, 2750.0), env_exp(0.020, 0.0030))
    place(out, ping, 0.0, 0.55)
    body = apply_env(tone(0.034, 940.0), env_exp(0.034, 0.0065))
    place(out, body, 0.0, 0.45)
    return finish(out, 0.0005, 0.010)


def s_drag(rng: random.Random) -> list:
    """Тихий шорох: полосовой шум с медленным «дыханием»."""
    n = noise(DUR["drag"], rng)
    n = biquad(biquad(n, "hp", 520.0, 0.7), "lp", 3600.0, 0.9)
    am = shape_random(DUR["drag"], rng, seg=0.025, lo=0.35, hi=1.0)
    x = [v * a for v, a in zip(n, am)]
    return finish(x, 0.030, 0.080)


def s_drop(rng: random.Random) -> list:
    """Мягкий стук: нисходящий свип + приглушённый контакт."""
    out = silence(DUR["drop"])
    swp = tone(0.12, lambda t: 55.0 + 115.0 * math.exp(-t / 0.035))
    swp = apply_env(swp, env_exp(0.12, 0.045))
    place(out, swp, 0.0, 1.0)
    ct = apply_env(biquad(noise(0.010, rng), "lp", 750.0, 0.7), env_exp(0.010, 0.004))
    place(out, ct, 0.0, 0.7)
    return finish(out, 0.003, 0.035)


def s_drop_error(rng: random.Random) -> list:
    """Глухой удар «не туда»: низкий спад без ярких гармоник."""
    out = silence(DUR["drop_error"])
    swp = tone(0.22, lambda t: 40.0 + 60.0 * math.exp(-t / 0.06))
    swp = apply_env(swp, env_exp(0.22, 0.080))
    place(out, biquad(swp, "lp", 320.0, 0.7), 0.0, 1.0)
    thud = apply_env(biquad(noise(0.030, rng), "lp", 420.0, 0.6), env_exp(0.030, 0.012))
    place(out, thud, 0.0, 0.6)
    return finish(out, 0.004, 0.070)


def s_recv(rng: random.Random) -> list:
    """Короткий сигнал + запись: писк уведомления, второй писк, шум ленты."""
    out = silence(DUR["recv"])
    beep = apply_env(tone(0.100, 880.0), env_ar(0.100, 0.005, 0.020))
    place(out, beep, 0.0, 1.0)
    blip = apply_env(tone(0.070, 1760.0), env_ar(0.070, 0.004, 0.015))
    place(out, blip, 0.130, 0.75)
    tape = biquad(biquad(noise(DUR["recv"], rng), "hp", 2200.0, 0.7), "lp", 6500.0, 0.7)
    place(out, tape, 0.0, 0.10)
    return finish(out, 0.002, 0.030)


def s_request_ready(rng: random.Random) -> list:
    """Восходящий аккорд: три ноты вверх, мягкая атака."""
    del rng
    out = silence(DUR["request_ready"])
    notes = [(523.25, 0.0), (659.25, 0.130), (783.99, 0.260)]
    for i, (f, at) in enumerate(notes):
        seg = DUR["request_ready"] - at
        t = rich(seg, f, [(1.0, 1.0), (2.0, 0.30), (3.0, 0.12)])
        t = apply_env(t, env_ar(seg, 0.010, 0.12))
        t = [v * math.exp(-(i2 / SR) / 0.55) for i2, v in enumerate(t)]
        place(out, t, at, 1.0 - i * 0.12)
    return finish(out, 0.008, 0.090)


def s_minigame_win(rng: random.Random) -> list:
    """Победа: восходящее арпеджио из четырёх нот."""
    del rng
    out = silence(DUR["minigame_win"])
    notes = [523.25, 659.25, 783.99, 1046.50]
    for i, f in enumerate(notes):
        at = i * 0.085
        seg = DUR["minigame_win"] - at
        t = tri(seg, f, amp=1.0)
        t = [v + 0.30 * math.sin(TWO_PI * f * 2.0 * (i2 / SR)) for i2, v in enumerate(t)]
        tau = 0.22 if i == len(notes) - 1 else 0.10
        t = apply_env(t, env_exp(seg, tau))
        t = fade(t, 0.003, 0.010)
        place(out, t, at, 1.0 - i * 0.10)
    return finish(out, 0.003, 0.070)


def s_minigame_fail(rng: random.Random) -> list:
    """Провал: нисходящие ноты с изгибом и низкий гул в хвосте."""
    out = silence(DUR["minigame_fail"])
    notes = [392.00, 330.00, 262.00, 196.00]
    for i, f in enumerate(notes):
        at = i * 0.090
        seg = DUR["minigame_fail"] - at  # ноты укладываются ровно в 500 мс
        bend = lambda t, _f=f, _s=seg: 1.0 - 0.08 * min(1.0, t / max(0.01, _s))
        t = rich(seg, f, [(1.0, 1.0), (2.0, 0.45), (3.0, 0.25)], bend=bend)
        t = apply_env(t, env_ar(seg, 0.006, 0.06))
        t = apply_env(t, env_exp(seg, 0.13))
        place(out, t, at, 1.0 - i * 0.10)
    # низкий вибрирующий «бзз» в конце
    buzz_d = 0.230
    buzz = square(buzz_d, 98.0, amp=1.0)
    am = [0.55 + 0.45 * math.sin(TWO_PI * 9.0 * (i / SR)) for i in range(len(buzz))]
    buzz = [v * a for v, a in zip(buzz, am)]
    buzz = apply_env(biquad(buzz, "lp", 900.0, 0.8), env_ar(buzz_d, 0.010, 0.06))
    place(out, buzz, 0.270, 0.55)
    return finish(out, 0.004, 0.060)


def s_modem(rng: random.Random) -> list:
    """Модемный скриз 0.8 с: набор → свип → резкий цифровой шум → тон-шаги."""
    out = silence(DUR["modem"])

    # 1) DTMF-набор (два тона)
    def dtmf(seg: float, lo: float, hi: float) -> list:
        t = [a + 0.5 * b for a, b in zip(tone(seg, lo), tone(seg, hi))]
        return apply_env(t, env_ar(seg, 0.003, 0.010))

    place(out, dtmf(0.050, 697.0, 1209.0), 0.0, 0.9)
    place(out, dtmf(0.050, 770.0, 1336.0), 0.075, 0.9)

    # 2) растущий несущий свип
    sweep = tone(0.150, lambda t: 350.0 + 1250.0 * (t / 0.150))
    sweep = apply_env(biquad(sweep, "lp", 4000.0, 0.7), env_ar(0.150, 0.010, 0.030))
    place(out, sweep, 0.140, 0.85)

    # 3) «скрип» цифрового канала: FM-носитель со случайными фазовыми срывами
    seg_d = 0.330
    n = nsamp(seg_d)
    screech = [0.0] * n
    ph = 0.0
    reset_every = max(1, nsamp(0.007))
    gate = 1.0
    for i in range(n):
        t = i / SR
        if i % reset_every == 0:
            gate = rng.uniform(0.55, 1.0)
        f = 1800.0 + 620.0 * math.sin(TWO_PI * 87.0 * t) + rng.uniform(-260.0, 260.0)
        ph += TWO_PI * f / SR
        if ph >= TWO_PI:
            ph -= TWO_PI
        screech[i] = math.sin(ph) * gate * (0.62 + 0.38 * math.sin(TWO_PI * 95.0 * t))
    hiss = biquad(biquad(noise(seg_d, rng), "hp", 1500.0, 0.7), "lp", 5200.0, 0.8)
    hiss = [v * r for v, r in zip(hiss, shape_random(seg_d, rng, 0.006, 0.3, 1.0))]
    screech = [a * 0.75 + b * 0.45 for a, b in zip(screech, hiss)]
    screech = apply_env(screech, env_ar(seg_d, 0.006, 0.020))
    place(out, screech, 0.290, 0.95)

    # 4) финальные тон-шаги (переключение двух частот каждые 12 мс)
    tail_d = DUR["modem"] - 0.620
    tn = nsamp(tail_d)
    tail = [0.0] * tn
    step = max(1, nsamp(0.012))
    ramp = max(1, nsamp(0.0015))
    ph2 = 0.0
    for i in range(tn):
        f = 1650.0 if (i // step) % 2 == 0 else 1900.0
        ph2 += TWO_PI * f / SR
        if ph2 >= TWO_PI:
            ph2 -= TWO_PI
        pos = i % step
        edge = 1.0
        if pos < ramp:
            edge = pos / ramp
        elif pos > step - ramp:
            edge = (step - pos) / ramp
        tail[i] = math.sin(ph2) * edge
    tail = apply_env(tail, env_ar(tail_d, 0.002, 0.020))
    place(out, tail, 0.620, 0.85)
    return finish(out, 0.002, 0.015)


def s_connect_fail(rng: random.Random) -> list:
    """«бзз» — глухой прерывистый сигнал ошибки."""
    out = silence(DUR["connect_fail"])
    pulse_d = 0.100
    for k in range(3):
        p = square(pulse_d, 140.0, amp=1.0)
        grit = biquad(noise(pulse_d, rng), "lp", 1300.0, 0.7)
        p = [a + 0.18 * b for a, b in zip(p, grit)]
        p = apply_env(biquad(p, "lp", 2600.0, 0.7), env_ar(pulse_d, 0.004, 0.012))
        place(out, p, k * 0.120, 1.0 - k * 0.12)
    return finish(out, 0.003, 0.040)


def s_tick(rng: random.Random) -> list:
    """Тиканье: очень короткий сухой щелчок (< 5 с)."""
    out = silence(DUR["tick"])
    tr = apply_env(biquad(noise(0.002, rng), "hp", 2500.0, 0.8), env_exp(0.002, 0.0006))
    place(out, tr, 0.0, 1.0)
    ping = apply_env(tone(0.010, 3600.0), env_exp(0.010, 0.0018))
    place(out, ping, 0.0, 0.50)
    body = apply_env(tone(0.024, 1700.0), env_exp(0.024, 0.0040))
    place(out, body, 0.0, 0.45)
    return finish(out, 0.0003, 0.008)


def s_packet_loss(rng: random.Random) -> list:
    """Потери пакетов: россыпь коротких тресков."""
    out = silence(DUR["packet_loss"])
    for _ in range(14):
        at = rng.uniform(0.0, DUR["packet_loss"] - 0.014)
        ln = rng.uniform(0.003, 0.011)
        b = biquad(biquad(noise(ln, rng), "hp", 1500.0, 0.7), "lp", 6000.0, 0.7)
        b = apply_env(b, env_exp(ln, max(0.0008, ln * 0.4)))
        place(out, b, at, rng.uniform(0.45, 1.0))
    return finish(out, 0.001, 0.015)


def s_attack(rng: random.Random) -> list:
    """Тревожный сигнал: двухтоновая сирена."""
    out = silence(DUR["attack"])
    period = 0.080
    k = 0
    t0 = 0.0
    while t0 < DUR["attack"] - 0.010:
        seg = min(period, DUR["attack"] - t0)
        f = 880.0 if k % 2 == 0 else 770.0
        t = rich(seg, f, [(1.0, 1.0), (3.0, 0.35), (5.0, 0.18)])
        t = apply_env(biquad(t, "lp", 3200.0, 0.7), env_ar(seg, 0.004, 0.014))
        place(out, t, t0, 1.0)
        low = apply_env(tone(seg, 110.0), env_ar(seg, 0.004, 0.020))
        place(out, low, t0, 0.45)
        t0 += period
        k += 1
    return finish(out, 0.003, 0.030)


def s_attack_blocked(rng: random.Random) -> list:
    """Металлический удар: неармоничные обертоны."""
    out = silence(DUR["attack_blocked"])
    partials = [(430.0, 1.0, 0.060), (713.0, 0.70, 0.080), (1097.0, 0.60, 0.065),
                (1621.0, 0.45, 0.050), (2411.0, 0.30, 0.035)]
    for f, w, tau in partials:
        t = apply_env(tone(0.300, f), env_exp(0.300, tau))
        place(out, t, 0.0, w)
    strike = apply_env(biquad(noise(0.007, rng), "hp", 2000.0, 0.7), env_exp(0.007, 0.0022))
    place(out, strike, 0.0, 1.0)
    body = apply_env(tone(0.120, 90.0), env_exp(0.120, 0.030))
    place(out, body, 0.0, 0.7)
    return finish(out, 0.001, 0.030)


def s_money_up(rng: random.Random) -> list:
    """Касса: «ka-ching» — щелчки механики и звон."""
    out = silence(DUR["money_up"])
    for at, g in ((0.0, 1.0), (0.130, 0.7)):
        clack = biquad(biquad(noise(0.007, rng), "hp", 1000.0, 0.7), "lp", 4200.0, 0.7)
        clack = apply_env(clack, env_exp(0.007, 0.0022))
        place(out, clack, at, g)
    mech = apply_env(tone(0.060, 380.0), env_exp(0.060, 0.016))
    place(out, mech, 0.0, 0.6)
    for f, w, tau in ((1570.0, 1.0, 0.22), (2350.0, 0.62, 0.15),
                      (3140.0, 0.42, 0.11), (4720.0, 0.22, 0.07)):
        t = apply_env(tone(0.360, f), env_exp(0.360, tau))
        place(out, t, 0.060, w)
    return finish(out, 0.001, 0.030)


def s_money_down(rng: random.Random) -> list:
    """Глухой вычет: сползающий вниз тон."""
    out = silence(DUR["money_down"])
    swp = tone(0.300, lambda t: 180.0 + 240.0 * math.exp(-t / 0.09))
    swp = apply_env(biquad(swp, "lp", 950.0, 0.7), env_exp(0.300, 0.100))
    place(out, swp, 0.0, 1.0)
    thud = apply_env(biquad(noise(0.020, rng), "lp", 520.0, 0.6), env_exp(0.020, 0.008))
    place(out, thud, 0.0, 0.7)
    return finish(out, 0.003, 0.060)


def s_hour_end(rng: random.Random) -> list:
    """Сигнал смены: колокольные две ноты."""
    del rng
    out = silence(DUR["hour_end"])
    for at, f in ((0.0, 783.99), (0.260, 1046.50)):
        for mult, w, tau in ((1.0, 1.0, 0.34), (2.76, 0.35, 0.18), (5.4, 0.15, 0.10)):
            seg = DUR["hour_end"] - at
            t = apply_env(tone(seg, f * mult), env_exp(seg, tau))
            place(out, t, at, w)
    return finish(out, 0.003, 0.100)


def s_run_end(rng: random.Random) -> list:
    """Длинный спад конца забега: удар + низ + уходящий аккорд."""
    out = silence(DUR["run_end"])
    impact = biquad(biquad(noise(0.030, rng), "hp", 300.0, 0.7), "lp", 4200.0, 0.7)
    impact = apply_env(impact, env_exp(0.030, 0.010))
    place(out, impact, 0.0, 0.9)
    low = tone(0.500, lambda t: 38.0 + 92.0 * math.exp(-t / 0.11))
    low = apply_env(low, env_exp(0.500, 0.150))
    place(out, low, 0.0, 1.0)
    for f in (130.81, 196.00, 261.63):
        t = rich(0.790, f, [(1.0, 1.0), (2.0, 0.40), (3.0, 0.18)])
        t = apply_env(t, env_exp(0.790, 0.360))
        place(out, t, 0.010, 0.75)
    shim = apply_env(tone(0.500, 1180.0), env_exp(0.500, 0.220))
    place(out, shim, 0.0, 0.20)
    return finish(out, 0.004, 0.150)


def s_hum(rng: random.Random) -> list:
    """Фоновый гул серверной: 3 с, начало и конец совпадают (loop-friendly).

    Все тона — целое число циклов за 3 с (кратно 1/3 Гц), AM — ровно 3 цикла,
    вентиляционный шум фильтруется «по кругу» (periodic_filter), поэтому шов
    петли статистически неотличим от любой другой пары отсчётов.
    """
    d = HUM_DUR
    n = nsamp(d)
    hum = tone(d, 50.0, 1.00)
    hum = [a + b for a, b in zip(hum, tone(d, 25.0, 0.35))]   # низкий рокот
    hum = [a + b for a, b in zip(hum, tone(d, 100.0, 0.45))]  # вторая гармоника
    hum = [a + b for a, b in zip(hum, tone(d, 150.0, 0.22))]  # «трансформатор»
    hum = [a + b for a, b in zip(hum, tone(d, 125.0, 0.10))]  # биение
    am = [1.0 + 0.05 * math.sin(TWO_PI * 1.0 * (i / SR)) for i in range(n)]  # 3 цикла
    hum = [v * a for v, a in zip(hum, am)]

    fan = noise(d, rng)
    fan = periodic_filter(fan, "hp", 180.0, 0.7)
    fan = periodic_filter(fan, "lp", 900.0, 0.8)
    fan_amp = 0.55
    peak_fan = max(abs(v) for v in fan) or 1.0
    fan = [v * (fan_amp / peak_fan) for v in fan]

    x = [0.55 * a + 1.0 * b for a, b in zip(hum, fan)]
    x = remove_dc(x)
    # Никаких fade: петля должна быть непрерывной.
    return normalize(x)


SFX_GENERATORS = {
    "click": s_click,
    "drag": s_drag,
    "drop": s_drop,
    "drop_error": s_drop_error,
    "recv": s_recv,
    "request_ready": s_request_ready,
    "minigame_win": s_minigame_win,
    "minigame_fail": s_minigame_fail,
    "modem": s_modem,
    "connect_fail": s_connect_fail,
    "tick": s_tick,
    "packet_loss": s_packet_loss,
    "attack": s_attack,
    "attack_blocked": s_attack_blocked,
    "money_up": s_money_up,
    "money_down": s_money_down,
    "hour_end": s_hour_end,
    "run_end": s_run_end,
}


# ---------------------------------------------------------------- ПРОВЕРКИ / MAIN

def peak_db(x: list) -> float:
    m = max(abs(v) for v in x)
    return 20.0 * math.log10(m) if m > 0 else float("-inf")


def check_sfx(name: str, x: list) -> list:
    errs = []
    dur = len(x) / SR
    if not (0.030 <= dur <= 0.800):
        errs.append("длительность %.1f мс вне 30..800" % (dur * 1000))
    db = peak_db(x)
    if not (-6.5 <= db <= -5.5):
        errs.append("пик %.2f dBFS" % db)
    if max(abs(v) for v in x) > 1.0:
        errs.append("клип")
    return errs


def check_hum(x: list) -> list:
    errs = []
    dur = len(x) / SR
    if not (2.0 <= dur <= 4.0):
        errs.append("длительность %.2f с вне 2..4" % dur)
    db = peak_db(x)
    if not (-6.5 <= db <= -5.5):
        errs.append("пик %.2f dBFS" % db)
    # шов петли: сравнить шаг на стыке со средним шагом внутри буфера
    seam = abs(x[0] - x[-1])
    steps = [abs(x[i] - x[i - 1]) for i in range(1, len(x), 97)]
    avg = (sum(steps) / len(steps)) if steps else 0.0
    if seam > 3.0 * avg:
        errs.append("шов петли %.4f > 3x среднего шага %.4f" % (seam, avg))
    return errs, seam, avg


def main() -> int:
    os.makedirs(SFX_DIR, exist_ok=True)
    os.makedirs(MUSIC_DIR, exist_ok=True)

    rows = []
    failed = 0

    for i, (name, gen) in enumerate(SFX_GENERATORS.items()):
        rng = random.Random(1000 + i)
        x = gen(rng)
        errs = check_sfx(name, x)
        path = os.path.join(SFX_DIR, name + ".wav")
        write_wav(path, x)
        rows.append(("sfx/" + name + ".wav", len(x) / SR, peak_db(x), errs))
        failed += len(errs)

    rng = random.Random(777)
    hum = s_hum(rng)
    hum_errs, seam, avg = check_hum(hum)
    hpath = os.path.join(MUSIC_DIR, "hum.wav")
    write_wav(hpath, hum)
    rows.append(("music/hum.wav", len(hum) / SR, peak_db(hum), hum_errs))
    failed += len(hum_errs)

    print("%-26s %9s %10s  %s" % ("файл", "мс", "пик dBFS", "статус"))
    for name, dur, db, errs in rows:
        status = "OK" if not errs else "; ".join(errs)
        print("%-26s %9.1f %10.2f  %s" % (name, dur * 1000, db, status))
    print("-" * 62)
    print("всего файлов: %d   ошибок: %d" % (len(rows), failed))
    print("hum: шов петли=%.5f  средний шаг отсчётов=%.5f" % (seam, avg))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

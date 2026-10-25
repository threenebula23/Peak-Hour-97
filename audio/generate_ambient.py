#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Генератор эмбиент-петель и звуков HDD для PEAK HOUR 97.

Все ассеты синтезируются программно, только стандартная библиотека Python 3
(math/random/struct/wave/os), без внешних сэмплов и лицензионных ограничений.
Генерация детерминирована: у каждого файла фиксированный seed.

Запуск:
    python3 audio/generate_ambient.py

Результат:
    audio/amb/fan_loop.wav    — 8.0 с, бесшовная петля вентилятора
    audio/amb/seek_short.wav  — 0.12 с, «клик-клац» головки HDD
    audio/amb/seek_series.wav — 0.40 с, серия из четырёх кликов разной высоты
    audio/amb/room_loop.wav   — 15.0 с, тихий низкий комнатный шум, петля

Формат WAV: 22050 Гц, 16 бит, моно. Пик каждого файла нормируется ровно
к −6 dBFS (как в audio/generate_sfx.py): 10^(-6/20) ≈ 0.50119 < 1.0,
поэтому клиппинг невозможен.

Бесшовность петель:
  * все тональные компоненты и AM имеют целое число периодов за длину петли;
  * хвост длиной crossfade «вклеивается» в начало (равномощный кроссфейд);
  * отсчёты на стыке — соседние отсчёты одного непрерывного потока,
    поэтому |first-last| сравним с обычным шагом между отсчётами.
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
AMB_DIR = os.path.join(HERE, "amb")

# Длительности, с.
DUR = {
    "fan_loop": 8.0,
    "seek_short": 0.12,
    "seek_series": 0.40,
    "room_loop": 15.0,
}

# Кроссфейд петли, с.
XFADE = {
    "fan_loop": 0.020,
    "room_loop": 0.500,
}


# ---------------------------------------------------------------- БАЗОВЫЕ УТИЛИТЫ

def nsamp(dur: float) -> int:
    """Количество отсчётов для длительности в секундах."""
    return max(1, int(round(SR * dur)))


def silence(dur: float) -> list:
    return [0.0] * nsamp(dur)


def noise(dur: float, rng: random.Random, amp: float = 1.0) -> list:
    return [rng.uniform(-amp, amp) for _ in range(nsamp(dur))]


def tone_n(n: int, freq: float, amp: float = 1.0, phase: float = 0.0) -> list:
    """Синус заданной длины в отсчётах, с непрерывной фазой."""
    out = [0.0] * n
    ph = phase
    dt = TWO_PI / SR
    for i in range(n):
        out[i] = amp * math.sin(ph)
        ph += dt * freq
        if ph >= TWO_PI:
            ph -= TWO_PI
    return out


def place(dst: list, src: list, at: float = 0.0, gain: float = 1.0) -> None:
    """Наложить src в dst со сдвигом at (сек); dst при необходимости растёт."""
    off = nsamp(at)
    need = off + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, v in enumerate(src):
        dst[off + i] += gain * v


# ---------------------------------------------------------------- ФИЛЬТРЫ

def onepole_lp(x: list, fc: float) -> list:
    """Однополюсный ФНЧ: y[n] = y[n-1] + a*(x[n] - y[n-1])."""
    a = 1.0 - math.exp(-TWO_PI * fc / SR)
    y = 0.0
    out = [0.0] * len(x)
    for i, xi in enumerate(x):
        y += a * (xi - y)
        out[i] = y
    return out


def biquad(x: list, kind: str, fc: float, q: float = 0.707) -> list:
    """RBJ biquad: 'lp' | 'hp' | 'bp'."""
    w0 = TWO_PI * fc / SR
    c = math.cos(w0)
    s = math.sin(w0)
    alpha = s / (2.0 * q)
    if kind == "lp":
        b0, b1, b2 = (1.0 - c) / 2.0, 1.0 - c, (1.0 - c) / 2.0
    elif kind == "hp":
        b0, b1, b2 = (1.0 + c) / 2.0, -(1.0 + c), (1.0 + c) / 2.0
    else:  # bp, constant peak gain
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


def brown_noise(white: list, leak: float = 0.995) -> list:
    """Брауновский шум: утечка-интегратор белого шума (нулевой DC)."""
    acc = 0.0
    out = [0.0] * len(white)
    for i, w in enumerate(white):
        acc = acc * leak + w * 0.05
        out[i] = acc
    return out


# ---------------------------------------------------------------- ОГИБАЮЩИЕ / МИКС

def fade(x: list, fin: float, fout: float) -> list:
    """Обнуление краёв (для одноразовых SFX, не для петель)."""
    n = len(x)
    ni = min(nsamp(fin), n)
    no = min(nsamp(fout), n)
    for i in range(ni):
        x[i] *= i / max(1, ni)
    for i in range(no):
        idx = n - 1 - i
        x[idx] *= i / max(1, no)
    return x


def remove_dc(x: list) -> list:
    if not x:
        return x
    mean = sum(x) / len(x)
    return [v - mean for v in x]


def scale_rms(x: list, target: float) -> list:
    if not x:
        return x
    rms = math.sqrt(sum(v * v for v in x) / len(x))
    if rms <= 1e-12:
        return x
    g = target / rms
    return [v * g for v in x]


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


def crossfade_loop(x: list, n: int, xf: int) -> list:
    """Бесшовная петля: хвост x[n:n+xf] вклеивается в начало x[0:xf].

    На стыке остаются соседние отсчёты исходного потока (x[n-1] -> x[n]),
    поэтому скачок не больше обычного шага сигнала. xf должен быть < n.
    """
    if xf <= 0 or xf >= n:
        return x[:n]
    out = x[:n]
    for i in range(xf):
        w = i / xf                      # 0 → хвост, 1 → начало
        out[i] = x[i] * w + x[n + i] * (1.0 - w)
    return out


def write_wav(path: str, x: list) -> None:
    """16-битный моно WAV; клиппинг невозможен после normalize()."""
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


# ---------------------------------------------------------------- ЗВУКИ

def s_fan_loop(rng: random.Random) -> list:
    """Вентилятор: брауновский/розовый шум + тон 180 Гц + медленная AM.

    Длина 8 с. Частоты AM (2 и 5 циклов) и тона (1440 циклов) кратны 1/8 Гц,
    поэтому при кроссфейде фазы совпадают и петля не «дышит» на шве.
    """
    d = DUR["fan_loop"]
    n = nsamp(d)
    xf = nsamp(XFADE["fan_loop"])
    total = n + xf

    white = [rng.uniform(-1.0, 1.0) for _ in range(total)]
    brown = brown_noise(white, leak=0.995)
    body = onepole_lp(brown, 850.0)          # основной низкий «гул воздуха»
    air = onepole_lp(white, 2600.0)          # розоватый шелест лопастей
    body = scale_rms(body, 0.32)
    air = scale_rms(air, 0.09)

    mix = [b + a for b, a in zip(body, air)]

    # Тон двигателя: 180 Гц + тихая вторая гармоника (обе кратны 1/8 Гц).
    # Длина — total отсчётов, чтобы после кроссфейда фаза на шве совпадала.
    hum_full = tone_n(total, 180.0, 0.11)
    hum_full = [h + 0.035 * s for h, s in zip(hum_full, tone_n(total, 360.0, 1.0))]

    # Медленная AM: 0.25 Гц (2 цикла) и 0.625 Гц (5 циклов) за 8 с.
    am = [1.0 + 0.10 * math.sin(TWO_PI * (2.0 / d) * (i / SR) + 0.4)
              + 0.045 * math.sin(TWO_PI * (5.0 / d) * (i / SR) + 1.3)
          for i in range(total)]

    x = [0.0] * total
    for i in range(total):
        x[i] = (mix[i] + hum_full[i]) * am[i]

    x = crossfade_loop(x, n, xf)
    x = remove_dc(x)
    return normalize(x)


def click_voice(rng: random.Random, dur: float, res_freq: float, res_tau: float,
                res_amp: float, hp_f: float, lp_f: float, noise_amp: float,
                thud_freq: float, thud_amp: float, thud_tau: float,
                impulse_amp: float = 0.8) -> list:
    """Один транзиент HDD: единичный импульс + фильтрованный шум + резонанс."""
    n = nsamp(dur)
    out = [0.0] * n

    # Единичный импульс (широкополосный «тик»).
    out[0] += impulse_amp
    if n > 1:
        out[1] -= 0.45 * impulse_amp

    # Короткий шумовой всплеск, отфильтрованный в полосу головки.
    bn = min(n, nsamp(0.006))
    burst = biquad(biquad(noise(0.006, rng), "hp", hp_f, 0.7), "lp", lp_f, 0.8)
    for i in range(bn):
        out[i] += noise_amp * burst[i] * math.exp(-(i / SR) / 0.0015)

    # Резонанс корпуса/пластины — «клик» с тоном.
    for i in range(n):
        t = i / SR
        out[i] += res_amp * math.sin(TWO_PI * res_freq * t) * math.exp(-t / res_tau)

    # Низкий «клац»/стук механики.
    for i in range(n):
        t = i / SR
        out[i] += thud_amp * math.sin(TWO_PI * thud_freq * t) * math.exp(-t / thud_tau)

    return fade(out, 0.0003, 0.004)


def s_seek_short(rng: random.Random) -> list:
    """«Клик-клац»: два транзиента с быстрым спадом, второй ниже по высоте."""
    out = silence(DUR["seek_short"])
    c1 = click_voice(rng, 0.060, res_freq=2850.0, res_tau=0.0032, res_amp=0.50,
                     hp_f=2400.0, lp_f=7200.0, noise_amp=0.95,
                     thud_freq=185.0, thud_amp=0.30, thud_tau=0.008)
    place(out, c1, 0.000, 1.00)
    c2 = click_voice(rng, 0.070, res_freq=1580.0, res_tau=0.0048, res_amp=0.55,
                     hp_f=1100.0, lp_f=5200.0, noise_amp=0.95,
                     thud_freq=115.0, thud_amp=0.70, thud_tau=0.013)
    place(out, c2, 0.033, 1.00)
    return normalize(fade(remove_dc(out), 0.0003, 0.010))


def s_seek_series(rng: random.Random) -> list:
    """Серия из четырёх кликов HDD с неровными интервалами и разной высотой."""
    d = DUR["seek_series"]
    out = silence(d)
    events = [
        # at,    res_freq, res_tau, res_amp, hp_f,   lp_f,  noise, thud_f, thud_amp, thud_tau, gain
        (0.000, 2700.0, 0.0030, 0.48, 2300.0, 7000.0, 0.90, 190.0, 0.28, 0.008, 0.95),
        (0.048, 1750.0, 0.0038, 0.52, 1400.0, 5600.0, 0.92, 130.0, 0.42, 0.010, 0.90),
        (0.126, 3350.0, 0.0026, 0.42, 2800.0, 7500.0, 0.85, 205.0, 0.22, 0.007, 0.85),
        (0.246, 1280.0, 0.0050, 0.58, 900.0,  4800.0, 0.95, 105.0, 0.72, 0.014, 1.00),
    ]
    for at, rf, rt, ra, hp, lp, na, tf, ta, tt, g in events:
        seg = min(0.075, d - at)
        c = click_voice(rng, seg, res_freq=rf, res_tau=rt, res_amp=ra,
                        hp_f=hp, lp_f=lp, noise_amp=na,
                        thud_freq=tf, thud_amp=ta, thud_tau=tt)
        place(out, c, at, g)
    return normalize(fade(remove_dc(out), 0.0003, 0.012))


def s_room_loop(rng: random.Random) -> list:
    """Комнатный шум: очень низкий брауновский гул + медленная AM, 15 с.

    Один цикл AM (1/15 Гц) и три цикла (0.2 Гц) укладываются в петлю ровно,
    кроссфейд 0.5 с убирает шов шума. Высокие частоты срезаны однополюсным ФНЧ,
    поэтому шум воспринимается тихим, хотя пик нормирован к −6 dBFS.
    """
    d = DUR["room_loop"]
    n = nsamp(d)
    xf = nsamp(XFADE["room_loop"])
    total = n + xf

    white = [rng.uniform(-1.0, 1.0) for _ in range(total)]
    brown = brown_noise(white, leak=0.999)
    rumble = onepole_lp(brown, 160.0)
    rumble = onepole_lp(rumble, 90.0)
    air = onepole_lp(white, 600.0)
    rumble = scale_rms(rumble, 0.30)
    air = scale_rms(air, 0.012)

    am = [1.0 + 0.22 * math.sin(TWO_PI * (1.0 / d) * (i / SR) + 0.7)
              + 0.07 * math.sin(TWO_PI * (3.0 / d) * (i / SR) + 2.1)
          for i in range(total)]

    x = [(r + a) * m for r, a, m in zip(rumble, air, am)]
    x = crossfade_loop(x, n, xf)
    x = remove_dc(x)
    return normalize(x)


AMBIENT_GENERATORS = {
    "fan_loop": s_fan_loop,
    "seek_short": s_seek_short,
    "seek_series": s_seek_series,
    "room_loop": s_room_loop,
}

# Фиксированные seed'ы — генерация полностью воспроизводима.
SEEDS = {
    "fan_loop": 20771,
    "seek_short": 20772,
    "seek_series": 20773,
    "room_loop": 20774,
}

LOOPS = {"fan_loop", "room_loop"}


# ---------------------------------------------------------------- ПРОВЕРКА

def peak_db(x: list) -> float:
    m = max(abs(v) for v in x) if x else 0.0
    return 20.0 * math.log10(m) if m > 0.0 else float("-inf")


def read_wav(path: str):
    """Прочитать WAV и вернуть (params, samples_int, samples_float)."""
    with wave.open(path, "rb") as w:
        nch = w.getnchannels()
        sw = w.getsampwidth()
        sr = w.getframerate()
        nf = w.getnframes()
        raw = w.readframes(nf)
    fmt = "<%dh" % nf
    ints = list(struct.unpack(fmt, raw)) if nf else []
    floats = [v / 32767.0 for v in ints]
    params = {"channels": nch, "sampwidth": sw, "sr": sr, "frames": nf}
    return params, ints, floats


def verify_wav(path: str, expected_dur: float, loop: bool) -> tuple:
    """Проверить записанный файл и напечатать его фактические параметры."""
    params, ints, floats = read_wav(path)
    name = os.path.relpath(path, HERE)
    dur = params["frames"] / params["sr"]
    db = peak_db(floats)
    max_abs = max((abs(v) for v in ints), default=0)

    errs = []
    if abs(dur - expected_dur) > 1.0 / SR:
        errs.append("длительность %.4f != %.4f" % (dur, expected_dur))
    if params["sr"] != SR:
        errs.append("SR %d" % params["sr"])
    if params["channels"] != 1:
        errs.append("channels %d" % params["channels"])
    if params["sampwidth"] != 2:
        errs.append("sampwidth %d" % params["sampwidth"])
    if not (-6.05 <= db <= -5.95):
        errs.append("пик %.2f dBFS" % db)
    if max_abs >= 32767:
        errs.append("клиппинг")

    seam = avg = None
    if loop:
        seam = abs(ints[0] - ints[-1])
        steps = [abs(ints[i] - ints[i - 1]) for i in range(1, len(ints), 97)]
        avg = (sum(steps) / len(steps)) if steps else 0.0
        # шов должен быть не больше типичного шага (+2 LSB на квантование)
        if seam > 3.0 * avg + 2.0:
            errs.append("шов %d > 3*avg %.1f" % (seam, avg))

    print("%-22s %8.3f %7d %5d %5d %9.2f  %s%s"
          % (name, dur, params["sr"], params["channels"], params["sampwidth"],
             db,
             ("first=%d last=%d |first-last|=%d avg-step=%.1f"
              % (ints[0], ints[-1], seam, avg)) if loop else
             ("first=%d last=%d" % (ints[0], ints[-1])),
             ("  ОШИБКИ: " + "; ".join(errs)) if errs else "  OK"))
    return errs, params, ints, floats


# ---------------------------------------------------------------- MAIN

def main() -> int:
    os.makedirs(AMB_DIR, exist_ok=True)

    written = []
    for name, gen in AMBIENT_GENERATORS.items():
        rng = random.Random(SEEDS[name])
        x = gen(rng)
        path = os.path.join(AMB_DIR, name + ".wav")
        write_wav(path, x)
        written.append((name, path))
        print("записан: %s  (%d сэмплов, seed=%d)"
              % (os.path.relpath(path, HERE), len(x), SEEDS[name]))

    print()
    print("%-22s %8s %7s %5s %5s %9s  %s"
          % ("файл", "сек", "SR", "кан.", "шир.", "пик dBFS", "first/last"))
    print("-" * 118)

    failed = 0
    for name, path in written:
        errs, _, _, _ = verify_wav(path, DUR[name], name in LOOPS)
        failed += len(errs)

    print("-" * 118)
    print("всего файлов: %d   ошибок: %d   seed'ы: %s"
          % (len(written), failed,
             ", ".join("%s=%d" % (n, SEEDS[n]) for n in AMBIENT_GENERATORS)))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

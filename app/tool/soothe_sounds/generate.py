#!/usr/bin/env python3
"""生成哄睡声音（#38 S-3）：白噪音、粉噪音、棕噪音、嘘声。

- 只用 Python 标准库，固定随机种子，同一台机器每次运行输出一样。
- 输出 app/assets/soothe/*.wav：单声道、22050 Hz、16 bit，每段 10 秒，首尾无缝循环。
- 响度统一到约 -24 dBFS（RMS），峰值不超过 -6 dBFS；App 里音量默认 30%、最高 70%，
  不做任何增益，所以实际声音不会比系统音量更大。
- 生成结果以 CC0 1.0 发布（见 assets/soothe/LICENSE.md），不含任何第三方素材。

用法（在 app/ 目录下）：python3 tool/soothe_sounds/generate.py
"""
import math
import os
import random
import struct
import wave

RATE = 22050
SECONDS = 10
N = RATE * SECONDS
XFADE = RATE  # 噪声类：多生成 1 秒，和开头交叉淡化，循环处听不出接缝
TARGET_RMS = 10 ** (-24 / 20)
PEAK = 10 ** (-6 / 20)
OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets', 'soothe')


def white(rng, n):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def pink(rng, n):
    # Paul Kellet 的精简滤波：白噪声 → 约 -3 dB/倍频程
    b0 = b1 = b2 = 0.0
    out = []
    for w in white(rng, n):
        b0 = 0.99765 * b0 + w * 0.0990460
        b1 = 0.96300 * b1 + w * 0.2965164
        b2 = 0.57000 * b2 + w * 1.0526913
        out.append(b0 + b1 + b2 + w * 0.1848)
    return out


def brown(rng, n):
    # 积分白噪声（带泄漏，避免直流漂移）→ 约 -6 dB/倍频程
    y = 0.0
    out = []
    for w in white(rng, n):
        y = 0.995 * y + w * 0.1
        out.append(y)
    return out


def bandpass(xs, f0, q):
    # RBJ 带通（恒定 0 dB 峰值增益）
    w0 = 2 * math.pi * f0 / RATE
    alpha = math.sin(w0) / (2 * q)
    a0 = 1 + alpha
    b0, b2 = alpha / a0, -alpha / a0
    a1, a2 = -2 * math.cos(w0) / a0, (1 - alpha) / a0
    x1 = x2 = y1 = y2 = 0.0
    out = []
    for x in xs:
        y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        out.append(y)
    return out


def loop_noise(gen, rng):
    xs = gen(rng, N + XFADE)
    head, tail = xs[:XFADE], xs[N:]
    body = xs[XFADE:N]
    # 结尾一秒 = 原结尾淡出 + 开头淡入，接回开头时连续
    mixed = []
    for i in range(XFADE):
        t = i / XFADE
        mixed.append(tail[i] * math.cos(t * math.pi / 2) + head[i] * math.sin(t * math.pi / 2))
    # 开头被挪到结尾：循环顺序 body → mixed → body …
    return body + mixed


def shush(rng):
    # "嘘——"：2–5 kHz 一带的噪声，加上有节奏的音量包络。每 2 秒一声，10 秒正好 5 声，首尾都是静音段，循环无缝
    noise = bandpass(bandpass(white(rng, N + RATE), 3200, 0.9), 3200, 0.9)[RATE:]
    period = 2 * RATE
    rise, hold, fall = int(0.25 * RATE), int(1.1 * RATE), int(0.45 * RATE)
    out = []
    for i, x in enumerate(noise):
        p = i % period
        if p < rise:
            g = math.sin(p / rise * math.pi / 2) ** 2
        elif p < rise + hold:
            g = 1.0
        elif p < rise + hold + fall:
            g = math.cos((p - rise - hold) / fall * math.pi / 2) ** 2
        else:
            g = 0.0
        out.append(x * g)
    return out


def normalize(xs):
    rms = math.sqrt(sum(x * x for x in xs) / len(xs))
    k = TARGET_RMS / rms
    peak = max(abs(x) for x in xs) * k
    if peak > PEAK:
        k *= PEAK / peak
    return [x * k for x in xs]


def write(name, xs):
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', max(-32767, min(32767, round(x * 32767)))) for x in xs))
    print(path, len(xs) / RATE, 's')


def main():
    os.makedirs(OUT, exist_ok=True)
    write('white.wav', normalize(loop_noise(white, random.Random(3801))))
    write('pink.wav', normalize(loop_noise(pink, random.Random(3802))))
    write('brown.wav', normalize(loop_noise(brown, random.Random(3803))))
    write('shush.wav', normalize(shush(random.Random(3804))))


if __name__ == '__main__':
    main()

"""Makes Mikky's spell sound (2026-10-06: « il manque un sound effect sur le
sort, et que le son dure plus longtemps »): ours, made by code, so it can
be published (the other sounds are the user's own and stay out of git).

    python tool/make_spell_sound.py

writes assets/sounds/spell.mp3 (needs numpy, and ffmpeg on the PATH or in
C:/ffmpeg/bin). The sound, 2.4 s:
  - 0.00 to 0.20: the magic gathers, a rising shimmer and a soft whoosh;
  - 0.20: the star bursts, a bright bell chord (bells: not quite in tune
    partials, quick to strike, slow to die);
  - 0.20 to 0.60: a quick arpeggio going up, little bells;
  - then sparkles, here and there, fading, and echoes that carry it on;
  a soft compression so the tail is heard to its end.
A light square wave under the bells: a touch of the pixel games.
"""
import os
import shutil
import subprocess
import tempfile
import wave

import numpy as np

RATE = 44100
LENGTH = 2.4
rng = np.random.default_rng(7)
t = np.arange(int(RATE * LENGTH)) / RATE
left = np.zeros_like(t)
right = np.zeros_like(t)


def bell(f, start, amp, decay=1.1, pan=0.0, square=0.0):
    """A bell struck at [start]: its partials, a quick strike, a long
    decay; [square] adds a little of a square wave (the pixel games)."""
    global left, right
    s = t - start
    on = s >= 0
    s = np.where(on, s, 0)
    env = np.where(on, (1 - np.exp(-s * 900)) * np.exp(-s / decay * 2.2), 0)
    tone = np.zeros_like(t)
    for ratio, gain, d in [(1.0, 1.0, 1.0), (2.76, .45, .6), (5.4, .22, .35), (8.93, .1, .2)]:
        tone += gain * np.sin(2 * np.pi * f * ratio * s) * np.exp(-s / (decay * d) * 2.2)
    if square:
        tone += square * np.sign(np.sin(2 * np.pi * f * s)) * np.exp(-s * 9)
    sig = amp * env * tone
    left += sig * (1 - pan) / 2 * 2
    right += sig * (1 + pan) / 2 * 2


# The magic gathers: a rising shimmer and a soft whoosh, up to the burst.
burst = .2
rise = t < burst
glide = 700 + 1500 * (t / burst) ** 2
phase = 2 * np.pi * np.cumsum(glide) / RATE
shimmer = np.where(rise, np.sin(phase) * (t / burst) ** 2 * .18 * (1 + .3 * np.sin(2 * np.pi * 38 * t)), 0)
noise = rng.standard_normal(len(t))
# A soft band of noise: smoothed twice, its highs taken.
smooth = np.convolve(noise, np.ones(8) / 8, mode='same')
band = noise - smooth
whoosh = np.where(rise, band * (t / burst) ** 3 * .22, 0)
whoosh += np.where((t >= burst) & (t < burst + .25), band * .22 * np.exp(-(t - burst) * 18), 0)
left += shimmer + whoosh
right += shimmer + whoosh * .9

# The burst: a bright chord (E major, high), struck at once.
for f, pan in [(1318.5, -.3), (1661.2, .3), (1975.5, -.1), (2637.0, .2)]:
    bell(f, burst, .2, decay=1.9, pan=pan, square=.15)
bell(659.25, burst, .16, decay=1.6)

# A quick arpeggio going up (E major pentatonic).
notes = [1318.5, 1480.0, 1661.2, 1975.5, 2217.5, 2637.0, 2960.0, 3322.4]
for i, f in enumerate(notes):
    bell(f, burst + .03 + i * .045, .1 * (1 - i * .06), decay=.55, pan=(-.6 + 1.2 * i / len(notes)), square=.1)

# Sparkles, here and there, fewer and softer as it goes.
for i in range(34):
    at = burst + .35 + rng.random() ** 1.6 * (LENGTH - .9)
    f = rng.choice(notes) * rng.choice([1, 2])
    bell(f, at, .11 * (1 - .6 * (at - burst) / LENGTH), decay=.45, pan=rng.uniform(-.9, .9))

# Echoes that carry it on (left and right a little apart).
def echo(sig, delay, gain, taps):
    out = sig.copy()
    d = int(delay * RATE)
    for k in range(1, taps + 1):
        out[d * k:] += sig[:len(sig) - d * k] * gain ** k
    return out


left = echo(left, .13, .5, 9)
right = echo(right, .17, .48, 9)

# A soft compression: the tail carries, the strike does not jump out.
peak = max(np.abs(left).max(), np.abs(right).max())
left, right = np.tanh(left / peak * 2.6), np.tanh(right / peak * 2.6)

# The end fades out; a little headroom.
fade = np.clip((LENGTH - t) / .5, 0, 1) ** 2
left *= fade
right *= fade
peak = max(np.abs(left).max(), np.abs(right).max())
left, right = left / peak * .89, right / peak * .89

here = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(here, '..', 'assets', 'sounds', 'spell.mp3')
with tempfile.TemporaryDirectory() as tmp:
    wav = os.path.join(tmp, 'spell.wav')
    data = (np.stack([left, right], axis=1) * 32767).astype('<i2')
    with wave.open(wav, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    ffmpeg = shutil.which('ffmpeg') or 'C:/ffmpeg/bin/ffmpeg.exe'
    subprocess.run([ffmpeg, '-y', '-loglevel', 'error', '-i', wav, '-codec:a', 'libmp3lame', '-q:a', '2', out], check=True)
print('wrote', os.path.normpath(out))

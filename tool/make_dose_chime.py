#!/usr/bin/env python3
"""يولّد نغمة تذكير الجرعة — من الصفر، من غير أي ملف صوت خارجي.

النغمة بتاعتنا: مفيش عيّنة من حد ومفيش رخصة تتتبع. اللي بيطلع من هنا
هو المصدر (WAV)، وبعده `afconvert` بيعمل النسختين اللي المنصّتين
بيقروهم:

    python3 tool/make_dose_chime.py /tmp/dose_chime.wav
    afconvert -f caff -d ima4 -c 1 /tmp/dose_chime.wav ios/Runner/dose_chime.caf
    afconvert -f m4af -d aac -b 64000 /tmp/dose_chime.wav android/app/src/main/res/raw/dose_chime.m4a

الشكل: جرس تلات نغمات طالعة (صول٥ – سي٥ – ري٦، ٧٨٤/٩٨٨/١١٧٥ هرتز)
بيتكرر كل ٢٫٢ ثانية لحد ~٢٤ ثانية. الأساسيات كلها تحت ١٫٢ كيلوهرتز
عن قصد: ضعف السمع مع السن بياكل الترددات العالية الأول، فنغمة «رفيعة»
بتختفي بالظبط عند اللي التطبيق موجود عشانه. الذروة −١ dBFS: عالية،
ومش مشوّهة.

**iOS بيرفض أي صوت أطول من ٣٠ ثانية ويرجع للنغمة الافتراضية في صمت** —
عشان كده الطول هنا ٢٤ ثانية، وفيه اختبار بيقرا الملف ويتأكد.
"""
import math
import struct
import sys
import wave

RATE = 44100
TOTAL_SECONDS = 24.0
MOTIF_EVERY = 2.2          # ثانية بين كل جرس والتاني
NOTES = (784.0, 988.0, 1175.0)   # G5, B5, D6
NOTE_GAP = 0.19            # بين نغمات الجرس الواحد
DECAY = 0.75               # ثابت الاضمحلال (ثانية)
PEAK = 0.89                # −1 dBFS


def bell(t, freq):
    """نغمة جرس: أساسي + توافقيتين بيموتوا أسرع."""
    if t < 0:
        return 0.0
    env = math.exp(-t / DECAY)
    return env * (
        math.sin(2 * math.pi * freq * t)
        + 0.35 * math.exp(-t / (DECAY * 0.5)) * math.sin(2 * math.pi * freq * 2.0 * t)
        + 0.12 * math.exp(-t / (DECAY * 0.3)) * math.sin(2 * math.pi * freq * 3.0 * t)
    )


def main(out):
    n = int(TOTAL_SECONDS * RATE)
    samples = [0.0] * n
    starts = []
    t0 = 0.0
    while t0 + NOTE_GAP * 2 + 1.0 < TOTAL_SECONDS:
        for k, f in enumerate(NOTES):
            starts.append((t0 + k * NOTE_GAP, f, 1.0 if k < 2 else 1.15))
        t0 += MOTIF_EVERY
    for start, f, gain in starts:
        i0 = int(start * RATE)
        i1 = min(n, i0 + int(3.0 * RATE))
        for i in range(i0, i1):
            samples[i] += gain * bell((i - i0) / RATE, f)
    # خبوت في آخر نص ثانية عشان الملف ما يقطعش فجأة
    fade = int(0.5 * RATE)
    for i in range(n - fade, n):
        samples[i] *= (n - i) / fade
    peak = max(abs(s) for s in samples) or 1.0
    scale = PEAK / peak
    with wave.open(out, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(
            struct.pack('<h', int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))
    print(f'{out}: {TOTAL_SECONDS}s, {len(starts)} notes, peak {PEAK}')


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'dose_chime.wav')

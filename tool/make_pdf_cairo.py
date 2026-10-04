#!/usr/bin/env python3
"""نسخة Cairo لملف الـPDF بس.

مكتبة `pdf` بتشكّل العربي بنفسها وبتطلب **أشكال العرض** (Presentation Forms،
U+FB50–FDFF وU+FE70–FEFF). Cairo فيه أشكال الأول والنص والآخر، بس **مفيهوش
الشكل المنفرد** لأغلب الحروف (ي بعد د، «و» لوحدها، ه بعد د…) — فـ«دي» و«ده»
و«و» كانوا بيترسموا غلط في الملف. الشاشات سليمة: فلاتر بيشكّل من الحروف
الأصلية.

السكربت بياخد Cairo-Regular وCairo-Bold، ولكل شكل منفرد ناقص بيضيف سطر في
جدول cmap بيشاور على **رسمة الحرف الأصلي نفسها** في Cairo (الحرف الأصلي
لوحده = شكله المنفرد). مفيش حرف بيترسم من جديد، ومفيش رسمة بتتغيّر. والاسم
الداخلي بيتغيّر لـ«Cairo PDF» عشان النسخة المعدّلة ما تتلخبطش مع الأصل (رخصة
OFL بتسمح بالتعديل).

    python3 tool/make_pdf_cairo.py

محتاج fontTools.
"""
import os
import unicodedata

from fontTools.ttLib import TTFont

FONTS = os.path.join(os.path.dirname(__file__), "..", "assets", "fonts")
OUT = os.path.join(FONTS, "pdf")


def patch(weight: str) -> int:
    font = TTFont(os.path.join(FONTS, f"Cairo-{weight}.ttf"))
    cmap = font.getBestCmap()
    added = {}
    for cp in list(range(0xFB50, 0xFE00)) + list(range(0xFE70, 0xFEFF)):
        if cp in cmap:
            continue
        decomposition = unicodedata.decomposition(chr(cp)).split()
        if len(decomposition) != 2 or decomposition[0] != "<isolated>":
            continue
        base = int(decomposition[1], 16)
        if base in cmap:
            added[cp] = cmap[base]
    for table in font["cmap"].tables:
        if table.isUnicode():
            table.cmap.update(added)
    for record in font["name"].names:
        if record.nameID in (1, 4, 6, 16):
            text = record.toUnicode()
            record.string = text.replace("Cairo", "Cairo PDF", 1) if record.nameID != 6 else text.replace("Cairo", "CairoPDF", 1)
    os.makedirs(OUT, exist_ok=True)
    font.save(os.path.join(OUT, f"CairoPdf-{weight}.ttf"))
    return len(added)


if __name__ == "__main__":
    for w in ("Regular", "Bold"):
        print(w, patch(w), "شكل منفرد اتضاف")

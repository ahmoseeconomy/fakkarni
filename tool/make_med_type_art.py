#!/usr/bin/env python3
"""رسومات نوع الدوا — نسخ التطبيق من رسومات المالك (Magnific).

الأصول بتفضل زي ما هي في مكانها (برّه الريبو)؛ السكربت ده بياخد نسخة من كل
واحدة، بيقصّها على حدود الرسمة نفسها (الشفافية)، وبيحطّها في **إطار واحد**
لكل الأنواع — مربع، الضلع الأطول للرسمة ٨٤٪ منه، في النص — وبيصغّرها لـ
٥١٢ بكسل. كده العلبة العريضة والإزازة الطويلة بيبانوا بنفس الحجم جنب بعض،
والتسعة مع بعض أقل من ميجا بدل ٨.

    python3 tool/make_med_type_art.py ~/Downloads

محتاج Pillow. الأسامي متربوطة بالأرقام اللي في آخر ملفات Magnific؛ النوع
اتحدد بالعين (المالك أكّده ٤ أكتوبر ٢٠٢٦).
"""
import os
import sys

from PIL import Image

SOURCES = {
    "tablet": "13883",
    "capsule": "23549",
    "injection": "34329",
    "ointment": "47051",
    "syrup": "58175",
    "drops": "69370",
    "inhaler": "80964",
    "suppository": "27214",
    "generic": "14350",
}

SIDE = 512
FILL = 0.84  # الضلع الأطول للرسمة جوّه الإطار
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "med_types")


def frame(path: str) -> Image.Image:
    im = Image.open(path).convert("RGBA")
    bbox = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    art = im.crop(bbox)
    w, h = art.size
    scale = SIDE * FILL / max(w, h)
    art = art.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
    canvas = Image.new("RGBA", (SIDE, SIDE), (0, 0, 0, 0))
    canvas.alpha_composite(art, ((SIDE - art.width) // 2, (SIDE - art.height) // 2))
    return canvas


def main() -> None:
    src_dir = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Downloads")
    files = os.listdir(src_dir)
    os.makedirs(OUT, exist_ok=True)
    for kind, tag in SOURCES.items():
        match = [f for f in files if f.startswith("magnific") and f.endswith(f"__{tag}.png")]
        if len(match) != 1:
            sys.exit(f"{kind}: لقيت {len(match)} ملف بالرقم {tag}")
        out = os.path.join(OUT, f"{kind}.png")
        frame(os.path.join(src_dir, match[0])).save(out, optimize=True)
        print(f"{kind}: {os.path.getsize(out) // 1024}KB")


if __name__ == "__main__":
    main()

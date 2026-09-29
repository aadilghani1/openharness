"""Bake local Avenir outlines into bounded 4-bit proportional text atlases."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math

root = Path(__file__).resolve().parents[1]
out = root / 'generated'
out.mkdir(exist_ok=True)
source = ['#include "pro_canvas.h"\n']
for size in (24, 32, 42, 56):
    height = math.ceil(size * 1.375)
    f = ImageFont.truetype('/System/Library/Fonts/Avenir Next.ttc', size * 2, index=5 if size < 42 else 2)
    data = bytearray()
    glyphs = []
    for cp in range(32, 256):
        ch = chr(cp) if cp < 127 or cp >= 160 else '?'
        advance = max(1, math.ceil(f.getlength(ch) / 2))
        width = advance + 2
        im = Image.new('L', (width * 2, height * 2))
        ImageDraw.Draw(im).text((2, size * 2), ch, font=f, fill=255, anchor='ls')
        im = im.resize((width, height), Image.Resampling.LANCZOS)
        a = [min(15, (v + 8) // 17) for v in im.tobytes()]
        if len(a) & 1: a.append(0)
        glyphs.append((len(data), width, advance))
        data.extend((a[i] << 4) | a[i+1] for i in range(0,len(a),2))
    source.append(f'static const uint8_t alpha_{size}[]={{\n')
    source.extend(','.join(str(v) for v in data[i:i+96])+',\n' for i in range(0,len(data),96))
    source.append('};\n')
    source.append(f'static const ht_pro_glyph_t glyphs_{size}[]={{\n')
    source.extend('{%d,%d,%d},\n'%g for g in glyphs)
    source.append('};\n')
    source.append(f'const ht_pro_font_t ht_pro_{size}={{32,255,{height},glyphs_{size},alpha_{size}}};\n')
    print(size, height, len(data))
(out/'pro_fonts.c').write_text(''.join(source))

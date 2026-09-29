#!/usr/bin/env python3
"""Generate the Pro's illustrated companion without changing shared dial art.

The source is the approved "Take a little company" illustration in
pro-concepts/tools/design.py. All drawings here are code-authored geometry.
The pack contains independently zlib-compressed images. A masked block decodes
to RGB565 little-endian pixels followed by one straight alpha byte per pixel.
Landscape blocks contain RGB565 pixels only. No font data is embedded.
"""
from __future__ import annotations

from pathlib import Path
import hashlib
import json
import math
import struct
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "generated"
PREVIEWS = OUT / "previews"
SCALE = 3
HERO = 350
COMPACT = 160
FRAMES = 24
MOODS = ("idle", "working", "attention", "done", "offline", "asleep", "booped", "listening")
DURATIONS = (150, 90, 140, 55, 180, 220, 35, 125)
ORIGIN = (152, 145)


class Canvas:
    """Coordinates stay registered to the original 720px concept artwork."""

    def __init__(self, size=HERO, origin=ORIGIN, fill=(0, 0, 0, 0)):
        self.image = Image.new("RGBA", (size * SCALE, size * SCALE), fill)
        self.draw = ImageDraw.Draw(self.image)
        self.origin = origin

    def point(self, xy):
        return tuple(round((xy[n] - self.origin[n]) * SCALE) for n in (0, 1))

    def rect(self, bounds):
        return (*self.point(bounds[:2]), *self.point(bounds[2:]))

    def ellipse(self, bounds, fill, outline=None, width=1):
        self.draw.ellipse(self.rect(bounds), fill, outline, round(width * SCALE))

    def line(self, points, fill, width=1, rounded=False):
        self.draw.line([self.point(p) for p in points], fill, round(width * SCALE), joint="curve")
        if rounded:
            radius = width / 2
            for x, y in (points[0], points[-1]):
                self.ellipse((x - radius, y - radius, x + radius, y + radius), fill)

    def arc(self, bounds, start, end, fill, width=1):
        self.draw.arc(self.rect(bounds), start, end, fill, round(width * SCALE))

    def finish(self, size=None):
        return self.image.resize((size or HERO, size or HERO), Image.Resampling.LANCZOS)


def cubic(a, b, c, d):
    points = []
    for step in range(65):
        t = step / 64
        u = 1 - t
        points.append(tuple(u**3 * a[n] + 3*u*u*t*b[n] + 3*u*t*t*c[n] + t**3*d[n]
                            for n in (0, 1)))
    return points


def render_octopus(mood: str, frame: int, touch_look=None):
    # Listening is five real input levels with four subtle body phases each.
    level = min(frame // 4, 4) if mood == "listening" else 0
    phase = (frame % 4) * math.tau / 4 if mood == "listening" else frame * math.tau / FRAMES
    if mood == "offline":
        phase = 0
    pulse = math.sin(math.pi * frame / (FRAMES - 1))
    if touch_look is not None:
        phase, pulse = 0, 1
    bob = (0.7 if mood == "listening" else 1.5 if mood == "asleep" else 3) * math.sin(phase)
    if mood in ("offline", "booped"):
        bob = 0 if mood == "offline" else 4 * pulse
    if mood == "done":
        bob = -8 * pulse
    c = Canvas()
    c.ellipse((213, 441, 431, 466), (24, 49, 33, 30))

    # The same eight arms and registration as the original approved illustration.
    for i, end_x in enumerate((192, 225, 262, 303, 344, 384, 424, 465)):
        start = (293 + i * 8, 336 + bob)
        swing = (0 if mood == "offline" else 2 if mood == "asleep" else 5) * math.sin(phase + i)
        end = (end_x, 414 + 18 * math.sin(i * 1.8) + swing)
        if mood == "working" and i in (0, 2, 5, 7):
            end = (end_x + 2 * math.sin(phase + i), end[1] - 18 - 10 * math.sin(phase * 2 + i))
        elif mood == "attention" and i == 7:
            end = (461 + 5 * math.sin(phase), 283 + 8 * math.sin(phase))
        elif mood == "done" and i in (0, 7):
            end = (end_x + (-4 if i == 0 else 4) * pulse, end[1] - 98 * pulse)
        elif mood == "booped":
            end = (end_x + (end_x - 322) * .025 * pulse, end[1] + 3 * pulse)
        c1 = (start[0] + (end_x - 320) * .2, 410 + bob)
        c2 = (end[0] - 18 * math.cos(i), end[1] + 34)
        points = cubic(start, c1, c2, end)
        ink = "#78558e" if i % 2 else "#624778"
        if mood == "offline":
            ink = "#837b8d" if i % 2 else "#736b80"
        c.line(points, ink, 24, True)
        c.line([(x, y + 5) for x, y in points[32:]], "#b592b4" if mood != "offline" else "#a6a0ae", 6, True)

    squeeze = .955 if touch_look is not None else 1 - .055 * pulse if mood == "booped" else .95 if mood == "asleep" else 1
    widen = 1.035 if touch_look is not None else 1 + .035 * pulse if mood == "booped" else 1

    def hb(bounds):
        x1, y1, x2, y2 = bounds
        return (322 + (x1 - 322) * widen, 338 + (y1 - 338) * squeeze + bob,
                322 + (x2 - 322) * widen, 338 + (y2 - 338) * squeeze + bob)

    def hp(x, y):
        return (322 + (x - 322) * widen, 338 + (y - 338) * squeeze + bob)

    body, face, shine = ("#9974af", "#a381bc", "#b296c6")
    if mood == "offline":
        body, face, shine = ("#9890a3", "#a49bac", "#b4acbe")
    c.ellipse(hb((207, 173, 437, 383)), body)
    c.ellipse(hb((218, 179, 415, 363)), face)
    c.ellipse(hb((248, 200, 353, 247)), shine)

    blink = mood not in ("attention", "listening", "done", "booped", "asleep", "offline") and frame in (18, 19)
    happy = (mood == "done" and 3 <= frame <= 19) or mood == "booped" and touch_look is None
    sleeping = mood == "asleep"
    for x in (277, 367):
        if happy:
            c.arc(hb((x - 16, 282, x + 16, 307)), 193, 347, "#352d49", 6)
        elif blink or sleeping:
            if sleeping:
                c.arc(hb((x - 16, 278, x + 16, 300)), 10, 170, "#514762", 6)
            else:
                c.line([hp(x - 15, 292), hp(x + 14, 292)], "#352d49", 6, True)
        else:
            eye_height = 25 if mood != "attention" else 29
            c.ellipse(hb((x - 22, 287 - eye_height, x + 22, 287 + eye_height)), "#f8f0df")
            gaze = touch_look * 5 if touch_look is not None else 5 * math.sin(phase / 2) if mood == "working" else 0
            pupil_y = 4 if mood == "offline" else -3 if mood == "attention" else 0
            c.ellipse(hb((x - 8 + gaze, 275 + pupil_y, x + 12 + gaze, 301 + pupil_y)), "#302d45")
            c.ellipse(hb((x + 1 + gaze, 278 + pupil_y, x + 7 + gaze, 284 + pupil_y)), "#ffffff")
            if mood == "working":
                points = [(x - 17, 256), (x + 12, 262)] if x == 277 else [(x - 12, 262), (x + 17, 256)]
                c.line([hp(*p) for p in points], "#775784", 3, True)
    cheeks = "#d49bb6" if mood in ("booped", "done") else "#c893b0"
    if mood != "offline":
        c.ellipse(hb((242, 312, 263, 323)), cheeks)
        c.ellipse(hb((381, 312, 402, 323)), cheeks)
    if mood == "listening" and level > 0:
        radius_x = (5, 8, 11, 14, 17)[level]
        radius_y = (2, 4, 7, 11, 15)[level]
        c.ellipse(hb((322-radius_x, 325-radius_y, 322+radius_x, 325+radius_y)), "#50334f")
        if level >= 3:
            c.ellipse(hb((315, 329, 329, 333 + (level - 3)*3)), "#d797b1")
    elif sleeping:
        c.ellipse(hb((318, 318, 326, 324)), "#6f4c70")
    elif mood == "attention":
        c.ellipse(hb((317, 317, 327, 325)), "#50334f")
    elif mood == "offline":
        c.line([hp(309, 325), hp(335, 325)], "#6e6079", 3, True)
    else:
        c.arc(hb((303, 304, 343, 334)), 10, 170, "#50334f", 4)

    # A finite, local glint accompanies completion; it is not a persistent badge.
    if mood == "done" and 3 <= frame <= 16:
        glow = math.sin((frame - 3) / 13 * math.pi)
        for x, y, radius in ((456, 228, 7), (190, 270, 5)):
            r = radius * glow
            c.line([(x-r, y), (x+r, y)], "#f9e7a2", 2, True)
            c.line([(x, y-r), (x, y+r)], "#f9e7a2", 2, True)
    return c.finish()


def landscape():
    c = Canvas(720, (0, 0), "#d9e8cf")
    c.ellipse((489, 102, 629, 242), "#fbebad")
    shapes = (
        ([(0,341),(122,299),(300,357),(528,273),(720,332),(720,720),(0,720)], "#a8bf92"),
        ([(0,431),(182,376),(414,404),(591,355),(720,418),(720,720),(0,720)], "#6d966f"),
        ([(0,518),(188,475),(455,481),(720,541),(720,720),(0,720)], "#2b5949"),
    )
    for points, ink in shapes:
        c.draw.polygon([c.point(p) for p in points], fill=ink)
    for x, y in ((54,439),(616,483),(657,457)):
        c.line([(x,y+20),(x+4,y),(x+9,y+20)], "#d2e0ad", 2)
    return c.finish(720).convert("RGB")


def letter(variant, size=64):
    im = Image.new("RGBA", (64*SCALE, 64*SCALE))
    d = ImageDraw.Draw(im)
    lift = (0, 3, 6)[variant]
    # A tiny curl at the foot lets the envelope read as held, rather than a badge.
    d.line([(24*SCALE,(51-lift)*SCALE),(32*SCALE,57*SCALE),(39*SCALE,52*SCALE)],
           "#78558e", 7*SCALE, joint="curve")
    d.rounded_rectangle((4*SCALE,(11-lift)*SCALE,60*SCALE,(49-lift)*SCALE),
                        5*SCALE, "#fff0cb", "#b79b69", 2*SCALE)
    d.line([(7*SCALE,(15-lift)*SCALE),(32*SCALE,(32-lift)*SCALE),(57*SCALE,(15-lift)*SCALE)],
           "#b79b69", 2*SCALE, joint="curve")
    d.line([(7*SCALE,(46-lift)*SCALE),(23*SCALE,(31-lift)*SCALE)], "#d2b785", SCALE)
    d.line([(57*SCALE,(46-lift)*SCALE),(41*SCALE,(31-lift)*SCALE)], "#d2b785", SCALE)
    im = im.resize((size, size), Image.Resampling.LANCZOS)
    # Keep one entirely transparent boundary for seamless dirty-rectangle
    # replacement; small downsampled envelopes otherwise retain a1/255 fringe.
    alpha = im.getchannel("A")
    ImageDraw.Draw(alpha).rectangle((0, 0, size-1, size-1), outline=0, width=1)
    im.putalpha(alpha)
    return im


def encode(image, alpha):
    rgba = np.array(image.convert("RGBA"), dtype=np.uint16)
    rgb = rgba[..., :3]
    # RGB at fully transparent pixels must be zero; prevents unused-color entropy.
    if alpha:
        rgb[rgba[..., 3] == 0] = 0
    rgb565 = ((rgb[..., 0] >> 3) << 11) | ((rgb[..., 1] >> 2) << 5) | (rgb[..., 2] >> 3)
    raw = rgb565.astype("<u2").tobytes()
    if alpha:
        raw += rgba[..., 3].astype("u1").tobytes()
    return raw


def main():
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    blob = bytearray()
    blocks, memo = [], {}

    def asset(name, image, alpha=True, duration=100):
        raw = encode(image, alpha)
        key = hashlib.sha256(raw).hexdigest()
        if key not in memo:
            packed = zlib.compress(raw, 9)
            assert zlib.decompress(packed) == raw
            memo[key] = (len(blob), len(packed))
            blob.extend(packed)
        offset, length = memo[key]
        block = dict(name=name, offset=offset, length=length, raw_length=len(raw),
                     width=image.width, height=image.height, duration_ms=duration,
                     alpha=int(alpha), sha256=key)
        blocks.append(block)
        return block

    landscape_image = landscape()
    backdrop = asset("landscape", landscape_image, False)
    landscape_image.save(PREVIEWS / "landscape.png")
    movies = {mood: [render_octopus(mood, f) for f in range(FRAMES)] for mood in MOODS}
    # Frames20..23 are fallback silence; clients use level*4 + phase, levels0..4.
    movies["listening"][20:] = movies["listening"][:4]
    mood_meta, touch_meta, letter_meta = [], [], []
    for size in (HERO, COMPACT):
        mood_rows = []
        for mood, duration in zip(MOODS, DURATIONS):
            row = []
            for f, source in enumerate(movies[mood]):
                im = source if size == HERO else source.resize((size,size), Image.Resampling.LANCZOS)
                row.append(asset(f"octopus_{size}_{mood}_{f:02}", im, duration=duration))
            mood_rows.append(row)
        mood_meta.append(mood_rows)
        touch_meta.append([asset(f"touch_{size}_{gaze:+}", render_octopus("booped", 0, gaze).resize((size,size), Image.Resampling.LANCZOS))
                           for gaze in range(-2,3)])
        letter_size = 64 if size == HERO else 30
        letter_meta.append([asset(f"letter_{size}_{variant}", letter(variant,letter_size), duration=160) for variant in range(3)])

    # Export previews on the same landscape, with no generated sample app text.
    preview_frames = {}
    for mood in MOODS:
        sequence = []
        for im in movies[mood]:
            stage = landscape_image.copy()
            stage.paste(im, ORIGIN, im)
            sequence.append(stage.resize((360,360),Image.Resampling.LANCZOS))
        preview_frames[mood] = sequence
        sequence[0].save(PREVIEWS / f"{mood}.png")
        sequence[0].save(PREVIEWS / f"{mood}.gif", save_all=True, append_images=sequence[1:],
                         duration=DURATIONS[MOODS.index(mood)], loop=0, disposal=2)
    sheet = Image.new("RGB", (4*300,2*330), "#f4f2e8")
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Menlo.ttc",19)
    except OSError:
        font = ImageFont.load_default()
    for index,mood in enumerate(MOODS):
        x,y = (index%4)*300,(index//4)*330
        # Expressive midpoint for single-image review.
        show = 11 if mood in ("done","booped") else 14 if mood=="listening" else 4
        sheet.paste(preview_frames[mood][show].resize((300,300),Image.Resampling.LANCZOS),(x,y))
        draw.text((x+12,y+305), mood, font=font, fill="#2b5949")
    sheet.save(PREVIEWS / "moods-contact-sheet.png")
    pressed = Image.new("RGB",(5*200,210),"#d9e8cf")
    for index,gaze in enumerate(range(-2,3)):
        im=render_octopus("booped",0,gaze).resize((200,200),Image.Resampling.LANCZOS)
        pressed.paste(im,(index*200,0),im)
    pressed.save(PREVIEWS / "touch-gaze.png")
    letters=Image.new("RGB",(3*96,96),"#6d966f")
    for index in range(3):
        im=letter(index)
        letters.paste(im,(index*96+16,16),im)
    letters.save(PREVIEWS / "letters.png")

    def initializer(block):
        return "{%d,%d,%d,%d,%d,%d,%d}" % tuple(block[k] for k in
                    ("offset","length","raw_length","width","height","duration_ms","alpha"))

    h = ["/* Generated by tools/generate_art.py. RGB565LE then straight alpha8. */",
         "#pragma once", "#include <stdint.h>",
         "typedef struct { uint32_t offset, length, raw_length; uint16_t width, height, duration_ms; uint8_t alpha; } pro_art_frame_t;",
         "enum { PRO_ART_HERO=0, PRO_ART_COMPACT=1, PRO_ART_SIZE_COUNT=2, PRO_ART_MOOD_COUNT=8, PRO_ART_FRAMES=24,",
         "       PRO_ART_LISTENING_STRIDE=4, PRO_ART_LISTENING_LEVELS=5, PRO_ART_TOUCH_FRAMES=5, PRO_ART_LETTER_FRAMES=3 };",
         "/* Mood indices exactly match HT_CHARACTER_IDLE..HT_CHARACTER_LISTENING. */",
         "static const uint16_t pro_art_sizes[2] = {350,160};",
         "/* Letter origin within a portrait; use same origin for all animation frames. */",
         "static const int16_t pro_art_letter_anchor[2][2] = {{281,220},{128,101}};",
         "static const pro_art_frame_t pro_art_landscape = " + initializer(backdrop) + ";",
         "static const pro_art_frame_t pro_octopus_frames[2][8][24] = {"]
    for mood_rows in mood_meta:
        h.append(" {")
        for mood,row in zip(MOODS,mood_rows):
            h.append("  { /* " + mood + " */")
            h.extend("   "+initializer(frame)+"," for frame in row)
            h.append("  },")
        h.append(" },")
    h.append("};")
    for name,rows in (("pro_octopus_touch_frames",touch_meta),("pro_art_letter",letter_meta)):
        h.append(f"static const pro_art_frame_t {name}[2][{len(rows[0])}] = {{")
        h.extend(" {"+",".join(initializer(frame) for frame in row)+"}," for row in rows)
        h.append("};")
    digest=hashlib.sha256(blob).hexdigest()
    h.extend((f"#define PRO_ART_PACK_BYTES {len(blob)}u",f'#define PRO_ART_PACK_SHA256 "{digest}"',""))
    (OUT / "pro_art.h").write_text("\n".join(h))
    (OUT / "pro_art.pack").write_bytes(blob)
    manifest=dict(format="zlib(RGB565LE_plane + optional_alpha8_plane)",
                  sizes=[HERO,COMPACT],moods=list(MOODS),frames=FRAMES,
                  listening="index = clamp(real_input_level,0,4)*4 + gentle_phase(0..3)",
                  touch="index = clamp(pose.look,-2,2)+2; select while pose.pressed",
                  completion="done and booped are finite sequences; hold final pose or return to idle",
                  letter_anchor=[[281,220],[128,101]],
                  bytes=len(blob),sha256=digest,unique_blocks=len(memo),blocks=blocks)
    (OUT / "manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
    # Independently decode and validate every exported range and exact byte count.
    for b in blocks:
        raw=zlib.decompress(blob[b["offset"]:b["offset"]+b["length"]])
        assert len(raw)==b["raw_length"]
        assert hashlib.sha256(raw).hexdigest()==b["sha256"]
        if b["alpha"]:
            n = b["width"] * b["height"]
            mask = np.frombuffer(raw, dtype=np.uint8, offset=n*2).reshape((b["height"], b["width"]))
            assert not (mask[0].any() or mask[-1].any() or mask[:,0].any() or mask[:,-1].any()), b["name"]
            assert mask.max() == 255, b["name"]
    # Full RGB565 edge colors and alpha8 retain the approved illustration's
    # antialiasing. The Pro's existing 0x7e0000 app slot permits this6MiB art cap;
    # the final linked firmware must still be checked against that partition.
    assert len(blob)<6*1024*1024, f"Pack exceeds6MiB: {len(blob)}"
    print(json.dumps({"bytes":len(blob),"sha256":digest,"blocks":len(blocks),"unique_blocks":len(memo),"output":str(OUT)}))


if __name__ == "__main__":
    main()

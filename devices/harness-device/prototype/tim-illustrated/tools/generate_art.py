#!/usr/bin/env python3
"""The approved Pro Octo, rasterized at the round dial's two native sizes."""
from pathlib import Path
import hashlib
import importlib.util
import json
import zlib
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]
shared=ROOT.parent/'pro-companion/tools/generate_art.py'
spec=importlib.util.spec_from_file_location('octo_art',shared)
art=importlib.util.module_from_spec(spec);spec.loader.exec_module(art)
OUT=ROOT/'generated';OUT.mkdir(parents=True,exist_ok=True)
SIZES=(240,108)
blob=bytearray();blocks=[];memo={}
def asset(name,image,duration=100):
    # Pack in the round panel's wire order: opaque spans are direct memcpy.
    raw=bytearray(art.encode(image,True));n=image.width*image.height*2
    raw[:n:2],raw[1:n:2]=raw[1:n:2],raw[:n:2]
    key=hashlib.sha256(raw).hexdigest()
    if key not in memo:
        packed=zlib.compress(raw,9);memo[key]=(len(blob),len(packed));blob.extend(packed)
    offset,length=memo[key]
    b=dict(name=name,offset=offset,length=length,raw_length=len(raw),width=image.width,
           height=image.height,duration_ms=duration,sha256=key)
    blocks.append(b);return b
def resized(image,size):
    im=image.resize((size,size),Image.Resampling.LANCZOS)
    alpha=im.getchannel('A');ImageDraw.Draw(alpha).rectangle((0,0,size-1,size-1),outline=0)
    im.putalpha(alpha);return im
movies={m:[art.render_octopus(m,f) for f in range(24)] for m in art.MOODS}
movies['listening'][20:]=movies['listening'][:4]
rows=[];touch=[];letters=[]
for size in SIZES:
    rows.append([[asset(f'{size}_{m}_{f}',resized(im,size),d) for f,im in enumerate(movies[m])]
                 for m,d in zip(art.MOODS,art.DURATIONS)])
    touch.append([asset(f'{size}_touch_{g}',resized(art.render_octopus('booped',0,g),size)) for g in range(-2,3)])
    letters.append([asset(f'{size}_letter_{v}',art.letter(v,round(64*size/350)),160) for v in range(3)])
def init(b):
    return '{'+','.join(str(b[k]) for k in ('offset','length','raw_length','width','height','duration_ms'))+'}'
h=['/* Generated: zlib(panel-order RGB565 + alpha8). */','#pragma once','#include <stdint.h>',
   'typedef struct { uint32_t offset,length,raw_length; uint16_t width,height,duration_ms; } tim_art_frame_t;',
   'enum { TIM_ART_FRAMES=24, TIM_ART_HERO=240, TIM_ART_SMALL=108 };',
   'static const uint16_t tim_art_duration[8] = {'+','.join(map(str,art.DURATIONS))+'};',
   'static const tim_art_frame_t tim_art_frames[2][8][24] = {']
for moods in rows:
    h.append('{');h.extend('{'+','.join(map(init,row))+'},' for row in moods);h.append('},')
h.append('};')
for name,table in [('tim_art_touch',touch),('tim_art_letter',letters)]:
    h.append(f'static const tim_art_frame_t {name}[2][{len(table[0])}] = {{')
    h.extend('{'+','.join(map(init,row))+'},' for row in table);h.append('};')
h.append('static const int16_t tim_art_letter_anchor[2][2] = {{193,151},{87,68}};')
(OUT/'tim_art.h').write_text('\n'.join(h)+'\n');(OUT/'tim_art.pack').write_bytes(blob)
manifest=dict(format='zlib(RGB565BE plane + alpha8 plane)',sizes=SIZES,moods=art.MOODS,frames=24,
              source_sha256=hashlib.sha256(shared.read_bytes()).hexdigest(),bytes=len(blob),
              sha256=hashlib.sha256(blob).hexdigest(),blocks=blocks,unique_blocks=len(memo))
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
for b in blocks:
    raw=zlib.decompress(blob[b['offset']:b['offset']+b['length']])
    assert len(raw)==b['raw_length'] and hashlib.sha256(raw).hexdigest()==b['sha256']
assert len(blob)<4*1024*1024
print(json.dumps({k:v for k,v in manifest.items() if k!='blocks'}))

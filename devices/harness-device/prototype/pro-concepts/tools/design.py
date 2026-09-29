"""Eight authored 720px review faces. Baked typography; native Tim/Tux artwork.

Every frame is exportable as PNG. Only the changing rectangle is sent to the LCD.
Compressed RGB565 frames are independently decoded and compared below.
"""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont,ImageChops
import math,struct,json,hashlib,zlib

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'generated'
OUT.mkdir(exist_ok=True)
S=2
FONTS={}
def font(size,weight='regular'):
    key=(size,weight)
    if key not in FONTS:
        if weight=='mono': p='/System/Library/Fonts/Menlo.ttc'; index=0
        elif weight=='serif': p='/System/Library/Fonts/Supplemental/Georgia.ttf'; index=0
        else: p='/System/Library/Fonts/Avenir Next.ttc'; index={'regular':7,'medium':5,'demi':2,'bold':0}[weight]
        FONTS[key]=ImageFont.truetype(p,int(size*S),index=index)
    return FONTS[key]

def new(bg): return Image.new('RGB',(720*S,720*S),bg)
def box(im,xy,fill,r=0,outline=None,width=1):
    d=ImageDraw.Draw(im); b=tuple(int(v*S) for v in xy)
    if r:d.rounded_rectangle(b,r*S,fill,outline,width*S)
    else:d.rectangle(b,fill,outline,width*S)
def oval(im,xy,fill=None,outline=None,width=1):
    ImageDraw.Draw(im).ellipse(tuple(int(v*S) for v in xy),fill,outline,width*S)
def line(im,xy,fill,width=1): ImageDraw.Draw(im).line([tuple(int(v*S) for v in p) for p in xy],fill,width*S)
def text(im,xy,s,size=28,color='#182c2b',weight='regular',anchor='lt',spacing=None):
    d=ImageDraw.Draw(im)
    for n,t in enumerate(s.split('\n')):
        d.text((xy[0]*S,(xy[1]+n*(spacing or size*1.16))*S),t,font=font(size,weight),fill=color,anchor=anchor)
def tracked(im,xy,s,size=17,color='#778581',space=3):
    x=xy[0]
    for ch in s:
        text(im,(x,xy[1]),ch,size,color,'demi')
        x+=ImageDraw.Draw(im).textlength(ch,font=font(size,'demi'))/S+space
def header(im,mode,dark=False,color=None):
    fg=color or ('#e7ede8' if dark else '#273d37')
    tracked(im,(44,39),'harness',20,fg,2.2)
    # Connection/pocket marks are part of the mode label, never a tappable control.
    x=512
    if mode=='DOCKED':
        line(im,[(x,43),(x,59),(x+26,59),(x+26,43)],fg,2)
        line(im,[(x+7,43),(x+7,37),(x+19,37),(x+19,43)],fg,2)
    else:
        box(im,(x+3,36,x+22,61),None,5,fg,2)
        line(im,[(x+9,56),(x+16,56)],fg,2)
    text(im,(550,40),mode,17,fg,'demi')
def footer(im,num,title,dark=False):
    fg='#bac7c4' if dark else '#6a7770'
    line(im,[(44,646),(676,646)],'#2c3b39' if dark else '#d2d9cf')
    text(im,(44,669),f'{num:02d} / 11',18,fg,'mono')
    text(im,(158,668),title,21,fg,'medium')
    text(im,(643,670),'swipe',19,fg,'regular','rt')
    line(im,[(655,679),(675,679)],fg,1)
    line(im,[(668,673),(675,679),(668,685)],fg,1)

SPR={}
def sprite(im,kind,frame,cx,y,width,tint=None):
    key=(kind,frame%24,tint)
    if key not in SPR:
        a=Image.open(OUT/f'sprites/{kind}-{frame%24:02d}.ppm').convert('RGB')
        # Same fixed square for all frames, so no pulsing scale or shifting registration.
        a=a.crop((135,0,585,450))
        if kind=='tim':
            alpha=a.getchannel('B')
            col=Image.new('RGBA',a.size,tint or '#b8a7ff');col.putalpha(alpha);a=col
        else:
            alpha=a.convert('L').point(lambda v:255 if v else 0)
            a=a.convert('RGBA');a.putalpha(alpha)
        SPR[key]=a
    a=SPR[key].resize((int(width*S),int(width*S)),Image.Resampling.NEAREST)
    im.paste(a,(int((cx-width/2)*S),int(y*S)),a)

def illustrated_octo(im,f):
    """An authored, solid illustration to compare against the ASCII portraits."""
    phase=f*math.tau/24
    bob=3*math.sin(phase)
    oval(im,(213,441,431,466),'#729667')
    # Arms follow cubic curves; rounded strokes retain their soft silhouette.
    for i,end_x in enumerate([192,225,262,303,344,384,424,465]):
        start=(293+i*8,336+bob)
        end=(end_x,414+18*math.sin(i*1.8)+5*math.sin(phase+i))
        c1=(start[0]+(end_x-320)*.2,410+bob)
        c2=(end_x-18*math.cos(i),end[1]+34)
        pts=[]
        for step in range(41):
            t=step/40;u=1-t
            pts.append((u**3*start[0]+3*u*u*t*c1[0]+3*u*t*t*c2[0]+t**3*end[0],u**3*start[1]+3*u*u*t*c1[1]+3*u*t*t*c2[1]+t**3*end[1]))
        line(im,pts,'#78558e' if i%2 else '#624778',24)
        x,y=end;oval(im,(x-12,y-12,x+12,y+12),'#78558e' if i%2 else '#624778')
        line(im,[(x,y+5) for x,y in pts[20:]],'#b592b4',6)
    oval(im,(207,173+bob,437,383+bob),'#9974af')
    oval(im,(218,179+bob,415,363+bob),'#a381bc')
    oval(im,(248,200+bob,353,247+bob),'#b296c6')
    for x in [277,367]:
        if f in [18,19]:line(im,[(x-15,292+bob),(x+14,292+bob)],'#352d49',7)
        else:
            oval(im,(x-22,262+bob,x+22,312+bob),'#f8f0df')
            oval(im,(x-8,275+bob,x+12,301+bob),'#302d45')
            oval(im,(x+1,278+bob,x+7,284+bob),'#ffffff')
    oval(im,(242,312+bob,263,323+bob),'#c893b0')
    oval(im,(381,312+bob,402,323+bob),'#c893b0')
    ImageDraw.Draw(im).arc((303*S,(304+bob)*S,343*S,(334+bob)*S),10,170,'#50334f',4*S)

def companion(f):
    im=new('#102a28');header(im,'DOCKED',True)
    text(im,(360,119),'A little company.\nA lot of possibility.',48,'#e6eee1','medium','mt',57)
    oval(im,(194,492,526,529),'#183b36')
    sprite(im,'tim',f,360,224,358,'#a8d4a3')
    oval(im,(239,582,249,592),'#cbe79a')
    text(im,(268,577),'Right here with you',25,'#d7e6cb','regular')
    footer(im,1,'Companion',True);return im

def focus(f):
    im=new('#f4f1e7');header(im,'DOCKED')
    tracked(im,(44,123),'WEBSITE / DESIGN',17,'#778075',2)
    text(im,(42,179),'A calmer\nhome screen.',76,'#18392f','demi',spacing=86)
    text(im,(45,390),'Finding the shape of your next idea.',27,'#607065')
    box(im,(44,462,676,468),'#d7ded0',3)
    box(im,(44,462,412,468),'#426b46',3)
    dot=58+int((f/23)*326)
    oval(im,(dot-4,458,dot+8,471),'#9cc686')
    text(im,(44,507),'Refining the layout',32,'#18392f','demi')
    text(im,(44,553),'Working on your Mac',25,'#607065')
    sprite(im,'tim',0,605,508,100,'#6c8063')
    footer(im,2,'Focus');return im

def swarm(f):
    im=new('#131c29');header(im,'DOCKED',True)
    text(im,(44,119),'One desk.\nThree minds.',54,'#edf0e9','demi',spacing=63)
    text(im,(674,174),'03',64,'#597084','regular','rt')
    rows=[('Design','Sketching six directions','#b6cafa','tim'),('Code','Checking the last details','#d0c4fb','tux'),('Research','Ready for your review','#cddfa8','tim')]
    for i,(name,sub,col,ch) in enumerate(rows):
        y=274+i*110
        box(im,(44,y,676,y+98),'#202e3d',19)
        sprite(im,ch,f if i==0 else 2,91,y+7,78,col)
        text(im,(149,y+17),name,29,col,'demi')
        text(im,(149,y+57),sub,22,'#c8d2d6')
        for j in range(3):oval(im,(611+j*13,y+26,617+j*13,y+32),col if i<2 and (f//3)%3==j else '#4c5b66')
    footer(im,3,'Swarm',True);return im

def dispatch(f):
    im=new('#e6dfef');header(im,'DOCKED',color='#584367')
    box(im,(44,119,676,598),'#fdfbf6',26)
    # Paper edge and cancellation lines give the result an object-like presence.
    box(im,(538,146,645,254),'#e3edf0',8)
    sprite(im,'tux',f,591,158,91)
    for y in [174,186,198]:line(im,[(478,y),(547,y)],'#bcb1c6',1)
    text(im,(78,169),'A little\nprogress.',65,'#473c58','demi',spacing=74)
    line(im,[(79,349),(641,349)],'#ded9e4')
    text(im,(79,383),'The new layouts are ready.\nEverything is saved\non your Mac.',31,'#554d60',spacing=41)
    tracked(im,(79,555),'DESIGN  ·  JUST NOW',16,'#83728d',1.5)
    footer(im,4,'Dispatch');return im

def brief(f):
    im=new('#f5f1e7');header(im,'ON THE GO')
    text(im,(43,122),'While you\nwere away.',63,'#263b34','serif',spacing=76)
    items=[('Your layouts are ready.','Six directions to review on your Mac.'),('The last check passed.','A quieter afternoon, already.'),('One idea worth keeping.','Bring the creature into the story.')]
    for i,(a,b) in enumerate(items):
        y=309+i*107
        text(im,(44,y+3),f'0{i+1}',20,'#819083','mono')
        text(im,(100,y),a,29,'#263b34','demi')
        text(im,(100,y+42),b,23,'#6c786d')
        if i<2:line(im,[(100,y+81),(676,y+81)],'#d9ddcf')
    footer(im,5,'Pocket brief');return im

def field(f):
    im=new('#d9e8cf');header(im,'ON THE GO',color='#365343')
    oval(im,(489,102,629,242),'#fbebad')
    # Authored landscape, with the ASCII companion as the foreground character.
    d=ImageDraw.Draw(im)
    d.polygon([(0,341*S),(122*S,299*S),(300*S,357*S),(528*S,273*S),(720*S,332*S),(720*S,646*S),(0,646*S)],fill='#a8bf92')
    d.polygon([(0,431*S),(182*S,376*S),(414*S,404*S),(591*S,355*S),(720*S,418*S),(720*S,646*S),(0,646*S)],fill='#6d966f')
    d.polygon([(0,518*S),(188*S,475*S),(455*S,481*S),(720*S,541*S),(720*S,646*S),(0,646*S)],fill='#2b5949')
    illustrated_octo(im,f)
    for x,y in [(54,439),(616,483),(657,457)]:
        line(im,[(x,y+20),(x+4,y),(x+9,y+20)],'#d2e0ad',2)
    text(im,(43,495),'Take a little\ncompany.',58,'#f1f0d8','medium',spacing=65)
    footer(im,6,'Field companion');return im

def thought(f):
    im=new('#282038');header(im,'ON THE GO',True,color='#e3dcef')
    text(im,(44,119),'Keep that\nthought.',65,'#f1eaf7','medium',spacing=77)
    text(im,(47,300),'Every good thing starts somewhere.',25,'#b6a8cc')
    sprite(im,'tim',f,566,190,144,'#bda4ed')
    # A voiced thought is represented by the creature's world; no microphone button.
    for j in range(43):
        x=53+j*14.6
        wave=math.sin(j*.27+f*math.tau/24)*.5+.5
        envelope=math.sin(j/42*math.pi)**1.5
        height=8+envelope*(22+64*wave)
        col='#c5a5ee' if j%3 else '#e6c9cc'
        box(im,(x,442-height/2,x+5,442+height/2),col,3)
    text(im,(360,551),'Go on. I’m listening.',31,'#f1eaf7','regular','mt')
    footer(im,7,'Thought catcher',True);return im

def quiet(f):
    im=new('#eff0e8');header(im,'ON THE GO')
    text(im,(360,136),'09:41',89,'#344e45','regular','mt')
    tracked(im,(272,254),'A SLOW MOMENT',16,'#78887a',2)
    sprite(im,'tim',0,360,312,107,'#7a856e')
    text(im,(360,473),'Here, when\nyou need me.',48,'#344e45','regular','mt',57)
    footer(im,8,'Quiet companion');return im

def screen_profile(which):
    profiles=[('Soft paper','#eee9dc','#364a3e','#fffaf0',55),
              ('Clear daylight','#f8f8f2','#182620','#ffffff',90),
              ('Night ink','#171c20','#eceee5','#283138',40)]
    title,bg,fg,card,level=profiles[which]
    def draw(f):
        im=new(bg)
        tracked(im,(44,39),'harness',20,fg,2.2)
        tracked(im,(469,42),'SCREEN STUDY',15,fg,1.7)
        text(im,(44,123),title,52,fg,'demi')
        text(im,(44,197),'Readable at a glance.',32,fg)
        box(im,(44,269,676,398),card,16)
        text(im,(67,293),'Your preview is ready.\nSix directions to review.',32,fg,'medium',spacing=44)
        sprite(im,'tim',0,155,429,125,'#a68acc' if which==2 else '#655580')
        for j in range(12):
            v=round(255*j/11)
            box(im,(283+j*31,447,312+j*31,497),(v,v,v))
        text(im,(282,516),'Shadows to highlights',22,fg)
        text(im,(44,586),f'Backlight {level}%  ·  Compare text + blacks',24,fg)
        footer(im,9+which,title,which==2)
        return im
    return draw

SCENES=[companion,focus,swarm,dispatch,brief,field,thought,quiet,*[screen_profile(i) for i in range(3)]]
NAMES=['Companion','Focus','Swarm','Dispatch','Pocket brief','Field companion','Thought catcher','Quiet companion','Soft paper','Clear daylight','Night ink']
LEVELS=[170,220,175,210,210,220,155,170,140,230,102]

def pack565(im):
    import numpy as np
    a=np.asarray(im.convert('RGB'),dtype=np.uint16)
    return (((a[:,:,0]>>3)<<11)|((a[:,:,1]>>2)<<5)|(a[:,:,2]>>3)).astype('<u2').tobytes()
def compress_frame(data):
    # Independently decodable zlib frames use the ESP32-P4 ROM's miniz decoder.
    out=zlib.compress(data,9)
    assert zlib.decompress(out)==data
    return out

blob=bytearray(); metas=[]; all_frames=[]
for i,draw in enumerate(SCENES):
    frames=[]
    for f in range(24 if i in (0,1,2,3,5,6) else 1):
        im=draw(f).resize((720,720),Image.Resampling.LANCZOS)
        frames.append(im)
    frames[0].save(OUT/f'{i+1:02d}-{NAMES[i].lower().replace(" ","-")}.png')
    frames[0].save(OUT/f'{i+1:02d}.png')
    off=len(blob);encoded=compress_frame(pack565(frames[0]));blob+=encoded
    # All animation frames replace one fixed rectangle. Text outside it never redraws.
    bounds=None
    for frame in frames[1:]:
        diff=ImageChops.difference(frames[0],frame).getbbox()
        if diff:
            bounds=diff if bounds is None else (min(bounds[0],diff[0]),min(bounds[1],diff[1]),max(bounds[2],diff[2]),max(bounds[3],diff[3]))
    anim=[]
    if bounds:
        bounds=(max(0,bounds[0]-2),max(0,bounds[1]-2),min(720,bounds[2]+2),min(646,bounds[3]+2))
        for f in frames:
            chunk=compress_frame(pack565(f.crop(bounds)));anim.append((len(blob),len(chunk)));blob+=chunk
    metas.append(dict(name=NAMES[i],mode='Docked' if i<4 else 'On the go' if i<8 else 'Screen study',brightness=LEVELS[i],base=(off,len(encoded)),rect=bounds,frames=anim))
    frames[0].save(OUT/f'{i+1:02d}.gif',save_all=True,append_images=frames[1:],duration=120,loop=0)
    all_frames.append(frames[0])
    print(NAMES[i], 'base',len(encoded),'animation',sum(n for _,n in anim),'rect',bounds)

(ROOT/'main/gallery.pack').write_bytes(blob)
hdr=['#pragma once','#include <stdint.h>','#define GALLERY_SCENES 11',
     'typedef struct { uint32_t off,len; } gallery_asset_t;',
     'typedef struct { const char *name; gallery_asset_t base; uint16_t x,y,w,h,frames,brightness; gallery_asset_t anim[24]; } gallery_scene_t;',
     'static const gallery_scene_t scenes[GALLERY_SCENES] = {']
for meta in metas:
    r=meta['rect'] or (0,0,0,0);x,y,x1,y1=r
    pairs=','.join('{%d,%d}'%p for p in meta['frames'])
    hdr.append('{"%s",{%d,%d},%d,%d,%d,%d,%d,%d,{%s}},'%(meta['name'],*meta['base'],x,y,x1-x,y1-y,len(meta['frames']),meta['brightness'],pairs))
hdr.append('};')
(ROOT/'main/gallery_assets.h').write_text('\n'.join(hdr)+'\n')
(OUT/'manifest.json').write_text(json.dumps(dict(size=len(blob),sha256=hashlib.sha256(blob).hexdigest(),scenes=metas),indent=2))
sheet=Image.new('RGB',(1488,1152),'#deded7')
for i,im in enumerate(all_frames):sheet.paste(im.resize((352,352),Image.Resampling.LANCZOS),(16+(i%4)*368,16+(i//4)*384))
sheet.save(OUT/'contact-sheet.png')
(OUT/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Harness Pro / Eight directions</title><style>body{background:#171d20;color:#eee;font:18px system-ui;margin:32px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:24px}img{width:100%;border-radius:20px}h1{font-size:26px}p{color:#a9b3b4}figure{margin:0}figcaption{padding:12px 0}</style><h1>Harness Pro / Eight directions</h1><p>01–04 Docked · 05–08 On the go · 09–11 Screen studies · Swipe on the device to compare. All content is illustrative.</p><main>'+''.join(f'<figure><img src="{i+1:02d}.gif"><figcaption>{i+1:02d} / {name}</figcaption></figure>' for i,name in enumerate(NAMES))+'</main>')
print('TOTAL',len(blob),'bytes')

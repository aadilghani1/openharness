// Pro typography and alpha images must be identical under full and partial repaint.
#include "pro_canvas.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static unsigned failures, comparisons;
#define CHECK(expr, message) do { if (!(expr)) { fprintf(stderr, "FAIL %s:%d: %s\n", __func__, __LINE__, message); failures++; } } while (0)
static uint16_t full[HT_WIDTH * HT_HEIGHT], incremental[HT_WIDTH * HT_HEIGHT];
static uint16_t scratch[HT_WIDTH * HT_HEIGHT];
static uint32_t rng = 0x97ccf391;
static unsigned random_(void) { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }

static uint16_t blend_reference(uint16_t fg, uint16_t bg, unsigned alpha)
{
    unsigned r = (((fg >> 11) & 31) * alpha + ((bg >> 11) & 31) * (255-alpha) + 127) / 255;
    unsigned g = (((fg >> 5) & 63) * alpha + ((bg >> 5) & 63) * (255-alpha) + 127) / 255;
    unsigned b = ((fg & 31) * alpha + (bg & 31) * (255-alpha) + 127) / 255;
    return (uint16_t)((r << 11) | (g << 5) | b);
}

/* Independent scalar oracle for the public primitive raster contract. Keep the
 * obvious per-pixel shape/alpha math here while production uses copy/span paths. */
static void raster_reference(const ht_run_t *r, ht_rect_t clip, uint16_t *out)
{
    int x0=clip.x>r->x?clip.x:r->x, x1=clip.x+clip.w<r->x+r->w?clip.x+clip.w:r->x+r->w;
    int y0=clip.y>r->y?clip.y:r->y, y1=clip.y+clip.h<r->y+r->pro_height?clip.y+clip.h:r->y+r->pro_height;
    if(x0>=x1||y0>=y1)return;
    if(r->pro_kind==2) {
        int rad=r->radius;
        for(int y=y0;y<y1;y++)for(int x=x0;x<x1;x++) {
            int dx=x-r->x,dy=y-r->y;
            if(dx>=r->w-rad)dx=r->w-1-dx;
            if(dy>=r->pro_height-rad)dy=r->pro_height-1-dy;
            if(dx<rad&&dy<rad&&(rad-1-dx)*(rad-1-dx)+(rad-1-dy)*(rad-1-dy)>rad*rad)continue;
            out[(y-clip.y)*clip.w+x-clip.x]=r->fg;
        }
    } else if(r->pro_kind==3) {
        for(int y=y0;y<y1;y++)for(int x=x0;x<x1;x++) {
            size_t index=(size_t)(y-r->y)*r->bitmap.width+x-r->x;
            unsigned alpha=r->bitmap.alpha?r->bitmap.alpha[index]:255;
            if(alpha) {
                uint16_t *dst=&out[(y-clip.y)*clip.w+x-clip.x];
                *dst=blend_reference(r->bitmap.pixels[index],*dst,alpha);
            }
        }
    } else if(r->pro_kind==1) {
        const ht_pro_font_t *f=r->pro_font;const char *p=r->text;int gx=r->x;
        while(*p&&gx<x1) {
            uint32_t cp=ht_utf8_next(&p);
            if(cp==0x2018||cp==0x2019)cp='\'';
            if(cp==0x201c||cp==0x201d)cp='"';
            if(cp>=0x2010&&cp<=0x2015)cp='-';
            int viet=ht_pro_vietnamese_index(cp);
            if(viet<0&&(cp<f->first||cp>f->last))cp='?';
            const ht_pro_glyph_t *g=&f->glyphs[viet>=0 ? f->last-f->first+1+viet : cp-f->first];
            int left=x0>gx?x0:gx,right=x1<gx+g->width?x1:gx+g->width;
            for(int y=y0;y<y1;y++)for(int x=left;x<right;x++) {
                size_t k=(size_t)(y-r->y)*g->width+x-gx;
                unsigned a=(f->alpha[g->offset+k/2]>>((1-(k%2))*4))&15;
                if(a){uint16_t *dst=&out[(y-clip.y)*clip.w+x-clip.x];*dst=blend_reference(r->fg,*dst,a*17);}
            }
            gx+=g->advance;
        }
    }
}

static void primitive_equivalence(void)
{
    uint16_t colors[83*71];uint8_t alpha[83*71];
    for(unsigned i=0;i<83*71;i++){colors[i]=(uint16_t)random_();alpha[i]=(uint8_t)random_();}
    for(unsigned i=0;i<256;i++)alpha[i]=(uint8_t)i; // every alpha value, arbitrary colors
    for(unsigned i=300;i<1000;i++)alpha[i]=0;
    for(unsigned i=1700;i<3100;i++)alpha[i]=255;
    const ht_pro_font_t *fonts[]={&ht_pro_24,&ht_pro_32,&ht_pro_42,&ht_pro_56};
    for(int n=0;n<1400;n++) {
        ht_scene_t s;ht_scene_clear(&s,0);
        int x=(int)(random_()%81)-40,y=(int)(random_()%81)-40;
        int w=1+random_()%310,h=1+random_()%260;
        if(n%3==0)ht_pro_rect(&s,x,y,w,h,(int)(random_()%180)-8,(uint16_t)random_());
        else if(n%3==1) {
            ht_pro_bitmap_t bm={.pixels=colors,.alpha=n%2?alpha:NULL,.width=83,.height=71,.revision=1};ht_pro_image(&s,x,y,&bm);
        } else ht_pro_text(&s,x,y,w,fonts[n%4],(uint16_t)random_(),"Clip Wfj~ pixels / unicode cafe");
        ht_rect_t clip={(int)(random_()%101)-50,(int)(random_()%101)-50,1+random_()%280,1+random_()%210};
        size_t count=(size_t)clip.w*clip.h;
        for(size_t i=0;i<count;i++)full[i]=scratch[i]=(uint16_t)random_();
        raster_reference(&s.runs[0],clip,full);ht_pro_raster(&s.runs[0],clip,scratch);
        CHECK(!memcmp(full,scratch,count*sizeof *full),"optimized primitive must exactly match scalar oracle");
    }
    puts("Checked1,400 random clipped shape/image/font primitives against independent scalar pixel oracle");
}

static void exhaustive_blend(void)
{
    uint16_t *colors=malloc(64*256*sizeof *colors);uint8_t *alpha=malloc(64*256);
    assert(colors&&alpha);
    for(unsigned fg=0;fg<64;fg++)for(unsigned a=0;a<256;a++) {
        unsigned k=fg*256+a;
        // All6bit green pairs, and every5bit red/blue pair appear in this matrix.
        colors[k]=(uint16_t)(((fg>>1)<<11)|(fg<<5)|(fg>>1));alpha[k]=(uint8_t)a;
    }
    ht_pro_bitmap_t bitmap={.pixels=colors,.alpha=alpha,.width=256,.height=64,.revision=1};ht_scene_t scene;ht_scene_clear(&scene,0);
    ht_pro_image(&scene,0,0,&bitmap);
    for(unsigned bg=0;bg<64;bg++) {
        uint16_t background=(uint16_t)(((bg>>1)<<11)|(bg<<5)|(bg>>1));
        for(unsigned k=0;k<64*256;k++)scratch[k]=background;
        ht_pro_raster(&scene.runs[0],(ht_rect_t){0,0,256,64},scratch);
        for(unsigned k=0;k<64*256;k++) CHECK(scratch[k]==blend_reference(colors[k],background,alpha[k]),"shift/add rounded RGB565 blend must match /255 for every channel pair and alpha");
    }
    free(colors);free(alpha);
    puts("Checked1,048,576 complete RGB565 channel-pair/alpha combinations against rounded division oracle");
}

static void transition(const ht_scene_t *before, const ht_scene_t *after)
{
    ht_damage_t d;
    ht_damage(before, after, &d);
    uint32_t pixels = 0;
    for (int i=0; i<d.count; i++) {
        ht_rect_t r = d.rect[i];
        assert(r.x>=0 && r.y>=0 && r.w>0 && r.h>0 && r.x+r.w<=HT_WIDTH && r.y+r.h<=HT_HEIGHT);
        assert(!((r.x|r.y|r.w|r.h)&1));
        pixels += (uint32_t)r.w*r.h;
        ht_raster(after,r,scratch);
        for(int y=0;y<r.h;y++) memcpy(incremental+(r.y+y)*HT_WIDTH+r.x,scratch+y*r.w,(size_t)r.w*2);
    }
    CHECK(pixels==d.pixels,"damage pixel accounting");
    ht_raster(after,(ht_rect_t){0,0,HT_WIDTH,HT_HEIGHT},full);
    if(memcmp(incremental,full,sizeof full)) {
        for(size_t i=0;i<sizeof full/sizeof *full;i++) if(incremental[i]!=full[i]) {
            fprintf(stderr,"first mismatch at %zu,%zu: %04x != %04x (%u rects)\n",i%HT_WIDTH,i/HT_WIDTH,incremental[i],full[i],d.count);
            break;
        }
        CHECK(false,"partial repaint differs from fresh complete scene");
    }
    comparisons++;
}

static void typography(void)
{
    const ht_pro_font_t *fonts[] = {&ht_pro_24,&ht_pro_32,&ht_pro_42,&ht_pro_56};
    const char *samples[] = {"Tiếng Việt", "Ngôn ngữ và giọng nói", "ĐĂĨŨƠƯ ự Ỹ Ắ", "Working", "A little company.", "Caf\xc3\xa9", "Don\xe2\x80\x99t stop", "1\xe2\x85\x93 + \xe2\x85\x94", "Hello\xe2\x80\xa6", "\xf0\x9f\x90\x99"};
    for(unsigned f=0;f<sizeof fonts/sizeof *fonts;f++) {
        const ht_pro_font_t *font=fonts[f];
        CHECK(ht_pro_width(font,"WWW")>ht_pro_width(font,"iii"),"font must remain proportional");
        for(unsigned i=0;i<sizeof samples/sizeof *samples;i++) {
            char visible[512]; ht_display_text(visible,sizeof visible,samples[i],&ht_mono_28);
            int width=ht_pro_width(font,visible);
            CHECK(ht_pro_width(font,samples[i])==width,"measurement must match displayed Unicode normalization");
            ht_scene_t s;ht_scene_clear(&s,0);
            CHECK(ht_pro_text(&s,0,0,width,font,0xffff,samples[i]),"exact-fit text accepted");
            CHECK(!strcmp(s.runs[0].text,visible),"exact-fit final glyph and Unicode expansion preserved");
            ht_scene_clear(&s,0);ht_pro_center(&s,0,font,0xffff,samples[i]);
            if(width<=HT_WIDTH-80) CHECK(!strcmp(s.runs[0].text,visible),"centered normalized text must not be clipped");
        }
        char vietnamese[128];
        ht_display_text(vietnamese,sizeof vietnamese,"Tiếng Việt: ĐĂĨŨƠƯ ự Ỹ Ắ",&ht_mono_28);
        CHECK(!strcmp(vietnamese,"Tiếng Việt: ĐĂĨŨƠƯ ự Ỹ Ắ"),"Vietnamese accents survive normalization");
        for(unsigned cp=256;cp<=0x1ef9;cp++) {
            int index=ht_pro_vietnamese_index(cp);if(index<0)continue;
            const ht_pro_glyph_t *g=&font->glyphs[font->last-font->first+1+index];
            unsigned ink=0;for(unsigned byte=0;byte<((unsigned)g->width*font->height+1)/2;byte++)ink+=font->alpha[g->offset+byte];
            CHECK(g->width&&g->advance&&ink,"every Vietnamese atlas glyph has ink");
        }
        ht_scene_t s;ht_scene_clear(&s,0);
        const char *cut="HelloX";
        int width=ht_pro_width(font,cut)-1;
        ht_pro_text(&s,0,0,width,font,0xffff,cut);
        CHECK(strstr(s.runs[0].text,"...")!=NULL,"rejecting the final glyph must still show ellipsis");
        CHECK(ht_pro_width(font,s.runs[0].text)<=width,"ellipsis must fit available width");
        char longword[129];memset(longword,'i',128);longword[128]=0;
        ht_scene_clear(&s,0);ht_pro_text(&s,0,0,30000,font,0xffff,longword);
        CHECK(strlen(s.runs[0].text)<HT_TEXT_BYTES,"stored text remains bounded");
        CHECK(strstr(s.runs[0].text,"...")!=NULL,"byte-limit truncation must show ellipsis");
        ht_scene_clear(&s,0);ht_pro_text(&s,0,0,1,font,0xffff,"W");
        CHECK(!s.runs[0].text[0],"glyph too wide for one pixel is omitted safely");
    }
    puts("Checked proportional metrics, normalized UTF-8, exact fits, final-glyph and byte-budget ellipsis");
}

static size_t strip_spaces(char *out, const char *text)
{
    size_t n=0;
    for(;*text;text++) if(*text!=' ' && *text!='\n' && *text!='\t') out[n++]=*text;
    out[n]=0;return n;
}

static void wrap_progress(void)
{
    const char *text="First line\nSecond line\n\nCaf\xc3\xa9 d\xc3\xa9j\xc3\xa0 vu. A_very_long_token_0123456789_and_more. 1\xe2\x85\x93 + \xe2\x85\x94. \xf0\x9f\x90\x99 End.";
    char visible[4096],expected[4096];
    ht_display_text(visible,sizeof visible,text,&ht_mono_28);strip_spaces(expected,visible);
    for(int width=60;width<=360;width+=37) {
        int rows=ht_pro_text_rows(text,&ht_pro_24,width);
        CHECK(rows>0 && rows<HT_RUNS,"bounded UTF-8 wrapping terminates");
        ht_scene_t s;ht_scene_clear(&s,0);
        int drawn=ht_pro_wrap(&s,0,0,width,HT_RUNS,0,&ht_pro_24,0xffff,text);
        CHECK(drawn==rows && s.count==rows,"row count and wrapped run count agree");
        char joined[4096]={0};size_t used=0;
        for(int i=0;i<s.count;i++) used+=strip_spaces(joined+used,s.runs[i].text);
        CHECK(!strcmp(joined,expected),"wrapping must retain every normalized non-space glyph");
        for(int skip=0;skip<rows;skip++) {
            ht_scene_t page;ht_scene_clear(&page,0);
            CHECK(ht_pro_wrap(&page,0,0,width,1,skip,&ht_pro_24,0xffff,text)==1,"each requested row exists");
            CHECK(!strcmp(page.runs[0].text,s.runs[skip].text),"skip rows must be stable");
        }
    }
    CHECK(ht_pro_text_rows("   WWW",&ht_pro_24,1)==3,"leading spaces plus subglyph width must make one-glyph progress");
    CHECK(ht_pro_text_rows("\n\nX",&ht_pro_24,100)==3,"explicit blank rows remain present");
    CHECK(ht_pro_text_rows("",&ht_pro_24,100)==0,"empty content has no rows");
    CHECK(ht_pro_text_rows("word",&ht_pro_24,0)==0,"zero-width row count is safe");
    puts("Checked word/Unicode wrap, explicit newlines, skipped rows and narrow-width progress");
}

static size_t utf8(unsigned cp,char out[5])
{
    if(cp<128){out[0]=(char)cp;out[1]=0;return 1;}
    if(cp<2048){out[0]=(char)(0xc0|(cp>>6));out[1]=(char)(0x80|(cp&63));out[2]=0;return 2;}
    out[0]=(char)(0xe0|(cp>>12));out[1]=(char)(0x80|((cp>>6)&63));out[2]=(char)(0x80|(cp&63));out[3]=0;return 3;
}

static void font_atlas_and_clips(void)
{
    const ht_pro_font_t *fonts[]={&ht_pro_24,&ht_pro_32,&ht_pro_42,&ht_pro_56};
    for(unsigned n=0;n<4;n++) {
        const ht_pro_font_t *f=fonts[n];
        unsigned overhang=0;
        for(unsigned cp=f->first;cp<=0x1ef9;cp++) {
            int viet=ht_pro_vietnamese_index(cp);
            if(cp>f->last && viet<0)continue;
            const ht_pro_glyph_t *g=&f->glyphs[viet>=0 ? f->last-f->first+1+viet : cp-f->first];
            CHECK(g->advance && g->width && f->height,"atlas glyph dimensions nonzero");
            // Identical masks may share an offset. ASan checks the full span
            // as every glyph is rasterized below, including Vietnamese.
            ht_scene_t s;ht_scene_clear(&s,0);
            ht_pro_text(&s,0,0,100,f,0xffff,"A");
            utf8(cp,s.runs[0].text);s.runs[0].w=100;
            // This directly exercises every generated atlas glyph, including the last one.
            ht_raster(&s,(ht_rect_t){0,0,100,f->height},scratch);
            for(unsigned y=0;y<f->height;y++) for(unsigned x=0;x<g->width;x++) {
                size_t k=(size_t)y*g->width+x;
                unsigned alpha=(f->alpha[g->offset+k/2]>>((1-(k%2))*4))&15;
                CHECK(scratch[y*100+x]==blend_reference(0xffff,0,alpha*17),"font atlas raster preserves actual nibble mask");
                if(x>=g->advance && alpha && cp>=32 && cp<127) overhang++;
            }
            const ht_rect_t clips[]={{-8,-5,29,17},{3,2,7,11},{65,5,30,13}};
            for(unsigned c=0;c<sizeof clips/sizeof *clips;c++) {
                ht_rect_t clip=clips[c];size_t pixels=(size_t)clip.w*clip.h;
                uint16_t *guard=malloc((pixels+32)*sizeof *guard);assert(guard);
                for(size_t i=0;i<pixels+32;i++)guard[i]=0xabcd;
                ht_raster(&s,clip,guard+16);
                for(int i=0;i<16;i++) CHECK(guard[i]==0xabcd && guard[16+pixels+i]==0xabcd,"clipped font raster writes within requested buffer");
                free(guard);
            }
        }
        if(overhang) fprintf(stderr,"NOTE font%u has %u opaque nibble pixels past glyph advance; checking rightmost glyph bounds\n",f->height,overhang);
        // A wide allocation must not clip actual trailing-glyph ink at its advance.
        const char *tails="fjJTy~";
        for(const char *p=tails;*p;p++) {
            char text[2]={*p,0};ht_scene_t s;ht_scene_clear(&s,0);
            ht_pro_text(&s,0,0,100,f,0xffff,text);
            ht_raster(&s,(ht_rect_t){0,0,100,f->height},scratch);
            const ht_pro_glyph_t *g=&f->glyphs[(unsigned char)*p-f->first];
            bool complete=true;
            for(unsigned y=0;y<f->height;y++) for(unsigned x=0;x<g->width;x++) {
                size_t k=(size_t)y*g->width+x;
                unsigned alpha=(f->alpha[g->offset+k/2]>>((1-(k%2))*4))&15;
                if(scratch[y*100+x]!=blend_reference(0xffff,0,alpha*17))complete=false;
            }
            CHECK(complete,"rightmost glyph ink must fit run bounds");
        }
    }
    puts("Checked all 1,304 real font glyphs, nibble bounds, trailing overhang and guarded clipped rasters");
}

static uint8_t *read_fixture(const char *path,size_t expected)
{
    FILE *f=fopen(path,"rb");assert(f);uint8_t *data=malloc(expected);assert(data);
    assert(fread(data,1,expected,f)==expected && fgetc(f)==EOF);fclose(f);return data;
}

static void shapes_and_alpha(const ht_pro_bitmap_t *landscape)
{
    uint16_t pixels[20];uint8_t alpha[20];
    const unsigned levels[]={0,1,127,254,255};
    for(int i=0;i<20;i++){pixels[i]=i%2?0xf800:0x001f;alpha[i]=(uint8_t)levels[i%5];}
    ht_pro_bitmap_t image={.pixels=pixels,.alpha=alpha,.width=5,.height=4,.revision=1};
    ht_scene_t s;ht_scene_clear(&s,0);ht_pro_image(&s,0,0,landscape);ht_pro_image(&s,233,333,&image);
    ht_raster(&s,(ht_rect_t){233,333,5,4},scratch);
    for(int y=0;y<4;y++)for(int x=0;x<5;x++) {
        size_t k=y*5+x;uint16_t bg=landscape->pixels[(333+y)*720+233+x];
        CHECK(scratch[k]==blend_reference(pixels[k],bg,alpha[k]),"straight alpha8 must composite over real landscape in native RGB565");
    }
    CHECK(scratch[0]==landscape->pixels[333*720+233],"fully transparent pixel preserves background");
    CHECK(scratch[4]==pixels[4],"fully opaque pixel preserves native panel color");
    ht_scene_clear(&s,0x1234);ht_pro_rect(&s,-7,-11,35,45,0,0xffff);
    const ht_rect_t clip={-20,-20,63,57};size_t count=(size_t)clip.w*clip.h;
    uint16_t *guard=malloc((count+32)*sizeof *guard);assert(guard);
    for(size_t i=0;i<count+32;i++)guard[i]=0xa11a;
    ht_raster(&s,clip,guard+16);
    for(int y=0;y<clip.h;y++)for(int x=0;x<clip.w;x++) {
        int sx=x+clip.x,sy=y+clip.y;
        CHECK(guard[16+y*clip.w+x]==(sx>=-7 && sx<28 && sy>=-11 && sy<34?0xffff:0x1234),"negative rectangle clipping preserves geometry");
    }
    for(int i=0;i<16;i++)CHECK(guard[i]==0xa11a && guard[16+count+i]==0xa11a,"negative clipping respects output guard");
    free(guard);
    ht_scene_clear(&s,0);
    CHECK(!ht_pro_rect(&s,0,0,0,20,3,1) && !ht_pro_rect(&s,0,0,20,-1,3,1),"empty and negative rectangles rejected");
    ht_pro_rect(&s,0,0,40,40,20,0xffff);
    ht_raster(&s,(ht_rect_t){0,0,40,40},scratch);
    CHECK(scratch[0]==0 && scratch[20*40+20]==0xffff,"rounded rectangle clear corners and solid center");
    puts("Checked real-landscape RGB565 alpha endpoints/intermediate levels, rounded shapes and negative clips");
}

static void animated_damage(const ht_pro_bitmap_t *landscape,uint8_t *hero0,const uint8_t *hero1,const uint8_t *compact)
{
    ht_pro_bitmap_t hero={.pixels=(uint16_t*)hero0,.alpha=hero0+350*350*2,.width=350,.height=350,.revision=1};
    ht_scene_t a,b;ht_scene_clear(&a,0x4321);ht_pro_image(&a,0,0,landscape);
    ht_pro_image(&a,180,140,&hero);ht_pro_text(&a,44,540,600,&ht_pro_42,0xffff,"A little company.");
    transition(NULL,&a);
    memcpy(hero0,hero1,350*350*3);hero.revision++;
    ht_scene_clear(&b,a.background);ht_pro_image(&b,0,0,landscape);ht_pro_image(&b,180,140,&hero);
    ht_pro_text(&b,44,540,600,&ht_pro_42,0xffff,"A little company.");
    ht_damage_t d;ht_damage(&a,&b,&d);
    CHECK(d.count && d.pixels<720u*720u/2,"same-pointer bitmap revision damages portrait only");
    transition(&a,&b);a=b;
    ht_damage(&a,&b,&d);CHECK(!d.count,"unchanged scene needs no repaint");
    ht_pro_bitmap_t small={.pixels=(const uint16_t*)compact,.alpha=compact+160*160*2,.width=160,.height=160,.revision=3};
    for(int i=0;i<48;i++) {
        ht_scene_clear(&b,a.background);ht_pro_image(&b,0,0,landscape);
        int x=(int)(random_()%750)-30,y=(int)(random_()%690)-20;
        if(i%7) ht_pro_image(&b,x,y,i%3?&small:&hero);
        ht_pro_rect(&b,43+i,470,634-i,125,i%24,ht_rgb(i%2?0xf4f2e8:0x2b5949));
        ht_pro_text(&b,55,490,550,&ht_pro_32,ht_rgb(i%2?0x2b5949:0xf4f2e8),i%2?"Ready to review on your Mac.":"A shorter result.");
        if(i%5) ht_pro_text(&b,55,610,400,&ht_pro_24,0xffff,i%2?"Design / Working":"Research / Ready");
        transition(&a,&b);a=b;
    }
    ht_scene_clear(&b,a.background);ht_pro_image(&b,0,0,landscape);transition(&a,&b);
    printf("Checked %u real-asset full/partial scene transitions, image revision/size/movement/removal, shapes and variable text\n",comparisons);
}

static uint64_t raster_hash(const uint16_t *pixels,size_t count)
{
    uint64_t value=UINT64_C(1469598103934665603);
    for(size_t i=0;i<count;i++){value^=pixels[i];value*=UINT64_C(1099511628211);}
    return value;
}
static void benchmark(const ht_pro_bitmap_t *landscape,const uint8_t *hero_pixels,const uint8_t *compact_pixels)
{
    ht_pro_bitmap_t hero={.pixels=(const uint16_t*)hero_pixels,.alpha=hero_pixels+350*350*2,.width=350,.height=350,.revision=1};
    ht_pro_bitmap_t compact={.pixels=(const uint16_t*)compact_pixels,.alpha=compact_pixels+160*160*2,.width=160,.height=160,.revision=1};
    static ht_scene_t scenes[5];
    const char *names[]={"landscape720","companion720","portrait350","summary720","reading720"};
    ht_rect_t clips[]={{0,0,720,720},{0,0,720,720},{185,132,350,350},{0,0,720,720},{0,0,720,720}};
    for(int i=0;i<5;i++)ht_scene_clear(&scenes[i],ht_rgb(0xf4f2e8));
    ht_pro_image(&scenes[0],0,0,landscape);
    ht_scene_t *home=&scenes[1];ht_pro_image(home,0,0,landscape);
    ht_pro_text(home,44,29,260,&ht_pro_24,ht_rgb(0x365343),"harness");
    ht_pro_text(home,355,29,168,&ht_pro_24,ht_rgb(0x365343),"Docked");
    ht_pro_text(home,44,73,480,&ht_pro_24,ht_rgb(0x365343),"Your creative studio");
    ht_pro_rect(home,548,24,128,64,22,ht_rgb(0xe6e8dc));
    ht_pro_text(home,566,39,92,&ht_pro_24,ht_rgb(0x263b34),"Explore");
    ht_pro_image(home,185,132,&hero);
    ht_pro_wrap(home,44,476,632,2,0,&ht_pro_42,ht_rgb(0xf1f0d8),"Take a little\ncompany.");
    ht_pro_rect(home,0,596,720,124,0,ht_rgb(0x244d40));
    ht_pro_text(home,44,604,470,&ht_pro_32,ht_rgb(0xf1f0d8),"Design");
    ht_pro_text(home,44,656,490,&ht_pro_24,ht_rgb(0xd2e0cd),"Tap to talk. Swipe to move.");
    scenes[2]=*home;
    ht_scene_t *summary=&scenes[3];ht_pro_image(summary,0,0,landscape);
    ht_pro_image(summary,48,128,&compact);
    ht_pro_text(summary,238,158,432,&ht_pro_42,ht_rgb(0x365343),"A little progress.");
    ht_pro_text(summary,240,220,430,&ht_pro_24,ht_rgb(0x52674f),"Made together. Ready for you.");
    ht_pro_rect(summary,40,310,640,266,26,ht_rgb(0xfbf9ef));
    ht_pro_wrap(summary,64,329,592,5,0,&ht_pro_32,ht_rgb(0x263b34),"Your new layouts are ready. Six directions, saved on your Mac. Take a look when you're ready.");
    ht_pro_rect(summary,0,596,720,124,0,ht_rgb(0x244d40));
    ht_pro_text(summary,44,604,470,&ht_pro_32,ht_rgb(0xf1f0d8),"Design");
    ht_pro_text(summary,44,656,490,&ht_pro_24,ht_rgb(0xd2e0cd),"Ready for you");
    ht_scene_t *reader=&scenes[4];
    ht_pro_text(reader,150,39,538,&ht_pro_42,ht_rgb(0x263b34),"Latest result");
    ht_pro_text(reader,48,134,624,&ht_pro_24,ht_rgb(0x627466),"Design");
    ht_pro_wrap(reader,56,190,608,9,0,&ht_pro_32,ht_rgb(0x263b34),"Your new layouts are ready. Six directions, saved on your Mac.\n\nThe companion stays with you while you work. A tap starts voice, a horizontal swipe changes panes, and a vertical swipe scrolls the desktop.\n\nThe landscape gives Tim a place to live, with clear text whenever there is something to read.");
    for(int i=0;i<3;i++)ht_pro_rect(reader,32+i*248,606,i==1?224:160,68,22,ht_rgb(0xe6e8dc));
    ht_pro_text(reader,240,623,190,&ht_pro_24,ht_rgb(0x263b34),"Open on desktop");
    const unsigned repeats=300;
    volatile uint16_t witness=0;
    for(unsigned n=0;n<5;n++) {
        double times[5];ht_rect_t area=clips[n];
        for(unsigned batch=0;batch<5;batch++) {
            clock_t start=clock();
            for(unsigned repeat=0;repeat<repeats;repeat++) {
                // Production transfers at most24 scanlines in each raster call.
                for(int y=area.y;y<area.y+area.h;y+=24) {
                    int rows=area.y+area.h-y;if(rows>24)rows=24;
                    ht_raster(&scenes[n],(ht_rect_t){area.x,y,area.w,rows},scratch);
                    witness^=scratch[(repeat+batch)%(area.w*rows)];
                }
            }
            times[batch]=(double)(clock()-start)*1000000.0/CLOCKS_PER_SEC/repeats;
        }
        for(unsigned a=0;a<5;a++)for(unsigned b=a+1;b<5;b++)if(times[a]>times[b]){double t=times[a];times[a]=times[b];times[b]=t;}
        ht_raster(&scenes[n],area,full);
        printf("BENCH {\"scene\":\"%s\",\"median_us\":%.3f,\"min_us\":%.3f,\"max_us\":%.3f,\"hash\":\"%016llx\",\"repeats\":%u}\n",names[n],times[2],times[0],times[4],(unsigned long long)raster_hash(full,(size_t)area.w*area.h),repeats);
    }
    (void)witness;
}

int main(int argc,char **argv)
{
    assert(HT_WIDTH==720 && (argc==5||argc==6));
    uint8_t *bg=read_fixture(argv[1],720*720*2),*hero0=read_fixture(argv[2],350*350*3);
    uint8_t *hero1=read_fixture(argv[3],350*350*3),*compact=read_fixture(argv[4],160*160*3);
    ht_pro_bitmap_t landscape={.pixels=(uint16_t*)bg,.width=720,.height=720,.revision=1};
    if(argc==6) {
        assert(!strcmp(argv[5],"--benchmark"));benchmark(&landscape,hero0,compact);
        free(bg);free(hero0);free(hero1);free(compact);return 0;
    }
    typography();wrap_progress();font_atlas_and_clips();shapes_and_alpha(&landscape);
    primitive_equivalence();exhaustive_blend();animated_damage(&landscape,hero0,hero1,compact);
    free(bg);free(hero0);free(hero1);free(compact);
    if(failures){fprintf(stderr,"Pro canvas: %u checks failed\n",failures);return 1;}
    puts("Pro canvas ASan/UBSan: PASS");return 0;
}

# Renders assets/images/icon.png and assets/branding/icon_{ios,foreground}.png.
# Usage: python assets/branding/generate_icons.py <out_dir>  (needs Pillow), then
# copy icon.png to assets/images/, the others here, and run: dart run flutter_launcher_icons
# Keep the bar geometry in sync with AppMarkPainter (lib/ui/brand.dart).
import sys
from PIL import Image, ImageDraw
out = sys.argv[1]
INK=(0x14,0x16,0x1A,255); WHITE=(255,255,255,255); LIME=(0xD2,0xF3,0x5A,255)
SS=4; N=1024
def glyph(d, ox, oy, size):
    k = size/120
    def r(x,y,w,h,c,rad=5):
        d.rounded_rectangle([ox+x*k, oy+y*k, ox+(x+w)*k-1, oy+(y+h)*k-1], radius=rad*k, fill=c)
    r(28,26,18,68,WHITE); r(28,26,50,16,WHITE); r(28,78,50,16,WHITE); r(74,38,18,44,LIME,6)
def make(name, bg, glyph_frac, radius_frac):
    M=N*SS
    im=Image.new('RGBA',(M,M),(0,0,0,0)); d=ImageDraw.Draw(im)
    if bg=='rounded': d.rounded_rectangle([0,0,M-1,M-1], radius=M*radius_frac, fill=INK)
    elif bg=='full': d.rectangle([0,0,M,M], fill=INK)
    g=M*glyph_frac; glyph(d,(M-g)/2,(M-g)/2,g)
    im=im.resize((N,N),Image.LANCZOS)
    if bg=='full': im=im.convert('RGB')
    im.save(f'{out}/{name}', optimize=True)
# Logo.dc.html: 440 square, radius 96, glyph 300
make('icon.png','rounded',300/440,96/440)
make('icon_ios.png','full',300/440,0)
# adaptive: 108dp canvas, ~72dp visible; glyph keeps 300/440 of the visible area
make('icon_foreground.png',None,(72/108)*(300/440),0)

#!/usr/bin/env python3
"""Render LED mockups of the SomaFM screens on a simulated 52x16 panel.

The 3x5 font is an approximation of AWTRIX's `small` font, good enough to
judge layout, colour and density. Channel colours are read from
scripts/somafm_lib.be so the mockups follow the generated table.

Usage:  python3 tools/mockup.py [docs/mockups.png]
"""
import re, pathlib
import sys
from PIL import Image, ImageDraw
F={'A':"010101111101101",'B':"110101110101110",'C':"011100100100011",'D':"110101101101110",'E':"111100110100111",
'F':"111100110100100",'G':"011100101101011",'H':"101101111101101",'I':"111010010010111",'J':"001001001101010",
'K':"101101110101101",'L':"100100100100111",'M':"101111111101101",'N':"110101101101101",'O':"010101101101010",
'P':"110101110100100",'Q':"010101101111011",'R':"110101110101101",'S':"011100010001110",'T':"111010010010010",
'U':"101101101101011",'V':"101101101010010",'W':"101101111111101",'X':"101101010101101",'Y':"101101010010010",
'Z':"111001010100111",'0':"011101101101110",'1':"010110010010010",'2':"110001010100111",'3':"110001010001110",
'4':"101101111001001",'5':"111100110001110",'6':"011100111101111",'7':"111001010100100",'8':"111101111101111",
'9':"111101111001110",' ':"000000000000000",'-':"000000111000000",'.':"000000000000010",'·':"000000010000000",
'&':"010101010101011","'":"010010000000000",'(':"001010010010001",')':"100010010010100",'%':"101001010100101",
':':"000010000010000",'/':"001001010100100"}
W,H=52,16
AMBER=(255,168,48); TEAL=(32,184,192); WHITE=(235,235,235); GREY=(110,110,110); DIM=(32,32,32)
class Panel:
    def __init__(s): s.p=[[None]*W for _ in range(H)]
    def px(s,x,y,c):
        if 0<=x<W and 0<=y<H: s.p[y][x]=c
    def text(s,x,y,t,c):  # y = baseline (caps rows y-5..y-1)
        for ch in t.upper():
            g=F.get(ch,F[' '])
            for i,b in enumerate(g):
                if b=='1': s.px(x+i%3,y-5+i//3,c)
            x+=4
        return x
    def rect(s,x,y,w,h,c):
        for yy in range(y,y+h):
            for xx in range(x,x+w): s.px(xx,yy,c)
    def tw(s,t): return len(t)*4-1
def eq(P,x,ytop,h,levels,c):
    for i,l in enumerate(levels):
        for k in range(l): P.px(x+i*2,ytop+h-1-k,c)
def star(P,x,y,c):
    for dx,dy in [(2,0),(1,1),(2,1),(3,1),(0,2),(1,2),(2,2),(3,2),(4,2),(1,3),(2,3),(3,3),(1,4),(3,4)]: P.px(x+dx,y+dy,c)
def posbar(P,idx,n,favs,c):
    P.rect(0,15,W,1,DIM)
    if favs: P.px(int(favs*(W-3)/(n-1))+1,15,(0,0,0))
    x=int(idx*(W-3)/(n-1)); P.rect(x,15,3,1,c)

screens=[]
def S(title,P): screens.append((title,P))
LIB = pathlib.Path(__file__).resolve().parent.parent / "scripts" / "somafm_lib.be"
COL = {m[0]: int(m[1], 16) for m in re.findall(r'\["([a-z0-9]+)", "[^"]*", "[^"]*", 0x([0-9A-F]{6})\]', LIB.read_text())}
def rgb(cid, fallback=0xB4B4B4):
    v = COL.get(cid, fallback); return ((v >> 16) & 255, (v >> 8) & 255, v & 255)
GS=rgb("groovesalad"); SA=rgb("secretagent"); DZ=rgb("dronezone")

P=Panel(); P.rect(0,0,2,15,GS); P.text(4,6,"Groove Salad",WHITE); eq(P,4,8,5,[3,5,2],GS); P.text(10,14,"playing",AMBER); posbar(P,1,53,3,AMBER)
S("1  List - favourite, currently playing (channel colour bar + live EQ)",P)
P=Panel(); P.rect(0,0,2,15,DZ); P.text(4,6,"Drone Zone",WHITE); star(P,4,8,AMBER); P.text(10,14,"ambient",GREY); posbar(P,2,53,3,AMBER)
S("2  List - favourite (star), not playing",P)
P=Panel(); P.rect(0,0,2,15,SA); P.text(4,6,"Secret Agen",WHITE); P.text(4,14,"lounge",GREY); posbar(P,38,53,3,AMBER)
S("3  List - regular channel (long name scrolls; clipped here)",P)
P=Panel(); P.rect(0,0,2,15,GREY); P.text(4,6,"Radio off",WHITE); P.rect(4,9,5,5,AMBER); P.text(11,14,"stop",GREY); posbar(P,0,53,3,AMBER)
S("4  List - 'Radio off' (first item, only while playing)",P)
P=Panel(); P.rect(0,0,2,15,DZ); P.text(4,6,"Drone Zone",DZ); P.text(4,14,"tuning..",GREY)
S("5  Tuning (dots animate)",P)
P=Panel(); eq(P,0,1,5,[4,6,3],GS); P.text(7,6,"Groove Salad",AMBER); P.text(0,14,"Asonat - Forgotten",WHITE)
S("6  Now playing - rotation card / tuner (channel amber, 'Artist - Title' white, scrolls)",P)
P=Panel(); eq(P,0,1,5,[2,5,6],GS); P.text(7,6,"Groove Salad",AMBER); P.text(0,14,"Sounds From The",WHITE); P.rect(0,15,int(W*0.6),1,TEAL); P.rect(int(W*0.6),15,W-int(W*0.6),1,DIM)
S("7  Now playing + volume overlay (knob turned; teal bar 1.5 s)",P)
P=Panel(); eq(P,0,1,5,[1,2,1],(255,255,255)); P.text(7,6,"Police Scan",AMBER); P.text(0,14,"OutdoorAmbi",WHITE)
S("8  Now playing - stream title without artist (police scanner)",P)
P=Panel(); P.text(4,6,"No signal",AMBER); P.text(4,14,"retrying",GREY)
S("9  Error - stream not reachable (AWTRIX auto-retries)",P)

LED=9; pad=14; cap=18
img=Image.new('RGB',(W*LED+2*pad, len(screens)*(H*LED+pad+cap)+pad),(18,18,18))
d=ImageDraw.Draw(img)
y0=pad
for t,P in screens:
    d.text((pad,y0),t,fill=(200,200,200)); y0+=cap
    d.rectangle([pad-4,y0-4,pad+W*LED+3,y0+H*LED+3],fill=(0,0,0))
    for y in range(H):
        for x in range(W):
            c=P.p[y][x] or (22,22,22)
            d.ellipse([pad+x*LED+1,y0+y*LED+1,pad+x*LED+LED-2,y0+y*LED+LED-2],fill=c)
    y0+=H*LED+pad
img.save(sys.argv[1] if len(sys.argv) > 1 else str(LIB.parent.parent / 'docs' / 'mockups.png'))

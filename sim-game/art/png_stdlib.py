"""Read a PNG without Pillow, so a CI check can look at a sprite.

NOT MINE: Maren wrote this on 2026-10-02 to verify my shadow numbers
independently (`shared/assay/png_nopil.py`), and it is vendored here
UNMODIFIED, body and all. Two reasons it lives in the repo now rather than in
shared docs: `art/check_part_contract.py` runs in CI with plain `python3` and
no pip, and a second implementation of a PNG decoder is exactly the kind of
"two readers that can disagree" this pipeline keeps getting bitten by.

    w, h, px = read_rgba("client/assets/sprites/head.png")   # px[y][x] = rgba

Part sheets are 128x306: three 128x102 grade rows (C, B, A). Scan ONE row, not
the sheet, or every count comes out 3x -- Maren's own note, and she made that
mistake first.
"""
import zlib, struct
def read_rgba(path):
    d=open(path,'rb').read(); assert d[:8]==b'\x89PNG\r\n\x1a\n'
    i=8; idat=b''; w=h=bd=ct=None; pal=None; trns=None
    while i<len(d):
        ln=struct.unpack('>I',d[i:i+4])[0]; typ=d[i+4:i+8]; data=d[i+8:i+8+ln]; i+=12+ln
        if typ==b'IHDR': w,h,bd,ct=struct.unpack('>IIBB',data[:10])
        elif typ==b'IDAT': idat+=data
        elif typ==b'PLTE': pal=data
        elif typ==b'tRNS': trns=data
        elif typ==b'IEND': break
    raw=zlib.decompress(idat)
    nch={0:1,2:3,3:1,4:2,6:4}[ct]; assert bd==8, bd
    stride=w*nch; out=bytearray(); prev=bytearray(stride); p=0
    for y in range(h):
        f=raw[p]; p+=1; line=bytearray(raw[p:p+stride]); p+=stride
        for x in range(stride):
            a=line[x-nch] if x>=nch else 0; b=prev[x]; c=prev[x-nch] if x>=nch else 0
            if f==1: line[x]=(line[x]+a)&255
            elif f==2: line[x]=(line[x]+b)&255
            elif f==3: line[x]=(line[x]+((a+b)>>1))&255
            elif f==4:
                pp=a+b-c; pa,pb,pc=abs(pp-a),abs(pp-b),abs(pp-c)
                pr=a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
                line[x]=(line[x]+pr)&255
        out+=line; prev=line
    px=[]
    for y in range(h):
        row=[]
        for x in range(w):
            o=(y*stride)+x*nch
            if ct==6: row.append(tuple(out[o:o+4]))
            elif ct==2: row.append((out[o],out[o+1],out[o+2],255))
            elif ct==3:
                idx=out[o]; r,g,b=pal[idx*3:idx*3+3]
                a=trns[idx] if trns and idx<len(trns) else 255
                row.append((r,g,b,a))
            elif ct==4: row.append((out[o],out[o],out[o],out[o+1]))
            else: row.append((out[o],out[o],out[o],255))
        px.append(row)
    return w,h,px

# Maren, 2026-10-02. PIL IS NOT INSTALLED on this Mac for any python3 I could
# find (3.11, 3.13, homebrew, /usr/bin) -- a note in my memory saying otherwise
# was wrong. This is enough to judge sprite sheets without it: pure zlib+struct,
# handles 8-bit grey/RGB/palette/RGBA with all five PNG filters.

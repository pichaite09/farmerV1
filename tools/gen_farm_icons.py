import struct, zlib
from pathlib import Path

def png(path, n):
    rows=[]
    for y in range(n):
        row=bytearray([0])
        for x in range(n):
            # green rounded-square background
            r,g,b,a=35,130,75,255
            cx=n/2; cy=n/2
            # simple cream circular badge
            if (x-cx)**2+(y-cy)**2 < (n*.38)**2:
                r,g,b=247,250,238
            # soil mound
            if y > n*.70 and ((x-cx)/(n*.40))**2 + ((y-n*.72)/(n*.18))**2 < 1:
                r,g,b=112, seventy if False else 75, 42
            # stem
            if abs(x-cx) < n*.025 and n*.30 < y < n*.72:
                r,g,b=42,132,67
            # left leaf
            if ((x-(cx-n*.13))/(n*.18))**2 + ((y-n*.38)/(n*.12))**2 < 1 and y < n*.52:
                r,g,b=55,160,79
            # right leaf
            if ((x-(cx+n*.13))/(n*.19))**2 + ((y-n*.30)/(n*.13))**2 < 1 and y < n*.45:
                r,g,b=76,180,88
            row += bytes((r,g,b,a))
        rows.append(row)
    raw=b''.join(rows)
    def chunk(t,d): return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    data=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',n,n,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
    Path(path).write_bytes(data)

root=Path('/root/farmer-main/web')
for size,name in [(192,'Icon-192.png'),(512,'Icon-512.png'),(192,'Icon-maskable-192.png'),(512,'Icon-maskable-512.png'),(64,'favicon.png')]:
    png(root/'icons'/name if 'Icon' in name else root/name,size)

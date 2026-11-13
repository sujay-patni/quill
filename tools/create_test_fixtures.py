#!/usr/bin/env python3
"""Small original, uncompressed RAR4 containing a generated PNG. No personal books."""
import pathlib, struct, zlib

def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',8,8,8,2,0,0,0))+chunk(b'IDAT',zlib.compress((b'\x00'+b'\x70\xa0\x80'*8)*8))+chunk(b'IEND',b'')
def header(data):return struct.pack('<H',zlib.crc32(data)&0xffff)+data
name=b'page1.png'
main=header(struct.pack('<BHHHI',0x73,0,13,0,0))
file=header(struct.pack('<BHHIIBIIBBHI',0x74,0x8000,32+len(name),len(png),len(png),3,zlib.crc32(png),0,20,0x30,len(name),0x20)+name)
end=header(struct.pack('<BHH',0x7b,0,7))
path=pathlib.Path(__file__).resolve().parents[1]/'app/src/androidTest/assets/synthetic.rar'
path.write_bytes(b'Rar!\x1a\x07\x00'+main+file+png+end)
print(path.name, path.stat().st_size,'bytes')

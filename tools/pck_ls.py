import struct, sys, collections
p=sys.argv[1]
f=open(p,'rb'); head=f.read(64)
magic, pv, maj, mi, rev, flags = struct.unpack('<4s5I', head[:24])
base, = struct.unpack('<Q', head[24:32])
diroff, = struct.unpack('<Q', head[32:40])
print(f"pack_version={pv} godot={maj}.{mi}.{rev} flags={flags} base={base} diroff={diroff}")
f.seek(diroff)
cnt, = struct.unpack('<I', f.read(4))
print("files =", cnt)
ents=[]
for _ in range(cnt):
    ln, = struct.unpack('<I', f.read(4))
    name=f.read(ln).rstrip(b'\x00').decode('utf-8','replace')
    off, size = struct.unpack('<QQ', f.read(16))
    md5=f.read(16)
    fl, = struct.unpack('<I', f.read(4))
    ents.append((size,name))
g=collections.Counter()
for s,n in ents:
    top=n.split('/')[0] if '/' in n else n
    g[top]+=s
print("--- 顶层累计 (MB) ---")
for k,v in g.most_common(25): print(f"{v/1048576:8.3f}  {k}")
print("--- 最大 20 ---")
for s,n in sorted(ents,reverse=True)[:20]: print(f"{s/1048576:8.3f}  {n}")

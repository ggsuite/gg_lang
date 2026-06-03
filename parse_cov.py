import re
f=open('coverage/lcov.info').read()
for r in f.split('end_of_record'):
    m=re.search(r'SF:(.*)',r)
    if not m: continue
    sf=m.group(1).strip().replace(chr(92),'/')
    base=sf.split('/lib/')[-1] if '/lib/' in sf else sf
    unc=re.findall(r'DA:(\d+),0\b',r)
    lh=re.search(r'LH:(\d+)',r); lf=re.search(r'LF:(\d+)',r)
    if unc:
        print(f"{base}: LH={lh.group(1) if lh else '?'} LF={lf.group(1) if lf else '?'} UNCOVERED: {unc}")

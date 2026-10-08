import re, fugashi
T=fugashi.Tagger()
K=re.compile(r'[一-鿿々〆ヶ]')
def hira(s): return ''.join(chr(ord(c)-0x60) if 'ァ'<=c<='ヶ' else c for c in s)
def tok(surface, kana):
    if not K.search(surface) or not kana: return surface
    r=hira(kana)
    parts=re.findall(r'[一-鿿々〆ヶ]+|[^一-鿿々〆ヶ]+',surface)
    pat=''.join('(.+?)' if K.match(p) else '('+re.escape(hira(p))+')' for p in parts)
    m=re.fullmatch(pat,r)
    if not m: return '{'+surface+'|'+r+'}'
    return ''.join('{'+p+'|'+g+'}' if K.match(p) else p for p,g in zip(parts,m.groups()))
FIX={'ほけんきんがく':None}
def ruby(text):
    out=[]
    for w in T(text):
        kana=w.feature.kana if w.feature.kana and w.feature.kana!='*' else None
        out.append(tok(w.surface,kana)+(w.white_space or ''))
    return ''.join(out)
def ruby_trap(text, trap):
    if trap and trap in text:
        i=text.index(trap); return ruby(text[:i])+'[['+ruby(trap)+']]'+ruby(text[i+len(trap):])
    return ruby(text)
if __name__=='__main__':
    import sys
    for s in sys.argv[1:]: print(ruby(s))

_ruby=ruby
def ruby(text):
    s=_ruby(text)
    return re.sub(r'([0-9０-９,，]+)\{日\|[^}]+\}', r'\1{日|にち}', s)

FIXES = [
 (r'\{満期\|まんき\}\{日\|にち\}', '{満期日|まんきび}'),
 (r'\{申込\|もうしこみ\}\{日\|にち\}', '{申込日|もうしこみび}'),
 (r'\{届出\|とどけで\}\{日\|にち\}', '{届出日|とどけでび}'),
 (r'\{即\|そく\}\{収\|おさむ\}', '{即収|そくしゅう}'),
 (r'\{直\|じか\}\{扱\|こき\}', '{直扱|じきあつかい}'),
 (r'\{扱\|こき\}', '{扱|あつかい}'),
 (r'\{返\|ぺん\}', '{返|へん}'),
 (r'\{主\|ぬし\}', '{主|しゅ}'),
 (r'\{受理\|じゅり\}\{日\|にち\}', '{受理日|じゅりび}'),
]
_ruby2 = ruby
def ruby(text):
    s = _ruby2(text)
    for a, b in FIXES: s = re.sub(a, b, s)
    return s

import re, json, sys
z=str.maketrans('０１２３４５６７８９','0123456789')
lines=open(sys.argv[1],encoding='utf-8').read().split('\n')
items=[];cur=None;state=None
H1=re.compile(r'^（?([０-９0-9]+)-([０-９0-9]+)）\s*$')
H2=re.compile(r'^問題\s*([０-９0-9]+)\s*(.*)$')
for raw in lines:
    s=raw.strip()
    m=H1.match(s); m2=H2.match(s)
    if m or m2:
        if m: cur={'type':'tf','n':m.group(1).translate(z)+'-'+m.group(2).translate(z),'q':'','rows':[]}
        else: cur={'type':'combo','n':m2.group(1).translate(z),'topic':m2.group(2).strip(),'q':'','rows':[]}
        items.append(cur);state='q';continue
    if cur is None: continue
    if 'あなたの' in s:
        if state in ('done','rows'): cur=None; continue
        state='hdr';continue
    if state=='hdr' and re.match(r'^-+( +-+)+$',s): state='rows';continue
    if state=='rows':
        if re.match(r'^-+$',s): state='done';continue
        if not s: continue
        cur['rows'].append(re.split(r'\s{2,}',s))
        continue
    if state=='q' and s and not re.match(r'^-+$',s): cur['q']+=s+'\n'
out=[]
for it in items:
    r=it['rows']
    if it['type']=='tf':
        a=r[0][0]; expl=''.join(x[1] if len(x)>1 and x[0]==a and i==0 else x[0] for i,x in enumerate(r)); 
        # pages are last col
        expl='';page=''
        for i,x in enumerate(r):
            cols=x[1:] if i==0 else x
            if len(cols)>=2: expl+=cols[0];page+=cols[1]
            elif cols:
                if re.match(r'^[\d～、（）()]+$',cols[0]): page+=cols[0]
                else: expl+=cols[0]
        out.append({'type':'tf','n':it['n'],'q':it['q'].strip(),'a':a,'w':expl,'p':page})
    else:
        q=it['q'].strip().split('\n')
        A=[l for l in q if l.startswith('ア．')];I=[l for l in q if l.startswith('イ．')]
        a=r[0][0]; exp={'ア':'','イ':''};pg={'ア':'','イ':''};key='ア'
        for i,x in enumerate(r):
            cols=x[1:] if i==0 else x
            for c in cols:
                mm=re.match(r'^([アイ])．(.*)$',c)
                if mm:
                    k,v=mm.groups()
                    if re.match(r'^[\d～、（）()]+$',v) and exp[k]: pg[k]+=v
                    else: key=k;exp[k]+=v
                elif re.match(r'^[\d～、（）()]+$',c): pg[key]+=c
                else: exp[key]+=c
        out.append({'type':'combo','n':it['n'],'topic':it['topic'],'ア':A[0][2:],'イ':I[0][2:],'a':a,'wア':exp['ア'],'wイ':exp['イ'],'pア':pg['ア'],'pイ':pg['イ']})
json.dump(out,open(sys.argv[2],'w'),ensure_ascii=False,indent=1)
from collections import Counter
print(len(out),Counter((o['type'],o['a']) for o in out))
for o in out:
    if o['type']=='tf' and (o['a'] not in '正誤' or not o['w'] or not o['p']): print('BAD',o)
    if o['type']=='combo' and (o['a'] not in 'ABCD' or not o['wア'] or not o['wイ'] or not o['pア']): print('BAD',o)

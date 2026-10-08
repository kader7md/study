import json, re, sys
sys.path.insert(0, '.')
from furi import ruby, ruby_trap
Q = json.load(open('qs2.json'))
E = []
for i in range(4): E += json.load(open(f'en{i}.json'))
OK = '設問のとおり正しい。'
def clean(s): return re.sub(r'\s+', '', s)
out = []
stmts = []
for x, e in zip(Q, E):
    if x['type'] == 'tf':
        q = clean(x['q']); t = x['a'] == '正'
        out.append({'k': 'tf', 'n': x['n'], 'a': '○' if t else '×',
            'j': ruby_trap(q, e['trap']), 'en': e['en'], 'why': e['why'], 'ty': e['type'],
            'w': '' if x['w'] == OK else ruby(clean(x['w'])), 'p': x['p']})
        stmts.append((q, t, e['type']))
    else:
        items = []
        for key, ek, tk in (('ア', 'a', 'a'), ('イ', 'i', 'i')):
            q = clean(x[key]); t = x['a'] in ('AB' if key == 'ア' else 'AC')
            items.append({'j': ruby_trap(q, e['trap_' + tk]), 'en': e['en_' + ek], 'why': e['why_' + ek], 'ty': e['type_' + tk],
                'w': '' if x['w' + key] == OK else ruby(clean(x['w' + key])), 'p': x['p' + key], 't': t})
            stmts.append((q, t, e['type_' + tk]))
        out.append({'k': 'combo', 'n': '問題' + x['n'], 'topic': ruby(x['topic']), 'topic_en': e['topic_en'], 'a': x['a'], 'items': items})
# wording statistics from this test
feats = [
 ('absolute', r'いっさい|一切|必ず|すべて|全て|のみ(?!ならず)|に限り|どのような場合|いかなる|全額|常に|絶対'),
 ('soft', r'原則|一般的|など|場合があ|ことがあ|一定|基本的|努め'),
 ('notneeded', r'必要はありません|必要はない'),
 ('must', r'なければなりません|必要があ'),
 ('mustnot', r'てはなりません|てはいけ'),
]
stats = {'total': len(stmts), 'true': sum(t for _, t, _ in stmts), 'f': {}}
for k, p in feats:
    h = [t for s, t, _ in stmts if re.search(p, s)]
    stats['f'][k] = [len(h), sum(h)]
from collections import Counter
stats['types'] = Counter(ty for _, t, ty in stmts if not t)
V = json.load(open('vocab.json'))
voc = [[g, ruby(k), en, d] for g, k, en, d in V]
data = {'Q': out, 'S': stats, 'V': voc}
tpl = open(sys.argv[1]).read()
html = tpl.replace('/*__DATA__*/', 'var DATA = ' + json.dumps(data, ensure_ascii=False) + ';')
open(sys.argv[2], 'w').write(html)
json.dump(data, open('data.json', 'w'), ensure_ascii=False, indent=1)
print(len(out), stats)

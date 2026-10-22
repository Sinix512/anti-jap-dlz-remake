"""把 ANTI-JAP 里的 IMG / TXT.DAT 抽成 PNG 和文本，先验证格式假设。"""
from pathlib import Path
import json
from extract import img, txt

GAME = Path('../dlz/ANTI-JAP')
OUT = Path(__file__).parent / 'out'

ok = fail = 0
fails = []
for p in sorted(GAME.glob('*.IMG')):
    try:
        img.save_png(p, OUT / 'img' / (p.stem + '.png'))
        ok += 1
    except Exception as e:
        fail += 1
        fails.append((p.name, str(e)))
print(f'IMG: {ok} 成功, {fail} 失败')
for n, e in fails[:5]:
    print('  FAIL', n, e)

recs = txt.load(GAME / 'TXT.DAT')
(OUT / 'txt').mkdir(parents=True, exist_ok=True)
(OUT / 'txt' / 'dialogue.txt').write_text(
    '\n\n'.join(f'#{r.number}\n{r.text}' for r in recs), encoding='utf-8')
(OUT / 'json').mkdir(parents=True, exist_ok=True)
(OUT / 'json' / 'txt_records.json').write_text(
    json.dumps([{'n': r.number, 'text': r.text} for r in recs],
               ensure_ascii=False, indent=1), encoding='utf-8')
print(f'TXT: {len(recs)} 条记录, 共 {sum(len(r.text) for r in recs)} 字')

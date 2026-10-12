#!/usr/bin/env python3
# 檢查翻譯鍵有沒有漏：程式裡 tr("固定的鍵") 與 data/*.json 裡像翻譯鍵的字串，都要在 localization/strings_zh_TW.csv 找得到。
# 用字串組出來的鍵（例如 "hunt.option." + id）檢查不到，要靠試玩或 headless 測試看畫面有沒有出現原始的鍵名（QA-66）。
# 用法：python3 tools/check_keys.py（在專案根目錄執行；有缺的鍵時回傳 1）
import csv, glob, json, re, sys

keys = {r[0] for r in csv.reader(open('localization/strings_zh_TW.csv', encoding='utf-8')) if r}
prefixes = {k.split('.')[0] for k in keys}
missing = []

for f in glob.glob('scripts/**/*.gd', recursive=True):
    for i, line in enumerate(open(f, encoding='utf-8'), 1):
        for m in re.finditer(r'tr\("([a-z0-9_.]+)"\)', line):
            if m.group(1) not in keys:
                missing.append(f'{f}:{i}  {m.group(1)}')

def walk(o, path, f):
    if isinstance(o, dict):
        for k, v in o.items():
            walk(v, f'{path}/{k}', f)
    elif isinstance(o, list):
        for i, v in enumerate(o):
            walk(v, f'{path}[{i}]', f)
    elif isinstance(o, str) and re.fullmatch(r'[a-z_]+(\.[a-z0-9_]+)+', o) and o.split('.')[0] in prefixes:
        if o not in keys:
            missing.append(f'{f}{path}  {o}')

for f in glob.glob('data/*.json'):
    walk(json.load(open(f, encoding='utf-8')), '', f)

# 用資料 ID 組出來的鍵（2026-10-13：新地形的 factor.terrain.* 漏寫，畫面出現原始鍵名）
regions = json.load(open('data/regions.json', encoding='utf-8'))
animals = json.load(open('data/animals.json', encoding='utf-8'))
def need(k, why):
    if k not in keys:
        missing.append(f'{why}  {k}')
for m, v in regions['maps'].items():
    if isinstance(v, dict):
        for k in (f'map.{m}', f'den.map.{m}.desc'):
            need(k, 'data/regions.json maps')
terrains = set()
for r, v in regions['regions'].items():
    need(f'region.{r}', 'data/regions.json')
    if v.get('can_den'):
        need(f'den.{r}.desc', 'data/regions.json can_den')
    if v.get('den_bonus'):
        need(f'ui.region_info.den_bonus.{r}', 'data/regions.json den_bonus')
    for a in list(v.get('prey_weights', {})) + list(v.get('competitor_weights', {})):
        need(f'animal.{a}', f'data/regions.json {r}')
    terrains.update(v.get('terrains', []))
for t in sorted(terrains):
    for k in (f'explore.location.{t}', f'factor.terrain.{t}'):
        need(k, 'data/regions.json terrains')
for a, v in animals.items():
    need(f'animal.{a}', 'data/animals.json')
    kind = v.get('refuge', {}).get('kind') if isinstance(v.get('refuge'), dict) else None
    if kind:
        for k in (f'factor.refuge_near.{kind}', f'factor.refuge_far.{kind}', f'reason.refuge_near_{kind}'):
            need(k, f'data/animals.json {a} refuge')

for m in missing:
    print('缺少翻譯鍵：' + m)
print(f'翻譯鍵檢查：{len(keys)} 個鍵，缺 {len(missing)} 個')
sys.exit(1 if missing else 0)

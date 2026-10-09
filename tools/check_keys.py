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

for m in missing:
    print('缺少翻譯鍵：' + m)
print(f'翻譯鍵檢查：{len(keys)} 個鍵，缺 {len(missing)} 個')
sys.exit(1 if missing else 0)

#!/usr/bin/env python3
# 文案的靜態檢查（2026-10-13，pre-2.0-plan 的「文案檢查工具」）：依 docs/writing-guide.md 找出明顯的問題。
# 錯誤（回傳 1）：重複的鍵、半形標點、「我／玩家」、文字裡的 {佔位} 在程式裡沒有被替換。
# 提醒（只列出，要人看）：敘事文字裡出現遊戲用語、苔原狼的「牠們」沒有單數版本、可能在苔原出現的文字用了森林字眼。
# 用法：python3 tools/check_text.py [--notes]（加 --notes 才列出提醒的細節）
import csv, glob, re, sys

rows = [r for r in csv.reader(open('localization/strings_zh_TW.csv', encoding='utf-8')) if r]
header, rows = rows[0], rows[1:]
texts = {}
errors, notes = [], []

for r in rows:
    k, v = r[0], (r[1] if len(r) > 1 else '')
    if k in texts:
        errors.append(f'重複的鍵：{k}')
    texts[k] = v

CJK = r'[一-鿿]'
# 介面文字（數字、說明）不算敘事
UI_PREFIX = ('ui.', 'factor.', 'stats.', 'debug.', 'cost.', 'chance_label.', 'stat.', 'action.', 'summary.', 'reason.',
             'metrics.', 'tooltip.', 'combat.option.', 'hunt.option.', 'routine.option', 'explore.mode', 'prey_state.',
             'routine.', 'snow.tip.', 'combat.anim.', 'season.', 'period.', 'region', 'animal.', 'prey_name.', 'item.',
             'feature.', 'death.', 'injury_source.', 'year.kills', 'year.biggest', 'year.heavy', 'year.changes', 'year.title',
             'game.', 'menu.', 'settings.', 'tendency.', 'tendency_desc.', 'knowledge.', 'weather.', 'bear_steal.danger',
             # 按鈕與狀態列上的數字說明（刻意保留的介面文字）
             'feeding.', 'tendency_effect.', 'ice.option.', 'ice.prompt.', 'stranger.follow', 'tundra.follow', 'hunt.chase.round',
             'encounter.observe', 'log.feeding_ate', 'log.eat_remains')
GAME_TERMS = ['成功率', '回合', '加成', '經驗值', '飽食度', '能力值', '機率']

for k, v in texts.items():
    if re.search(CJK + r'[,?!;:()]|[,?!;:()]' + CJK, v):
        errors.append(f'半形標點：{k}  {v}')
    if '我' in v or '玩家' in v:
        errors.append(f'不該出現「我／玩家」：{k}  {v}')
    if not k.startswith(UI_PREFIX):
        for t in GAME_TERMS:
            if t in v:
                notes.append(f'遊戲用語「{t}」：{k}  {v}')

# {佔位}：程式裡用固定鍵 tr("key") 的地方，看後面有沒有 .replace("{x}"
code = ''
for f in glob.glob('scripts/**/*.gd', recursive=True):
    code += open(f, encoding='utf-8').read() + '\n'
# 一個鍵在程式裡每次出現，往後看幾行（常先存進變數再 .replace）收集被替換的佔位
replaced = {}
lines = code.split('\n')
for i, line in enumerate(lines):
    for m in re.finditer(r'_?t[rt]\("([a-z0-9_.]+)"\)', line):
        window = line[m.start():] + '\n' + '\n'.join(lines[i + 1:i + 8])
        replaced.setdefault(m.group(1), set()).update(re.findall(r'replace\("\{([a-z_]+)\}"', window))
for k, used in replaced.items():
    for kk in [k, k + '.single']:
        if kk in texts:
            need = set(re.findall(r'\{([a-z_]+)\}', texts[kk]))
            miss = need - used
            if miss:
                errors.append(f'佔位沒被替換：{kk} 缺 {sorted(miss)}  ← {texts[kk]}')

# 苔原狼：寫「牠們／那對／兩隻」的句子要有單數版本（只剩一隻時用 _tt 換成 .single）
for k, v in texts.items():
    if k.startswith(('tundra.', 'scavenger.tundra')) and not k.endswith('.single') and re.search('牠們|那對|兩隻', v) \
            and k + '.single' not in texts:
        notes.append(f'沒有單數版本：{k}  {v}')

# 可能在苔原出現的文字用了森林字眼
TUNDRA_OK = ('scavenger.', 'combat.', 'bear_steal.', 'challenger.', 'year.', 'hunt.', 'tundra.', 'territory.', 'lie_down.', 'fox.')
for k, v in texts.items():
    if k.startswith(TUNDRA_OK) and re.search('林|樹|松|雲杉', v):
        notes.append(f'森林字眼（苔原也會出現嗎？）：{k}  {v}')

for e in errors:
    print('錯誤：' + e)
if '--notes' in sys.argv:
    for n in notes:
        print('提醒：' + n)
print(f'文案檢查：{len(texts)} 條，錯誤 {len(errors)} 個，提醒 {len(notes)} 個' + ('' if '--notes' in sys.argv else '（加 --notes 看提醒）'))
sys.exit(1 if errors else 0)

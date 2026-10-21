# 文案條件對照表

文案一致性 C（2026-10-16）。文字裡有「比較、時間、數量、因果」的斷言時，要有實際狀態當依據。這份記錄每條斷言的依據，
`python3 tools/check_text.py --notes` 會提醒「有斷言字眼、但沒列在這份檔案裡」的文字。新增這類文字時，把鍵加進第一節（有條件）或第二節（純描述）。

斷言字眼：比上次、比以前、比當時、比去年、比昨天、遠比、越來越、不如以往、不如從前、又、終於、再次、今年、去年、第一次、從此、已經、這次、上次、少了很多、多了很多、因為、所以。

## 一、有條件的斷言

| 文字的鍵 | 在說什麼 | 依據是哪個狀態 | 不該出現的情況 |
| --- | --- | --- | --- |
| `year.hint.spring.hare_low` | 雪兔比去年少很多 | 雪兔倍率 ≤ 0.3 且比去年低（`hare_mult_last_year`） | 從谷底回升的那年說「少了很多」 |
| `year.hint.spring.hare_low_rising` | 雪兔還是少，但比去年多 | 雪兔倍率 ≤ 0.3 且比去年高 | 比去年少時出現 |
| `year.hint.spring.hare_high` | 雪兔多 | 雪兔倍率 ≥ 1.6（不做比較） | — |
| `year.hint.elder.winter.*` | 老狼預感今年冬天 | `year_state().winter`（當年擲出的冬況），老年、秋天 | 和實際冬況不同 |
| `challenger.again.*` | 年輕的狼又來了 | `challenger_visits` > 0 | 第一次見面時用 |
| `challenger.again.grew` | 牠比上次更壯 | `challenger_grew()`：上次是你打贏（`_after_challenger` 讓牠能力 +3） | 你讓了或輸了（牠沒變）時出現 |
| `combat.remember*、combat.remember.generic.*、knowledge.opponent` | 上次交手的結果、現在誰強 | `opponent_beaten` 記錄、`power_compare` 用對手實際能力（試玩 BUG-04） | 用資料表的固定數值比較 |
| `stranger.compare.*、tundra.compare.*` | 和你比強弱 | `npc_assessment` 的 compare（實際能力） | —（「已經不如你了」第一次跟蹤也會出現：黑狼會老，可接受） |
| `tundra.meet.again.single` | 這次只有牠一隻 | 現在只剩一隻，而且上次見到時是兩隻（`life_log.tundra_seen_size`） | 從頭到尾只見過一隻時出現 |
| `tundra.meet.again.single_same` | 那隻苔原狼又出現了 | 只剩一隻，上次也只有一隻 | — |
| `tundra.relation_change.*` | 關係改變 | `tundra_relation_key` 改變的那一刻 | — |
| `tundra.howl.familiar*` | 那對苔原狼又在嚎叫 | 認得苔原狼、關係友好 | — |
| `event.howl.2、event.howl.3` | 又聽到狼嚎 | `knowledge_level`（聽過的次數）≥ 2 | 第一次聽到時用 |
| `season_card.winter.full、season_card.winter.short` | 第一場雪落下、雪又來了 | 冬季第一天至少淺雪（換季時結算雪況，暖冬也一樣；`snow_sim` 檢查） | 冬季第一天沒雪 |
| `season_card.*.short` | 季節的「又」 | 第一次以後的換季（`seasons_seen`）；第一次用 full | 第一次就用短版 |
| `season_card.spring.bear_sensed` | 入冬前聞到的氣味又會回來 | `sensed:grizzly_bear` 且還沒辨識 | — |
| `season_card.review.grew` | 這一季又成長了一些 | 這一季有能力 ▲ ≥ 0.5、沒有 ▼、沒有挨餓 | 只長感知或技巧時說「強壯」（已改成「成長」） |
| `season_card.review.starved_some` | 常常挨餓，長得比較慢 | 有 ▲，這一季吃飽的天數比例 < 0.3 | 說「沒什麼長進」卻列出 ▲（已改） |
| `season_card.review.starved` | 瘦了，沒什麼長進 | 沒有任何變化 ≥ 0.5 且挨餓 | — |
| `season_card.review.declined` | 有些地方不如從前 | 有能力 ▼（老年衰退） | — |
| `sleep_reason.*_chase、*_fight` | 這幾天的追逐／纏鬥讓你長了 | 速度或力量 ▲，上次睡覺後有追獵（`since_sleep.chase`）或打鬥（`.fight`） | 只探索、採集時說追逐（已改成 roam） |
| `sleep_reason.roam` | 四處走動，身體結實了一些 | 速度或力量 ▲，上次睡覺後沒追獵也沒打鬥 | — |
| `sleep_reason.full_*、hungry_*` | 這幾天吃得很飽／常常餓著 | 醒來當下的飽食度（不是這幾天的平均） | 輕微：剛吃一頓大餐也算「這幾天吃得很飽」，先不改 |
| `sleep_reason.starved` | 肚子太空，長不起來 | 鍛鍊點 ≥ 15 且飢餓倍率 < 0.3 | — |
| `sleep_reason.none_*` | 沒長的原因 | 什麼都沒長：老年（每季一次）、沒活動、接近上限、變化太小 | — |
| `day_summary.*_healed、day_summary.heavy_healed_*、day_summary.old_injury_new` | 傷終於好了 | 傷勢從有到完全沒有（單一欄位，重傷蓋過輕傷；`notice_triage` 測試） | 還有傷時顯示痊癒 |
| `day_summary.hunger_*` | 飢餓的變化 | 飢餓階段（`hunger_tier`）改變 | — |
| `day_summary.old_injury_*` | 舊傷發作／平息 | `flare_index`、`flare_days` | — |
| `pack.news.*` | 黑狼家族的變化（多了一隻母狼、有了孩子、範圍變大、換了帶頭的、散了） | 那一季 `WolfPack.on_season_passed` 的事件（paired／pups／expanded／succession／dissolved），寫在下一張森林的季節卡片；`.known` 要已辨識黑狼 | 沒有發生那件事時出現；不在森林時寫 |
| `pack.sign.*、encounter.observed.stranger_wolf.pair／.pack` | 腳印、氣味、狼嚎、遠觀裡不只一隻狼 | `black_pack.stage` 是 pair／pack；`pack.sign.howl.pups` 要有幼狼；`pack.sign.observed.old` 要帶頭的是老年 | 獨居時出現 |
| `pack.meet.wary` | 那隻黑狼記得輸給你的那一次 | `pack_attitude()` = wary：黑狼 `yielded_to_player`（你打贏過）或被你殺死；第一代 | 沒打贏過時出現；換代後用 `.heir` |
| `pack.meet.scorn` | 你曾經在那隻黑狼面前退讓 | `pack_attitude()` = scorn：黑狼 `dominance` > 0（示弱、撤退、退讓過）；第一代 | 沒退讓過時出現；換代後用 `.heir` |
| `challenger.first.*.son` | 年輕的挑戰者是那隻黑狼的兒子 | 挑戰者出現時黑狼一家生過幼狼（`pack_had_pups()`，記在 `life_log.challenger_son`） | 黑狼從沒生過幼狼時出現 |
| `summary.pack*` | 黑狼一家的經過（成家、擴張、佔地盤、換代、散了、幾窩幼狼、撞上幾次） | `life_log.black_pack_events`、`pack_meetings` | — |
| `factor.old_age、reason.old_age` | 老了，腿腳和力氣不如從前 | 年齡 ≥ `hunt.age.decline_start`（6 歲）時，追擊與制伏有年齡的扣分（Phase 2b 第 3 步） | 6 歲前出現 |
| `hunt.give_up.*` | 放棄時的依據（步伐穩健、沒有明顯弱點、露出弱點） | 看得出體況時（`condition_known`）依體況；看不出來用 unknown | 沒看出體況卻寫依據 |
| `combat.grow.clean` | 打得越來越熟練 | 幾乎沒受傷就打贏（受傷 ≤ 15%），不是老年（技巧會長） | 老年技巧不再長時出現 |
| `combat.grow.clean_elder` | 老經驗還管用 | 同上，老年 | — |
| `combat.grow.costly` | 記住了牠的每一個動作 | 慘勝（受傷 ≥ 40%），學到對手的知識 | — |
| `first_win.*` | 第一次打贏 | `first_win` 事件；`.heavy` 是慘勝 | — |
| `first_win.cougar.body` | 躍上高處逃走 | 美洲獅在山地與森林西部（密林、倒木）都說得通 | 寫「岩壁」（森林西部沒有） |
| `first_big_kill.*` | 第一次獨自獵倒大型獵物 | `life_log` 第一次的紀錄 | — |
| `stranger.won_territory、stranger.killed_card` | 從此是你的（範圍） | 黑狼原本的地盤（QA-59、67） | 寫成你現在的區域 |
| `adult_body.*` | 成年身體描述 | 最高的能力與主要傾向（`notices.adult_transition.rules`） | — |
| `fire.arrive.regrowth、fire.arrive.regrown` | 鹿的足跡又多了 | `burn_state` = regrowth；白尾鹿出現 ×1.5（`events.json` regrowth_prey_mult） | — |
| `fire.arrive.ash.again` | 還是一片焦黑 | 第二次以後來到焦黑的區域 | — |
| `explore.again` | 又是那頭動物 | 同一個發現（`current_discovery.again`） | — |
| `death.card.injury` | 傷一直沒有好 | 非戰鬥、沒有挨餓到 0 的死亡（目前只有血量極低時被螫） | —（戰死、灰熊搶食致死都另有卡片） |
| `death.card.starvation` | 好幾天沒吃到東西 | 血量歸零時飽食度 ≤ 0 | — |
| `routine.moved` | 這幾天你走到了 | 照常過日子期間換了區域 | 輕微：不到一天就停時仍說「這幾天」，先不改 |
| `log.cache.stale` | 肉已經放了一陣子 | 挖出藏肉時已經過了新鮮期（`GameState.cache_state` = stale） | — |
| `log.cache.lost.rotten` | 藏的肉已經壞了 | 回到那一區時，藏肉超過新鮮期 rot_mult 倍（`_update_caches` 記成 rotten） | — |
| `log.cache.part_rotten` | 藏的肉有一段已經壞了 | 回到那一區（或在那裡動手藏、挖）時，有一段超過新鮮期 rot_mult 倍、被拿掉（`rotten_seen`） | — |
| `log.cache.replaced` | 放太久的那段 | 藏滿 2 段、有一段過了新鮮期時換掉最舊的那段（`cache_status` = replace） | — |

回歸測試：`tools/sim/text_claims.gd`（雪兔、年輕的狼、睡醒原因、苔原狼）、`tools/sim/notice_triage.gd`（痊癒）。

## 二、已看過、只是描述（沒有要對狀態的斷言）

例如「又大又壯」「又熟了」「雪又來了」這類描述，或觸發本身就保證成立的句子（例如風雪停了才出現的「終於停了」）。

`hunt.result.fail`、`prey_state.dangerous.elk.adult`、`prey_state.dangerous.bison.adult`、`event.bear_passing.leave`、`explore.threat_stale`、`log.carcass_gone`、`log.region_first_visit`、`death.card.old_age.mountain`、`season_card.summer.full`、`season_card.winter.full`、`tendency_change.stealth`、`tendency_change.pursuit`、`tendency_change.assault`、`tendency_change.cautious`、`adult_transition.bonus`、`elder_body.text`、`combat.opp.stamina.spent`、`stranger.meet_again`、`stranger.age.past_peak`、`stranger.last_assessment`、`fire.warning.late`、`fire.over`、`explore.carcass`、`blizzard.result.retreat`、`blizzard.over`、`ice.result.fail`、`ravens.nothing`、`tundra.meet.again.pair`、`tundra.howl.hostile`、`tundra.howl.replied`、`tundra.relation.friendly`、`tundra.mob.watch.drove_off`、`combat.stake.mob.wolverine`、`tundra.come`、`tundra.come.single`、`log.made_den.bonus.tundra_north`、`season_card.tundra.summer.full`、`blizzard.over.later`、`encounter.woken_direct`、`encounter.woken_direct_mother`、`log.injury_pushed_on`、`factor.combat.lethal`、`yearling.body`、`summary.first_big_kill`、`hunt.catch_breath.lost`、`hunt.probe.done`、`hunt.condition.healthy`、`factor.prey_exhausted`、`bear_steal.still`、`bear_steal.result.carry.whole`、`tundra.hunt.hint`、`tundra.hunt.hint.single`、`tundra.den.approach.seen`、`tundra.den.approach.seen.single`、`tundra.den.bear`、`tundra.den.bear.mother`、`tundra.den.result.drove_off`、`tundra.den.result.drove_off.single`、`tundra.den.watch.held`、`tundra.den.watch.held.single`、`year.hint.winter.severe`、`year.hint.winter.mild`、`lie_down.prompt`、`season_card.mountain.summer.full`、`season_card.mountain.autumn.full`、`hunt.refuge.water`、`combat.stake.carcass.black_bear`、`river.flood.prompt`、`river.flood.swept_ok`、`river.flood.swept_bad`、`injury.info.recovery.heavy`、`injury.info.old_title`、`sleep_spot.lost.wear`

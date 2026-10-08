# SPEC 更新提案之三（2026-10-08）

> **狀態：2026-10-08 使用者整份同意（C1 依資料為準），已寫入 `SPEC.md`。這份保留作為紀錄。**

依 `CLAUDE.md`，使用者同意後才寫入 `SPEC.md`。可以整份同意，也可以用編號逐項同意或修改。

- **A. 新增「Phase 1.8：獵物生態與季節」**：依真實生態調整狩獵，先做白尾鹿（資料見 `docs/ecology-reference.md`「獵物：白尾鹿」）
- **B. 新增「Phase 1.9：戰鬥演出」**：回合制的動畫演出，以及先後、打斷的規則
- **C. 修正 1.7 的白尾鹿描述、決策紀錄、待決事項**

兩個階段都排在 1.7 驗收之後；1.8 在前，因為它直接接著 1.7 的狩獵數值。

---

## A. Phase 1.8：獵物生態與季節

放在「Phase 1.7」整節之後、「待決事項」之前。

> ## Phase 1.8：獵物生態與季節
>
> ### 目標與驗收
>
> 1.7 讓每種獵物有自己的打法，但打法是固定的，和季節、雪況、獵物本身的狀況無關。真實的灰狼狩獵，成敗主要看雪況與挑對獵物：健康的成鹿通常追不到，深雪是狼最大的優勢，冬末虛弱的鹿最好抓，夏天則是到處搜躲起來的幼鹿。1.8 依真實生態補上這些變因，讓「什麼時候、挑哪一隻、怎麼追」成為玩家的判斷。先做白尾鹿；其他獵物等資料齊了用同樣的方式加入。
>
> 成功標準：
>
> - 季節有差：同一隻狼，冬季深雪時獵鹿明顯比夏秋容易；夏季主要靠找幼鹿。
> - 挑選有意義：玩家會先觀察或試探，放棄翹起白尾、狀況很好的鹿，把體力留給虛弱的那一隻。
> - 說得出原因：失手時，玩家能從畫面說出是雪太淺、鹿太健康、還是被鹿群發現。
>
> ### 範圍
>
> | 做 | 不做 |
> | --- | --- |
> | 雪況（隨季節變化，影響追擊與獵物反擊） | 群獵的「打散再隔離」（Phase 3 狼群） |
> | 獵物的體況與試探（白尾鹿） | 新地圖、新動物（Phase 2） |
> | 鹿群：大小隨季節、警覺、噴鼻息警報 | 天氣系統大改（只加雪況） |
> | 夏季幼鹿、繁殖期與掉角的雄鹿 | |
> | 修正 1.7 白尾鹿的追擊方式 | |
>
> ### 雪況
>
> - 每張地圖有目前的雪況：無雪、淺雪、深雪、硬雪殼。冬季初是淺雪，冬季中後段多半是深雪；冬末、春初的晝融夜凍可能形成硬雪殼；苔原風大，雪較常是硬雪殼。頂部與探索文字寫出雪況。
> - 無雪、淺雪：健康的鹿很快就甩開狼，長距離追下去多半白費體力；鹿站得穩，蹄的反擊較危險。
> - 深雪：鹿陷得比狼深，追擊與長距離跟隨明顯有利，鹿的體力消耗加快；幼鹿最危險。
> - 硬雪殼：狼能在上面跑、鹿會踩破陷下去，追擊大幅有利。
> - 狼自己在深雪裡移動也較累（移動的體力略增）。
>
> ### 獵物的體況與試探
>
> - 每頭白尾鹿有體況：健康、普通、虛弱（老、病、傷、營養不良）。虛弱的比例隨季節變化，冬末最多。現有的「受傷個體」算虛弱的一種。
> - 觀察成功或感知夠高時看得出體況。
> - 翹尾旗：健康的鹿一被追就豎起白尾逃跑，畫面寫出來，等於告訴玩家「追了也是白追」；這時放棄可以省下體力。追擊中鹿放下尾巴急轉時可能跟丟，密林更容易。
> - 試探：追一小段就停，看誰落後、跛腳（類似 1.6 觀察鹿群挑出跑得慢的那一隻，延伸到白尾鹿）。
>
> ### 鹿群
>
> - 白尾鹿的鹿群大小隨季節：冬季最大（平均 3～4 頭，鹿場更多），產仔季最小（1～2 頭）；母系家族為主，雄鹿 2～4 頭的小群，繁殖期多半落單。
> - 成群時潛近較難（很多雙眼睛），但觀察時能挑出弱者。
> - 失手時鹿會跺腳、噴鼻息，警告附近的鹿：這一帶的鹿短時間內更難接近。
> - 冬季鹿場：森林北部冬季鹿多、成群，狼在這裡的成功率較高（聚集反而吸引掠食者）。
>
> ### 季節的獵物組成
>
> - 夏季：新生幼鹿多，但頭幾週躲在高草中、沒有氣味，追蹤困難，要靠搜尋；母鹿在附近。
> - 秋季（繁殖期）：雄鹿追母鹿、警覺下降，但有角、較危險。
> - 冬季：繁殖期後的雄鹿體力掉很多；冬末掉角後反擊下降。
>
> ### 其他（可選）
>
> - 藏食：吃不完的殘骸可以「埋起來」，保存較久、較不容易被搶。
> - 涉水逃走：溪流地形時鹿有機會跳進水裡甩掉狼（沒有直接來源，半參考）。
>
> ### 其他獵物
>
> 北美馴鹿、駝鹿、野兔、雪兔、狐狸等，等使用者提供或確認資料後，用同一套（體況、雪況、群體、季節組成）加入；資料先整理進 `ecology-reference.md` 並附來源。
>
> ### 實作順序
>
> 1. 雪況（地圖狀態、顯示、對追擊與反擊的影響）
> 2. 白尾鹿的體況、翹尾旗與試探；修正 1.7 的追擊方式
> 3. 鹿群（大小、警覺、噴鼻息警報、鹿場）
> 4. 季節的獵物組成（夏季幼鹿、繁殖期與掉角的雄鹿）
> 5. 其他獵物（資料齊了再做）
>
> 每一步都以模擬確認各季節的狩獵成功率與壽命，結果記在 `progress.md`。
>
> ### 試玩指南
>
> - 1、2 步完成後：在冬季深雪與夏秋各獵幾次白尾鹿，比較難易；遇到翹尾旗的鹿時試著放棄或追下去。
> - 全部完成後：回答 1.8 驗收的三個問題。

---

## B. Phase 1.9：戰鬥演出

放在 Phase 1.8 之後。

> ## Phase 1.9：戰鬥演出
>
> ### 目標與驗收
>
> 戰鬥現在是選選項、看文字結果。1.9 把每一回合做成像回合制遊戲的動畫演出：選了「騷擾」，就看到狼繞著對手打轉、突然衝上去咬一口，可能咬空、可能被反打、也可能互相咬中，演完再進下一回合。同時加入「誰先動」與「打斷」，讓速度在戰鬥中看得見。
>
> 成功標準：
>
> - 看得懂：不看文字，只看動畫也知道這回合誰先動、誰打中誰。
> - 速度有感：速度快的狼常常先咬到；慢的狼常被對手搶先打中、打斷攻擊。
> - 不拖節奏：可以加速或略過動畫，長的戰鬥（灰熊十幾回合）也不會煩。
>
> ### 範圍
>
> | 做 | 不做 |
> | --- | --- |
> | 戰鬥模式的回合演出（灰熊、黑狼、苔原狼、狼獾、狐狸） | 狩獵的搏鬥（之後視情況比照） |
> | 先後與打斷的規則 | 多隻對手同時行動的大型戰鬥（Phase 3） |
> | 先用現有姿勢做補間動畫，正式動畫素材分批補 | |
>
> ### 回合的結果改成事件序列
>
> - 每回合依先後產生一串事件（例如：狼繞圈 → 狼撲上去 → 對手閃開並反擊 → 狼被打中），畫面照順序播放，紀錄文字也照這個順序寫。
> - 邏輯和畫面照舊分開：戰鬥邏輯只產生事件，播放由畫面負責。
>
> ### 先後與打斷
>
> - 玩家選狼的動作；比較雙方的速度（加上動作本身的快慢，例如猛撲慢、騷擾快）決定誰先動。
> - 狼先動時，對手可能：被打中、只閃開、閃開同時反擊。
> - 對手先動時，可能直接打中狼並打斷這回合的攻擊。
> - 這是規則改動，會改變勝負機率，要和戰鬥數值一起調，並重跑戰鬥模擬（目標是整體勝率和現在相近，差別在速度的份量）。
>
> ### 動畫
>
> - 第一步只用現有的單張姿勢，以補間動畫做出位移、繞圈、衝刺、震動、閃白、跳出傷害數字，不需要新素材。
> - 之後補多格動畫素材（狼：繞圈、撲咬、被打飛；對手：攻擊、閃避、受傷），檔名與 `art.json` 的對應寫在美術需求，換圖不用改程式。
> - 設定：動畫速度（一般、快）與「略過動畫」。
>
> ### 實作順序
>
> 1. 事件序列（邏輯不變，只是輸出更細）
> 2. 補間動畫播放、加速與略過
> 3. 先後與打斷的規則，重跑戰鬥模擬
> 4. 正式動畫素材（分批）
>
> ### 試玩指南
>
> - 1、2 步完成後：打幾場灰熊與黑狼，確認動畫看得懂、節奏不拖。
> - 3 步完成後：比較速度快與慢的狼打同一個對手的感覺。

---

## C. 其他修正

### C1. 1.7「依獵物決定狩獵方式」的白尾鹿
- 現在：「白尾鹿：林間短距離衝刺與伏擊有利，長距離跟隨容易在密林中跟丟。」
- 改成：
  > 白尾鹿：健康的鹿在沒雪或淺雪時很快就能甩開狼，長距離追下去多半白費體力；深雪時鹿陷得深，長距離跟隨反而有利（依雪況的規則見 Phase 1.8）。
- 備註：程式目前照 1.7 初版（短衝 +5%、跟隨 −8%），1.8 第 2 步依雪況改寫。

### C2. 決策紀錄
- 加：
  > | 2026-10-08 | 開 Phase 1.8「獵物生態與季節」：依真實生態（先白尾鹿）加入雪況、獵物體況與翹尾旗、鹿群、季節的獵物組成；1.7 白尾鹿「短衝較好」改為依雪況 |
  > | 2026-10-08 | 開 Phase 1.9「戰鬥演出」：回合制動畫演出、先後與打斷；先用現有姿勢做補間動畫，正式素材分批補 |

### C3. 待決事項
- 加：
  > - [ ] 1.8 其他獵物（北美馴鹿、駝鹿、野兔、雪兔、狐狸）的生態資料：使用者提供或確認後整理進 `ecology-reference.md`。
  > - [ ] 1.9 狩獵的搏鬥要不要也做成同樣的演出。

### C4. 使用方式（第 7 行）
- 「…與 Phase 1.7（規劃中）。」改成「…、Phase 1.7（實作完成，待試玩驗收）、Phase 1.8 與 1.9（規劃中）。」

---

## 使用者提供的白尾鹿資料來源（2026-10-08）

- USGS – Relationship between snow depth and gray wolf predation on white-tailed deer：https://www.usgs.gov/publications/relationship-between-snow-depth-and-gray-wolf-predation-white-tailed-deer
- USGS – Sixty years of White-tailed Deer yarding：https://www.usgs.gov/publications/sixty-years-white-tailed-deer-odocoileus-virginianus-yarding-a-gray-wolf-canis-lupus
- Canadian Field-Naturalist – Fawn risk from wolf predation：https://www.canadianfieldnaturalist.ca/index.php/cfn/article/view/1758
- Quetico Superior – Voyageurs Wolf Project study：https://queticosuperior.org/new-research-reveals-how-humans-enable-wolf-predation-on-deer/
- LCCMR – Effects of Wolf Predation on Beaver, Moose, and Deer：https://www.lccmr.mn.gov/projects/2017/finals/2017_03l.pdf
- International Wolf Center – Deer population thrives despite wolves：https://wolf.org/?p=61644
- Minnesota DNR – DelGiudice wolf article：https://files.dnr.state.mn.us/natural_resources/animals/mammals/wolves/delguidice_wolf_article.pdf
- Wolves on the Hunt (Mech et al.)：https://www.abebooks.com/9780226255149/Wolves-Hunt-Behavior-Hunting-Wild-022625514X/plp
- CFN review of Wolves on the Hunt：https://canadianfieldnaturalist.ca/index.php/cfn/article/download/1739/1730/6865
- CFN – Wolf caching deer in deep snow：https://canadianfieldnaturalist.ca/index.php/cfn/article/download/1200/1193/4768
- Snow conditions & apex predators：https://inaturalist.lu/posts/119994-new-research-article-apex-predators-exploit-advantageous-snow-conditions-across-hunting-modes
- Pennsylvania Game Commission – White-tailed Deer：https://pgc.pa.gov/Education/WildlifeNotesIndex/Pages/White-tailedDeer.aspx
- NHPR – Deer Breeding Season：https://www.nhpr.org/post/deer-breeding-and-hunting-season
- Field & Stream – What is rutting：https://www.fieldandstream.com/conservation/what-is-rutting/
- SEAFWA – Social Grouping of White-tailed Deer：https://seafwa.org/journal/1983/social-grouping-white-tailed-deer-shenandoah-national-park-virginia
- Montana State – Whitetail management：https://animalrangeextension.montana.edu/wildlife/documents/whitetail-mgmt.pdf
- Thames River – White-tailed Deer：https://thamesriver.on.ca/?p=1330
- FWC – White-Tailed Deer：https://fyccn.myfwc.com/education/bookmark/wildlife-discovery/deer/
- Springer – Sika deer antipredator behaviors：https://link.springer.com/article/10.1007/s42991-026-00571-w
- 3 Quarks Daily – The Rules of The Hunt Part II：https://3quarksdaily.com/?p=291342
- Realtree – Deer body language：https://realtree.com/deer-hunting/galleries/20-things-to-know-about-deer-body-language-and-behavior
- Why a white tail?：https://blog.kootenay-lake.ca/?p=8977

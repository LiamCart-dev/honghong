# 哄哄「提醒哄睡 + 辅助哄睡」安全文案草稿（#38）

> 本文件是 #38 审定文案的仓库副本（#38 评论 6286515825 的全文）。App 里的文案在 `app/lib/features/soothe/soothe_copy.dart`，由 `app/test/soothe_copy_test.dart` 逐字对照本文件。
> **状态：育儿指南已审（2026-10-20），按意见修改后可进开发**。2026-10-20 起草，同日按审阅意见修改。
> 规则沿用 #30：只说"可能"，给范围不给精确时间；每个面板末尾都放和 #30 相同的急症提示（直接复用 `stageEmergencyLine`）；不做诊断，不写药物建议。
> 每条后面的〔S#〕对应文末的来源。

---

## A. 清醒时长提醒

### A1. 提醒文案（App 内卡片 / 系统通知，两处共用）
- 标题：「宝宝醒了约 {X}，可能快困了」
- 正文：「留意困倦信号：打哈欠、眼神发直、揉眼睛、扭开脸、皱眉、握拳、手脚乱动、身体往后打挺。看到了就可以开始哄睡，不用等到哭。如果距离上次喂奶超过 2 小时左右，可能是饿了，拿不准就先喂一喂。每个宝宝不一样，以宝宝的信号为准。」〔S1〕（含 S1 "Tired or hungry?" 一节）〔S2〕
- 按钮：「开始哄睡」/「还不困」（还不困 = 本次醒着期间不再提醒）

### A2. 按月龄的清醒时长（"可能"＋范围，标题里只用下限）
| 月龄 | 文案 | 来源 |
|---|---|---|
| 0–3 个月 | 「这么大的宝宝，可能醒 1–1.5 小时就困了，有的宝宝能醒 2 小时左右」 | 〔S1〕Raising Children：新生儿有的醒 1–1.5 小时就累，有的能玩 2 小时以上；〔S2〕HSE：新生儿两次睡眠之间醒 1–2 小时，醒超过 1 小时可能就累了 |
| 3–6 个月 | 「可能醒 1.5–3 小时会困」 | 〔S1〕"At 3-6 months, babies might be tired after 1½-3 hours awake." |
| 6–12 个月 | 「可能醒 2–3 小时会困」 | 〔S1〕"At 6-12 months, babies might be tired after 2-3 hours awake." |
| 12 个月以上 | 第一版不提醒 | — |

育儿指南确认不用 45–60 分钟，Raising Children 原文已核对。

### A3. 一天总睡眠参考（只作参考，不给作息表）
- 「0–3 个月每天大约睡 13–18 小时，4–11 个月大约 12–16 小时。每个宝宝不一样，只要精神、吃奶、长体重都好，一般不用太担心。」〔S3〕WS/T 579

---

## B. 辅助哄睡（白噪音 / 粉噪音 / 「嘘」声）

### B1. 播放页固定提示（每次打开都显示，不能关闭）
- 「音量开小，大概跟洗澡水声差不多或更小，不要开到最大。手机离宝宝至少 2 米，**不要放进小床里，也不要放在床栏上**。」〔S4〕
- 「到时间会自动关掉（默认 30 分钟），不要整晚一直开着。」〔S4〕
- 「哄睡声音只是辅助，**不能代替大人看护**。宝宝睡着后请照常照看。」

开发说明：默认低音量，App 内不做音量增益（不放大超过系统音量）。

〔S4〕的说明（只给开发和审阅看，不放进 App）：Hugh 等 2014 年发表在 AAP 期刊 *Pediatrics* 上的研究，测了 14 台婴儿助眠机的最大音量。在 30 厘米处全部超过 50 dBA（医院新生儿室的建议上限），在 200 厘米处仍有 13 台超过。作者建议机器尽量远离婴儿、不放在床里或床栏上、用最低音量、限时使用。**2 米并不等于安全距离**，所以文案必须同时写"音量开小"和"至少 2 米"，不能只写距离。50 dBA 是医院新生儿室的标准，不是 AAP 给家用设备定的阈值，文案里**不写具体分贝数**（手机也没办法保证实际分贝）。

### B2. 哄睡步骤引导（卡片，可左右滑动）
1. **调暗灯光、安静下来**：「拉上窗帘，关掉大灯，说话小声一点。」〔S1〕
2. **包裹（可选）**：「用薄包巾包住身体，**腿和髋部要能自由弯曲、向两边张开**。宝宝**开始想翻身就停止包裹**。包着的宝宝只能仰卧放下。不要用加重的包巾。留意别热着，出汗、头发潮、呼吸快就是太热了。」〔S5〕〔S6〕〔S10〕
3. **轻轻摇、轻拍**：「抱在怀里，扶好头颈，慢慢走动或小幅度、有节奏地轻摇、轻拍。」〔S9〕〔S7〕
   - 紧接一行红字：「**绝不能摇晃宝宝**。轻摇是指动作很小、很慢的晃动，不是甩动或摇晃。」〔S9〕〔S7〕（S9 原文："it is never safe to shake, throw, hit, slam, or jerk any child"）
4. **嘘声 / 白噪音**：「在耳边轻轻发出"嘘——"，或打开哄哄的嘘声、白噪音（音量开小，手机离远）。」〔S4〕〔S9〕
5. **吸吮**：「可以给安抚奶嘴，或让宝宝吸吮。母乳喂养的宝宝，等喂奶顺利了再给安抚奶嘴；宝宝不要就别硬塞。」〔S6〕〔S9〕（AAP 安全睡眠建议里有"小睡和夜里睡觉时可以考虑用安抚奶嘴"）
6. **放回小床**：见 C1。

- 撑不住时（每张步骤卡底部都有入口）：「哄了很久还在哭、你快撑不住了：先把宝宝**仰卧放进安全的小床**，离开几分钟缓一缓，或者请家人接手。等自己平静下来，大约 10–15 分钟后再回去看看宝宝。」〔S9〕〔S7〕

---

## C. 必带的安全内容（播放页、步骤页、提醒详情的末尾都要有）

### C1. 安全睡眠
- 「宝宝睡着后，**仰卧**放回**平整、不倾斜**的小床或婴儿床。床上**不放枕头、被子、毛绒玩具**。」〔S6〕
- 「**不要让宝宝在倾斜的摇椅、安抚椅、秋千、汽车座椅里长时间睡**。在里面睡着了，就尽快抱到平整的小床上。」〔S6〕

### C2. 生病时不要用哄睡处理
- 「宝宝如果可能生病了（比如发烧、精神差、拒奶），**不要用哄睡的办法处理哭闹**，请先看医生。」
- 固定急症提示（和 #30 完全相同，直接复用 `stageEmergencyLine`）：
  「出现这些情况请立即就医：3 个月以下宝宝体温 ≥38℃；呼吸急促或费力、口唇发紫；抽搐；拒奶或吃奶明显变差；精神很差、叫不醒。」〔S8〕〔#30 审阅〕
- 「哭声和平时明显不一样，或者怎么哄都哄不好、持续很久，也请及时就医。」〔S7〕

### C3. 通用
- 「以上只是参考，不能替代医生判断，也不能代替大人看护。」

---

## 来源
| # | 机构 / 标题 | 链接 | 核实 |
|---|---|---|---|
| S1 | Raising Children Network（澳大利亚政府资助）：Tired signs in babies and toddlers | https://raisingchildren.net.au/babies/sleep/understanding-sleep/tired-signs | 已由育儿指南在浏览器核对原文 2026-10-20 |
| S2 | HSE（爱尔兰卫生服务署）：Newborn's sleep needs at 0 to 3 months | https://www2.hse.ie/babies-children/sleep/newborns/ | 2026-10-20 能打开（200） |
| S3 | 国家卫健委 WS/T 579—2017《0岁～5岁儿童睡眠卫生指南》 | https://www.nhc.gov.cn/wjw/c100311/201710/3f9da54855444a6b8f49051993a78933.shtml | 见 #30 核实报告 |
| S4 | Hugh SC 等. Infant Sleep Machines and Hazardous Sound Pressure Levels. *Pediatrics* 2014;133(4):677–681 | https://publications.aap.org/pediatrics/article/133/4/677/32749/ （doi:10.1542/peds.2013-3617；PubMed 24590753） | 读过摘要和正文摘录 |
| S5 | AAP HealthyChildren：Swaddling: Is it Safe for Your Baby? | https://www.healthychildren.org/English/ages-stages/baby/diapers-clothing/Pages/Swaddling-Is-it-Safe.aspx | 读过相关段落 |
| S6 | AAP 2022 安全睡眠建议：Evidence Base for 2022 Updated Recommendations for a Safe Infant Sleeping Environment；家长版 Safe Sleep and Your Baby | https://publications.aap.org/pediatrics/article/150/1/e2022057991/188305/ ；https://publications.aap.org/patiented/article/doi/10.1542/peo_document088/79989/ | 读过相关段落（平整不倾斜床面、坐姿装置不宜常规睡眠、包裹、安抚奶嘴） |
| S7 | AAP HealthyChildren：Colic Relief Tips for Parents（安抚方法、绝不能摇晃）；Seattle Children's / NCSBS：Period of PURPLE Crying（撑不住时先把宝宝放在安全的地方） | https://www.healthychildren.org/English/ages-stages/baby/crying-colic/Pages/colic.aspx ；https://www.seattlechildrens.org/health-safety/parenting/purple-education-crying/ | 见 #30 核实报告 |
| S8 | AAP HealthyChildren：Fever and Your Baby（3 个月及以下肛温 ≥38℃ 立即联系医生） | https://www.healthychildren.org/English/health-issues/conditions/fever/Pages/Fever-and-Your-Baby.aspx | 2026-10-20 已读原文 |
| S9 | AAP HealthyChildren：How to Calm a Fussy Baby（轻摇、嘘声/白噪音、吸吮；撑不住先放下、平静后再回来；"it is never safe to shake, throw, hit, slam, or jerk any child"） | https://www.healthychildren.org/english/ages-stages/baby/crying-colic/pages/calming-a-fussy-baby.aspx | 育儿指南审阅提供，2026-10-20 |
| S10 | AAP HealthyChildren：Good Night, Sleep Tight（防止过热：出汗、头发潮、呼吸快） | https://www.healthychildren.org/English/ages-stages/baby/sleep/Pages/Good-Night-Sleep-Tight.aspx | 育儿指南审阅提供，2026-10-20 |

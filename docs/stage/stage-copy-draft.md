# 哄哄「按月龄阶段提示」中文文案初稿（#30）

> 由 `app/lib/features/stage/stage_copy.dart` 导出，请改那个文件，不要改这里。

## 结果页一行提示

- 单个阶段：「这周宝宝可能在哭闹高峰期」
- 两个阶段重叠：「这周宝宝可能在猛长期，也可能在哭闹高峰期」
- 小字：「每个宝宝不一样，点开看看」

## 日龄窗口和重叠优先级

出生当天为第 0 天。重叠时的优先级：猛长期 > 哭闹高峰期 > 出牙期 > 睡眠模式变化期（最多显示两个名字）。

| 阶段 | 日龄（闭区间） |
|---|---|
| 猛长期 | [7, 10]、[21, 42] |
| 哭闹高峰期 | [14, 121] |
| 出牙期 | [122, 365] |
| 睡眠模式变化期 | [92, 152]、[183, 365] |

## 猛长期

**大致时间**：出生后约 7–10 天、3–6 周

部分宝宝可能出现几天的猛吃期：吃奶更勤、更黏人，哭闹也可能多一点，一般几天就过去。

**可能看到**

- 吃奶次数明显变多，每次吃得更久
- 刚喂完不久又想吃
- 比平时黏人、烦躁

**可以怎么做**

- 看到饥饿信号（咂嘴、转头找奶、吃手）就按需喂，不用等到哭了再喂
- 请家人多分担，喂奶的人抓紧时间休息

**出现这些情况请及时就医**

- 尿布明显变少（尿少）
- 体重不长
- 哭闹和平时不一样，或者好几天都不缓解

**来源**

- 美国儿科学会（AAP）HealthyChildren：[Your Baby's First Month: Growth & Physical Appearance](https://www.healthychildren.org/English/ages-stages/baby/Pages/First-Month-Physical-Appearance-and-Growth.aspx)（2026-04-03 更新）——「Typically, growth spurts happen at around 7 to 10 days old and again between 3 and 6 weeks old.」
- 国家卫生健康委员会办公厅：[婴幼儿喂养健康教育核心信息（国卫办妇幼函〔2020〕649号）](https://www.gov.cn/zhengce/zhengceku/2020-08/01/content_5531915.htm)（2020-07-29）——「按需哺乳，每日8-10次以上；……不应等到婴儿饥饿哭闹时再哺喂。」
- 中国疾病预防控制中心（转载中国营养学会《婴儿喂养指南（0-6个月）》）：[《婴儿喂养指南》（0-6个月）](https://www.chinacdc.cn/jkyj/yyyjk2/jswj13949/201508/t20150817_296900.html)（2015-08-03）——「婴儿异常哭闹时，应考虑非饥饿原因，应积极就医。」

## 哭闹高峰期

**大致时间**：约出生 2 周起，6–8 周前后常最明显，多数 3–4 个月逐渐缓解

这段时间宝宝可能哭得比较多，傍晚和夜里更明显，有时怎么哄都难停下来。很多宝宝都会经历这个阶段，它会过去的。

> ⚠️ **绝不能摇晃宝宝。再累、再着急也不要摇晃，摇晃可能造成严重的脑损伤。**

**可能看到**

- 可能突然哭起来，不太好哄
- 哭的时候脸涨红、握拳、蜷腿，看起来很难受
- 傍晚到夜里哭得更多
- 不哭的时候，吃奶、精神都和平时一样

**可以怎么做**

- 先看看是不是饿了、困了、尿布湿了，或者太冷太热
- 抱着慢慢走动、轻拍、包裹、轻声哼唱或白噪音，都可以试试
- 自己快撑不住时，把宝宝仰卧放进安全的小床，离开几分钟缓一缓，或者请家人接手

**出现这些情况请及时就医**

- 发烧
- 呕吐（尤其是喷射状、绿色或带血）
- 大便带血
- 精神差、嗜睡、不好叫醒
- 哭声和平时明显不一样（特别微弱或特别尖）
- 吃奶不好、体重不长
- 4 个月以后还是这样哭

**来源**

- 美国儿科学会（AAP）HealthyChildren：[Colic Relief Tips for Parents](https://www.healthychildren.org/English/ages-stages/baby/crying-colic/Pages/colic.aspx)（2024-04-22 更新）——「The length of this regular fussing usually peaks at about 3 hours a day by 6 weeks old, and then declines to 1 or 2 hours a day by 3 to 4 months of age.」
- Seattle Children's（PURPLE 项目由美国 National Center on Shaken Baby Syndrome 开发）：[Period of PURPLE Crying](https://www.seattlechildrens.org/health-safety/parenting/purple-education-crying/)（2024-05-02）——「Crying usually begins at 2 weeks of age and increases in the first few months. Most babies reach their peak of crying at 2 months.」
- 中国疾病预防控制中心（转载中国营养学会《婴儿喂养指南（0-6个月）》）：[《婴儿喂养指南》（0-6个月）](https://www.chinacdc.cn/jkyj/yyyjk2/jswj13949/201508/t20150817_296900.html)（2015-08-03）——「婴儿异常哭闹时，应考虑非饥饿原因，应积极就医。」

## 出牙期

**大致时间**：约 6 个月起（4–12 个月开始都正常）

宝宝可能开始出牙了。出牙时可能有点烦躁、睡得不踏实，多数宝宝症状轻，几天就过去。

> ⚠️ **出牙不会引起 38℃ 及以上的发烧。体温 ≥38℃ 时不要当成出牙，请及时就医。**

**可能看到**

- 口水变多
- 爱啃手、啃东西
- 牙龈红肿，碰到会躲
- 比平时烦躁，睡得不太好

**可以怎么做**

- 洗干净手，用手指轻轻按摩牙龈
- 给干净的实心牙胶，或凉的湿毛巾咬一咬
- 不要用含苯佐卡因的出牙凝胶，也不要给宝宝戴琥珀项链之类的饰物

**出现这些情况请及时就医**

- 体温 ≥38℃
- 特别难受、怎么哄都不好，或精神差
- 吃奶明显变少

**来源**

- 英国国家医疗服务体系（NHS）：[Baby teething symptoms](https://www.nhs.uk/baby/babys-development/teething/baby-teething-symptoms/)（2026-05-14 审核）——「Most babies start teething at around 6 months, but others start teething before they are 4 months old and some after 12 months.」
- 美国儿科学会（AAP）HealthyChildren：[When Does Teething Start?](https://www.healthychildren.org/English/ages-stages/baby/teething-tooth-care/Pages/Teething-4-to-7-Months.aspx)（2024-06-26 更新）——「If your baby has a fever higher than 101°F (38.3°C), it's probably not from teething.」
- 国家疾病预防控制局：[告别"小蛀牙"系列之五：保护牙齿，从第一颗开始](https://www.ndcpa.gov.cn/jbkzzx/c100040/common/content/content_1871104464313241600.html)（2024-12-18）——「第一颗乳牙通常在宝宝 6个月左右萌出，到 2岁半左右 20颗乳牙萌出完毕。」

## 睡眠模式变化期

**大致时间**：约 3–5 个月；6 个月以后学新本领时

宝宝的睡眠可能正在变化：3–5 个月睡眠会逐渐变规律；6 个月以后学翻身、坐、爬，或者开始认人、离不开大人，夜醒可能暂时变多。这是发育中的正常变化。

**可能看到**

- 夜里醒得比以前多
- 入睡变难，要抱要哄
- 白天小睡时间不太规律

**可以怎么做**

- 尽量固定睡前流程和上床时间
- 白天多见光、多活动，晚上保持暗和安静
- 宝宝犯困时就放到床上，让宝宝慢慢练习自己入睡

**出现这些情况请及时就医**

- 每天睡眠明显不在推荐范围（卫健委 WS/T 579：0–3 个月 13–18 小时，4–11 个月 12–16 小时）
- 睡觉时打鼾、呼吸不畅或憋气
- 同时发烧，或者哭闹和平时明显不一样

**来源**

- 国家卫生健康委员会（原国家卫生计生委）：[WS/T 579—2017《0岁～5岁儿童睡眠卫生指南》](https://www.nhc.gov.cn/wjw/c100311/201710/3f9da54855444a6b8f49051993a78933.shtml)（2017-10-12 发布）——「从3个月～5个月起，儿童睡眠逐渐规律。推荐睡眠时间：0～3个月 13～18 小时，4～11个月 12～16 小时。」
- 美国儿科学会（AAP）HealthyChildren：[Getting Your Baby to Sleep](https://www.healthychildren.org/english/ages-stages/baby/sleep/pages/getting-your-baby-to-sleep.aspx)（2024-06-04 更新）——「Babies do not have regular sleep cycles until about 4 months of age.」
- Raising Children Network（澳大利亚政府资助）：[Baby sleep patterns at 2-12 months: what to expect](https://raisingchildren.net.au/babies/sleep/understanding-sleep/baby-sleep-2-12-months)（页面未标日期）——「Changes in baby sleep patterns over the first 12 months are developmentally normal.」

## 每个说明面板底部（统一）

- 每个宝宝不一样，早一点、晚一点或者不明显都很常见。
- 早产宝宝请按矫正月龄理解。
- 这里只是按月龄的可能情况，仅供参考，不能替代医生判断。有任何担心，请及时就医。


# 历法与民俗资料

核对日期：2026-09-17。以下计算和条目都在本地完成，不依赖语言模型返回日期。

## 计算边界

- 公历：Foundation `Calendar(identifier: .gregorian)`。
- 农历：Foundation `Calendar(identifier: .chinese)`，同时读取 `.isLeapMonth`；不自行拼装月份、不用近似朔望公式。[Apple Calendar 标识符文档](https://developer.apple.com/documentation/foundation/nscalendar/identifier)
- 首版整个日历固定使用 `Asia/Shanghai`。现代日期对应 UTC+08:00；日界为当地零时。用户更改 Mac 系统时区不会改变农历对应日。日程输入界面也应标明北京时间。
- 年干支、生肖采用农历正月初一换年，不采用八字命理的立春换年。Foundation 中国历 `.year` 为六十年循环中的序号。生肖取该序号对应地支。[香港天文台：天干和地支](https://www.hko.gov.hk/sc/gts/time/stemsandbranches.htm)、[十二生肖](https://www.hko.gov.hk/sc/gts/time/12animals.htm)
- 日干支以香港天文台《2010 年年历》三月页的 **2010-03-15（正月三十）甲子日**为基准，使用公历日差对 60 取模。该页还用于检验 3/1 庚戌、3/16 乙丑、3/30 己卯。按北京时间零时换日；不实现不同命理流派的晚子时换日或真太阳时修正。[月历原页](https://www.hko.gov.hk/tc/gts/astron2010/files/03_2010c.pdf)、[2010 年公农历对照表](https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T2010c.txt)
- 月视图固定 42 格，周一开始，按历法逐日递增，避免用固定秒数跨越历史夏令时。
- 这是一版现代民用日历。已设置 2025–2027 关键日期回归用例；不能将这组抽样验证解释为已经逐日验证所有历史年份。香港天文台也说明远期、接近午夜的新月或节气可能因天文计算精度出现日期差异。[对照表说明](https://www.hko.gov.hk/sc/gts/time/conversion.htm)

## 节气日期表

已逐项核对 **2025–2027 年、共 72 个节气民用日期**。来源是香港天文台发布的公历与农历对照表。香港和北京在这些年份都使用 UTC+08:00，故民用日期一致。首版仅显示日期，不显示交节精确时刻，也不据此推导命理月柱。

| 月份／节气 | 2025 日 | 2026 日 | 2027 日 |
| --- | --- | --- | --- |
| 1 月：小寒／大寒 | 5／20 | 5／20 | 5／20 |
| 2 月：立春／雨水 | 3／18 | 4／18 | 4／19 |
| 3 月：惊蛰／春分 | 5／20 | 5／20 | 6／21 |
| 4 月：清明／谷雨 | 4／20 | 5／20 | 5／20 |
| 5 月：立夏／小满 | 5／21 | 5／21 | 6／21 |
| 6 月：芒种／夏至 | 5／21 | 5／21 | 6／21 |
| 7 月：小暑／大暑 | 7／22 | 7／23 | 7／23 |
| 8 月：立秋／处暑 | 7／23 | 7／23 | 8／23 |
| 9 月：白露／秋分 | 7／23 | 7／23 | 8／23 |
| 10 月：寒露／霜降 | 8／23 | 8／23 | 8／23 |
| 11 月：立冬／小雪 | 7／22 | 7／22 | 7／22 |
| 12 月：大雪／冬至 | 7／21 | 7／22 | 7／22 |

原表：[2025 文本](https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T2025c.txt)／[PDF](https://www.hko.gov.hk/tc/gts/time/calendar/pdf/files/2025.pdf)、[2026 文本](https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T2026c.txt)／[PDF](https://www.hko.gov.hk/tc/gts/time/calendar/pdf/files/2026.pdf)、[2027 文本](https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T2027c.txt)／[PDF](https://www.hko.gov.hk/tc/gts/time/calendar/pdf/files/2027.pdf)。代码表位于 `Sources/LingxiCore/CalendarEngine.swift`。

`solarTerm(on:)` 在无节气和超出覆盖年份时均返回 `nil`；UI 用 `hasSolarTermData(for:)` 区分两者并提示覆盖范围。超出范围不会使用近似公式或 AI 补全。清明在首版作为节气显示，其日期随年度表变化，并非固定公历 4 月 5 日。

扩展年度时必须先核对天文台新年表、补全 24 条日期和边界回归用例，再更新覆盖说明。

## 节日与神诞目录

以下是文化纪念日目录，不是法定放假／调休表。首版不推断放假安排。

| 条目 | 普通农历月日 | 资料来源与地域 |
| --- | --- | --- |
| 春节、元宵 | 1/1、1/15 | [央视网：中国传统节日](https://tv.cctv.cn/special/zgctjr/festivalchina/index.shtml)，中国传统节日 |
| 端午、七夕 | 5/5、7/7 | 同上 |
| 中秋、重阳 | 8/15、9/9 | 同上 |
| 玉皇大帝诞 | 1/9 | [华人庙宇委员会：节诞日期](https://www.ctc.org.hk/zh-hans/festival/)，香港所列庙宇传统 |
| 文昌诞 | 2/3 | 同上 |
| 观音诞（降生纪念） | 2/19 | 同上；该资料区分降生、成道等不同纪念日 |
| 北帝诞 | 3/3 | 同上；另有[长洲北帝庙口述史](https://www.ctc.org.hk/長洲玉虛宮北帝廟/)记录个别年份改期，不能把目录日期当成实际庆典公告 |
| 天后诞 | 3/23 | [香港非物质文化遗产办事处：香港天后诞](https://www.icho.hk/tc/web/icho/representative_list_tin_hau.html)，明确记载社区亦可能另择活动日 |
| 观音成道日 | 6/19 | [华人庙宇委员会：节诞日期](https://www.ctc.org.hk/zh-hans/festival/)，香港所列庙宇传统 |

每条数据保留稳定 `id`、分类、农历日期、简要介绍、地域、来源标题和 URL；介绍为简短自编概述。神诞日期是**相关传统中的纪念日说法**，不是神话人物出生事实的断言。地域和来源需要在详情中一起显示。

首版目录采用普通农历月份，闰月不重复投放同名节日或神诞。这个选择是产品的资料规则，不能表述为所有地区一致的民俗；如要支持闰月庆典，必须添加明确地域、庙宇公告与独立规则。已测试 2025 年 7 月 13 日普通六月十九与 8 月 12 日闰六月十九的区别。

## 不属于本历法核心的内容

民用 CalendarEngine 不生成黄历宜忌、吉凶评分或八字月柱、时柱。v0.3 新增独立 FourPillarsEngine 负责八字四柱与交节时刻，详见[四柱与出生档案说明](bazi-v0.3.md)。它不会覆盖本页描述的民用历法口径。后续引入宜忌必须提供可以核对的具体历书版本、流派与授权，不能把 AI 生成的建议冒充历书事实。

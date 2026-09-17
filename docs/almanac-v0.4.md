# v0.4 万年历：计算范围、传统口径与来源

核对日期：2026-09-17。本页更新 v0.1–v0.3 的节气覆盖说明；旧版 `calendar-sources.md` 中的 2025–2027 静态日期限制已被本地算法替代。公历、农历和民用干支的既有定义不变。

## 三种信息分开

| 信息 | 实现与口径 | 能说明什么 |
| --- | --- | --- |
| 公历、农历、节日对应日期 | Foundation Gregorian/Chinese；Asia/Shanghai；民用零点换日 | 某一民用日期的历法信息。农历干支年和生肖仍在正月初一换年 |
| 二十四节气交界 | 既有 `NativeSolarTermProvider` 的太阳视黄经计算；与 `FourPillarsEngine` 共用结果 | 一个绝对时刻；月历另按北京时间把它标在所在民用日期 |
| 日、时黄历 | 固定 `lunar-swift 1.1.8` 的规则与表格 | 这一版本的传统分类，不是结果预测、统一历书结论或法定放假安排 |

香港天文台介绍二十四节气为太阳黄经每隔 15° 的界点，包含相间的十二「节」与十二「中气」。新 API 同时返回两类，不只返回用于八字换月的十二节。[香港天文台：二十四节气](https://www.hko.gov.hk/tc/gts/time/24solarterms.htm)

公开节气查询范围为 **1901–2099 年**。内部 1900/2100 年只供边界年的前后节查询。2025–2027 年 72 个民用日期继续逐项匹配已有香港天文台原表：[2025](https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T2025c.txt)、[2026](https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T2026c.txt)、[2027](https://www.hko.gov.hk/tc/gts/time/calendar/text/files/T2027c.txt)。这不等于对 199 年每个天文时刻进行独立观测验证；交节时刻应标注「算法计算」，不要显示成官方秒级实测值。远期接近午夜的界点存在计算模型和精度差异。[天文台对照表说明](https://www.hko.gov.hk/sc/gts/time/conversion.htm)

## 新 Core API

```swift
let calendar = CalendarEngine()
let terms = try calendar.solarTerms(in: 2026) // 24 个，按时间排序
let context = try calendar.solarTermContext(at: instant)
// context.previous: <= instant；next: > instant；onDay: 所在日期的节气（可以尚未交节）

let almanac = AlmanacEngine.shared
let day = try almanac.day(on: date)
let hour = try almanac.hour(at: instant)
```

`AlmanacDay` 含宜忌、吉神/凶煞、值神及黄黑道分类、冲煞、喜神/财神/福神/阴阳贵人方位、彭祖百忌、星宿、建除、六曜、候/物候、日禄、胎神、月相名称、年/月/日九星及 13 个日内时段。`AlmanacHour` 含干支、宜忌、值神/吉凶分类、冲煞、方位及当时九星。九星保留数字、颜色、五行、星名以及中乾兑艮离坎坤震巽顺序的九宫分布；不生成评分或命运断语。

- `hours` 包含早子时 00:00–01:00、丑时 01:00–03:00……晚子时 23:00–24:00，共 13 行；区间右端不包含。
- 日黄历用 `getDayYi(sect: 1)`/`getDayJi(sect: 1)`，按民用日干支和**交节日期**对应月建。交节日凌晨与交节后返回同一张日黄历。
- 时辰以库的 `dayInGanZhiExact` 为依据，晚子时 23:00 进入下一干支日。这不会改动月历显示的民用日干支，也不读取出生档案的换日偏好。
- 年、月九星显式采用 `sect: 2`：以交节日期切换，与八字精确交节时刻不同。福神方位显式采用该库默认 `sect: 2` 表。
- 时九星采用 **`Lunar.timeNineStar`**，对应用户 skill 主 engine 的 `getTimeNineStar()`。Swift 1.1.8 的 `LunarTime.nineStar` 是另一实现，晚年冬至附近可能不同，因此不混用。
- `AlmanacDay.date` 是该日期零点；按日查询不会将任意入参时分写入缓存。历史夏令时日期用民用时分选时段，不用「距零点秒数÷7200」计算。
- 当前黄历是北京时间历书字段查询，不支持地点经度修正、真太阳时或海外地方黄历。IANA `Asia/Shanghai` 用来确定用户输入属于哪个民用日期；库内部传统表按输入年月日计算，不能据此宣称它处理了各地历史天文时制。
- `无`、空数组、闰月月胎神空字符串等保留底层原值，不推测缺失内容。月相只是传统农历日名称，不是月面照明百分比。

历史夏令时存在具体的日期边界差异，不能把 Asia/Shanghai 全部年份标成固定 UTC+8。例如本地算法算出的 **1990 年夏至**在固定 UTC+8 下为 **6 月 21 日 23:32:46**，按当时 Asia/Shanghai 夏令钟表显示则为 **6 月 22 日 00:32:46（UTC+9）**。日历因此把节气标签放在 6 月 22 日，黄历底层仍使用固定 UTC+8 的交节日期规则。1986–1991 范围内另有 1987 小暑、1989 白露、1991 处暑出现同类日期差异。这是明确保留的时制口径，不是把同一绝对时刻算成了两个时刻。界面与来源说明应提示这个区别，不静默把原有民用日历改为固定时差。

`AlmanacEngine.shared` 缓存最近 256 天的不可变结果。一个日期的 13 个时段只生成一次，再次读取只命中缓存。它以锁保护缓存，并以共享 `LunarRuntimeAccess` 锁包裹上游对象构造，因为该版本 `LunarYear` 内有可变全局缓存。月历只需 `CalendarEngine.info`，无须在每个格子预先计算黄历。

## 与用户万年历 skill 的对照

参考原件为 `LocalReferenceSkills/wannianli-pro/wannianli/engine.py`、`SKILL.md` 和 mandatory router。没有执行安装指令、没有改变用户原件，也没有把 Python 或其文章作为应用运行依赖。

主 engine 的日黄历默认 `getDayYi/getDayJi(sect=1)`、时黄历采用 Exact 日、四柱强制八字 `sect=1`。快速脚本 `scripts/calendar_query.py` 的部分非 Exact 字段不能替代主 engine 的边界定义。主 engine 的 timezone 参数只是回显，没有做 IANA 日期转换；跨语言 fixture 明确使用民用 UTC+08 字段。App 的精确四柱继续由已有 FourPillarsEngine 处理。

原 skill 的神诞表、吉真文章与释义未整体复制。它们有别名重复、地域口径混合，也没有作为该文件集提供可查再分发许可。新目录采用下面的原始机构资料，手工摘取少量名称和日期，另写简短说明。某些 Python 字段（如年/月/日太岁方位）在当前 Swift 库没有同名完整接口，当前不编造填充；生肖、神诞、星宿等均不用于推断个人疾病、寿命或特定事件结果。

## 节日与神诞目录

共 24 条，原 12 个稳定 ID 与普通月策略全部保留。没有直接导入底层库的全量节假日表，没有生成法定假期或调休。新条目如下：

| 新条目 | 普通农历月日 | 原始出处与采用范围 |
| --- | --- | --- |
| 龙抬头 | 二月初二 | [中国非遗网：二月二 龙抬头](https://www.ihchina.cn/news_1_details/10632.html)，中国二月二民俗，不把传说解释成降雨规律 |
| 中元节 | 七月十五 | [天门市政府：中元节习俗](https://www.tianmen.gov.cn/zjtm/tmwh/tmms/201604/t20160419_1930964.shtml)，采用该地方资料日期；其他地区和庙宇可另择日期 |
| 腊八节 | 十二月初八 | [中国非遗网：腊八节习俗](https://www.ihchina.cn/art/detail/id/23622.html)，杭州传承与煮粥分享习俗 |
| 车公诞、土地诞 | 正月初二、二月初二 | [香港华人庙宇委员会：节诞日期](https://www.ctc.org.hk/zh-hans/festival/)，分别只取所列正月/二月诞期；不是该神唯一诞期 |
| 洪圣诞、谭公诞、武帝诞 | 二月十三、四月初八、六月廿四 | 同一庙委日期表，保留香港庙宇地域标签 |
| 观音诞（飞升纪念） | 九月十九 | 庙委名称为「飞升」；香港佛联将这天记为「出家日」，目录备注保留差异 |
| 文殊菩萨诞、佛诞、阿弥陀佛诞 | 四月初四、四月初八、十一月十七 | [香港佛教联合会 2025 年历](https://www.hkbuddhist.org/editor_upload_image/file/calendar2025.pdf)，PDF 最后一页「佛、菩萨诞期（农历）」表；采用香港汉传佛教纪念日期 |

每条仍有 `region/sourceTitle/sourceURL`。闰月不自动重复纪念日；不把一地当年的实际庆典安排外推为所有地区的固定活动日。比如香港庙委中元法会列「七月十四日前后」，这与天门七月十五条目并非同一活动公告。

## 代码与数据许可

运行库是 [6tail/lunar-swift](https://github.com/6tail/lunar-swift)，固定 1.1.8、commit `a7ec0e9b29f84a5d98b09b9ffd31145f17470d56`。完整 MIT 许可和版权声明在 `Vendor/LunarSwiftRuntime/LICENSE`，来源记录在 `NOTICE.md`；库源码按该 commit 保留。已有节气算法的许可说明沿用 v0.3 文档和相关 Vendor 文件。

网页和宗教机构年历用于核查名称/日期及简短自编概述，不复制全文、版式、照片或第三方商业文章。不将网页公开可读等同于开放许可，也不将这些机构标为应用背书。

## 验证

`CalendarTests` 验证 1901–2099 每年恰有 24 个不同节气、全部 72 个 HKO 民用日期保持一致、24 个节与中气的前/精确/后界点、1901/2099 跨年查询和超范围失败。既有公农历、春节换年、民用零点、闰月及原神诞日期测试保留；新增目录来源、原 ID 保留和闰月不重复测试。

`AlmanacTests` 读取 `Tests/Fixtures/almanac-reference.json`。该 fixture 由用户真正的 `wannianli.engine.build_calendar_day` + 隔离安装的 `lunar_python==1.4.8` 生成，记录原 engine 的 SHA-256。六个合成日期为 1901-01-01、1988-02-15、2025-08-12、2026-02-04、2026-09-17、2099-12-31，每天比较全部 13 时段，覆盖普通日、晚子、闰月、立春日和公开范围两端。比较日时宜忌、神煞、值神、冲煞、五类方位、年/月/日/时九星数字。离线 Swift 测试不依赖用户 skill 或 Python。

此外验证同一民用日缓存不受入参时刻影响、晚子与次日早子干支/宜相接、时段完整不重叠、九宫编号唯一、并发读缓存返回完整快照、非有限日期与范围错误。纯规则验证，不读写用户出生档案、系统日历或提醒事项。

本次独立运行 `CalendarTests|AlmanacTests` 共 19 项全部通过。可重复验证 Python fixture：`python3 Tests/Fixtures/generate-almanac-reference.py`；默认只读比对，只有显式 `--write` 才会重写合成 fixture。

完整项目测试使用 `zsh scripts/test.sh`。独立构建时将脚本中的 scratch path 改为工作区 `build/almanac-v04-check`，并追加 `--filter 'CalendarTests|AlmanacTests'`。

要在已安装隔离依赖的工作区抽查原 engine，可以运行：

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH="$PWD/build/python-reference/site-packages:$PWD/LocalReferenceSkills/wannianli-pro" python3 - <<'PY'
from wannianli.engine import build_calendar_day
r = build_calendar_day(date_text="2026-09-17", time_text="23:00", timezone="Asia/Shanghai")
print(r["huangli"]["day"])
print(r["huangli"]["time"])
print(r["flying_star"]["time"]["number"])
PY
```

# CLI 与 Skill：让自己的 Agent 使用灵性日历（v0.6）

文档路径保留 `cli-v0.5.md`，现已包含 v0.6 新增能力；协议版本仍以 `capabilities` 为准。

本版提供本机 `lingxi` CLI、随应用分发的 Skill、可查询知识和分析回写。运行在这台 Mac 上、能够执行命令的 Agent 可以读取档案和排盘、操作日程、保存日记与解读。应用负责计算与落盘，没有新增内置 Agent 框架、模型调用循环、MCP 或网络服务。

## 开始连接

先打开灵性日历。CLI 随应用放在 `Contents/MacOS/lingxi`，无需安装到系统目录。在本仓库构建后可运行：

```sh
./scripts/build-app.sh
open build/灵性日历.app
build/灵性日历.app/Contents/MacOS/lingxi status
build/灵性日历.app/Contents/MacOS/lingxi capabilities
build/灵性日历.app/Contents/MacOS/lingxi skill path
```

`skill path` 返回随包 `AgentSkill` 目录和 `SKILL.md` 的绝对路径。可以让支持本地 Skill 的 Agent 按其自身加载方式读取该目录；若该 Agent 需要固定技能目录，把整个目录以 `lingxi-calendar` 名称复制过去，同时保留 `references`。应用不会修改 Agent 的全局配置。知识正文通过 CLI 查询，无需把全部资料一次性塞入上下文。

如果 CLI 不在 PATH，提供完整可执行文件路径即可。下文的 `lingxi` 是这一可执行文件的简称。业务命令要求应用正在运行；CLI 不直接改 JSON，也不自动启动应用。`--help` 和 `skill path` 可用于查看帮助和本地随包资源。

从首页、命盘或具体日程点击「交给我的 Agent」，可以复制完整任务说明：CLI 与 Skill 的本机路径、目标日期／档案／日程、北京时间参考时分、读取入口及是否回写日笺。卦象页选择的时分会保留为 `--at HH:mm`。复制仅生成任务文本，没有启动模型或执行写入；将文本发送给自己的 Agent 后，以它实际返回的 CLI 结果核对完成情况。

## 可用能力

| 命令 | 作用 |
| --- | --- |
| `status`、`capabilities` | 查看应用日期、环境、状态和当前接口参数 |
| `profiles list/show/create/update/delete` | 读取与维护出生档案 |
| `chart show --profile ID` | 确定性四柱、候选盘和命盘详情 |
| `luck show --profile ID` | 起运、大运、流年与节月 |
| `strength show --profile ID` | 本地普通扶抑初判、证据、规则版本及实际采用的前提 |
| `hexagrams show --profile ID --date YYYY-MM-DD` | 先后天、年／月／日卦、元堂、当前爻和有效时段 |
| `calendar day --date YYYY-MM-DD` | 农历、节气、黄历和节日来源 |
| `context --profile ID --date YYYY-MM-DD` | 某人的某日组合上下文，含 `nativeStrength`、`strengthBasis` 与 `hexagrams` |
| `events list/show/create/update/delete` | 查询与操作日程 |
| `tasks list/show/complete` | 查询待办（含已完成与无期限），或完成本地待办；恢复通过 `events update` 设置 `isCompleted: false` |
| `journal list/show/create/update/delete` | 日记查询、创建与编辑 |
| `insights list/show/save/delete` | 分析与建议查询、保存和删除 |
| `knowledge search/read` | 按需检索和读取内置知识及已登记的本机资料 |
| `open day/chart/event/journal` | 在 Mac 界面显示对应内容 |

所有业务输出均为 JSON；`capabilities` 是本机安装版本的参数说明。通过 `--input FILE` 或 `--input -` 传 JSON 参数对象，不能传完整请求信封。普通 `--key VALUE` 按字符串传递，只有 `year/month/day/hour/minute/count/limit/offset` 转为整数。出生档案的 `birthYear` 等数值、布尔值、复杂对象和 `null` 使用 JSON 输入或 `--param KEY=JSON`。重复键会报错，不会静默覆盖。

简单读取示例：

```sh
lingxi profiles list
lingxi profiles show --profile PROFILE_ID
lingxi context --profile PROFILE_ID --date 2026-09-20
lingxi strength show --profile PROFILE_ID
lingxi hexagrams show --profile PROFILE_ID --date 2026-09-20 --at 12:00
lingxi knowledge search --query 旺衰
lingxi knowledge read --id strength-analysis
```

替换示例中的 `PROFILE_ID` 为实际返回的档案 ID。多个档案时应明确选择；不根据昵称推断生日或排运性别。

`calendar day`、`context` 与 `hexagrams show` 以 `--date` 和 `--at` 指定 **Asia/Shanghai** 的参考时刻；`at` 默认 `12:00`，可用 `--at 23:30` 查看另一时刻。河洛报告中的自然日按出生档案 IANA 时区零点递进，不跟随八字的 23 点换日选项；节月在精确交节时刻切换。遇到交节，当地同一天可能有两个不同的月卦／日卦，应显示返回的区间，不能宣称全天不变。[完整河洛口径及参考脚本边界修正](heluo-v0.6.md)。

`luck show --profile PROFILE_ID --year 2026` 在大运之外返回该立春流年和十二节月。`events show --id ID` 可直接读取本地事项；Apple 事项需先查询包含它的日期范围，Apple 待办可先运行 `tasks list`。无期限待办不靠日期范围发现，应查询 `tasks list`。

## Skill 怎样分析和回写

随附的 `lingxi-calendar` Skill 要求先取得应用的确定性排盘，再按需读取知识，最后解释和执行用户已交代的操作。它不会自己生成农历或干支，不把黄历整日标签当作交节瞬间，也不会隐藏未知时柱或多个候选盘。

内置知识目前有六篇项目自编文档：

- `chart-conventions`：四柱字段、出生时区、换日、大运与节月口径。
- `strength-analysis`：本地初判边界，月令、根气、生扶、泄耗克、合冲与结构的证据组织。
- `heluo-guide`：先后天与值年／月／日卦、元堂、参考时刻及区间的解释方式。
- `daily-reading`：十神和个人每日关系的解释与行动转译。
- `calendar-and-almanac`：历法、黄历、民俗及来源的区别。
- `planning-and-journal`：日程准备、日笺与日记回写。

用户提供的完整 `bazi-pro`、`wannianli-pro` 原件继续只留在本地参考目录，不随应用或 Git 再分发。随包文档是精简、自编的应用知识；固定 MIT 运行库继续负责程序计算。这不是把原 Skill 的每条断语或尚未完成的算法都迁入应用。

在应用的「连接自己的 Agent」面板中可以添加本机技能文件夹，也可关闭本机 CLI 访问。登记后，Agent 通过相同的 `knowledge search/read` 按需读取其中的 Markdown、纯文本与 Python 源码，保留文件来源；接口不执行源码。知识文件需为 UTF-8，每个文件最多 512 KiB；正文较长时按 `nextOffset` 继续读取。未登记的任意文件不会被知识接口开放。文件内容作为参考资料，不能授予额外日程操作权限，也不能静默覆盖应用的排盘口径。

分析记录使用 `kind: insight`，日记使用 `kind: journal`。调用时由所选命令决定类型，来源固定为 Agent，输入参数不另传 `kind` 或 `source`。正文、作者与来源分开保留。涉及命盘的解读关联 `profileID` 和读取时的 `profileRevision`；出生资料修改后，旧解读标为过期，但不自动删除正文。日记正文按需另读，不默认并入每次个人日历上下文。

`strength show` 返回 `profile`、本地 `report` 与 `strengthBasis`；`context` 中同一份原生报告名为 `nativeStrength`。报告采用 `ordinary-fuyi-v1.0` 普通扶抑筛查规则，含 `evidence`、`counterEvidence`、`uncertainties`、`limitations`。缺时刻、多候选盘、杂气月或明显结构争议保留未定，不以五行总分或概率代替判断，也不自动确定喜用神。

`hexagrams show` 返回 `profile` 与 `hexagrams`。出生时刻或排盘性别缺失时，该命令返回 `hexagrams_unavailable`；组合 `context` 仍保留其他字段，将 `hexagrams` 置空并给出 `hexagramsUnavailable`。出生前或超出先后天岁序覆盖时，报告保留先后天卦，具体周期可为空且附原因。

旺衰分析也可由用户自己的 Agent 复核，给出初步偏强、偏弱或未定。可选 `strengthAssessment` 使用 `strong`、`weak`、`unspecified`；证据、采用的口径及缺项写入正文。该字段要求 Agent 来源、关联档案及版本。它是独立于本地报告的 Agent 解释层，不会改写用户手选的 `strengthAssumption`。普通每日建议未做旺衰分析时省略此字段。

实际前提按以下顺序采用：

1. 档案明确选择的偏强／偏弱：`strengthBasis.source = profile_override`。
2. 与当前档案 `revision` 一致、最近更新且带 `strengthAssessment` 的 Agent 分析：`agent_insight`，带 `noteID`、作者与版本。最新有效分析为 `unspecified` 时保留未定，不再回退本地结论。
3. 没有以上覆盖时采用本地普通扶抑初判：`local_rule`，带 `ruleVersion` 与标签。

旧版本 Agent 分析保留正文但不参与当前解读。本地报告始终可以查询，包括用户手动或 Agent 结论正在优先生效时；不要把 `nativeStrength` 错当成实际生效的前提。

写入示例：先将以下参数保存为 JSON 文件，并替换成实际档案 ID、版本和分析内容，再运行 `lingxi insights save --input /path/to/insight.json --request-id UNIQUE_REQUEST_ID`。不要额外传 `source` 或 `kind`。

```json
{
  "date": "2026-09-20",
  "profileID": "实际档案 UUID",
  "profileRevision": "profiles show 返回的 revision",
  "title": "面试前的日笺",
  "body": "由 Agent 依据实际命盘与面试安排生成的解释、依据和准备清单。",
  "author": "用户所用 Agent 名称"
}
```

保存返回记录 ID 和 `revision`。使用 `insights show --id ID` 查看正文；更新则再次调用 `insights save`，同时提供 `id` 与刚读取的 `revision`。`list` 默认返回摘要，分页参数为 `offset`、`limit`。

CLI 创建或更新的记录标为 Agent 撰写；在窗口中手工编辑后标为用户记录，并移除机器可采用的 `strengthAssessment`，避免修改后的正文继续被当作同一份 Agent 结论。关联档案的分析仍需保留有效版本。

日程的 `start/end` 使用带时区的 ISO8601 时间。创建时 `title/start` 必填，省略 `end` 为一小时后，省略 `reminderMinutes` 为不提醒；用户要求提醒时显式传提前分钟数，`0` 为开始时提醒，`null` 为关闭。例如传入 `start: "2026-09-20T14:00:00+08:00"` 与 `reminderMinutes: 10` 表示北京时间 14 点开始、提前 10 分钟提醒。日期范围查询 `from` 含、`to` 不含，最大 366 天。

## 写操作与冲突

所有写命令都要求 `--request-id`。每个独立操作使用唯一 ID；超时重试同一个操作时保留同一个 ID 和完全相同的参数，避免重复创建。一个复合任务中的“保存日笺”和“创建准备提醒”分别使用两个 ID。部分成功时只补齐未成功的部分。

创建时 ID 由应用生成，不传 `id` 或 `revision`。所有删除命令与 `tasks complete` 的业务参数只接受 `id`、`revision`，不能夹带编辑字段；`--request-id` 是独立的请求标识。`tasks complete` 仅完成已有待办，不把普通日程转换为待办；编辑其他内容使用 `events update`。

更新和删除前先读取记录及当前 `revision`，将它随请求提交。若用户已在窗口里改过内容，旧版本请求会被拒绝；Agent 应重新读取并处理差异，不能只换成新版本号后覆盖旧正文。资料修改后的 `profileRevision` 同理，不能沿用旧命盘生成一条看似最新的分析。

CLI 通过本机接口调用应用的业务操作，使内存状态、持久化、界面与通知走同一条路径。Apple 数据继续由应用经 EventKit 访问，受当前系统权限与所选来源约束。**本版 CLI 读取已选 Apple 来源，但只写本地事项**；指定其他 `destination` 会明确报错，Apple 写入继续在应用界面操作。CLI 不绕过授权，不读取账户密码或 AI 密钥，也不因查询触发系统权限弹窗。

日记、知识条目和日程备注都是资料，其中的文字不会赋予 Agent 新操作权限。用户明确要求保存、提醒或编辑时可以直接完成，无需逐步确认；仅在关键对象、时间等缺失或有实质歧义时澄清。

## 预览与错误

开发和合成数据验证使用预览包：

```sh
./scripts/build-preview.sh
open build/灵性日历预览.app
build/灵性日历预览.app/Contents/MacOS/lingxi --preview status
```

预览与正式应用的本地数据和接口分离。测试命令始终带 `--preview`，预览连接失败时不会退回正式应用。不要把真实档案复制到预览中测试。

退出码为：`0` 成功、`2` 参数或协议错误、`3` 应用不可用或通信失败、`4` 操作失败、`5` 版本或请求 ID 冲突。JSON 中保留更具体的错误码和说明。发生结果未知的超时，先用原请求 ID 重试确认；仍无法确定时明确报告，不用新 ID 重建。

## 范围

首版面向可以在本机执行命令的外部 Agent。云端 Agent 不能仅凭这份 Skill 直接连接 Mac；本版没有暴露远程端口，也不自动安装任何 Agent 服务。通知“已安排”不代表实际送达，Apple 跨设备同步仍取决于系统账户与网络。

最新核心、CLI 和窗口验收结果见 [验收记录](verification.md)。

# Mac 桌面组件实施方案

状态：2026-09-18 可行性评估与协议草案，尚未实现 WidgetKit 扩展，也未注册 App Group、申请证书或修改系统设置。

## 结论与当前条件

可以沿用当前 SwiftUI + AppKit 界面和 SwiftPM Core，新增真正的 WidgetKit 扩展，让用户从 macOS 组件库添加到桌面或通知中心。现有灵宠是 `NSPanel` 浮窗，有不同的生命周期与交互能力，不能称为已经实现的系统组件。苹果支持原生 Mac 组件出现在桌面和通知中心。[WidgetKit 概览](https://developer.apple.com/documentation/widgetkit)

本机只读检查结果：

| 项目 | 检查结果 |
| --- | --- |
| 当前开发目录 | `/Library/Developer/CommandLineTools` |
| SDK | macOS SDK 26.5，包含 WidgetKit、AppIntents、SwiftUI 框架 |
| 完整 Xcode | `/Applications`、`~/Applications` 标准位置未发现 Xcode；当前 `xcodebuild -version` 提示只有 Command Line Tools |
| 当前可见代码签名身份 | `security find-identity -v -p codesigning` 返回 0 个有效身份；未读取私钥或证书个人信息 |
| 当前应用签名 | ad-hoc，`TeamIdentifier=not set` |
| 当前工程 | SwiftPM 库及两个可执行目标；没有 Xcode project、Widget Extension target 或 entitlements |
| 当前打包 | 脚本手工组装 `.app` 并作 ad-hoc 签名，没有内嵌 `.appex` |

SDK 中有框架不等于已具备完整扩展构建、签名和系统发现的验证环境。下一阶段需要安装完整 Xcode，并配置应用与扩展可用的同一开发团队签名。当前不能宣称能交付经组件库实际验证的安装包。

## 第一版组件范围

建议先做一个组件、两种尺寸；设置为只读，点击回到应用相应页面：

- **小尺寸「我的今日」**：公历/农历、今日卦名及六爻、简短主题；清楚显示正午参考口径。资料不全时显示具体缺项及打开档案入口。
- **中尺寸「今日与安排」**：左侧日期与卦，右侧最多两项接下来日程；当天未安排时给出轻量留白提示。提供查看今日、打开某项安排的入口。
- 允许把右侧摘要切换为最近一项倒计时／纪念日；仅使用用户已开启展示的生日，保留自然日与农历调整规则提示，不把组件刷新当作系统通知。
- 尊重主应用配色偏好，但另外适配系统单色/淡化表现、高对比度与较大文本。灵宠可以作为小幅静态装饰，不放持续动画、聊天框或复杂命盘。
- 默认不显示出生日期、日记正文、完整姓名或日程备注。是否显示档案称呼、日程标题，由用户在应用内明确选择；支持只显示时间与“有一项安排”。

首版默认跟随主应用选择的“用于桌面组件的档案”，不要悄悄跟随任何一次临时切换的 UI 档案。之后若确有多档案需求，再用 `AppIntentConfiguration` 提供单个组件的档案选择。macOS 14 已支持 App Intents 组件配置，与本项目最低系统要求一致。[组件配置](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget)、[App Intents 配置的系统要求](https://developer.apple.com/documentation/widgetkit/migrating-from-sirikit-intents-to-app-intents)

## 工程路径

1. 新建薄 Xcode 工程，增加宿主应用和 `LingxingWidgets` Widget Extension 两个目标。宿主沿用现有 `AppDelegate`、`NSHostingView` 与 AppKit 生命周期，不需要为组件把主应用重写成 SwiftUI `App`。
2. 保留 SwiftPM 中的 `LingxiCore` 和 `lingxi` CLI。Xcode 宿主连接本地 Core package，并复用现有 App 源文件及资源。扩展只链接小型共享快照模型，避免依赖 `AppStore`、`NSApplication`、EventKit 权限服务或 CLI socket。
3. 扩展由 Xcode 管理 Info.plist、构建设置、签名及嵌入，随主应用放入 `Contents/PlugIns/*.appex`。现有纯 SwiftPM 脚本继续用于开发和 Core/CLI 检查；有组件的交付包走 Xcode 构建路径。
4. 添加共享模型模块，例如 `LingxiWidgetShared`，内容限 Codable 快照、版本检查、日期标识和导航路由，不引入主应用的状态容器。
5. 新建真正的 WidgetKit `Widget`、`TimelineProvider` 与 SwiftUI entry view。使用 `containerBackground`、系统内容边距，核验背景移除与桌面淡化颜色。

这是针对本工程的建议。苹果的标准起点是在 Xcode 项目添加 Widget Extension target；包含应用首次启动后，组件才会出现在组件库。[创建组件扩展](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)、[桌面组件布局和渲染](https://developer.apple.com/videos/play/wwdc2023/10027/)

## App Group 与签名

建议使用待注册的 `group.com.lingxing.calendar`；这是候选名称，目前没有创建。主应用和扩展都加入同一 App Group，通过 `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` 取得系统管理的共享目录。正式与预览的 bundle identifier、group 和 URL scheme 必须分别配置，预览不得读正式快照。

按 Apple 当前文档，macOS 推荐 `group.` 前缀，该 group 需要出现在相应 provisioning profile 中；macOS 也支持 `<TeamID>.<group name>` 形式，不需要 provisioning profile，但仍校验签名团队，且不跨到 iOS 等平台。后者不是让无团队 ad-hoc 签名替代有效签名的办法。[现有 macOS 应用的 App Group 访问](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)

主应用当前未启用 App Sandbox。不能为了添加组件直接开启整个主应用沙盒，从而意外破坏现有外部 Skill 文件访问、CLI socket 和数据位置。应使用扩展模板适当的沙盒设置，并为宿主配置 App Group；Apple 支持未启用 App Sandbox 的 macOS 应用使用组容器。第一版只导出组件快照，保留主数据现有位置，不做隐式数据迁移。[App Group 设置](https://developer.apple.com/documentation/xcode/configuring-app-groups)、[macOS 组容器与非沙盒应用](https://developer.apple.com/documentation/xcode/protecting-local-app-data-using-containers)

公开分发时，再验证 Developer ID 签名、嵌套扩展签名和公证。当前脚本的 ad-hoc 签名不能作为这些检查的替代；也不能仅给外层 `.app` 补签后就认定扩展可运行。[macOS 分发签名](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)

## 共享快照 v1 草案

**单一写入者是主应用，组件只读。** 每次日程保存、档案更新、组件档案选择改变、授权来源变化、配色变化后，主应用生成下一段时间的精简快照，原子替换组容器内固定文件 `WidgetSnapshots/current-v1.json`。完整写入成功后才请求刷新对应 widget kind。组件不直接读写原有 `events.json`、`profiles.json`、`notes.json`，也不启动应用 CLI。

建议协议字段：

| 字段 | 含义 |
| --- | --- |
| `schemaVersion` | 固定为 1；不支持的版本显示需更新应用 |
| `revision`、`generatedAt` | 快照标识及生成瞬间，不是用户可写业务 revision |
| `coverageStart`、`coverageEnd` | 预计算数据覆盖区间，开始含、结束不含 |
| `calendarTimeZone` | 初版固定 `Asia/Shanghai`，与主日历日期一致 |
| `profileID`、`profileRevision` | 指定档案标识和生成时版本；无档案时为 null，不包含出生信息 |
| `displayName` | 用户允许显示的称呼，可为 null |
| `theme` | 已选主色、副色及单色/双色样式，使用受限枚举 |
| `sourceUpdatedAt`、`sourceState` | 日程来源最后同步时间及权限/错误状态，避免把旧快照说成实时同步 |
| `entries[]` | 按绝对生效时间排序的展示记录；数量、文本长度和文件大小有上限 |

每个 entry 包含：

- `effectiveAt`、`expiresAt`：本 entry 的绝对有效区间。
- `calendarDate`：主日历的严格 `YYYY-MM-DD`。
- `referenceInstant`：个人解释/卦象实际使用的绝对参考瞬间。初版沿用主页的北京时间 12:00，组件文字不能暗示它是“现在这一分钟”的卦。
- `lunarLabel`、`dayGanzhi`、可选 `solarTerm`：主应用可靠算法产生的展示事实。
- 可选 `hexagram`：卦序、卦名、六爻数组、当前爻、方法版本、卦所属日期及其时区/有效区间；字段缺失时包含可读原因，不补造。
- 可选 `strength`：本地初判或有效覆盖来源的简短标签、来源和版本，不显示确定吉凶。
- `agenda[]`：最多两项显示记录，带事项 ID、**本次 occurrenceStart**、结束时间、可选标题和只读状态。本地重复事件不能只用原始系列起始时间链接。
- 可选 `milestone`：用户选择展示的下一项倒计时，包含脱敏标题、目标日期、剩余自然日和规则提示，不包含生日原始年份。
- `navigation`：允许的打开页面及相应记录 ID；不包含脚本、任意文件路径或写入操作。

建议先预计算未来 7 天；以本地民用日边界切换日历和“正午参考”记录，以已知日程的起止点更新“接下来”。使用 Calendar 的日期运算，不用固定 `+86400` 代替跨夏令时的自然日。`effectiveAt` 与用于计算卦的 `referenceInstant` 分开，防止把当地前一日的河洛日卦误标成主日历同一天。档案时区不同于日历时区时同时展示河洛日期/时区。

组件加载时先校验版本、区间、排序、六爻数量和 ID；读取失败或覆盖过期，显示“打开应用更新”，不把昨天的卦继续标成今日。不保留日记正文、Agent 对话或出生原始档案作为过期兜底。单个快照建议不超过 256 KiB，原子替换失败时保留上一份完整文件并记失败状态。

这份协议尚未实现。其设计使应用退出时，系统仍能展示预计算的未来记录；超出覆盖期则诚实显示需要更新。

## 刷新与交互边界

WidgetKit 扩展不是持续运行的小应用。主应用应提前准备 timeline，并在内容变化时调用 `WidgetCenter.shared.reloadTimelines(ofKind:)`。系统管理刷新预算和实际调度，不能把“请求刷新”说成马上刷新，更不能依赖组件准时发提醒。当前通知服务继续负责提醒。[TimelineProvider](https://developer.apple.com/documentation/widgetkit/timelineprovider)、[保持组件更新](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)

第一版不在组件里完成或编辑待办，只点击导航。第二阶段若要加入完成按钮，使用 App Intents，先把“完成指定待办”抽为跨进程可调用的命令服务，保持原有 revision 校验、幂等语义及 Apple 来源权限规则。普通 AppIntent 默认可能在扩展进程执行，不能直接假定能拿到主应用内存中的 AppStore，也不能通过第二套 JSON 写入绕开它。真正需要打开应用的交互使用 `Link`/`widgetURL`，不伪装成后台完成动作。[组件交互与 App Intents](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)

## 只导航 deep link v1 草案

正式 scheme 建议 `lingxi`，预览使用 `lingxi-preview`，均尚未注册。使用 `URLComponents` 构建并校验 query，不拼接未转义文本。示意路由：

```text
lingxi://widget/day?v=1&date=2026-09-18&at=12:00&profile=<UUID>
lingxi://widget/hexagrams?v=1&date=2026-09-18&at=12:00&profile=<UUID>
lingxi://widget/event?v=1&id=<UUID>&occurrenceStart=<ISO8601>
```

主应用在 Info.plist 注册 scheme，由 AppKit 的 `application(_:open:)` 接收。冷启动期间先排队，等 AppStore/窗口就绪后再导航。复用 `store.select` 保持月历、选中日期和系统来源刷新一致；卦路由必须同时保留参考时刻。

严格限定 scheme、host `widget`、三个 path、版本与参数；拒绝重复键、畸形 UUID、无时区的 ISO8601 和越界日期。档案已删除或事项不再存在时显示失效提示，不能静默改为另一个档案。外部来源权限撤回时不在链接处理器弹授权或写入。链接只打开页面，不据 URL 创建/完成/删除事项，不执行命令。组件点击打开应用是 Apple 支持的导航方式。[组件导航策略](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)

## 落地顺序与验收

1. 补齐完整 Xcode 和可用团队签名，建立宿主/扩展目标；确认签名和 group 配置只限本项目。
2. 先实现快照导出、严格读取及 deep-link parser，使用合成档案/日程测试正常、缺项、未知版本、部分写入、过期及重复事件。
3. 实现小/中组件，安装后首次启动宿主，在 macOS 桌面组件库验证发现、添加、删除和重启后保持。
4. 验证主应用关闭、Mac 睡眠/唤醒、午夜、节气交界、不同出生时区、权限撤回及档案删除；检查组件跳转到正确日期、时刻、档案和事件 occurrence。
5. 验证单色/双色、系统淡化、暗背景、高对比度、VoiceOver 和不同 MacBook 缩放。命理说明保持初判/传统解释与现实安排的区分。
6. 在 CI 增加扩展编译检查；无签名凭据的 CI 只能证明编译，不能声称通过本机组件发现与分发签名。真实签名、公证和系统交互另列验收。

本评估未修改源代码、执行 Widget 构建、登录 Apple 账户或修改证书权限，以上步骤均为下一阶段方案。

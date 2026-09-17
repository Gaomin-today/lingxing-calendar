import Foundation

public struct ParsedEvent: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var durationMinutes: Int
    public var notes: String
    public var repeatRule: String
    public var reminderMinutes: Int

    public init(title: String, start: Date, durationMinutes: Int = 60, notes: String = "", repeatRule: String = "none", reminderMinutes: Int = 10) {
        self.title = title
        self.start = start
        self.durationMinutes = durationMinutes
        self.notes = notes
        self.repeatRule = repeatRule
        self.reminderMinutes = reminderMinutes
    }
}

public enum ParseResult: Equatable, Sendable {
    case event(ParsedEvent)
    case needsClarification(String)
    case notAnEvent
}

/// A deliberately bounded offline parser. Calendar facts never come from a language model.
public struct NaturalLanguageParser: Sendable {
    public init() {}

    public func parse(_ text: String, now: Date = Date()) -> ParseResult {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return .notAnEvent }
        guard input.count <= 1_000 else { return .needsClarification("请用一句较短的话描述一件日程，包括日期、时间和名称。") }
        let explicitIntent = input.matches("提醒我|提醒一下|帮我.*(?:安排|创建|添加|新建|记录|记下)|(?:安排|创建|添加|新建).*(?:日程|会议|提醒)|记一下|记得|设置.*提醒|定个")
        if input.matches("取消|删除|改到|改成|修改|推迟|提前到|挪到|查看|查询|查一下") {
            return .notAnEvent
        }
        if !explicitIntent && input.matches("[?？]|怎么样|如何|好吗|好不好|适合|会不会|要不要|运势|算卦|占卜|抽签|塔罗|宜忌|聊聊|有空|有什么|有哪些|有几个") {
            return .notAnEvent
        }
        let temporalCue = input.matches("今天|明天|后天|大后天|每[天日周]|周[一二三四五六日天]|星期[一二三四五六日天]|礼拜[一二三四五六日天]|[零〇一二两三四五六七八九十0-9]+月|[0-9]{4}[-/]|[零〇一二两三四五六七八九十0-9]+[点时]|[0-9]+[:：][0-9]+")
        guard explicitIntent || temporalCue else { return .notAnEvent }

        if input.contains("农历") || input.contains("阴历") {
            return .needsClarification("农历日期需要先核对对应的公历日期。请在日历中选中那一天，或告诉我公历日期和具体时间。")
        }
        if input.matches("北京时间|上海时间") == false && input.matches("纽约|伦敦|东京|洛杉矶|旧金山|时区|UTC|GMT|美国时间|日本时间") {
            return .needsClarification("当前日程按北京时间（Asia/Shanghai）记录。请先换算为北京时间，并告诉我日期和时间。")
        }
        if input.matches("下下(?:周|星期|礼拜)|下个?月|月底|月末|年末|过[零〇一二两三四五六七八九十0-9]+天|[零〇一二两三四五六七八九十0-9]+天后") {
            return .needsClarification("请把相对日期换成明确的公历日期，例如“10月5日下午三点开会”。")
        }
        if input.matches("每隔|隔周|每个?月|每年|每个?工作日|仅工作日") {
            return .needsClarification("第一版支持单次、每天或每周重复。请先用这三种方式安排，其他重复规则需要逐次添加。")
        }

        var work = input
        var reminder = 10
        let numberPattern = "[零〇一二两三四五六七八九十百0-9]+"
        let reminderMatches = work.matchGroups("提前\\s*(\(numberPattern))\\s*(分钟|小时)\\s*(?:提醒我|提醒一下|提醒)?")
        if reminderMatches.count > 1 {
            return .needsClarification("请指定一个提醒时间，例如“提前 10 分钟提醒”。")
        }
        if let match = reminderMatches.first {
            guard let amount = Self.number(match[1]), amount >= 0, amount <= 10_080 else {
                return .needsClarification("请用明确的分钟数设置提醒，例如“提前 10 分钟提醒”。")
            }
            reminder = amount * (match[2] == "小时" ? 60 : 1)
            guard reminder <= 10_080 else { return .needsClarification("第一版支持最多提前 7 天提醒，请缩短提醒间隔。") }
            work = work.replacingOccurrences(of: match[0], with: " ")
        }
        if work.matches("不(?:用|要)?提醒|关闭提醒") {
            reminder = -1
            work = work.replacingRegex("不(?:用|要)?提醒|关闭提醒", with: " ")
        }

        var duration = 60
        let durationMatches = work.matchGroups("(?:持续|时长(?:为)?|共)\\s*(\(numberPattern)|半|一个|两个)\\s*(小时|分钟)")
        if durationMatches.count > 1 { return .needsClarification("请只设置一个日程时长。") }
        if let match = durationMatches.first {
            let amount = match[1] == "半" ? 0.5 : Double(Self.number(match[1].replacingOccurrences(of: "个", with: "")) ?? -1)
            guard amount > 0 && amount <= (match[2] == "小时" ? 24 : 1_440) else {
                return .needsClarification("日程时长需在 1 分钟至 24 小时之间，请说明具体时长。")
            }
            duration = Int(amount * (match[2] == "小时" ? 60 : 1))
            guard duration > 0 && duration <= 1_440 else { return .needsClarification("日程时长需在 1 分钟至 24 小时之间，请说明具体时长。") }
            work = work.replacingOccurrences(of: match[0], with: " ")
        }
        if work.matches("持续|时长|提前[零〇一二两三四五六七八九十0-9]") {
            return .needsClarification("暂时无法识别时长或提醒间隔。请使用整数分钟，例如“持续 90 分钟，提前 10 分钟提醒”。")
        }

        let daily = work.matches("每天|每日")
        let weekly = work.contains("每周") || work.contains("每星期") || work.contains("每礼拜")
        if daily && weekly { return .needsClarification("这件事是每天重复，还是每周重复？") }
        let repeatRule = daily ? "daily" : (weekly ? "weekly" : "none")

        let timePattern = "(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|晚间|夜里)?\\s*(?<![零〇一二两三四五六七八九十0-9])([零〇一二两三四五六七八九十0-9]{1,3})\\s*(?:([:：])\\s*([0-9]{1,2})|(?:点|时)\\s*(半|一刻|三刻|[零〇一二两三四五六七八九十0-9]{1,3}分?)?)(?![零〇一二两三四五六七八九十0-9])"
        let times = work.matchGroups(timePattern)
        guard !times.isEmpty else {
            return .needsClarification("你想安排在几点？请补充具体时间，例如“明天下午三点开会”。")
        }
        guard times.count == 1 else {
            return .needsClarification("我看到了多个时间。请一次安排一件事，并用“持续 60 分钟”说明时长，例如“明天下午三点开会，持续 60 分钟”。")
        }
        let time = times[0]
        guard var hour = Self.number(time[2]), hour >= 0 && hour <= 23 else {
            return .needsClarification("小时需在 0 至 23 之间，请重新说明时间。")
        }
        let period = time[1]
        let colonTime = !time[3].isEmpty
        var minute = 0
        if colonTime {
            minute = Int(time[4]) ?? -1
        } else if !time[5].isEmpty {
            switch time[5] {
            case "半": minute = 30
            case "一刻": minute = 15
            case "三刻": minute = 45
            default: minute = Self.number(time[5].replacingOccurrences(of: "分", with: "")) ?? -1
            }
        }
        guard (0...59).contains(minute) else { return .needsClarification("分钟需在 0 至 59 之间，请重新说明时间。") }
        switch period {
        case "凌晨", "早上", "早晨", "上午":
            guard hour < 12 else { return .needsClarification("上午或凌晨的时间有些歧义，请用 24 小时制说明，例如 00:00 或 11:00。") }
        case "中午":
            if hour == 1 || hour == 2 { hour += 12 }
            guard (11...14).contains(hour) else { return .needsClarification("请用 24 小时制说明中午的具体时间，例如 12:30。") }
        case "下午":
            if (1...11).contains(hour) { hour += 12 }
            guard hour >= 12 else { return .needsClarification("请用 24 小时制说明下午的具体时间，例如 15:00。") }
        case "傍晚", "晚上", "晚间", "夜里":
            guard hour != 0 && hour != 12 else { return .needsClarification("午夜可能跨日，请明确公历日期并使用 00:00。") }
            if hour < 12 { hour += 12 }
        default:
            if !colonTime && (1...11).contains(hour) {
                return .needsClarification("你说的\(time[2])点是上午还是下午？也可以用 24 小时制，例如 15:00。")
            }
        }
        work = work.replacingOccurrences(of: time[0], with: " ")

        let calendar = Self.calendar
        let today = calendar.startOfDay(for: now)
        var day: Date?
        var dateTokens: [String] = []
        var hasExplicitDate = false
        var repeatingWeekday: Int?

        let isoDates = work.matchGroups("(?<![0-9])([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2})(?![0-9])")
        for match in isoDates {
            guard let parsed = Self.validDate(year: Int(match[1])!, month: Int(match[2])!, day: Int(match[3])!) else {
                return .needsClarification("这个公历日期不存在，请检查月份和日期。")
            }
            day = parsed
            dateTokens.append(match[0])
            hasExplicitDate = true
        }
        let chineseDates = work.matchGroups("(?:(今年|明年|[0-9]{4}年)\\s*)?([零〇一二两三四五六七八九十0-9]{1,3})月([零〇一二两三四五六七八九十0-9]{1,3})[日号]?")
        for match in chineseDates {
            var year = calendar.component(.year, from: now)
            if match[1] == "明年" { year += 1 }
            else if match[1].hasSuffix("年"), let explicitYear = Int(match[1].dropLast()) { year = explicitYear }
            guard let month = Self.number(match[2]), let monthDay = Self.number(match[3]),
                  let parsed = Self.validDate(year: year, month: month, day: monthDay) else {
                return .needsClarification("这个公历日期不存在，请检查月份和日期。")
            }
            day = parsed
            dateTokens.append(match[0])
            hasExplicitDate = true
        }
        for match in work.matchGroups("大后天|后天|明天|今天") {
            let offset = ["今天": 0, "明天": 1, "后天": 2, "大后天": 3][match[0]]!
            day = calendar.date(byAdding: .day, value: offset, to: today)
            dateTokens.append(match[0])
            hasExplicitDate = true
        }
        let weekdays = work.matchGroups("(下|本|这|每)?(?:周|星期|礼拜)([一二三四五六日天])")
        for match in weekdays {
            let target = ["一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6][match[2]]!
            let current = (calendar.component(.weekday, from: today) + 5) % 7
            let offset = target - current + (match[1] == "下" ? 7 : 0)
            day = calendar.date(byAdding: .day, value: offset, to: today)
            dateTokens.append(match[0])
            if match[1] == "每" { repeatingWeekday = target }
            else { hasExplicitDate = true }
        }
        if dateTokens.count > 1 { return .needsClarification("我看到了多个日期。请明确这次日程的开始日期。") }
        for token in dateTokens { work = work.replacingOccurrences(of: token, with: " ") }
        if weekly && day == nil { return .needsClarification("你想每周几安排？例如“每周三下午三点开会”。") }
        if daily && day == nil { day = today }
        guard let chosenDay = day else { return .needsClarification("你想安排在哪一天？请告诉我日期，例如“明天下午三点开会”。") }
        guard var start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: chosenDay) else {
            return .needsClarification("暂时无法识别这个时间，请使用“2026-09-18 15:00 开会”这样的格式。")
        }
        if start <= now {
            if repeatingWeekday != nil && !hasExplicitDate {
                start = calendar.date(byAdding: .day, value: 7, to: start)!
            } else if daily && !hasExplicitDate {
                start = calendar.date(byAdding: .day, value: 1, to: start)!
            } else {
                return .needsClarification("这个时间已经过去了。请确认要安排的未来日期和时间，我不会自动把它移到下一天或下一年。")
            }
        }

        work = work.replacingRegex("每天|每日|每周|每星期|每礼拜|北京时间|上海时间", with: " ")
        work = work.replacingRegex("\\s+", with: " ")
        let prefix = "^(?:请|麻烦|帮我|给我|替我|我要|我想|记得|记一下|记录一下|记下|提醒一下|提醒我|安排一下|安排|创建|添加|新建|设置|定个|一个|一场|一次|个|在|于|的|日程[:：]?|提醒[:：]?|\\s)+"
        work = work.replacingRegex(prefix, with: "")
        work = work.replacingRegex("(?:提醒我|提醒一下|提醒|[，,。；;\\s])+$", with: "")
        work = work.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "，,。；;：:、")))
        if work.isEmpty || work == "日程" || work == "提醒" {
            return .needsClarification("这个时间要做什么？请告诉我日程名称，例如“开会”或“面试”。")
        }
        return .event(ParsedEvent(title: work, start: start, durationMinutes: duration, repeatRule: repeatRule, reminderMinutes: reminder))
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2
        return calendar
    }

    private static func validDate(year: Int, month: Int, day: Int) -> Date? {
        guard (1900...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return parts.year == year && parts.month == month && parts.day == day ? date : nil
    }

    private static func number(_ value: String) -> Int? {
        if let arabic = Int(value) { return arabic }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if value.count == 1, let first = value.first, let digit = digits[first] { return digit }
        if value.contains("十") {
            let parts = value.split(separator: "十", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let tens = parts[0].isEmpty ? 1 : (parts[0].count == 1 ? digits[parts[0].first!] : nil),
                  let ones = parts[1].isEmpty ? 0 : (parts[1].count == 1 ? digits[parts[1].first!] : nil) else { return nil }
            return tens * 10 + ones
        }
        return nil
    }
}

public struct AdviceContent: Equatable, Sendable {
    public var fact: String
    public var tradition: String
    public var action: String

    public init(fact: String, tradition: String, action: String) {
        self.fact = fact
        self.tradition = tradition
        self.action = action
    }
}

public struct AdviceEngine: Sendable {
    public init() {}

    public func advice(for title: String, on date: Date) -> AdviceContent {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        let fact = "\(formatter.string(from: date))，按北京时间显示。农历、节气和节日请以日历中经过计算与来源标注的信息为准。"
        if title.matches("面试|应聘|求职") {
            return AdviceContent(fact: fact, tradition: "民间有在重要事情前讨个好彩头的习惯。若你喜欢，可以带一件让自己安心的小物；这只是个人仪式，不代表面试结果。这里未查询当日黄历宜忌。", action: "提前核对地点或会议链接；准备 1 分钟自我介绍和 2 个具体项目案例；列出想问对方的 3 个问题，并预留 15 分钟缓冲。")
        }
        if title.matches("出行|出发|出差|旅行|旅游|飞机|航班|高铁|火车|机场|车站") {
            return AdviceContent(fact: fact, tradition: "“出入平安”是常见的祝愿。各地出行习俗不同，你可以把出发前的整理当作安心仪式；此处不据时辰判断行程吉凶，也不替代天气和交通信息。", action: "出发前确认车次或航班、证件与目的地地址；查看实际天气和交通，给换乘留出缓冲；把行程告诉信任的人，并备好充电设备。")
        }
        if title.matches("签约|签合同|合同|签署") {
            return AdviceContent(fact: fact, tradition: "传统生活中有人为签约选择“好日子”，但不同黄历与地区说法可能不同。第一版没有据来源核验的当日宜忌，不据此给出吉凶或成败判断。", action: "逐项核对主体名称、金额、付款节点、交付标准与退出条件；把口头承诺写清楚，保留完整文本。看不懂或重要的条款，先请具备相应资格的专业人士核实。")
        }
        if title.matches("开会|会议|例会|沟通|汇报|讨论") {
            return AdviceContent(fact: fact, tradition: "可以借“和气”这一传统寄意提醒自己认真倾听，把它作为沟通前的心理准备；这不是当日宜忌，也不保证交流结果。", action: "会前发出议题与期望结论，准备需要共同决定的问题；开始时确认时长，结束前记下每项行动的负责人和截止时间。")
        }
        return AdviceContent(fact: fact, tradition: "民俗中的择日与祈愿可以作为整理心绪的仪式；地区与传承各有不同。这里不生成没有来源的宜忌，也不承诺预测结果。", action: "写下这件事最想完成的一步，提前准备需要的材料，并留出 10 至 15 分钟缓冲。若安排太满，先保留最重要的一件事。")
    }

    public func reply(to text: String, on date: Date, eventTitles: [String]) -> String {
        if text.matches("算卦|占卜|抽签|塔罗|运势|吉凶|命运") {
            return "我们可以把这个话题当作民俗与自我探索。我现在没有进行卦象计算，也不能预测结果。先想一件最在意的事：你期待什么、担心什么、有哪些信息还没确认？从中选一个今天能做的小行动。你最想聊的是哪一件事？"
        }
        if text.matches("难过|焦虑|紧张|伤心|压力|心事|烦|孤独|累") {
            return "听起来你现在有些不轻松。可以先把安排放缓一点，喝口水，给自己几次慢呼吸。你愿意从最让你挂心的那件事说起吗？我可以陪你把它拆成眼前能处理的一小步。"
        }
        if text.matches("取消|删除|修改|改到|改成|推迟") {
            return "请在日历里打开对应日程，选择编辑或删除。第一版聊天可以创建日程，暂时不会自动修改或删除已有安排。"
        }
        if text.matches("安排|日程|计划|提醒|有什么|有哪些") {
            if eventTitles.isEmpty {
                return "当前选中日期还没有日程。你可以说“提醒我明天下午三点开会”；我会先展示识别出的日期和时间，再由你确认保存。"
            }
            return "当前选中日期的安排：\(eventTitles.joined(separator: "、"))。可以选中一项查看准备建议，也可以告诉我一个带有日期和时间的新安排。"
        }
        if text.matches("建议|准备|面试|签约|出行|开会|会议") {
            let content = advice(for: text, on: date)
            return "行动建议：\(content.action)\n\n传统说法：\(content.tradition)"
        }
        if text.matches("节日|神诞|诞辰|节气|农历|习俗") {
            return "请先在日历中选中你想了解的日期，查看节日卡片及来源。神诞与习俗可能因地区和传承不同；没有核验来源的内容，我不会补成确定的日期或禁忌。"
        }
        return "我在。你可以和我聊聊眼前的心事，也可以说“提醒我明天下午三点开会”，或选中日期、日程查看准备建议。当前是本地助手模式，所有时间都按北京时间处理。"
    }
}

private extension String {
    func matches(_ pattern: String) -> Bool { range(of: pattern, options: .regularExpression) != nil }

    func replacingRegex(_ pattern: String, with replacement: String) -> String {
        replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }

    func matchGroups(_ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = self as NSString
        return regex.matches(in: self, range: NSRange(location: 0, length: source.length)).map { result in
            (0..<result.numberOfRanges).map { index in
                let range = result.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
        }
    }
}

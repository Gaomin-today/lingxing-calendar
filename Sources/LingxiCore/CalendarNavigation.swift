import Foundation

/// Date parsing and period movement shared by the calendar UI and external clients.
/// All returned dates use the app's civil calendar (Asia/Shanghai) and are clipped
/// to the solar-term coverage supported by the app.
public struct CalendarNavigation: Sendable {
    public enum Period: String, Codable, CaseIterable, Sendable {
        case year, month, week, day
    }

    public enum Error: Swift.Error, Equatable, LocalizedError, Sendable {
        case invalidDate(String)
        case unsupportedDate

        public var errorDescription: String? {
            switch self {
            case .invalidDate(let value): return "无法识别日期“\(value)”，请使用 YYYY-MM-DD、YYYY/M/D 或 YYYY年M月D日。"
            case .unsupportedDate: return "日期仅支持 1901-01-01 至 2099-12-31。"
            }
        }
    }

    public static let supportedYears = 1901...2099
    public let calendar: Calendar

    public init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = 2
        self.calendar = calendar
    }

    /// Parses an explicit civil date or the Chinese relative words 今天、明天、昨天.
    /// Separators are intentionally strict so a typo cannot silently become another day.
    public func parseDate(_ input: String, relativeTo reference: Date = Date()) throws -> Date {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = calendar.startOfDay(for: reference)
        if value == "今天" { return try checked(base) }
        if value == "明天" { return try checked(calendar.date(byAdding: .day, value: 1, to: base)!) }
        if value == "昨天" { return try checked(calendar.date(byAdding: .day, value: -1, to: base)!) }

        let patterns = [
            #"^(\d{4})-(\d{1,2})-(\d{1,2})$"#,
            #"^(\d{4})/(\d{1,2})/(\d{1,2})$"#,
            #"^(\d{4})年(\d{1,2})月(\d{1,2})日$"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = expression.firstMatch(in: value, range: range), match.numberOfRanges == 4 else { continue }
            let numbers = (1..<4).compactMap { index -> Int? in
                guard let partRange = Range(match.range(at: index), in: value) else { return nil }
                return Int(value[partRange])
            }
            guard numbers.count == 3 else { break }
            guard let date = calendar.date(from: DateComponents(year: numbers[0], month: numbers[1], day: numbers[2])) else {
                throw Error.invalidDate(value)
            }
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            guard components.year == numbers[0], components.month == numbers[1], components.day == numbers[2] else {
                throw Error.invalidDate(value)
            }
            return try checked(date)
        }
        throw Error.invalidDate(value)
    }

    /// Moves a date by a calendar period. Month and year movement preserve the
    /// original day where possible and clamp 31st to the destination month's end.
    public func shift(_ date: Date, by amount: Int, period: Period) throws -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { throw Error.invalidDate("\(date)") }
        var target: Date?
        switch period {
        case .day:
            target = calendar.date(byAdding: .day, value: amount, to: date)
        case .week:
            target = calendar.date(byAdding: .day, value: amount * 7, to: date)
        case .month:
            target = dateByAddingMonthOrYear(.month, amount: amount, year: year, month: month, day: day, time: components)
        case .year:
            target = dateByAddingMonthOrYear(.year, amount: amount, year: year, month: month, day: day, time: components)
        }
        guard let target else { throw Error.invalidDate("\(date)") }
        return try clipped(target)
    }

    private func dateByAddingMonthOrYear(_ component: Calendar.Component, amount: Int, year: Int, month: Int, day: Int, time: DateComponents) -> Date? {
        guard let anchor = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        guard let moved = calendar.date(byAdding: component, value: amount, to: anchor) else { return nil }
        let destination = calendar.dateComponents([.year, .month], from: moved)
        guard let y = destination.year, let m = destination.month,
              let range = calendar.range(of: .day, in: .month, for: moved) else { return nil }
        let clampedDay = min(day, range.count)
        return calendar.date(from: DateComponents(year: y, month: m, day: clampedDay,
                                                   hour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0))
    }

    private func checked(_ date: Date) throws -> Date {
        let year = calendar.component(.year, from: date)
        guard Self.supportedYears.contains(year) else { throw Error.unsupportedDate }
        return date
    }

    private func clipped(_ date: Date) throws -> Date {
        let lower = calendar.date(from: DateComponents(year: 1901, month: 1, day: 1))!
        // Navigation is civil-date based. Keep the supported upper bound at
        // the beginning of the final day so clipping never manufactures a
        // time-of-day that was not in the input.
        let upper = calendar.date(from: DateComponents(year: 2099, month: 12, day: 31))!
        if date < lower { return lower }
        if date > upper { return upper }
        return date
    }
}

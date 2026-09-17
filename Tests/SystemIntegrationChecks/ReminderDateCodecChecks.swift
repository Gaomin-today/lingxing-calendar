import Foundation
import LingxiCore

/// Run with `zsh scripts/test-apple-codec.sh` from the repository root.
/// The executable links the actual bridge but never initializes EventKit or
/// accesses user calendars, reminders, preferences, notifications, or files.
@main
enum ReminderDateCodecChecks {
    static func main() {
        var beijingCalendar = Calendar(identifier: .gregorian)
        beijingCalendar.timeZone = CalendarEngine.timeZone
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

        // Providers may retain a zone on components that have no clock time.
        // A civil date still needs to appear on that date in the app calendar.
        var civil = DateComponents(year: 2026, month: 9, day: 17)
        civil.timeZone = losAngeles
        let displayedDate = SystemReminderDateCodec.date(from: civil)!
        require(beijingCalendar.component(.day, from: displayedDate) == 17,
                "date-only deadline retains its civil day")
        require(beijingCalendar.component(.hour, from: displayedDate) == 0,
                "date-only deadline displays at Beijing midnight")

        let savedCivil = SystemReminderDateCodec.components(
            for: displayedDate, hasTime: false, originalTimeZone: losAngeles
        )
        require(savedCivil.year == 2026 && savedCivil.month == 9 && savedCivil.day == 17,
                "date-only deadline round-trips without shifting a day")
        require(savedCivil.hour == nil && savedCivil.minute == nil
                && savedCivil.second == nil && savedCivil.timeZone == nil,
                "date-only output remains floating and has no clock components")

        // A timed deadline is an instant. Los Angeles is UTC-7 on this date;
        // 15:30 there is 06:30 the following day in Beijing.
        var timed = DateComponents(year: 2026, month: 9, day: 17, hour: 15, minute: 30)
        timed.timeZone = losAngeles
        let instant = SystemReminderDateCodec.date(from: timed)!
        let savedTimed = SystemReminderDateCodec.components(
            for: instant, hasTime: true, originalTimeZone: losAngeles
        )
        require(savedTimed.year == 2026 && savedTimed.month == 9 && savedTimed.day == 17
                && savedTimed.hour == 15 && savedTimed.minute == 30
                && savedTimed.timeZone == losAngeles,
                "timed deadline round-trips its provider time zone")
        require(beijingCalendar.component(.day, from: instant) == 18
                && beijingCalendar.component(.hour, from: instant) == 6
                && beijingCalendar.component(.minute, from: instant) == 30,
                "timed deadline displays the correct Beijing instant")

        print("6 reminder date invariants passed; no EventKit store instantiated.")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("Reminder date check failed: \(name)") }
    }
}

import Foundation
import Testing
@testable import Goose

private var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()

/// 2026-10-05 is a Monday.
private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

struct ScheduleTests {
    let profile = UUID()

    @Test func daytimeScheduleIsActiveOnlyInsideItsHours() {
        let work = BlockSchedule(name: "Work", profileID: profile, startHour: 9, endHour: 17, weekdays: [2, 3, 4, 5, 6])
        #expect(work.isActive(at: date(5, 10), calendar: calendar))
        #expect(!work.isActive(at: date(5, 8, 59), calendar: calendar))
        #expect(!work.isActive(at: date(5, 17), calendar: calendar))
        // Sunday the 4th isn't a work day.
        #expect(!work.isActive(at: date(4, 10), calendar: calendar))
    }

    @Test func overnightScheduleBelongsToTheDayItStarted() {
        // Monday nights only.
        let night = BlockSchedule(name: "Night", profileID: profile, startHour: 21, endHour: 7, weekdays: [2])
        #expect(night.crossesMidnight)
        #expect(night.isActive(at: date(5, 22), calendar: calendar))
        // Early Tuesday is still Monday night.
        #expect(night.isActive(at: date(6, 6), calendar: calendar))
        // Early Monday belongs to Sunday night, which isn't scheduled.
        #expect(!night.isActive(at: date(5, 6), calendar: calendar))
        #expect(!night.isActive(at: date(6, 7), calendar: calendar))
    }

    @Test func activeEndRollsOverToTheNextMorning() {
        let night = BlockSchedule(name: "Night", profileID: profile, startHour: 21, endHour: 7)
        #expect(night.activeEnd(at: date(5, 22), calendar: calendar) == date(6, 7))
        #expect(night.activeEnd(at: date(6, 3), calendar: calendar) == date(6, 7))
        #expect(night.activeEnd(at: date(6, 12), calendar: calendar) == nil)
    }

    @Test func durationHandlesOvernightSchedules() {
        #expect(BlockSchedule(name: "", profileID: profile, startHour: 21, endHour: 7).durationMinutes == 10 * 60)
        #expect(BlockSchedule(name: "", profileID: profile, startHour: 9, endHour: 17).durationMinutes == 8 * 60)
        #expect(BlockSchedule(name: "", profileID: profile, startHour: 9, startMinute: 0, endHour: 9, endMinute: 10).durationMinutes < BlockSchedule.minimumMinutes)
    }

    @Test func runStartIsTheSameThroughoutOneRun() {
        // Every check during one night must agree, so unlocking early isn't
        // undone by the next check re-locking you.
        let night = BlockSchedule(name: "Night", profileID: profile, startHour: 21, endHour: 7)
        let start = date(5, 21)
        #expect(night.activeStart(at: date(5, 21), calendar: calendar) == start)
        #expect(night.activeStart(at: date(5, 23, 30), calendar: calendar) == start)
        #expect(night.activeStart(at: date(6, 6, 59), calendar: calendar) == start)
        // The next night is a new run.
        #expect(night.activeStart(at: date(6, 22), calendar: calendar) == date(6, 21))
    }

    @Test func nextStartSkipsDaysOffTheSchedule() {
        // Weeknights only; Friday the 9th is the last one before the weekend.
        let weeknights = BlockSchedule(name: "", profileID: profile, startHour: 21, endHour: 7, weekdays: [2, 3, 4, 5, 6])
        #expect(weeknights.nextStart(after: date(5, 12), calendar: calendar) == date(5, 21))
        #expect(weeknights.nextStart(after: date(5, 21, 30), calendar: calendar) == date(6, 21))
        #expect(weeknights.nextStart(after: date(9, 22), calendar: calendar) == date(12, 21))
    }

    @Test func disabledScheduleIsNeverActive() {
        var night = BlockSchedule(name: "Night", profileID: profile, startHour: 21, endHour: 7)
        night.isEnabled = false
        #expect(!night.isActive(at: date(5, 22), calendar: calendar))
    }

    @Test func signatureIgnoresWeekdayOrder() {
        let a = BlockSchedule(name: "A", profileID: profile, weekdays: [2, 4, 6])
        let b = BlockSchedule(name: "B", profileID: profile, weekdays: [6, 2, 4])
        #expect(BlockRulesManager.signature(a) == BlockRulesManager.signature(b))
    }

    @Test func signatureChangesWithTiming() {
        let a = BlockSchedule(name: "A", profileID: profile, startHour: 21)
        let b = BlockSchedule(name: "A", profileID: profile, startHour: 22)
        #expect(BlockRulesManager.signature(a) != BlockRulesManager.signature(b))
    }

    @Test func ruleIDIsReadBackFromActivityNames() {
        let id = UUID()
        #expect(RuleActivity.ruleID(in: RuleActivity.scheduleName(id)) == id)
        #expect(RuleActivity.ruleID(in: RuleActivity.scheduleName(id, weekday: 3)) == id)
        #expect(RuleActivity.ruleID(in: RuleActivity.limitName(id)) == id)
        #expect(RuleActivity.ruleID(in: "gooseTimer") == nil)
    }
}

struct StatsTests {
    private func session(_ start: Date, _ end: Date) -> BlockSession {
        BlockSession(start: start, end: end, profileName: "Test")
    }

    @Test func blockPastMidnightCountsTowardBothDays() {
        let stats = BlockStats(sessions: [session(date(5, 22), date(6, 2))], now: date(6, 12), calendar: calendar)
        #expect(stats.blocked(on: date(5, 12)) == 2 * 3600)
        #expect(stats.blocked(on: date(6, 12)) == 2 * 3600)
    }

    @Test func streakCountsConsecutiveDays() {
        let sessions = [
            session(date(3, 9), date(3, 10)),
            session(date(4, 9), date(4, 10)),
            session(date(5, 9), date(5, 10)),
        ]
        #expect(BlockStats(sessions: sessions, now: date(5, 12), calendar: calendar).streak == 3)
        // Nothing yet on Tuesday doesn't break the streak.
        #expect(BlockStats(sessions: sessions, now: date(6, 8), calendar: calendar).streak == 3)
        // A whole missed day does.
        #expect(BlockStats(sessions: sessions, now: date(7, 8), calendar: calendar).streak == 0)
    }

    @Test func lastSevenDaysEndsToday() {
        let stats = BlockStats(sessions: [session(date(5, 9), date(5, 11))], now: date(5, 12), calendar: calendar)
        #expect(stats.lastSevenDays.count == 7)
        #expect(stats.lastSevenDays.last?.seconds == TimeInterval(2 * 3600))
        #expect(stats.lastSevenDaysTotal == 2 * 3600)
    }

    @Test func formatsDurations() {
        #expect(formatDuration(45 * 60) == "45m")
        #expect(formatDuration(2 * 3600) == "2h")
        #expect(formatDuration(90 * 60) == "1h 30m")
    }
}

struct WebsiteTests {
    @Test func profileSavedBeforeWebsitesLoadsWithNone() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Work","appTokens":[],"categoryTokens":[],"icon":"briefcase"}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(profile.webDomainTokens.isEmpty)
    }
}

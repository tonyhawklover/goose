import Foundation
import Testing
@testable import Goose

struct SavedDataTests {
    @Test func profileSavedBeforeUnlockMethodsLoadsAsTagProfile() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Work","appTokens":[],"categoryTokens":[],"icon":"briefcase"}"#
        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))
        #expect(profile.name == "Work")
        #expect(profile.unlockMethod == .key)
        #expect(profile.timerMinutes == 30)
    }

    @Test func profileRoundTripsUnlockMethod() throws {
        let profile = Profile(name: "Focus", appTokens: [], categoryTokens: [], unlockMethod: .timer, timerMinutes: 90)
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        #expect(decoded.unlockMethod == .timer)
        #expect(decoded.timerMinutes == 90)
    }

    @Test func tagSavedBeforeQRCodesLoadsAsNFC() throws {
        let json = #"{"id":"\#(UUID().uuidString)","code":"GOOSE-1234ABCD","name":"Tag 1"}"#
        let tag = try JSONDecoder().decode(GooseTag.self, from: Data(json.utf8))
        #expect(tag.kind == .nfc)
        #expect(tag.isGeneral)
    }

    @Test func qrCodeRoundTripsKind() throws {
        let tag = GooseTag(name: "QR Code 1", kind: .qr)
        let decoded = try JSONDecoder().decode(GooseTag.self, from: JSONEncoder().encode(tag))
        #expect(decoded.kind == .qr)
        #expect(decoded.code == tag.code)
    }
}

struct TimerWindowTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func shortTimerStartsMonitoringInThePast() {
        let end = now.addingTimeInterval(15 * 60)
        let start = TimerWindow.monitoringStart(endingAt: end, now: now)
        #expect(start < now)
        #expect(end.timeIntervalSince(start) >= TimerWindow.minimumLength)
    }

    @Test func longTimerStartsMonitoringNow() {
        let end = now.addingTimeInterval(2 * 60 * 60)
        #expect(TimerWindow.monitoringStart(endingAt: end, now: now) == now)
    }

    @Test func anyTimerLengthMeetsTheMinimum() {
        for minutes in [1, 5, 14, 15, 16, 30, 60, 8 * 60, 24 * 60 - 1] {
            let end = now.addingTimeInterval(TimeInterval(minutes * 60))
            let start = TimerWindow.monitoringStart(endingAt: end, now: now)
            #expect(end.timeIntervalSince(start) >= TimerWindow.minimumLength)
        }
    }
}

struct FormatMinutesTests {
    @Test(arguments: [
        (15, "15 min"),
        (60, "1 hour"),
        (90, "1 hour 30 min"),
        (120, "2 hours"),
        (480, "8 hours"),
    ])
    func formats(minutes: Int, expected: String) {
        #expect(formatMinutes(minutes) == expected)
    }
}

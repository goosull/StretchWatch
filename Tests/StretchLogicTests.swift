import XCTest
// Shared logic is compiled directly into this test target (see project.yml),
// so the types are in-module — no import of the app needed.

final class StretchLogicTests: XCTestCase {

    // Fixed UTC calendar so day-bucketing is deterministic across machines.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // MARK: - Quiet hours

    func testQuietOvernightWindow() {
        var s = StretchSettings(); s.quietEnabled = true; s.quietStartHour = 22; s.quietEndHour = 7
        XCTAssertTrue(s.isQuiet(date(2026, 7, 8, 23), calendar: cal))  // 11pm
        XCTAssertTrue(s.isQuiet(date(2026, 7, 8, 3), calendar: cal))   // 3am
        XCTAssertFalse(s.isQuiet(date(2026, 7, 8, 12), calendar: cal)) // noon
        XCTAssertFalse(s.isQuiet(date(2026, 7, 8, 7), calendar: cal))  // exactly 7am = awake
    }

    func testQuietSameDayWindow() {
        var s = StretchSettings(); s.quietEnabled = true; s.quietStartHour = 9; s.quietEndHour = 17
        XCTAssertTrue(s.isQuiet(date(2026, 7, 8, 10), calendar: cal))
        XCTAssertFalse(s.isQuiet(date(2026, 7, 8, 20), calendar: cal))
    }

    func testQuietDisabled() {
        var s = StretchSettings(); s.quietEnabled = false; s.quietStartHour = 22; s.quietEndHour = 7
        XCTAssertFalse(s.isQuiet(date(2026, 7, 8, 23), calendar: cal))
    }

    func testAdjustedFireMovesOutOfQuietToMorning() {
        var s = StretchSettings(); s.quietEnabled = true; s.quietStartHour = 22; s.quietEndHour = 7
        let fire = date(2026, 7, 8, 23, 30)            // 11:30pm — quiet
        let adjusted = s.adjustedFire(fire, calendar: cal)
        XCTAssertEqual(cal.component(.hour, from: adjusted), 7)
        XCTAssertEqual(cal.component(.day, from: adjusted), 9)  // next morning
    }

    func testAdjustedFireLeavesDaytimeAlone() {
        var s = StretchSettings(); s.quietEnabled = true; s.quietStartHour = 22; s.quietEndHour = 7
        let fire = date(2026, 7, 8, 14)
        XCTAssertEqual(s.adjustedFire(fire, calendar: cal), fire)
    }

    // MARK: - Snapshot (today / streak / weekly)

    private func completed(_ date: Date) -> StretchEvent {
        StretchEvent(sessionId: UUID().uuidString, date: date, outcome: .completed, moveId: "neck-right")
    }

    func testTodayCountAndWeekly() {
        let now = date(2026, 7, 8, 15)
        let events = [
            completed(date(2026, 7, 8, 9)),
            completed(date(2026, 7, 8, 11)),
            completed(date(2026, 7, 7, 10)),
            completed(date(2026, 7, 3, 10)),   // within the trailing 7 days
            completed(date(2026, 6, 20, 10)),  // old, excluded
        ]
        let snap = StretchStore.snapshot(from: events, calendar: cal, now: now)
        XCTAssertEqual(snap.todayCount, 2)
        XCTAssertEqual(snap.weeklyActiveDays, 3)  // Jul 8, 7, 3
    }

    func testStreakConsecutiveDays() {
        let now = date(2026, 7, 8, 15)
        let events = [
            completed(date(2026, 7, 8, 9)),
            completed(date(2026, 7, 7, 9)),
            completed(date(2026, 7, 6, 9)),
            // gap on Jul 5 breaks it
            completed(date(2026, 7, 4, 9)),
        ]
        XCTAssertEqual(StretchStore.snapshot(from: events, calendar: cal, now: now).streakDays, 3)
    }

    func testStreakTodayNotYetDoneStaysAlive() {
        let now = date(2026, 7, 8, 15)  // nothing today
        let events = [
            completed(date(2026, 7, 7, 9)),
            completed(date(2026, 7, 6, 9)),
        ]
        // Today at 0 must not break the streak — the day isn't over.
        XCTAssertEqual(StretchStore.snapshot(from: events, calendar: cal, now: now).streakDays, 2)
    }

    func testCompletionIdempotencyKey() {
        // Two completions with the same sessionId should be treated as one by the
        // store; here we verify the snapshot counts distinct completions correctly.
        let now = date(2026, 7, 8, 15)
        let sid = "session-1"
        let events = [
            StretchEvent(sessionId: sid, date: date(2026, 7, 8, 9), outcome: .completed, moveId: "a"),
            StretchEvent(sessionId: sid, date: date(2026, 7, 8, 9), outcome: .completed, moveId: "a"),
        ]
        // Snapshot counts raw events; idempotency is enforced at record() time.
        // This documents that the store, not the snapshot, dedupes.
        XCTAssertEqual(StretchStore.snapshot(from: events, calendar: cal, now: now).todayCount, 2)
    }

    // MARK: - Move selection

    func testMoveSelectionNoImmediateRepeat() {
        for seed in 0..<20 {
            let pick = StretchLibrary.next(afterMoveId: "neck-right", seed: seed)
            XCTAssertNotEqual(pick.id, "neck-right")
        }
    }

    func testMoveSelectionRotatesRegion() {
        // After a neck move, the next should prefer a different region.
        let pick = StretchLibrary.next(afterMoveId: "neck-right", seed: 0)
        XCTAssertNotEqual(pick.region, .neck)
    }
}

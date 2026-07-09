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

    // MARK: - Weekly heatmap (per-day counts)

    func testWeeklyCountsPerDayOldestFirst() {
        let now = date(2026, 7, 8, 15)  // today = Jul 8
        let events = [
            completed(date(2026, 7, 8, 9)),   // today ×2
            completed(date(2026, 7, 8, 11)),
            completed(date(2026, 7, 7, 10)),  // yesterday ×1
            completed(date(2026, 7, 2, 10)),  // 6 days ago ×1 (boundary, included)
            completed(date(2026, 7, 1, 10)),  // 7 days ago (excluded)
        ]
        let counts = StretchStore.snapshot(from: events, calendar: cal, now: now).weeklyCounts
        XCTAssertEqual(counts.count, 7)
        XCTAssertEqual(counts[6], 2)  // today
        XCTAssertEqual(counts[5], 1)  // yesterday
        XCTAssertEqual(counts[0], 1)  // 6 days ago (Jul 2)
        XCTAssertEqual(counts[1], 0)  // Jul 3, empty
        XCTAssertEqual(counts.reduce(0, +), 4)  // Jul 1 excluded
    }

    func testWeeklyCountsOnlyCompleted() {
        let now = date(2026, 7, 8, 15)
        let events = [
            completed(date(2026, 7, 8, 9)),
            StretchEvent(sessionId: "s", date: date(2026, 7, 8, 10), outcome: .skipped, moveId: "a"),
            StretchEvent(sessionId: "s2", date: date(2026, 7, 8, 10), outcome: .scheduled, moveId: "a"),
        ]
        XCTAssertEqual(StretchStore.snapshot(from: events, calendar: cal, now: now).weeklyCounts[6], 1)
    }

    func testWeeklyCountsEmptyWhenNoEvents() {
        let snap = StretchStore.snapshot(from: [], calendar: cal, now: date(2026, 7, 8, 15))
        XCTAssertEqual(snap.weeklyCounts, [0, 0, 0, 0, 0, 0, 0])
    }

    func testHeatLevelBuckets() {
        XCTAssertEqual(StretchStore.heatLevel(0), 0)
        XCTAssertEqual(StretchStore.heatLevel(1), 1)
        XCTAssertEqual(StretchStore.heatLevel(2), 2)
        XCTAssertEqual(StretchStore.heatLevel(3), 3)
        XCTAssertEqual(StretchStore.heatLevel(9), 3)  // saturates at 3+
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

    // MARK: - Region focus filter

    func testEnabledRegionsRestrictsToChosenAreas() {
        for seed in 0..<30 {
            let pick = StretchLibrary.next(afterMoveId: nil, seed: seed, enabledRegions: [.wrist])
            XCTAssertEqual(pick.region, .wrist, "seed \(seed) leaked outside enabled regions")
        }
    }

    func testEnabledRegionsTwoAreasStayInside() {
        let allowed: Set<Stretch.Region> = [.neck, .back]
        for seed in 0..<30 {
            let pick = StretchLibrary.next(afterMoveId: "sh-roll", seed: seed, enabledRegions: allowed)
            XCTAssertTrue(allowed.contains(pick.region))
        }
    }

    func testEnabledRegionsNilOrEmptyMeansAll() {
        // nil → all regions reachable; empty → treated as all (never zero moves).
        let nilPick = StretchLibrary.next(afterMoveId: nil, seed: 3, enabledRegions: nil)
        XCTAssertTrue(Stretch.Region.allCases.contains(nilPick.region))
        let emptyPick = StretchLibrary.next(afterMoveId: nil, seed: 3, enabledRegions: [])
        XCTAssertTrue(Stretch.Region.allCases.contains(emptyPick.region))
    }

    func testEnabledSingleRegionNoImmediateRepeat() {
        // Even confined to one region, don't hand back the exact same move.
        for seed in 0..<20 {
            let pick = StretchLibrary.next(afterMoveId: "neck-right", seed: seed, enabledRegions: [.neck])
            XCTAssertEqual(pick.region, .neck)
            XCTAssertNotEqual(pick.id, "neck-right")
        }
    }

    func testActiveRegionsDefaultsToAll() {
        var s = StretchSettings()
        XCTAssertEqual(s.activeRegions, Set(Stretch.Region.allCases))  // nil → all
        s.enabledRegions = []
        XCTAssertEqual(s.activeRegions, Set(Stretch.Region.allCases))  // empty → all
        s.enabledRegions = [.wrist]
        XCTAssertEqual(s.activeRegions, [.wrist])
    }

    func testSettingsDecodesWithoutEnabledRegions() throws {
        // A settings blob saved before this feature (no enabledRegions key) must
        // still decode — other fields must not reset.
        let json = #"{"remindersOn":true,"intervalMinutes":30,"standingDesk":false,"quietEnabled":true,"quietStartHour":22,"quietEndHour":7}"#
        let s = try JSONDecoder().decode(StretchSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.intervalMinutes, 30)
        XCTAssertNil(s.enabledRegions)
        XCTAssertEqual(s.activeRegions, Set(Stretch.Region.allCases))
    }
}

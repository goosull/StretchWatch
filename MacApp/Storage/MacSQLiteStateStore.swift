import Foundation
import SQLite3

enum MacStoreError: LocalizedError, Sendable {
    case openFailed(String)
    case schemaFailed(String)
    case queryFailed(String)
    case encodingFailed
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "StretchWatch could not open its local store: \(message)"
        case .schemaFailed(let message): return "StretchWatch could not prepare its local store: \(message)"
        case .queryFailed(let message): return "StretchWatch could not save local state: \(message)"
        case .encodingFailed: return "StretchWatch could not encode local state."
        case .decodingFailed: return "StretchWatch found unreadable local state."
        }
    }
}

/// SQLite-backed source of truth for the Mac session. Snapshot and event insertion
/// share one transaction, so a crash cannot leave a new state without its audit row.
actor MacSQLiteStateStore: MacStateStore {
    private let dbAddress: Int
    private var db: OpaquePointer { OpaquePointer(bitPattern: dbAddress)! }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(inMemory: Bool = false) throws {
        var handle: OpaquePointer?
        let path: String = inMemory ? ":memory:" : Self.databaseURL.path
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let handle { sqlite3_close(handle) }
            throw MacStoreError.openFailed(message)
        }
        dbAddress = Int(bitPattern: handle)

        do {
            try Self.configure(handle)
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    deinit {
        sqlite3_close(OpaquePointer(bitPattern: dbAddress)!)
    }

    static var databaseURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("StretchWatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("mac-session.sqlite3")
    }

    func load() async throws -> MacSessionState? {
        let statement = try prepare("SELECT json FROM mac_state WHERE id = 1")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let blob = sqlite3_column_blob(statement, 0) else { throw MacStoreError.decodingFailed }
        let length = Int(sqlite3_column_bytes(statement, 0))
        let data = Data(bytes: blob, count: length)
        if let state = try? decoder.decode(MacSessionState.self, from: data) {
            return state
        }
        // A malformed snapshot must not brick the menu-bar app forever. The
        // event log remains available for diagnostics; only the unreadable
        // source-of-truth row is discarded.
        try execute("DELETE FROM mac_state WHERE id = 1")
        return nil
    }

    func commit(state: MacSessionState, event: MacEvent) async throws {
        if let key = event.idempotencyKey, try hasActionEvent(key: key) { return }
        guard let stateData = try? encoder.encode(state),
              (try? encoder.encode(event)) != nil else {
            throw MacStoreError.encodingFailed
        }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let stateStatement = try prepare("INSERT INTO mac_state (id, json) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json")
            defer { sqlite3_finalize(stateStatement) }
            try bindBlob(stateData, to: stateStatement, index: 1)
            try step(stateStatement)

            let eventStatement = try prepare("""
                INSERT INTO mac_events
                (id, timestamp, kind, state, session_id, attempt, action_identifier,
                 move_id, due_at, source, mode, app_version)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(eventStatement) }
            try bindText(event.id, to: eventStatement, index: 1)
            try bindDouble(event.timestamp.timeIntervalSinceReferenceDate, to: eventStatement, index: 2)
            try bindText(event.kind.rawValue, to: eventStatement, index: 3)
            try bindText(event.state.rawValue, to: eventStatement, index: 4)
            try bindOptionalText(event.sessionId, to: eventStatement, index: 5)
            try bindOptionalInt(event.attempt, to: eventStatement, index: 6)
            try bindOptionalText(event.actionIdentifier, to: eventStatement, index: 7)
            try bindOptionalText(event.moveId, to: eventStatement, index: 8)
            try bindOptionalDouble(event.dueAt?.timeIntervalSinceReferenceDate, to: eventStatement, index: 9)
            try bindText(event.source.rawValue, to: eventStatement, index: 10)
            try bindText(event.mode.rawValue, to: eventStatement, index: 11)
            try bindText(event.appVersion, to: eventStatement, index: 12)
            try step(eventStatement)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func pruneEvents(olderThan date: Date) async throws {
        let statement = try prepare("DELETE FROM mac_events WHERE timestamp < ?")
        defer { sqlite3_finalize(statement) }
        try bindDouble(date.timeIntervalSinceReferenceDate, to: statement, index: 1)
        try step(statement)
    }

    func eventCount() async throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM mac_events")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func metrics(since date: Date) async throws -> MacDashboardMetrics {
        let statement = try prepare("""
            SELECT kind, mode, COUNT(*)
            FROM mac_events
            WHERE timestamp >= ?
            GROUP BY kind, mode
            """)
        defer { sqlite3_finalize(statement) }
        try bindDouble(date.timeIntervalSinceReferenceDate, to: statement, index: 1)

        var result = MacDashboardMetrics()
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW,
                  let kindPointer = sqlite3_column_text(statement, 0),
                  let modePointer = sqlite3_column_text(statement, 1)
            else { throw lastError() }

            let kind = String(cString: kindPointer)
            let mode = String(cString: modePointer)
            let count = Int(sqlite3_column_int64(statement, 2))
            switch kind {
            case MacEventKind.completed.rawValue:
                result.completedToday += count
                if mode == MacSessionMode.manual.rawValue { result.manualCompletedToday += count }
                else { result.automaticCompletedToday += count }
            case MacEventKind.deliveryObserved.rawValue where mode == MacSessionMode.automatic.rawValue:
                result.automaticDeliveryObservedToday += count
            case MacEventKind.responded.rawValue where mode == MacSessionMode.automatic.rawValue:
                result.automaticRespondedToday += count
            case MacEventKind.presented.rawValue where mode == MacSessionMode.automatic.rawValue:
                result.automaticPresentedToday += count
            default:
                break
            }
        }
        return result
    }

    private static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private static func configure(_ db: OpaquePointer) throws {
        do {
            try executeDatabase(db, sql: "PRAGMA journal_mode = WAL")
            try executeDatabase(db, sql: "PRAGMA foreign_keys = ON")
            try executeDatabase(db, sql: """
                CREATE TABLE IF NOT EXISTS mac_state (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    json BLOB NOT NULL
                )
                """)
            try executeDatabase(db, sql: """
                CREATE TABLE IF NOT EXISTS mac_events (
                    id TEXT PRIMARY KEY NOT NULL,
                    timestamp REAL NOT NULL,
                    kind TEXT NOT NULL,
                    state TEXT NOT NULL,
                    session_id TEXT,
                    attempt INTEGER,
                    action_identifier TEXT,
                    move_id TEXT,
                    due_at REAL,
                    source TEXT NOT NULL,
                    mode TEXT NOT NULL,
                    app_version TEXT NOT NULL
                )
                """)
            try executeDatabase(db, sql: "CREATE INDEX IF NOT EXISTS mac_events_timestamp ON mac_events(timestamp)")
            try executeDatabase(db, sql: "CREATE INDEX IF NOT EXISTS mac_events_session ON mac_events(session_id)")
            try executeDatabase(db, sql: """
                CREATE UNIQUE INDEX IF NOT EXISTS mac_events_action_key
                ON mac_events(session_id, attempt, action_identifier)
                WHERE session_id IS NOT NULL AND attempt IS NOT NULL AND action_identifier IS NOT NULL
                """)
            try executeDatabase(db, sql: "PRAGMA user_version = 1")
        } catch {
            throw MacStoreError.schemaFailed(error.localizedDescription)
        }
    }

    private func hasActionEvent(key: String) throws -> Bool {
        let parts = key.split(separator: "|", maxSplits: 2).map(String.init)
        guard parts.count == 3, let attempt = Int(parts[1]) else { return false }
        let statement = try prepare("SELECT 1 FROM mac_events WHERE session_id = ? AND attempt = ? AND action_identifier = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        try bindText(parts[0], to: statement, index: 1)
        try bindInt(attempt, to: statement, index: 2)
        try bindText(parts[2], to: statement, index: 3)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private static func executeDatabase(_ db: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            if let errorMessage { sqlite3_free(errorMessage) }
            throw MacStoreError.queryFailed(message)
        }
    }

    private func execute(_ sql: String) throws {
        try Self.executeDatabase(db, sql: sql)
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw lastError()
        }
        return statement
    }

    private func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func lastError() -> MacStoreError {
        .queryFailed(String(cString: sqlite3_errmsg(db)))
    }

    private func bindText(_ value: String, to statement: OpaquePointer, index: Int32) throws {
        guard sqlite3_bind_text(statement, index, value, -1, Self.transient) == SQLITE_OK else { throw lastError() }
    }

    private func bindOptionalText(_ value: String?, to statement: OpaquePointer, index: Int32) throws {
        if let value { try bindText(value, to: statement, index: index) }
        else if sqlite3_bind_null(statement, index) != SQLITE_OK { throw lastError() }
    }

    private func bindInt(_ value: Int, to statement: OpaquePointer, index: Int32) throws {
        guard sqlite3_bind_int64(statement, index, sqlite3_int64(value)) == SQLITE_OK else { throw lastError() }
    }

    private func bindOptionalInt(_ value: Int?, to statement: OpaquePointer, index: Int32) throws {
        if let value { try bindInt(value, to: statement, index: index) }
        else if sqlite3_bind_null(statement, index) != SQLITE_OK { throw lastError() }
    }

    private func bindDouble(_ value: Double, to statement: OpaquePointer, index: Int32) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else { throw lastError() }
    }

    private func bindOptionalDouble(_ value: Double?, to statement: OpaquePointer, index: Int32) throws {
        if let value { try bindDouble(value, to: statement, index: index) }
        else if sqlite3_bind_null(statement, index) != SQLITE_OK { throw lastError() }
    }

    private func bindBlob(_ data: Data, to statement: OpaquePointer, index: Int32) throws {
        let result = data.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(data.count), Self.transient)
        }
        guard result == SQLITE_OK else { throw lastError() }
    }
}

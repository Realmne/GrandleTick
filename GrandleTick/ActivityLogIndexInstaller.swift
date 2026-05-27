import Foundation
import SQLite3

enum ActivityLogIndexInstaller {
    static func installIfNeeded(databaseURL: URL) {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return
        }

        defer { sqlite3_close(database) }

        let statements = [
            "CREATE INDEX IF NOT EXISTS ZACTIVITYLOG_ZSTARTTIME_IDX ON ZACTIVITYLOG (ZSTARTTIME)",
            "CREATE INDEX IF NOT EXISTS ZACTIVITYLOG_APP_TITLE_IDX ON ZACTIVITYLOG (ZAPPNAME, ZWINDOWTITLE)",
            "CREATE INDEX IF NOT EXISTS ZACTIVITYLOG_DOMAIN_IDX ON ZACTIVITYLOG (ZDOMAIN)",
            "CREATE INDEX IF NOT EXISTS ZACTIVITYLOG_BILIBILI_IDX ON ZACTIVITYLOG (ZBILIBILIIDENTIFIER)"
        ]

        for statement in statements {
            sqlite3_exec(database, statement, nil, nil, nil)
        }
    }
}

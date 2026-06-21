import Foundation
import SQLite3

// SwiftData 在定义 Model 时不提供灵活的复合索引创建，导致大数据量下统计查询较慢。
// 本方法在应用启动时直接操作底层 SQLite，建立时间、应用和域名索引以解决数据中心查询较慢的问题。
enum ActivityLogIndexInstaller {
    static func installIfNeeded(databaseURL: URL) {
        // 1. 打开指定路径的 SQLite 数据库。
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return
        }

        defer { sqlite3_close(database) }

        // 2. 依次执行创建索引的 SQL 语句以优化统计和检索性能。
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


import Foundation
import SwiftData
import SQLite3

enum LegacyStoreMigrator {
    private static let markerName = "LegacyStoreMigration.signature"

    static func migrateIfNeeded(context: ModelContext, appDirectoryURL: URL) {
        let oldDatabaseURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("default.store")

        guard FileManager.default.fileExists(atPath: oldDatabaseURL.path) else { return }

        let signature = migrationSignature(for: oldDatabaseURL)
        let markerURL = appDirectoryURL.appendingPathComponent(markerName)
        let oldRows = loadRows(from: oldDatabaseURL)

        guard !oldRows.isEmpty else {
            try? signature.write(to: markerURL, atomically: true, encoding: .utf8)
            return
        }

        let lastSignature = try? String(contentsOf: markerURL, encoding: .utf8)
        if lastSignature == signature { return }

        let descriptor = FetchDescriptor<ActivityLog>()
        let existingLogs = (try? context.fetch(descriptor)) ?? []
        var existingKeys = Set(existingLogs.map(makeKey))
        var insertedCount = 0

        // 1. 先把新库已有记录转成唯一键集合，后续迁移时只补缺失项。
        // 2. 旧库和新库可能并存一段时间，所以这里必须显式去重，避免重复写入。
        for oldRow in oldRows {
            let key = makeKey(
                appName: oldRow.appName,
                windowTitle: oldRow.windowTitle,
                startTime: oldRow.startTime,
                duration: oldRow.duration,
                domain: oldRow.domain,
                bilibiliIdentifier: oldRow.bilibiliIdentifier,
                fullUrl: oldRow.fullUrl
            )

            if existingKeys.contains(key) { continue }

            let log = ActivityLog(
                appName: oldRow.appName,
                windowTitle: oldRow.windowTitle,
                startTime: oldRow.startTime,
                duration: oldRow.duration,
                domain: oldRow.domain,
                bilibiliIdentifier: oldRow.bilibiliIdentifier,
                fullUrl: oldRow.fullUrl
            )
            context.insert(log)
            existingKeys.insert(key)
            insertedCount += 1
        }

        // 3. 只有真正补进新记录时才保存，避免每次启动都产生无意义写入。
        // 4. 保存完成后把旧库签名写到标记文件，下次如果旧库没变化就直接跳过。
        if insertedCount > 0 {
            try? context.save()
        }
        try? signature.write(to: markerURL, atomically: true, encoding: .utf8)
    }

    private static func migrationSignature(for fileURL: URL) -> String {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = values?.fileSize ?? 0
        let modifiedAt = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(fileSize)-\(modifiedAt)"
    }

    private static func makeKey(_ log: ActivityLog) -> String {
        makeKey(
            appName: log.appName,
            windowTitle: log.windowTitle,
            startTime: log.startTime,
            duration: log.duration,
            domain: log.domain,
            bilibiliIdentifier: log.bilibiliIdentifier,
            fullUrl: log.fullUrl
        )
    }

    private static func makeKey(
        appName: String,
        windowTitle: String,
        startTime: Date,
        duration: TimeInterval,
        domain: String?,
        bilibiliIdentifier: String?,
        fullUrl: String?
    ) -> String {
        let startTimestamp = String(format: "%.6f", startTime.timeIntervalSinceReferenceDate)
        let durationText = String(format: "%.6f", duration)
        return [
            appName,
            windowTitle,
            startTimestamp,
            durationText,
            domain ?? "",
            bilibiliIdentifier ?? "",
            fullUrl ?? ""
        ].joined(separator: "|")
    }

    private static func loadRows(from databaseURL: URL) -> [LegacyRow] {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return []
        }

        defer { sqlite3_close(database) }

        let sql = """
        SELECT ZAPPNAME, ZWINDOWTITLE, ZSTARTTIME, ZDURATION, ZDOMAIN, ZBVID, ZFULLURL
        FROM ZACTIVITYLOG
        ORDER BY ZSTARTTIME, Z_PK
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return []
        }

        defer { sqlite3_finalize(statement) }

        var rows: [LegacyRow] = []

        // 1. 旧库里保存的是 SwiftData 直接落下来的 SQLite 表。
        // 2. 这里按列顺序逐条读出，再转换成当前模型能直接插入的新记录结构。
        while sqlite3_step(statement) == SQLITE_ROW {
            let appName = text(from: statement, index: 0)
            let windowTitle = text(from: statement, index: 1)
            let startTime = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 2))
            let duration = sqlite3_column_double(statement, 3)
            let domain = optionalText(from: statement, index: 4)
            let bilibiliIdentifier = optionalText(from: statement, index: 5)
            let fullUrl = optionalText(from: statement, index: 6)

            rows.append(
                LegacyRow(
                    appName: appName,
                    windowTitle: windowTitle,
                    startTime: startTime,
                    duration: duration,
                    domain: domain,
                    bilibiliIdentifier: bilibiliIdentifier,
                    fullUrl: fullUrl
                )
            )
        }

        return rows
    }

    private static func text(from statement: OpaquePointer?, index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private static func optionalText(from statement: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return text(from: statement, index: index)
    }
}

private struct LegacyRow {
    let appName: String
    let windowTitle: String
    let startTime: Date
    let duration: TimeInterval
    let domain: String?
    let bilibiliIdentifier: String?
    let fullUrl: String?
}

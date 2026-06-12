import Foundation
import SwiftData
import SQLite3

enum ActivityLogCompactor {
    private static let markerName = "ActivityLogCompaction.v1.completed"
    private static let mergeGapTolerance: TimeInterval = 75

    // 1. 检查是否需要执行压缩。
    // 如果存在标记文件，说明压缩已完成，直接跳过。
    static func compactIfNeeded(context: ModelContext, appDirectoryURL: URL) {
        let markerURL = appDirectoryURL.appendingPathComponent(markerName)
        if FileManager.default.fileExists(atPath: markerURL.path) {
            return
        }

        // 2. 备份数据库以防万一。
        // 在进行破坏性合并操作前，通过 SQLite 的 backup API 创建一个热备份。
        let databaseURL = appDirectoryURL.appendingPathComponent("ActivityData.sqlite")
        backupDatabaseIfPossible(databaseURL: databaseURL, appDirectoryURL: appDirectoryURL)

        // 3. 扫描并合并相邻的相似日志。
        // 判定条件：身份相同且时间跨度在 mergeGapTolerance 范围内。
        let descriptor = FetchDescriptor<ActivityLog>(sortBy: [SortDescriptor(\.startTime, order: .forward)])
        guard let logs = try? context.fetch(descriptor), logs.count > 1 else {
            try? "empty".write(to: markerURL, atomically: true, encoding: .utf8)
            return
        }

        var deletedCount = 0
        var currentLog = logs[0]
        var currentKey = LogCompactionKey(log: currentLog)

        for nextLog in logs.dropFirst() {
            let nextKey = LogCompactionKey(log: nextLog)
            let currentEnd = currentLog.startTime.addingTimeInterval(currentLog.duration)
            let nextEnd = nextLog.startTime.addingTimeInterval(nextLog.duration)
            let gap = nextLog.startTime.timeIntervalSince(currentEnd)

            if currentKey == nextKey && gap <= mergeGapTolerance {
                let mergedEnd = max(currentEnd, nextEnd)
                currentLog.duration = mergedEnd.timeIntervalSince(currentLog.startTime)
                context.delete(nextLog)
                deletedCount += 1
            } else {
                currentLog = nextLog
                currentKey = nextKey
            }
        }

        // 4. 持久化合并后的状态并记录压缩日志。
        if deletedCount > 0 {
            try? context.save()
        }

        let markerText = "deleted=\(deletedCount)"
        try? markerText.write(to: markerURL, atomically: true, encoding: .utf8)
    }

    private static func backupDatabaseIfPossible(databaseURL: URL, appDirectoryURL: URL) {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return }

        let backupsDirectoryURL = appDirectoryURL.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupURL = backupsDirectoryURL.appendingPathComponent("ActivityData-pre-compaction-\(timestamp).sqlite")
        sqliteBackup(sourceURL: databaseURL, destinationURL: backupURL)
    }

    private static func sqliteBackup(sourceURL: URL, destinationURL: URL) {
        var sourceDatabase: OpaquePointer?
        var destinationDatabase: OpaquePointer?

        guard sqlite3_open_v2(sourceURL.path, &sourceDatabase, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(sourceDatabase)
            return
        }

        guard sqlite3_open_v2(destinationURL.path, &destinationDatabase, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(sourceDatabase)
            sqlite3_close(destinationDatabase)
            return
        }

        defer {
            sqlite3_close(sourceDatabase)
            sqlite3_close(destinationDatabase)
        }

        guard let sourceDatabase, let destinationDatabase,
              let backup = sqlite3_backup_init(destinationDatabase, "main", sourceDatabase, "main") else {
            return
        }

        sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
    }
}

private struct LogCompactionKey: Hashable {
    let appName: String
    let windowTitle: String
    let domain: String?
    let bilibiliIdentifier: String?
    let fullUrl: String?

    init(log: ActivityLog) {
        appName = log.appName
        windowTitle = log.windowTitle
        domain = log.domain
        bilibiliIdentifier = log.bilibiliIdentifier
        fullUrl = log.fullUrl
    }
}

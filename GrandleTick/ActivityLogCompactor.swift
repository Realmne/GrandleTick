import Foundation
import SwiftData
import SQLite3

enum ActivityLogCompactor {
    private static let markerName = "ActivityLogCompaction.v1.completed"
    private static let mergeGapTolerance: TimeInterval = 75

    static func compactIfNeeded(context: ModelContext, appDirectoryURL: URL) {
        let markerURL = appDirectoryURL.appendingPathComponent(markerName)
        if FileManager.default.fileExists(atPath: markerURL.path) {
            return
        }

        let databaseURL = appDirectoryURL.appendingPathComponent("ActivityData.sqlite")
        backupDatabaseIfPossible(databaseURL: databaseURL, appDirectoryURL: appDirectoryURL)

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

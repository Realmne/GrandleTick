import Foundation
import SQLite3

private let knowledgeTidV2s: Set<Int> = [1010, 2084, 2085, 2086, 2087, 2088, 2089, 2090, 2091, 2092, 2093, 2094, 2095]
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct BilibiliMetadata {
    let title: String
    let tidV2: Int
    let isKnowledge: Bool
}

private struct BilibiliViewResponse: Decodable {
    let code: Int
    let data: BilibiliViewData?
}

private struct BilibiliViewData: Decodable {
    let tid: Int
    let tidV2: Int?
    let title: String

    enum CodingKeys: String, CodingKey {
        case tid
        case tidV2 = "tid_v2"
        case title
    }
}

struct BilibiliHistoryMigrator {
    static func run() async {
        do {
            let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
            let appDirectory = homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("GrandleTick", isDirectory: true)
            let databaseURL = appDirectory.appendingPathComponent("ActivityData.sqlite")

            try backupDatabase(databaseURL: databaseURL, appDirectory: appDirectory)

            let rows = try loadRows(from: databaseURL)
            let distinctBVs = Set(rows.compactMap(\.bvid).filter { $0.hasPrefix("BV") })

            var metadataByBV: [String: BilibiliMetadata] = [:]
            for bvid in distinctBVs.sorted() {
                if let metadata = try? await fetchMetadata(for: bvid) {
                    metadataByBV[bvid] = metadata
                }
            }

            let stats = try migrateRows(
                in: databaseURL,
                rows: rows,
                metadataByBV: metadataByBV
            )

            print("backup=\(stats.backupPath)")
            print("rows_total=\(rows.count)")
            print("bvid_total=\(distinctBVs.count)")
            print("knowledge_rows=\(stats.knowledgeRows)")
            print("entertainment_rows=\(stats.entertainmentRows)")
            print("metadata_hits=\(metadataByBV.count)")
        } catch {
            fputs("migration failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func backupDatabase(databaseURL: URL, appDirectory: URL) throws {
        let backupsDirectory = appDirectory.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let backupURL = backupsDirectory.appendingPathComponent("ActivityData-pre-bilibili-zone-migration-\(timestamp).sqlite")

        var sourceDatabase: OpaquePointer?
        var destinationDatabase: OpaquePointer?

        guard sqlite3_open_v2(databaseURL.path, &sourceDatabase, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw MigrationError.databaseOpenFailed
        }

        guard sqlite3_open_v2(backupURL.path, &destinationDatabase, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(sourceDatabase)
            throw MigrationError.backupOpenFailed
        }

        defer {
            sqlite3_close(sourceDatabase)
            sqlite3_close(destinationDatabase)
        }

        guard let sourceDatabase,
              let destinationDatabase,
              let backup = sqlite3_backup_init(destinationDatabase, "main", sourceDatabase, "main") else {
            throw MigrationError.backupInitFailed
        }

        sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
    }

    private static func loadRows(from databaseURL: URL) throws -> [DatabaseRow] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw MigrationError.databaseOpenFailed
        }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT Z_PK, ZBILIBILIIDENTIFIER
        FROM ZACTIVITYLOG
        WHERE ZDOMAIN = 'bilibili.com'
        ORDER BY Z_PK
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MigrationError.statementPrepareFailed
        }
        defer { sqlite3_finalize(statement) }

        var rows: [DatabaseRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let row = DatabaseRow(
                primaryKey: sqlite3_column_int64(statement, 0),
                bvid: optionalText(statement, index: 1)
            )
            rows.append(row)
        }
        return rows
    }

    private static func migrateRows(
        in databaseURL: URL,
        rows: [DatabaseRow],
        metadataByBV: [String: BilibiliMetadata]
    ) throws -> MigrationStats {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw MigrationError.databaseOpenFailed
        }
        defer { sqlite3_close(database) }

        guard let database else {
            throw MigrationError.databaseOpenFailed
        }

        try execute(sql: "BEGIN IMMEDIATE TRANSACTION", database: database)
        do {
            let updateSQL = """
            UPDATE ZACTIVITYLOG
            SET ZWINDOWTITLE = ?, ZBILIBILIIDENTIFIER = ?, ZBILIBILITIDV2 = ?, ZFULLURL = NULL
            WHERE Z_PK = ?
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, updateSQL, -1, &statement, nil) == SQLITE_OK else {
                throw MigrationError.statementPrepareFailed
            }
            defer { sqlite3_finalize(statement) }

            var knowledgeRows = 0
            var entertainmentRows = 0

            for row in rows {
                let metadata = row.bvid.flatMap { metadataByBV[$0] }
                if let metadata, metadata.isKnowledge, let bvid = row.bvid {
                    try bindAndExecute(
                        statement: statement,
                        windowTitle: metadata.title,
                        bvid: bvid,
                        tidV2: metadata.tidV2,
                        primaryKey: row.primaryKey
                    )
                    knowledgeRows += 1
                } else {
                    try bindAndExecute(
                        statement: statement,
                        windowTitle: "娱乐",
                        bvid: nil,
                        tidV2: metadata?.tidV2,
                        primaryKey: row.primaryKey
                    )
                    entertainmentRows += 1
                }
            }

            try execute(sql: "COMMIT", database: database)

            let backupPath = backupPathForLatestMigration()
            return MigrationStats(
                knowledgeRows: knowledgeRows,
                entertainmentRows: entertainmentRows,
                backupPath: backupPath
            )
        } catch {
            try? execute(sql: "ROLLBACK", database: database)
            throw error
        }
    }

    private static func bindAndExecute(
        statement: OpaquePointer?,
        windowTitle: String,
        bvid: String?,
        tidV2: Int?,
        primaryKey: Int64
    ) throws {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)

        sqlite3_bind_text(statement, 1, windowTitle, -1, sqliteTransient)
        if let bvid {
            sqlite3_bind_text(statement, 2, bvid, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, 2)
        }
        if let tidV2 {
            sqlite3_bind_int64(statement, 3, sqlite3_int64(tidV2))
        } else {
            sqlite3_bind_null(statement, 3)
        }
        sqlite3_bind_int64(statement, 4, primaryKey)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw MigrationError.statementStepFailed
        }
    }

    private static func fetchMetadata(for bvid: String) async throws -> BilibiliMetadata {
        guard let url = URL(string: "https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)") else {
            throw MigrationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(BilibiliViewResponse.self, from: data)
        guard response.code == 0, let payload = response.data else {
            throw MigrationError.metadataFetchFailed
        }

        let tidV2 = payload.tidV2 ?? payload.tid
        let title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw MigrationError.metadataFetchFailed
        }

        return BilibiliMetadata(
            title: title,
            tidV2: tidV2,
            isKnowledge: knowledgeTidV2s.contains(tidV2)
        )
    }

    private static func execute(sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw MigrationError.statementStepFailed
        }
    }

    private static func optionalText(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        let text = String(cString: cString)
        return text.isEmpty ? nil : text
    }

    private static func backupPathForLatestMigration() -> String {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let backupsDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("GrandleTick", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)

        let candidates = (try? FileManager.default.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return candidates
            .filter { $0.lastPathComponent.contains("ActivityData-pre-bilibili-zone-migration-") }
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return leftDate > rightDate
            }
            .first?.path ?? ""
    }
}

private struct DatabaseRow {
    let primaryKey: Int64
    let bvid: String?
}

private struct MigrationStats {
    let knowledgeRows: Int
    let entertainmentRows: Int
    let backupPath: String
}

private enum MigrationError: Error {
    case invalidURL
    case databaseOpenFailed
    case backupOpenFailed
    case backupInitFailed
    case statementPrepareFailed
    case statementStepFailed
    case metadataFetchFailed
}

Task {
    await BilibiliHistoryMigrator.run()
    exit(0)
}

RunLoop.main.run()

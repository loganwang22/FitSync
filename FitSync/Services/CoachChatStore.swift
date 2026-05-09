import Foundation

/// Persists coach chat sessions as JSON files under Documents/coach_chats/.
/// One file per session keyed by UUID.
@MainActor
final class CoachChatStore {
    static let shared = CoachChatStore()

    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.directoryURL = docs.appendingPathComponent("coach_chats", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Read

    /// All sessions, newest first.
    func listSessions() -> [CoachChatSession] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else { return [] }

        let sessions: [CoachChatSession] = files.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let session = try? decoder.decode(CoachChatSession.self, from: data)
            else { return nil }
            return session
        }
        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadSession(id: UUID) -> CoachChatSession? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(CoachChatSession.self, from: data)
    }

    // MARK: - Write

    func save(_ session: CoachChatSession) {
        guard !session.messages.isEmpty else { return }
        let url = fileURL(for: session.id)
        do {
            let data = try encoder.encode(session)
            try data.write(to: url, options: .atomic)
        } catch {
            // Best-effort; swallow silently so a disk failure never breaks chat.
        }
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    func deleteAll() {
        for session in listSessions() {
            delete(id: session.id)
        }
    }

    // MARK: - Helpers

    private func fileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).json")
    }
}

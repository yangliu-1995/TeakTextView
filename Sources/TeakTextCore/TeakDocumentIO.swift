import Foundation
import TeakTextBuffer

/// File I/O and decoding run on this actor, never on the UI executor.
public actor TeakDocumentIO {
    public init() {}

    public func prepare(text: String) throws -> TeakDocumentSnapshot {
        try Task.checkCancellation()
        let snapshot = TTTextSnapshot.make(text: text)
        try Task.checkCancellation()
        return TeakDocumentSnapshot(native: snapshot)
    }

    public func open(url: URL) throws -> TeakDocumentSnapshot {
        guard url.isFileURL else { throw TeakTextError.localFileRequired }
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let snapshot = try TTTextSnapshot.load(url: url, isCancelled: { Task.isCancelled })
            try Task.checkCancellation()
            return TeakDocumentSnapshot(native: snapshot)
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }

    public func save(_ snapshot: TeakDocumentSnapshot, to url: URL) throws {
        guard url.isFileURL else { throw TeakTextError.localFileRequired }
        try Task.checkCancellation()
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            try snapshot.native.write(to: url, isCancelled: { Task.isCancelled })
        } catch {
            try Task.checkCancellation()
            throw error
        }
    }
}

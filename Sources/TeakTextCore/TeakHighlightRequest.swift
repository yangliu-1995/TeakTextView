import Foundation

public struct TeakHighlightRequest: Sendable {
    public let documentID: UUID
    public let revision: UInt64
    public let snapshot: TeakDocumentSnapshot
    public let range: NSRange
    /// Earliest edit since the host's last accepted plugin result. nil means no edits.
    public let invalidatedFrom: Int?

    public init(documentID: UUID, revision: UInt64, snapshot: TeakDocumentSnapshot,
                range: NSRange, invalidatedFrom: Int?) {
        self.documentID = documentID
        self.revision = revision
        self.snapshot = snapshot
        self.range = range
        self.invalidatedFrom = invalidatedFrom
    }
}

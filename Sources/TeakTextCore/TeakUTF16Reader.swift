import Foundation

/// Actor-owned cursor: at most one 16 Ki UTF-16 block is materialized.
final class TeakUTF16Reader {
    let snapshot: TeakDocumentSnapshot
    private var start = 0
    private var units: [UInt16] = []

    init(snapshot: TeakDocumentSnapshot) { self.snapshot = snapshot }

    func character(at offset: Int) throws -> UInt16? {
        guard offset >= 0, offset < snapshot.utf16Count else { return nil }
        if offset < start || offset >= start + units.count {
            start = offset
            units = try snapshot.utf16(in: NSRange(location: offset,
                length: min(Constants.chunkSize, snapshot.utf16Count - offset)))
        }
        return units[offset - start]
    }

    func matches(_ delimiter: [UInt16], at offset: Int) throws -> Bool {
        for (index, unit) in delimiter.enumerated() {
            if try character(at: offset + index) != unit { return false }
        }
        return true
    }
}

private extension TeakUTF16Reader {
    enum Constants { static let chunkSize = 16_384 }
}

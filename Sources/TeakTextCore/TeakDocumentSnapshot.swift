import Foundation
import TeakTextBuffer

/// UTF-16 offsets match UIKit. Copying a snapshot shares immutable rope nodes.
public struct TeakDocumentSnapshot: Sendable {
    @_spi(Storage) public let native: TTTextSnapshot

    @_spi(Storage) public init(native: TTTextSnapshot) {
        self.native = native
    }

    public var utf16Count: Int { Int(native.length) }
    public var lineCount: Int { Int(native.lineCount) }
    public var chunkCount: Int { Int(native.chunkCount) }
    public var encoding: String.Encoding { String.Encoding(rawValue: native.fileEncoding) }
    public var hasByteOrderMark: Bool { native.hasByteOrderMark }

    /// Logical line rank, including CRLF as a single newline and a trailing empty line.
    public func lineNumber(atUTF16Offset offset: Int) throws -> Int {
        try validate(NSRange(location: offset, length: 0))
        return Int(native.lineNumber(atUTF16Offset: UInt(offset)))
    }

    public func isLineStart(atUTF16Offset offset: Int) throws -> Bool {
        try validate(NSRange(location: offset, length: 0))
        return native.isLineStart(atUTF16Offset: UInt(offset))
    }

    /// This is an explicit copy of the requested range, never an implicit full-document binding.
    public func text(in range: NSRange) throws -> String {
        try validate(range)
        return native.substring(in: range)
    }

    public func replacing(_ range: NSRange, with text: String) throws -> Self {
        try validate(range)
        return Self(native: native.replacing(range, with: text))
    }

    public func utf16(in range: NSRange) throws -> [UInt16] {
        try validate(range)
        guard range.length > 0 else { return [] }
        var result = [UInt16](repeating: 0, count: range.length)
        result.withUnsafeMutableBufferPointer { native.getCharacters($0.baseAddress!, range: range) }
        return result
    }

    private func validate(_ range: NSRange) throws {
        guard range.location >= 0, range.length >= 0, range.location <= utf16Count,
              range.length <= utf16Count - range.location else { throw TeakTextError.invalidRange }
    }
}

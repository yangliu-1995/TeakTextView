import Foundation

struct TeakDemoSourceFile: Decodable, Sendable {
    let resourcePath: String
    let fileName: String
    let byteCount: Int64
    let sourceURL: URL
    let commitSHA: String
    let sha256: String

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

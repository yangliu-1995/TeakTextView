import Foundation

struct TeakDemoLanguageSamples: Decodable, Sendable {
    let languageID: String
    let displayName: String
    let normal: TeakDemoSourceFile
    let large: TeakDemoSourceFile
    let licensePaths: [String]
}

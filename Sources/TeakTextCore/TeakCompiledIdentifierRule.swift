struct TeakCompiledIdentifierRule: Sendable {
    let precededBy: [[UInt16]]
    let followedBy: [[UInt16]]
    let startsWith: [[UInt16]]
    let scope: String
}

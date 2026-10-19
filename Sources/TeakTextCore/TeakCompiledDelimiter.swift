struct TeakCompiledDelimiter: Sendable {
    let start: [UInt16]
    let end: [UInt16]
    let escape: UInt16?
    let multiline: Bool
    let scope: String
    let nested: Bool
    let characterLiteral: Bool
}

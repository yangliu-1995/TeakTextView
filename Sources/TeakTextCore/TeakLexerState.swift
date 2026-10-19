enum TeakLexerState: Sendable {
    case normal
    case line(scope: String)
    case delimited(index: Int, escaped: Bool, depth: Int)
}

import Foundation

public enum TeakTextError: Error, Sendable {
    case invalidRange
    case localFileRequired
    case invalidLanguageDefinition(String)
    case loadSuperseded
}

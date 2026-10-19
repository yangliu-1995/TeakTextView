#if canImport(UIKit)
import UIKit

@MainActor
public struct TeakTextTheme {
    public var font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    public var foregroundColor = UIColor.label
    public var backgroundColor = UIColor.systemBackground
    public var lineNumberColor = UIColor.secondaryLabel
    public var lineNumberBackgroundColor = UIColor.secondarySystemBackground
    public var scopeColors: [String: UIColor] = [
        "keyword": .systemPurple, "literal": .systemOrange, "type": .systemTeal,
        "string": .systemRed, "comment": .systemGreen, "number": .systemBlue,
        "tag": .systemPurple, "attribute": .systemTeal, "property": .systemTeal,
        "selector": .systemPurple, "variable": .systemTeal, "directive": .systemOrange,
        "heading": .systemPurple, "emphasis": .systemOrange, "code": .systemRed,
        "link": .systemBlue, "section": .systemPurple
    ]

    public init() {}
}
#endif

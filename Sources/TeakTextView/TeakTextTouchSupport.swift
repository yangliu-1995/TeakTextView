#if canImport(UIKit)
import UIKit
import ObjectiveC

/// Contains the platform capability check used to keep touch hit testing local.
/// No UIKit method is replaced; unsupported signatures retain native behavior.
enum TeakTextTouchSupport {
    static func prefersSelectionSegments(for selector: Selector) -> Bool {
        guard selector == Constants.geometrySelector,
              let method = class_getInstanceMethod(UITextView.self, selector),
              method_getNumberOfArguments(method) == 3 else { return false }
        var encoding = [CChar](repeating: 0, count: Constants.encodingCapacity)
        method_getReturnType(method, &encoding, Constants.encodingCapacity)
        guard text(from: encoding) == String(cString: NSValue(cgRect: .zero).objCType) else { return false }
        method_getArgumentType(method, 2, &encoding, Constants.encodingCapacity)
        return text(from: encoding) == "@"
    }

    private static func text(from encoding: [CChar]) -> String {
        String(decoding: encoding.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func selector(from hex: String) -> Selector? {
        let digits = Array(hex.utf8)
        guard digits.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(digits.count / 2)
        for offset in stride(from: 0, to: digits.count, by: 2) {
            guard let value = UInt8(String(decoding: digits[offset...offset + 1], as: UTF8.self), radix: 16) else {
                return nil
            }
            bytes.append(value)
        }
        return NSSelectorFromString(String(decoding: bytes, as: UTF8.self))
    }
}

private extension TeakTextTouchSupport {
    enum Constants {
        // _boundingRectForRange:
        static let geometrySelector = selector(from: "5f626f756e64696e6752656374466f7252616e67653a")
        static let encodingCapacity = 128
    }
}
#endif

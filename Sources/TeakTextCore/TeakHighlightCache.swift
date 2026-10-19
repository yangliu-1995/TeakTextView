import Foundation

/// Bounded, nonoverlapping presentation runs, separate from lexer validity.
/// Retained colors follow edits until a matching background result replaces them.
@_spi(Rendering)
public struct TeakHighlightCache: Sendable {
    public private(set) var spans: [TeakHighlightSpan] = []

    public init() {}

    /// Called by the plugin actor. Later plugin spans have presentation priority.
    init(spans: [TeakHighlightSpan]) {
        let events = spans.enumerated().flatMap { index, span in
            [(offset: span.range.location, index: index, starts: true),
             (offset: NSMaxRange(span.range), index: index, starts: false)]
        }.sorted { $0.offset < $1.offset }
        var active = [Bool](repeating: false, count: spans.count)
        var heap: [Int] = []
        var cursor = 0
        while cursor < events.count {
            let offset = events[cursor].offset
            while cursor < events.count, events[cursor].offset == offset {
                let event = events[cursor]
                active[event.index] = event.starts
                if event.starts { Self.push(event.index, onto: &heap) }
                cursor += 1
            }
            while let index = heap.first, !active[index] { Self.pop(&heap) }
            if cursor < events.count, let index = heap.first {
                Self.append(to: &self.spans, start: offset, end: events[cursor].offset, scope: spans[index].scope)
            }
        }
    }

    /// Receives each actual storage mutation, before NSTextStorage coalesces edits.
    /// This bounded coordinate update must share UIKit's synchronous edit boundary.
    public mutating func applyEdit(replacing range: NSRange, replacementLength: Int) {
        guard !spans.isEmpty else { return }
        let oldEnd = NSMaxRange(range)
        let delta = replacementLength - range.length
        let inheritedOffset = range.length > 0 ? range.location : max(0, range.location - 1)
        let inherited = scope(at: inheritedOffset)
        var result: [TeakHighlightSpan] = []
        for span in spans where span.range.location < range.location {
            Self.append(to: &result, start: span.range.location,
                end: min(NSMaxRange(span.range), range.location), scope: span.scope)
        }
        if let inherited {
            Self.append(to: &result, start: range.location,
                end: range.location + replacementLength, scope: inherited)
        }
        for span in spans where NSMaxRange(span.range) > oldEnd {
            Self.append(to: &result, start: max(span.range.location, oldEnd) + delta,
                end: NSMaxRange(span.range) + delta, scope: span.scope)
        }
        spans = result
    }

    /// Linear merge of canonical runs; unchanged colors generate no native writes.
    public func changes(from previous: Self) -> [TeakHighlightChange] {
        var result: [TeakHighlightChange] = []
        var oldIndex = 0
        var newIndex = 0
        var offset = min(previous.spans.first?.range.location ?? Int.max,
                         spans.first?.range.location ?? Int.max)
        while oldIndex < previous.spans.count || newIndex < spans.count {
            while oldIndex < previous.spans.count, NSMaxRange(previous.spans[oldIndex].range) <= offset { oldIndex += 1 }
            while newIndex < spans.count, NSMaxRange(spans[newIndex].range) <= offset { newIndex += 1 }
            let old = oldIndex < previous.spans.count ? previous.spans[oldIndex] : nil
            let new = newIndex < spans.count ? spans[newIndex] : nil
            let oldScope = old.flatMap { $0.range.location <= offset ? $0.scope : nil }
            let newScope = new.flatMap { $0.range.location <= offset ? $0.scope : nil }
            let end = min(old.map { $0.range.location > offset ? $0.range.location : NSMaxRange($0.range) } ?? Int.max,
                          new.map { $0.range.location > offset ? $0.range.location : NSMaxRange($0.range) } ?? Int.max)
            guard end != Int.max else { break }
            if oldScope != newScope { Self.appendChange(to: &result, start: offset, end: end, scope: newScope) }
            offset = end
        }
        return result
    }

    /// TextKit's validator replays only the runs intersecting its layout fragment.
    public func attributes(in range: NSRange) -> [TeakHighlightChange] {
        var result: [TeakHighlightChange] = []
        var cursor = range.location
        let upper = NSMaxRange(range)
        var index = firstSpan(endingAfter: cursor)
        while index < spans.count, spans[index].range.location < upper {
            let span = spans[index]
            Self.appendChange(to: &result, start: cursor, end: min(upper, span.range.location), scope: nil)
            let end = min(upper, NSMaxRange(span.range))
            Self.appendChange(to: &result, start: max(cursor, span.range.location), end: end, scope: span.scope)
            cursor = end
            index += 1
        }
        Self.appendChange(to: &result, start: cursor, end: upper, scope: nil)
        return result
    }

    private func scope(at offset: Int) -> String? {
        let index = firstSpan(endingAfter: offset)
        guard index < spans.count, spans[index].range.location <= offset else { return nil }
        return spans[index].scope
    }

    private func firstSpan(endingAfter offset: Int) -> Int {
        var lower = 0
        var upper = spans.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if NSMaxRange(spans[middle].range) <= offset { lower = middle + 1 }
            else { upper = middle }
        }
        return lower
    }

    private static func append(to spans: inout [TeakHighlightSpan], start: Int, end: Int, scope: String) {
        guard start < end else { return }
        if let last = spans.last, NSMaxRange(last.range) == start, last.scope == scope {
            spans[spans.count - 1] = TeakHighlightSpan(range: NSRange(location: last.range.location,
                length: end - last.range.location), scope: scope)
        } else { spans.append(TeakHighlightSpan(range: NSRange(location: start, length: end - start), scope: scope)) }
    }

    private static func appendChange(to changes: inout [TeakHighlightChange], start: Int, end: Int, scope: String?) {
        guard start < end else { return }
        if let last = changes.last, NSMaxRange(last.range) == start, last.scope == scope {
            changes[changes.count - 1] = TeakHighlightChange(range: NSRange(location: last.range.location,
                length: end - last.range.location), scope: scope)
        } else { changes.append(TeakHighlightChange(range: NSRange(location: start, length: end - start), scope: scope)) }
    }

    private static func push(_ value: Int, onto heap: inout [Int]) {
        heap.append(value)
        var child = heap.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard heap[parent] < heap[child] else { break }
            heap.swapAt(parent, child)
            child = parent
        }
    }

    private static func pop(_ heap: inout [Int]) {
        let last = heap.removeLast()
        guard !heap.isEmpty else { return }
        heap[0] = last
        var parent = 0
        while parent * 2 + 1 < heap.count {
            var child = parent * 2 + 1
            if child + 1 < heap.count, heap[child + 1] > heap[child] { child += 1 }
            guard heap[parent] < heap[child] else { break }
            heap.swapAt(parent, child)
            parent = child
        }
    }
}

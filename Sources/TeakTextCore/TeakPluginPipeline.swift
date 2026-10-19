import Foundation

public actor TeakPluginPipeline {
    public init() {}

    /// Resolve overlapping plugin layers in the background, skipping unknown scopes.
    @_spi(Rendering)
    public func presentation(for request: TeakHighlightRequest, plugins: [any TeakTextPlugin],
                             supportedScopes: Set<String>) async throws -> TeakHighlightCache {
        let spans = try await highlights(for: request, plugins: plugins)
        try Task.checkCancellation()
        return TeakHighlightCache(spans: spans.filter { supportedScopes.contains($0.scope) })
    }

    public func highlights(for request: TeakHighlightRequest,
                           plugins: [any TeakTextPlugin]) async throws -> [TeakHighlightSpan] {
        guard request.range.location >= 0, request.range.length >= 0,
              request.range.location <= request.snapshot.utf16Count,
              request.range.length <= request.snapshot.utf16Count - request.range.location else {
            throw TeakTextError.invalidRange
        }
        var result: [TeakHighlightSpan] = []
        for plugin in plugins {
            try Task.checkCancellation()
            let spans = try await plugin.highlights(for: request)
            for span in spans.prefix(Constants.maximumSpans - result.count) {
                guard span.range.location >= request.range.location, span.range.length > 0,
                      span.range.location <= NSMaxRange(request.range),
                      span.range.length <= NSMaxRange(request.range) - span.range.location else { continue }
                result.append(span)
            }
            if result.count == Constants.maximumSpans { break }
        }
        return result
    }
}

private extension TeakPluginPipeline {
    enum Constants { static let maximumSpans = 4096 }
}

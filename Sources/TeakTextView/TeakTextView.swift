#if canImport(UIKit)
import UIKit
@_spi(Storage) @_spi(Rendering) import TeakTextCore
import TeakTextStorage

/// Native input and selection, custom storage and plugins. UIKit is main-thread-only;
/// decoding, saving and lexing belong to independent background actors.
@MainActor
public final class TeakTextView: UIView, UITextViewDelegate, @preconcurrency NSTextLayoutManagerDelegate,
                                 @preconcurrency NSTextStorageDelegate {
    private let storage: TTTextStorage
    private let contentStorage: TTTextContentStorage
    private let textLayout: NSTextLayoutManager
    private let input: TeakInputTextView
    private let theme: TeakTextTheme
    private let lineNumbers = TeakLineNumberView(frame: .zero)
    private let textRenderer = TeakTextRenderView(frame: .zero)
    private var lineNumberWidth: NSLayoutConstraint?
    private let io = TeakDocumentIO()
    private let pipeline = TeakPluginPipeline()
    private var plugins: [any TeakTextPlugin] = []
    private var documentID = UUID()
    private var revision: UInt64 = 0
    private var savedRevision: UInt64 = 0
    private var loadID: UUID?
    private var applyingDocument = false
    private var invalidatedFrom: Int? = 0
    private var highlightTask: Task<Void, Never>?
    private var highlightID = UUID()
    private var scheduledRange: NSRange?
    private var scheduledRevision: UInt64?
    private var highlightCache = TeakHighlightCache()
    private var tokenCount = 0
    private var highlightMilliseconds = 0.0
    private var highlighting = false

    public var onMetricsChange: ((TeakEditorMetrics) -> Void)?
    public var onPluginError: ((Error) -> Void)?
    public var showsLineNumbers = true {
        didSet { setNeedsLayout() }
    }
    public var isEditable = true {
        didSet { input.isEditable = isEditable && loadID == nil }
    }
    public var selectedRange: NSRange {
        get { input.selectedRange }
        set {
            guard newValue.location >= 0, newValue.length >= 0,
                  newValue.location <= storage.length,
                  newValue.length <= storage.length - newValue.location else { return }
            input.selectedRange = newValue
        }
    }
    public var snapshot: TeakDocumentSnapshot { TeakDocumentSnapshot(native: storage.snapshot) }
    public var isDirty: Bool { revision != savedRevision }
    public override var undoManager: UndoManager? { input.undoManager }
    public var metrics: TeakEditorMetrics {
        let document = snapshot
        return TeakEditorMetrics(utf16Count: document.utf16Count, lineCount: document.lineCount,
            chunkCount: document.chunkCount, revision: revision, isDirty: isDirty,
            isLoading: loadID != nil, isHighlighting: highlighting,
            highlightedTokenCount: tokenCount, lastHighlightMilliseconds: highlightMilliseconds)
    }

    public init(frame: CGRect = .zero, theme: TeakTextTheme = TeakTextTheme()) {
        self.theme = theme
        let paragraph = NSMutableParagraphStyle()
        paragraph.defaultTabInterval = theme.font.pointSize * 2.4
        storage = TTTextStorage(attributes: [.font: theme.font, .foregroundColor: theme.foregroundColor,
                                            .paragraphStyle: paragraph])
        contentStorage = TTTextContentStorage()
        textLayout = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        contentStorage.textStorage = storage
        contentStorage.addTextLayoutManager(textLayout)
        textLayout.textContainer = container
        input = TeakInputTextView(frame: .zero, textContainer: container)
        super.init(frame: frame)
        input.translatesAutoresizingMaskIntoConstraints = false
        input.backgroundColor = theme.backgroundColor
        input.font = theme.font
        input.textColor = theme.foregroundColor
        input.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        input.contentInsetAdjustmentBehavior = .never
        input.automaticallyAdjustsScrollIndicatorInsets = false
        input.alwaysBounceVertical = true
        input.autocorrectionType = .no
        input.spellCheckingType = .no
        input.smartDashesType = .no
        input.smartQuotesType = .no
        input.smartInsertDeleteType = .no
        input.autocapitalizationType = .none
        input.textContentType = nil
        if #available(iOS 18.0, *) { input.writingToolsBehavior = .none }
        input.keyboardDismissMode = .interactive
        input.allowsEditingTextAttributes = false
        input.delegate = self
        // NSTextStorageDelegate predates actor annotations. TTTextStorage enforces
        // main-thread mutation and UIKit invokes its delegate synchronously there.
        storage.delegate = self
        storage.didReplaceCharacters = { [weak self, weak contentStorage] range, length in
            // TTTextStorage commits on the main thread before notifying TextKit.
            // Map every primitive edit, including IME/undo and coalesced edits.
            MainActor.assumeIsolated { () -> Void in
                contentStorage?.finishReplacement(in: range, replacementLength: length)
                guard let self else { return }
                if !self.applyingDocument {
                    self.highlightCache.applyEdit(replacing: range, replacementLength: Int(length))
                }
            }
        }
        // This layout manager belongs exclusively to UITextView on the main thread.
        // Keep native layout synchronous; parsing remains on the plugin actors.
        textLayout.layoutQueue = nil
        textLayout.delegate = self
        textLayout.renderingAttributesValidator = { [weak self] _, fragment in
            MainActor.assumeIsolated { () -> Void in self?.restoreHighlights(in: fragment) }
        }
        lineNumbers.translatesAutoresizingMaskIntoConstraints = false
        lineNumbers.textView = input
        lineNumbers.font = .monospacedDigitSystemFont(ofSize: theme.font.pointSize, weight: .regular)
        lineNumbers.foregroundColor = theme.lineNumberColor
        lineNumbers.backgroundColor = theme.lineNumberBackgroundColor
        addSubview(lineNumbers)
        addSubview(input)
        textRenderer.textView = input
        input.addSubview(textRenderer)
        let width = lineNumbers.widthAnchor.constraint(equalToConstant: 0)
        lineNumberWidth = width
        NSLayoutConstraint.activate([
            lineNumbers.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumbers.topAnchor.constraint(equalTo: topAnchor),
            lineNumbers.bottomAnchor.constraint(equalTo: bottomAnchor),
            width,
            input.leadingAnchor.constraint(equalTo: lineNumbers.trailingAnchor),
            input.trailingAnchor.constraint(equalTo: trailingAnchor),
            input.topAnchor.constraint(equalTo: topAnchor),
            input.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        // Do not access input.layoutManager: it would switch UITextView to TextKit 1.
        assert(input.textLayoutManager === textLayout)
        input.onDidLayout = { [weak self] in
            guard let self else { return }
            self.lineNumbers.document = self.snapshot
            self.lineNumbers.setNeedsDisplay()
            self.updateTextRendering()
            self.scheduleHighlights()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:theme:)") }

    deinit { highlightTask?.cancel() }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateBottomSafeAreaInsets()
        lineNumbers.document = snapshot
        lineNumbers.isHidden = !showsLineNumbers
        let width = showsLineNumbers ? lineNumbers.preferredWidth : 0
        if lineNumberWidth?.constant != width { lineNumberWidth?.constant = width }
        lineNumbers.setNeedsDisplay()
        updateTextRendering()
        scheduleHighlights()
    }

    public override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateBottomSafeAreaInsets()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            highlightTask?.cancel()
            scheduledRange = nil
            highlighting = false
        } else { scheduleHighlights() }
    }

    public func focus() { input.becomeFirstResponder() }
    public func dismissKeyboard() { input.resignFirstResponder() }
    public func selectAll() { input.selectAll(nil) }
    public func undo() { input.undoManager?.undo() }
    public func redo() { input.undoManager?.redo() }

    public func load(text: String) async throws {
        let id = beginLoad()
        defer { finishLoad(id) }
        let document = try await io.prepare(text: text)
        try publish(document, loadID: id)
    }

    public func open(fileURL: URL) async throws {
        let id = beginLoad()
        defer { finishLoad(id) }
        let document = try await io.open(url: fileURL)
        try publish(document, loadID: id)
    }

    /// Saves a point-in-time snapshot; edits made during a save remain dirty.
    public func save(to fileURL: URL) async throws {
        let document = snapshot
        let id = documentID
        let savingRevision = revision
        try await io.save(document, to: fileURL)
        if id == documentID {
            savedRevision = savingRevision
            reportMetrics()
        }
    }

    public func installPlugin(_ plugin: any TeakTextPlugin) {
        plugins.removeAll { $0.id == plugin.id }
        plugins.append(plugin)
        resetPlugins()
    }

    public func removePlugin(id: String) {
        plugins.removeAll { $0.id == id }
        resetPlugins()
    }

    public func removeAllPlugins() {
        plugins.removeAll()
        resetPlugins()
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        lineNumbers.setNeedsDisplay()
        updateTextRendering()
        scheduleHighlights()
    }

    public func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                                  textLayoutFragmentFor location: any NSTextLocation,
                                  in textElement: NSTextElement) -> NSTextLayoutFragment {
        TeakTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }

    public func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                         suggestedActions: [UIMenuElement]) -> UIMenu? {
        input.editingMenu()
    }

    @available(iOS 26.0, *)
    public func textView(_ textView: UITextView, editMenuForTextInRanges ranges: [NSValue],
                         suggestedActions: [UIMenuElement]) -> UIMenu? {
        input.editingMenu()
    }

    public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions,
                            range editedRange: NSRange, changeInLength _: Int) {
        guard editedMask.contains(.editedCharacters), !applyingDocument else { return }
        revision &+= 1
        textRenderer.invalidateAll()
        invalidatedFrom = min(invalidatedFrom ?? editedRange.location, editedRange.location)
        highlightTask?.cancel()
        highlightID = UUID()
        // Colors have already followed the primitive edits. Keep them available
        // to TextKit's validator while a new revision is parsed in the background.
        tokenCount = highlightCache.spans.count
        scheduledRange = nil
        highlighting = false
        reportMetrics()
        setNeedsLayout()
    }

    private func beginLoad() -> UUID {
        let id = UUID()
        loadID = id
        input.isEditable = false
        input.unmarkText()
        reportMetrics()
        return id
    }

    private func finishLoad(_ id: UUID) {
        guard loadID == id else { return }
        loadID = nil
        input.isEditable = isEditable
        reportMetrics()
        // Opening the load gate must schedule native layout even if an earlier
        // pass ran while loading and therefore could not request highlighting.
        input.setNeedsLayout()
        setNeedsLayout()
    }

    private func publish(_ document: TeakDocumentSnapshot, loadID id: UUID) throws {
        try Task.checkCancellation()
        guard loadID == id else { throw TeakTextError.loadSuperseded }
        highlightTask?.cancel()
        highlightID = UUID()
        clearHighlights()
        textRenderer.resetDocument()
        applyingDocument = true
        storage.installSnapshot(document.native)
        applyingDocument = false
        documentID = UUID()
        revision = 0
        savedRevision = 0
        invalidatedFrom = 0
        input.selectedRange = NSRange(location: 0, length: 0)
        input.setContentOffset(.zero, animated: false)
        input.undoManager?.removeAllActions()
        scheduledRange = nil
        scheduledRevision = nil
        highlighting = false
        reportMetrics()
        setNeedsLayout()
    }

    private func resetPlugins() {
        highlightTask?.cancel()
        highlightID = UUID()
        scheduledRange = nil
        invalidatedFrom = 0
        if plugins.isEmpty { clearHighlights() }
        highlighting = false
        reportMetrics()
        // A plugin can become available after native viewport layout has finished.
        scheduleHighlights()
        setNeedsLayout()
    }

    private func viewportRange() -> NSRange? {
        guard let viewport = textLayout.textViewportLayoutController.viewportRange else { return nil }
        // The native viewport contains whole layout fragments (usually paragraphs).
        // A minified file can be one paragraph: intersect its already-laid-out
        // visual rows with the screen instead of highlighting the entire element.
        let bounds = input.bounds.offsetBy(dx: -input.textContainerInset.left,
                                         dy: -input.textContainerInset.top)
        guard bounds.height > 0 else { return nil }
        var start: Int?
        var end = 0
        textLayout.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
            guard fragment.state == .layoutAvailable else { return false }
            let origin = fragment.layoutFragmentFrame.minY
            if origin > bounds.maxY { return false }
            guard let element = fragment.textElement?.elementRange else { return true }
            let elementOffset = self.contentStorage.offset(from: self.contentStorage.documentRange.location,
                                                           to: element.location)
            guard elementOffset >= 0, elementOffset <= self.storage.length else { return false }
            let lines = fragment.textLineFragments
            var lower = 0
            var upper = lines.count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if origin + lines[middle].typographicBounds.maxY < bounds.minY { lower = middle + 1 }
                else { upper = middle }
            }
            var index = lower
            while index < lines.count {
                let line = lines[index]
                if origin + line.typographicBounds.minY > bounds.maxY { break }
                let range = line.characterRange
                guard range.location >= 0, range.length >= 0,
                      range.location <= self.storage.length - elementOffset,
                      range.length <= self.storage.length - elementOffset - range.location else { return false }
                let offset = elementOffset + range.location
                start = min(start ?? offset, offset)
                end = max(end, offset + range.length)
                index += 1
            }
            return fragment.layoutFragmentFrame.maxY < bounds.maxY
        }
        guard let start, end > start else { return nil }
        // Stable overscan windows avoid cancelling/restarting the actor request
        // for every visual row crossed during scrolling.
        let lower = max(0, start / Constants.highlightOverscan * Constants.highlightOverscan
                        - Constants.highlightOverscan)
        let upper = min(storage.length,
            (end / Constants.highlightOverscan + 2) * Constants.highlightOverscan)
        return NSRange(location: lower, length: min(Constants.maximumHighlightLength,
            upper - lower))
    }

    private func scheduleHighlights() {
        guard window != nil, loadID == nil, !plugins.isEmpty, storage.length > 0,
              let range = viewportRange(), range.length > 0 else { return }
        guard scheduledRange != range || scheduledRevision != revision else { return }
        highlightTask?.cancel()
        let id = UUID()
        highlightID = id
        scheduledRange = range
        scheduledRevision = revision
        let request = TeakHighlightRequest(documentID: documentID, revision: revision,
            snapshot: snapshot, range: range, invalidatedFrom: invalidatedFrom)
        let plugins = plugins
        let pipeline = pipeline
        let supportedScopes = Set(theme.scopeColors.keys)
        highlighting = true
        reportMetrics()
        highlightTask = Task { [weak self] in
            do {
                let started = ContinuousClock.now
                let presentation = try await pipeline.presentation(for: request, plugins: plugins,
                    supportedScopes: supportedScopes)
                try Task.checkCancellation()
                guard let self, self.highlightID == id, self.documentID == request.documentID,
                      self.revision == request.revision else { return }
                self.commitHighlights(presentation)
                self.invalidatedFrom = nil
                let elapsed = started.duration(to: .now).components
                self.highlightMilliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
                self.highlighting = false
                // Rendering attributes don't change storage or glyph metrics;
                // ask the native view to present the newly committed colors.
                self.input.setNeedsLayout()
                self.input.setNeedsDisplay()
                self.reportMetrics()
            } catch is CancellationError {
                // A newer viewport, revision, plugin set or teardown owns the next result.
            } catch {
                guard let self, self.highlightID == id else { return }
                self.highlighting = false
                self.onPluginError?(error)
                self.reportMetrics()
            }
        }
    }

    private func nativeRange(_ range: NSRange) -> NSTextRange? {
        guard range.location <= storage.length, range.length <= storage.length - range.location,
              let start = contentStorage.location(contentStorage.documentRange.location, offsetBy: range.location),
              let end = contentStorage.location(start, offsetBy: range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    private func clearHighlights() {
        commitHighlights(TeakHighlightCache())
    }

    private func commitHighlights(_ presentation: TeakHighlightCache) {
        let changes = presentation.changes(from: highlightCache)
        // Publish the cache first: any synchronous native validation observes the
        // same complete result. No await or blank-color frame between updates.
        highlightCache = presentation
        tokenCount = presentation.spans.count
        applyHighlights(changes)
        textRenderer.invalidate(changes)
    }

    private func restoreHighlights(in fragment: NSTextLayoutFragment) {
        guard !applyingDocument else { return }
        let range = fragment.rangeInElement
        let start = contentStorage.offset(from: contentStorage.documentRange.location, to: range.location)
        let end = contentStorage.offset(from: contentStorage.documentRange.location, to: range.endLocation)
        guard start >= 0, end > start, end <= storage.length else { return }
        // Apple invalidates rendering attributes when a fragment is laid out again.
        // Reapply retained colors synchronously before drawing, without lexing or I/O.
        applyHighlights(highlightCache.attributes(in: NSRange(location: start, length: end - start)))
    }

    private func applyHighlights(_ changes: [TeakHighlightChange]) {
        for change in changes {
            guard let range = nativeRange(change.range) else { continue }
            let attributes: [NSAttributedString.Key: Any]
            if let scope = change.scope, let color = theme.scopeColors[scope] {
                attributes = [.foregroundColor: color]
            } else { attributes = [:] }
            textLayout.setRenderingAttributes(attributes, for: range)
        }
    }

    private func updateBottomSafeAreaInsets() {
        let bottom = safeAreaInsets.bottom
        if input.contentInset.bottom != bottom {
            var insets = input.contentInset
            insets.bottom = bottom
            input.contentInset = insets
        }
        if input.verticalScrollIndicatorInsets.bottom != bottom {
            var insets = input.verticalScrollIndicatorInsets
            insets.bottom = bottom
            input.verticalScrollIndicatorInsets = insets
        }
    }

    private func updateTextRendering() {
        textRenderer.updateViewport()
    }

    private func reportMetrics() { onMetricsChange?(metrics) }
}

private extension TeakTextView {
    enum Constants {
        static let highlightOverscan = 2048
        static let maximumHighlightLength = 65_536
    }
}
#endif

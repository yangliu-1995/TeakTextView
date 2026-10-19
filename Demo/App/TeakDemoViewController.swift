import UIKit
import UniformTypeIdentifiers
import TeakTextView
import TeakTextCore

@MainActor
final class TeakDemoViewController: UIViewController, UIDocumentPickerDelegate {
    private let editor = TeakTextView()
    private let status = UILabel()
    private let performance = TeakPerformanceMonitor()
    private let files = TeakDemoFiles()
    private let languages = TeakLanguageRegistry()
    private var documentURL: URL?
    private let samples: TeakDemoLanguageSamples
    private var activeSample: TeakDemoSourceFile?
    private var availableLanguages: [TeakLanguageDefinition] = []
    private var customLanguage: TeakLanguageDefinition?
    private var languageSelection = TeakDemoLanguageSelection.automatic
    private var syntaxEnabled = true
    private var importingLanguage = false
    private var operation: Task<Void, Never>?
    private var languageOperation: Task<Void, Never>?
    private var languageGeneration = UUID()
    private var fps = 0.0
    private var memory = 0.0

    init(samples: TeakDemoLanguageSamples) {
        self.samples = samples
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: String.LocalizationValue(samples.displayName))
        view.backgroundColor = .systemBackground
        // Keep the editor edge-to-edge when the keyboard is hidden. The editor
        // applies the home-indicator safe area to its scroll content instead.
        view.keyboardLayoutGuide.usesBottomSafeArea = false
        editor.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabel
        status.numberOfLines = 2
        view.addSubview(editor)
        view.addSubview(status)
        NSLayoutConstraint.activate([
            status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            status.heightAnchor.constraint(equalToConstant: 36),
            editor.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 4),
            editor.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        configureMenu()
        editor.onMetricsChange = { [weak self] _ in self?.updateStatus() }
        editor.onPluginError = { [weak self] error in self?.showError(error) }
        performance.onUpdate = { [weak self] fps, memory in
            self?.fps = fps
            self?.memory = memory
            self?.updateStatus()
        }
        loadSample(samples.normal)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        performance.start()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        performance.stop()
    }

    deinit {
        operation?.cancel()
        languageOperation?.cancel()
    }

    private func configureMenu() {
        let sampleMenu = UIMenu(title: String(localized: "Demo files"), children: [
            UIAction(title: String(localized: "Normal file") + " · " + samples.normal.sizeDescription,
                     state: activeSample?.resourcePath == samples.normal.resourcePath ? .on : .off) { [weak self] _ in
                guard let self else { return }; self.loadSample(self.samples.normal)
            },
            UIAction(title: String(localized: "Large file") + " · " + samples.large.sizeDescription,
                     state: activeSample?.resourcePath == samples.large.resourcePath ? .on : .off) { [weak self] _ in
                guard let self else { return }; self.loadSample(self.samples.large)
            },
            UIAction(title: String(localized: "View source on GitHub"), image: UIImage(systemName: "link"),
                     attributes: activeSample == nil ? .disabled : []) { [weak self] _ in
                guard let url = self?.activeSample?.sourceURL else { return }
                UIApplication.shared.open(url)
            },
            UIAction(title: String(localized: "Open Source Notices")) { [weak self] _ in self?.showNotices() }
        ])
        let menu = UIMenu(children: [
            sampleMenu,
            languageMenu(),
            UIAction(title: String(localized: "Open file…"), image: UIImage(systemName: "folder")) { [weak self] _ in self?.pickFile(language: false) },
            UIAction(title: String(localized: "Plain text input")) { [weak self] _ in self?.loadPlainText() },
            UIAction(title: String(localized: "Save"), image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in self?.save() },
            UIAction(title: String(localized: "Export copy")) { [weak self] _ in self?.exportCopy() },
            UIAction(title: String(localized: "Load language rules…")) { [weak self] _ in self?.pickFile(language: true) },
            UIAction(title: String(localized: "Line numbers"), state: editor.showsLineNumbers ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.editor.showsLineNumbers.toggle()
                self.configureMenu()
            },
            UIAction(title: String(localized: "Syntax highlighting"), state: syntaxEnabled ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.syntaxEnabled.toggle(); self.applyLanguage(); self.configureMenu()
            },
            UIAction(title: String(localized: "Read only"), state: editor.isEditable ? .off : .on) { [weak self] _ in
                guard let self else { return }
                self.editor.isEditable.toggle(); self.configureMenu()
            },
            UIAction(title: String(localized: "Select all")) { [weak self] _ in self?.editor.focus(); self?.editor.selectAll() },
            UIAction(title: String(localized: "Undo")) { [weak self] _ in self?.editor.undo() },
            UIAction(title: String(localized: "Redo")) { [weak self] _ in self?.editor.redo() },
            UIAction(title: String(localized: "Dismiss keyboard")) { [weak self] _ in self?.editor.dismissKeyboard() }
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: menu)
    }

    private func languageMenu() -> UIMenu {
        var choices = [
            UIAction(title: String(localized: "Automatic"), state: languageSelection == .automatic ? .on : .off) { [weak self] _ in
                self?.selectLanguage(.automatic)
            },
            UIAction(title: String(localized: "Plain text"), state: languageSelection == .plainText ? .on : .off) { [weak self] _ in
                self?.selectLanguage(.plainText)
            }
        ]
        var definitions = availableLanguages
        if let customLanguage {
            definitions.removeAll { $0.id == customLanguage.id }
            definitions.append(customLanguage)
        }
        choices += definitions.map { definition in
            UIAction(title: String(localized: String.LocalizationValue(definition.displayName)),
                     state: languageSelection == .language(definition.id) ? .on : .off) { [weak self] _ in
                self?.selectLanguage(.language(definition.id))
            }
        }
        return UIMenu(title: String(localized: "Language"), children: choices)
    }

    private func selectLanguage(_ selection: TeakDemoLanguageSelection) {
        languageSelection = selection
        applyLanguage()
        configureMenu()
    }

    private func loadSample(_ sample: TeakDemoSourceFile) {
        run { [self] in
            let url = try await files.sample(sample)
            try Task.checkCancellation()
            try await editor.open(fileURL: url)
            try Task.checkCancellation()
            documentURL = url
            activeSample = sample
            navigationItem.prompt = sample.fileName
            languageSelection = .automatic
            applyLanguage()
            configureMenu()
        }
    }

    private func showNotices() {
        run { [self] in
            let text = try await files.notices(samples)
            try Task.checkCancellation()
            navigationController?.pushViewController(TeakDemoNoticesViewController(text: text), animated: true)
        }
    }

    private func loadPlainText() {
        run { [self] in
            try await editor.load(text: "// Teak plain text input\nconst message = 'Hello, 中文 😃';\nconsole.log(message);\n")
            try Task.checkCancellation()
            documentURL = nil
            activeSample = nil
            languageSelection = .plainText
            applyLanguage()
            configureMenu()
            navigationItem.prompt = String(localized: "Plain text input")
        }
    }

    private func pickFile(language: Bool) {
        importingLanguage = language
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: language ? [.json] : [.text, .sourceCode, .data], asCopy: false)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        if importingLanguage {
            languageOperation?.cancel()
            let generation = UUID()
            languageGeneration = generation
            languageOperation = Task { [weak self] in
                guard let self else { return }
                do {
                    let language = try await self.languages.load(url: url)
                    let plugin = try await self.languages.makeHighlighter(language: language)
                    try Task.checkCancellation()
                    guard self.languageGeneration == generation else { return }
                    self.customLanguage = language
                    self.languageSelection = .language(language.id)
                    self.syntaxEnabled = true
                    self.editor.removeAllPlugins()
                    self.editor.installPlugin(plugin)
                    self.configureMenu()
                } catch is CancellationError {} catch {
                    if self.languageGeneration == generation { self.showError(error) }
                }
            }
        } else {
            run { [self] in
                try await editor.open(fileURL: url)
                try Task.checkCancellation()
                documentURL = url
                activeSample = nil
                languageSelection = .automatic
                navigationItem.prompt = url.lastPathComponent
                applyLanguage()
                configureMenu()
            }
        }
    }

    private func applyLanguage() {
        languageOperation?.cancel()
        let generation = UUID()
        languageGeneration = generation
        editor.removeAllPlugins()
        languageOperation = Task { [weak self] in
            guard let self else { return }
            do {
                let definitions = try await self.languages.bundledLanguages()
                try Task.checkCancellation()
                guard self.languageGeneration == generation else { return }
                self.availableLanguages = definitions
                self.configureMenu()
                guard self.syntaxEnabled else { return }
                let language: TeakLanguageDefinition?
                switch self.languageSelection {
                case .automatic:
                    if self.activeSample != nil {
                        // The catalog disambiguates shared suffixes such as C/C++ .h.
                        language = definitions.first { $0.id == self.samples.languageID }
                    } else {
                        let prefix = try self.editor.snapshot.text(in: NSRange(location: 0, length: min(1_024, self.editor.snapshot.utf16Count)))
                        language = TeakLanguageRegistry.detect(fileName: self.documentURL?.lastPathComponent,
                                                              firstLine: prefix, among: definitions)
                    }
                case .plainText: language = nil
                case let .language(id):
                    language = self.customLanguage?.id == id ? self.customLanguage : definitions.first { $0.id == id }
                }
                guard let language else { return }
                let plugin = try await self.languages.makeHighlighter(language: language)
                try Task.checkCancellation()
                guard self.languageGeneration == generation else { return }
                self.editor.installPlugin(plugin)
            } catch is CancellationError {} catch {
                if self.languageGeneration == generation { self.showError(error) }
            }
        }
    }

    private func save() {
        guard let url = documentURL else { exportCopy(); return }
        run { [self] in try await editor.save(to: url) }
    }

    private func exportCopy() {
        let snapshot = editor.snapshot
        run { [self] in
            let url = try await files.export(snapshot, fileName: documentURL?.lastPathComponent ?? "Teak-Export.txt")
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            present(picker, animated: true)
        }
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        operation?.cancel()
        operation = Task { [weak self] in
            do { try await action() }
            catch is CancellationError {}
            catch TeakTextError.loadSuperseded {}
            catch { self?.showError(error) }
        }
    }

    private func updateStatus() {
        let value = editor.metrics
        let state = value.isLoading ? String(localized: "Loading")
            : value.isHighlighting ? String(localized: "Highlighting")
            : value.isDirty ? String(localized: "Modified") : String(localized: "Ready")
        status.text = String(format: String(localized: "%d lines · %d UTF-16 · %d chunks · %@\n%.0f FPS · %.1f MiB · %.1f ms highlight"),
            value.lineCount, value.utf16Count, value.chunkCount, state, fps, memory, value.lastHighlightMilliseconds)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: String(localized: "Could not complete the operation"),
            message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}

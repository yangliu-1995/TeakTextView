import Foundation
import TeakTextCore

actor TeakDemoFiles {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    private var copies: [String: URL] = [:]

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func catalog() throws -> [TeakDemoLanguageSamples] {
        let url = try resourceURL("catalog.json")
        return try JSONDecoder().decode([TeakDemoLanguageSamples].self, from: Data(contentsOf: url))
    }

    /// Resources retain their upstream filename and suffix. Only these private
    /// copies can be edited or saved; the bundled source and notices stay intact.
    func sample(_ sample: TeakDemoSourceFile) throws -> URL {
        try Task.checkCancellation()
        if let copy = copies[sample.resourcePath] { return copy }
        let source = try resourceURL(sample.resourcePath)
        let target = directory.appendingPathComponent(UUID().uuidString).appendingPathComponent(sample.fileName)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: target)
        copies[sample.resourcePath] = target
        return target
    }

    func export(_ snapshot: TeakDocumentSnapshot, fileName: String) async throws -> URL {
        let target = directory.appendingPathComponent(UUID().uuidString).appendingPathComponent(fileName)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await TeakDocumentIO().save(snapshot, to: target)
        return target
    }

    func notices(_ samples: TeakDemoLanguageSamples) throws -> String {
        try samples.licensePaths.map { path in
            let text = try String(contentsOf: resourceURL(path), encoding: .utf8)
            return path + "\n\n" + text
        }.joined(separator: "\n\n────────────────\n\n")
    }

    private func resourceURL(_ path: String) throws -> URL {
        guard let root = Bundle.main.resourceURL else { throw CocoaError(.fileNoSuchFile) }
        let url = root.appendingPathComponent("Samples").appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileNoSuchFile) }
        return url
    }
}

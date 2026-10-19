import Foundation
import Testing
@testable import TeakTextCore

struct TeakLanguageTests {
    @Test func bundledCatalogAndFileDetection() async throws {
        let definitions = try await TeakLanguageRegistry().bundledLanguages()
        #expect(definitions.count == 19)
        #expect(Set(definitions.map(\.id)).count == 19)
        for definition in definitions {
            try definition.validate()
            let suffix = try #require(definition.fileExtensions.first)
            #expect(TeakLanguageRegistry.detect(fileName: "sample." + suffix.uppercased(), among: definitions)?.id == definition.id)
        }
        #expect(TeakLanguageRegistry.detect(fileName: "Cargo.lock", among: definitions)?.id == "toml")
        #expect(TeakLanguageRegistry.detect(fileName: "a.d.ts", among: definitions)?.id == "typescript")
        #expect(TeakLanguageRegistry.detect(fileName: "script", firstLine: "#!/usr/bin/env -S python3.12 -u\n", among: definitions)?.id == "python")
        #expect(TeakLanguageRegistry.detect(fileName: nil, firstLine: "#!/bin/bash\n", among: definitions)?.id == "bash")
        #expect(TeakLanguageRegistry.detect(fileName: nil, firstLine: "#!/bin/echo python\n", among: definitions) == nil)
        #expect(TeakLanguageRegistry.detect(fileName: "unknown.xyz", among: definitions) == nil)
    }

    @Test func lexicalScopesCoverMarkupConfigAndCaseInsensitiveSQL() async throws {
        let examples = [
            ("typescript", "interface Shape { size: number }", "interface", "keyword"),
            ("python", "def answer(): return None", "None", "literal"),
            ("html", "<my-element data-id=\"42\">", "my-element", "tag"),
            ("html", "<my-element data-id=\"42\">", "data-id", "attribute"),
            ("css", ".item { background-color: red; }", "background-color", "property"),
            ("markdown", "# Heading\n`let value = 42`", "# Heading", "heading"),
            ("sql", "sElEcT value FrOm records", "sElEcT", "keyword"),
            ("bash", "echo $HOME", "$HOME", "variable"),
            ("yaml", "some-key: true", "some-key", "property"),
            ("toml", "some-key = true", "some-key", "property"),
            ("json", "{\"value\": true}", "true", "literal")
        ]
        let registry = TeakLanguageRegistry()
        for (id, text, word, scope) in examples {
            let language = try await registry.bundledLanguage(id: id)
            let plugin = try TeakRuleHighlighter(language: language)
            let snapshot = try await TeakDocumentIO().prepare(text: text)
            let spans = try await plugin.highlights(for: TeakHighlightRequest(documentID: UUID(), revision: 0,
                snapshot: snapshot, range: NSRange(location: 0, length: snapshot.utf16Count), invalidatedFrom: 0))
            #expect(spans.contains { $0.scope == scope && $0.range == (text as NSString).range(of: word) })
        }
    }

    @Test func nestedCommentCheckpointAndRustLifetimeKeepFollowingCodeVisible() async throws {
        let language = try await TeakLanguageRegistry().bundledLanguage(id: "rust")
        let plugin = try TeakRuleHighlighter(language: language)
        let text = "/* outer /* " + String(repeating: "x", count: 17_000) + " */ still comment */ fn borrow<'a>(x: &'a str) { let c = '😃'; }"
        let snapshot = try await TeakDocumentIO().prepare(text: text)
        let documentID = UUID()
        _ = try await plugin.highlights(for: TeakHighlightRequest(documentID: documentID, revision: 0,
            snapshot: snapshot, range: NSRange(location: 8_000, length: 9_000), invalidatedFrom: 0))
        let range = NSRange(location: 16_900, length: snapshot.utf16Count - 16_900)
        let spans = try await plugin.highlights(for: TeakHighlightRequest(documentID: documentID, revision: 0,
            snapshot: snapshot, range: range, invalidatedFrom: nil))
        #expect(spans.contains { $0.scope == "keyword" && $0.range == (text as NSString).range(of: "fn") })
        #expect(spans.contains { $0.scope == "keyword" && $0.range == (text as NSString).range(of: "let") })
        #expect(spans.contains { $0.scope == "string" && $0.range == (text as NSString).range(of: "'😃'") })
    }
}

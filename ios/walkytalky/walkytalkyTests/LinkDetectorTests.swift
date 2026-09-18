//
//  LinkDetectorTests.swift
//  walkytalkyTests
//

import Foundation
import Testing
@testable import walkytalky

struct LinkDetectorTests {
    @Test func detectsAnHTTPSLinkAndMarksItTappable() {
        let attributed = LinkDetector.attributedString(from: "Check https://example.com out")
        let links = attributed.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://example.com")!])
    }

    @Test func detectsMultipleLinksInTheSameMessage() {
        let attributed = LinkDetector.attributedString(from: "https://a.com and https://b.com")
        let links = attributed.runs.compactMap(\.link)
        #expect(links.count == 2)
    }

    @Test func plainTextWithNoURLHasNoLinks() {
        let attributed = LinkDetector.attributedString(from: "just plain text, no links here")
        #expect(attributed.runs.compactMap(\.link).isEmpty)
    }

    @Test func bareDomainWithoutAnExplicitSchemeIsStillDetected() {
        let attributed = LinkDetector.attributedString(from: "visit example.com today")
        #expect(!attributed.runs.compactMap(\.link).isEmpty)
    }

    @Test func plainTextContentIsPreservedUnchanged() {
        let original = "hello https://example.com world"
        let attributed = LinkDetector.attributedString(from: original)
        #expect(String(attributed.characters) == original)
    }
}

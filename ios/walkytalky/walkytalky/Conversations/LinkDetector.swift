import Foundation
import SwiftUI

/// Finds URLs in decrypted message text and marks them as tappable links,
/// so `Text` renders them as such. Tapping is intercepted by
/// `ChatThreadView`'s `openURL` override to open in the in-app browser
/// instead of the system browser — this file only does detection, not
/// navigation.
enum LinkDetector {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func attributedString(from text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector else { return attributed }

        let matches = detector.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
        for match in matches {
            guard let url = match.url, let range = Range(match.range, in: attributed) else { continue }
            attributed[range].link = url
            attributed[range].underlineStyle = .single
        }
        return attributed
    }
}

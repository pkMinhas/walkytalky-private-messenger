//
//  AnonymousSignInUITests.swift
//  walkytalkyUITests
//

import XCTest

final class AnonymousSignInUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Taps "Continue" on the sign-in screen and confirms the app actually
    /// moves past it — the real thing a `simctl openurl`/screenshot smoke
    /// test can't exercise, since it requires an actual tap plus a live
    /// round trip to Firebase (signInAnonymously + the device-claim
    /// transaction) to complete.
    @MainActor
    func testTappingContinueSignsInAndReachesPasscodeSetup() throws {
        let app = XCUIApplication()
        app.launch()

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        // First-ever sign-in has no passcode yet, so a successful
        // sign-in lands on PasscodeSetupView next.
        let createPasscodeText = app.staticTexts["Create a passcode"]
        XCTAssertTrue(createPasscodeText.waitForExistence(timeout: 15))
    }

    /// Full flow: sign in, set a passcode, land on the empty chat list, then
    /// use its "View My User ID" action — the feature an admin needs so
    /// they know which uid to add to a `conversations/{id}` doc.
    @MainActor
    func testViewMyUserIDFromEmptyChatList() throws {
        let app = XCUIApplication()
        app.launch()

        let continueButton = app.buttons["Continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        XCTAssertTrue(app.staticTexts["Create a passcode"].waitForExistence(timeout: 15))
        app.typeText("135790")
        XCTAssertTrue(app.staticTexts["Confirm your passcode"].waitForExistence(timeout: 5))
        app.typeText("135790")

        let viewMyUserIDButton = app.buttons["View My User ID"]
        XCTAssertTrue(viewMyUserIDButton.waitForExistence(timeout: 10))
        viewMyUserIDButton.tap()

        XCTAssertTrue(app.navigationBars["My User ID"].waitForExistence(timeout: 5))
        // The uid itself is rendered as a Text with .textSelection(.enabled),
        // which XCUITest exposes as a static text element — just confirm
        // *some* alphanumeric id string of plausible length is shown, not
        // its exact value. Firebase anonymous uids are 28 characters.
        let uidPredicate = NSPredicate(format: "label MATCHES %@", "^[A-Za-z0-9]{10,}$")
        let uidText = app.staticTexts.matching(uidPredicate).firstMatch
        XCTAssertTrue(uidText.waitForExistence(timeout: 5))

        let copyButton = app.buttons["Copy"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 5))
        copyButton.tap()
        XCTAssertTrue(app.buttons["Copied"].waitForExistence(timeout: 5))
    }
}

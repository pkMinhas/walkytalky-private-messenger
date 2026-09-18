//
//  PasscodeTests.swift
//  walkytalkyTests
//

import Foundation
import SwiftUI
import Testing
@testable import walkytalky

struct PBKDF2Tests {
    @Test func sameInputsProduceSameHash() {
        let salt = PBKDF2.randomSalt()
        let a = PBKDF2.hash(password: "123456", salt: salt)
        let b = PBKDF2.hash(password: "123456", salt: salt)
        #expect(a == b)
        #expect(a.count == PBKDF2.keyLength)
    }

    @Test func differentSaltsProduceDifferentHashes() {
        let saltA = PBKDF2.randomSalt()
        let saltB = PBKDF2.randomSalt()
        #expect(saltA != saltB)
        let hashA = PBKDF2.hash(password: "123456", salt: saltA)
        let hashB = PBKDF2.hash(password: "123456", salt: saltB)
        #expect(hashA != hashB)
    }

    @Test func differentPasswordsProduceDifferentHashes() {
        let salt = PBKDF2.randomSalt()
        let hashA = PBKDF2.hash(password: "123456", salt: salt)
        let hashB = PBKDF2.hash(password: "654321", salt: salt)
        #expect(hashA != hashB)
    }

    @Test func constantTimeEqualsMatchesRegularEquality() {
        let salt = PBKDF2.randomSalt()
        let hash = PBKDF2.hash(password: "123456", salt: salt)
        #expect(PBKDF2.constantTimeEquals(hash, hash))
        #expect(!PBKDF2.constantTimeEquals(hash, Data(hash.reversed())))
        #expect(!PBKDF2.constantTimeEquals(hash, Data([0x01])))
    }
}

@MainActor
@Suite(.serialized)
struct PasscodeServiceTests {
    /// PasscodeService reads/writes fixed Keychain account names, so tests
    /// share device Keychain state — clear it before each test for isolation,
    /// and force serial execution (Swift Testing parallelizes by default)
    /// since concurrent tests would otherwise stomp each other's state.
    private func freshService() -> PasscodeService {
        for account in ["passcodeHash", "passcodeSalt", "passcodeFailedAttempts", "passcodeLockoutUntil"] {
            KeychainService.delete(account: account)
        }
        return PasscodeService()
    }

    @Test func startsWithNoPasscode() {
        let service = freshService()
        #expect(service.hasPasscode == false)
    }

    @Test func setThenVerifyCorrectPasscodeSucceeds() async {
        let service = freshService()
        await service.setPasscode("123456")
        #expect(service.hasPasscode)
        #expect(service.isLocked == false)
        #expect(await service.verify("123456"))
    }

    @Test func firstTwoWrongAttemptsDoNotTriggerLockout() async {
        let service = freshService()
        await service.setPasscode("123456")
        #expect(await service.verify("000000") == false)
        #expect(service.isLockedOut == false)
        #expect(await service.verify("111111") == false)
        #expect(service.isLockedOut == false)
    }

    @Test func thirdWrongAttemptTriggersLockout() async {
        let service = freshService()
        await service.setPasscode("123456")
        _ = await service.verify("000000") // 1st failure — no lockout yet
        _ = await service.verify("111111") // 2nd failure — no lockout yet
        #expect(await service.verify("222222") == false) // 3rd failure -> locked out
        // Third failure uses lockoutDelays[0] == 5s.
        #expect(service.isLockedOut)
        #expect(service.lockoutRemaining > 0 && service.lockoutRemaining <= 5)
    }

    @Test func lockoutBlocksFurtherAttemptsWithoutCountingThem() async {
        let service = freshService()
        await service.setPasscode("123456")
        _ = await service.verify("000000") // 1st failure
        _ = await service.verify("111111") // 2nd failure
        _ = await service.verify("222222") // 3rd failure -> locked out ~5s
        #expect(service.isLockedOut)
        // Even the *correct* passcode is rejected while locked out.
        #expect(await service.verify("123456") == false)
    }

    @Test func successfulUnlockResetsTheDelayCurve() async {
        let service = freshService()
        await service.setPasscode("123456")
        _ = await service.verify("000000") // 1st failure
        _ = await service.verify("111111") // 2nd failure
        _ = await service.verify("222222") // 3rd failure: ~5s lockout
        // Wait out the short first-tier lockout so we can unlock and re-check the curve.
        try? await Task.sleep(for: .seconds(6))
        #expect(service.isLockedOut == false)
        #expect(await service.verify("123456")) // resets failed-attempt counter
        _ = await service.verify("000000") // 1st failure again
        _ = await service.verify("111111") // 2nd failure again
        #expect(await service.verify("222222") == false) // 3rd failure -> back at tier 1 (~5s), not tier 2 (~30s)
        #expect(service.lockoutRemaining <= 5)
    }

    @Test func backgroundingLocksImmediatelyWithNoGracePeriod() async {
        let service = freshService()
        await service.setPasscode("123456")
        #expect(service.isLocked == false)

        service.handleScenePhaseChange(.background)
        #expect(service.isLocked) // instant, not after any elapsed time
    }

    @Test func backgroundingIsANoOpBeforeAPasscodeExists() {
        let service = freshService()
        #expect(service.hasPasscode == false)

        service.handleScenePhaseChange(.background)
        #expect(service.isLocked == false) // nothing to lock yet
    }

    @Test func returningToForegroundDoesNotUnlockOnItsOwn() async {
        let service = freshService()
        await service.setPasscode("123456")
        service.handleScenePhaseChange(.background)
        #expect(service.isLocked)

        service.handleScenePhaseChange(.active)
        #expect(service.isLocked) // still locked until verify() succeeds
    }
}

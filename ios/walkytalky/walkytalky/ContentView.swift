//
//  ContentView.swift
//  walkytalky
//
//  Created by Preet Minhas on 11/09/26.
//

import SwiftUI

/// Root router: switches between sign-in, device-conflict, passcode
/// setup/lock, and the signed-in app based on `AuthService.authState` and
/// `PasscodeService` state.
struct ContentView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var passcodeService: PasscodeService

    var body: some View {
        switch authService.authState {
        case .signedOut:
            SignInView()
        case .checkingDevice:
            ProgressView("Signing in…")
        case .deviceConflict:
            DeviceConflictView()
        case .signedIn:
            if !passcodeService.hasPasscode {
                PasscodeSetupView()
            } else if passcodeService.isLocked {
                PasscodeLockView()
            } else {
                ChatListView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthService())
        .environmentObject(PasscodeService())
        .environmentObject(ParticipantDirectory())
}

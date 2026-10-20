//
//  walkytalkyApp.swift
//  walkytalky
//
//  Created by Preet Minhas on 11/09/26.
//

import SwiftUI
import FirebaseCore

@main
struct walkytalkyApp: App {
    // No default value here on purpose: a `@StateObject` property initializer
    // runs before this struct's `init()` body, which would construct
    // AuthService (and touch Auth.auth()) before FirebaseApp.configure() below.
    @StateObject private var authService: AuthService
    @StateObject private var passcodeService = PasscodeService()
    @StateObject private var directory = ParticipantDirectory()
    @StateObject private var lastMessages = LastMessageDirectory()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FirebaseApp.configure()
        _authService = StateObject(wrappedValue: AuthService())
        // Must happen before the app finishes launching, per BGTaskScheduler's
        // own requirement — registering it any later means iOS never learns
        // the task exists.
        BackgroundMessageChecker.registerTask()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(passcodeService)
                .environmentObject(directory)
                .environmentObject(lastMessages)
                .task {
                    MediaStorage.removeLegacyPlaintextCache()
                    MediaCachePurgePolicy.purgeExpiredFiles()
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            passcodeService.handleScenePhaseChange(newPhase)
            switch newPhase {
            case .background:
                // The app locks here too, so decrypted media only ever sits
                // in memory while the app is unlocked and in use.
                MediaMemoryCache.shared.removeAll()
            case .active:
                MediaCachePurgePolicy.purgeExpiredFiles()
            default:
                break
            }
        }
    }
}

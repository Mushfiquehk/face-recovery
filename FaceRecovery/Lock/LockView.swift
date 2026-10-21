import SwiftUI

/// Full-screen cover shown at launch and after the app has been in the background. After five
/// wrong tries the pad pauses for 30 seconds.
struct LockView: View {
    let onUnlock: () -> Void

    @State private var failures = 0
    @State private var isPaused = false

    private static let maxFailures = 5
    private static let pause: Duration = .seconds(30)

    var body: some View {
        PinPad(
            title: "Enter your PIN",
            message: message,
            messageIsError: failures > 0,
            isDisabled: isPaused
        ) { pin in
            if PinStore.verify(pin) {
                onUnlock()
            } else {
                failures += 1
                if failures >= Self.maxFailures { pauseEntry() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .sensoryFeedback(.error, trigger: failures)
    }

    private var message: String? {
        if isPaused { return "Too many wrong tries. Please wait 30 seconds, then try again." }
        return failures > 0 ? "That PIN is not right. Please try again." : nil
    }

    private func pauseEntry() {
        isPaused = true
        Task {
            try? await Task.sleep(for: Self.pause)
            failures = 0
            isPaused = false
        }
    }
}

/// Shown instead of the app contents while the app is not active, so the app switcher
/// snapshot does not reveal a face scan.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
    }
}

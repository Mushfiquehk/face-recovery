import SwiftUI

/// Turn the PIN lock on, change the PIN, or turn it off. Changing and turning off ask for the
/// current PIN first. There is no recovery for a forgotten PIN: deleting the app clears it, along
/// with the scans, so Export is the only way to keep them.
struct PinSetupFlow: View {
    enum Mode {
        case create, change, disable
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case current, new, confirm(first: String)
    }

    @State private var step: Step
    @State private var mismatch = false
    @State private var wrongCurrent = false

    init(mode: Mode) {
        self.mode = mode
        _step = State(initialValue: mode == .create ? .new : .current)
    }

    var body: some View {
        NavigationStack {
            PinPad(
                title: title,
                message: message,
                messageIsError: mismatch || wrongCurrent
            ) { pin in
                handle(pin)
            }
            .id(stepID)
            .sensoryFeedback(.error, trigger: mismatch)
            .sensoryFeedback(.error, trigger: wrongCurrent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var stepID: String {
        switch step {
        case .current: "current"
        case .new: "new"
        case .confirm: "confirm"
        }
    }

    private var title: String {
        switch step {
        case .current: "Enter your current PIN"
        case .new: mode == .change ? "Choose a new 4-digit PIN" : "Choose a 4-digit PIN"
        case .confirm: "Enter it once more"
        }
    }

    private var message: String? {
        if wrongCurrent { return "That PIN is not right. Please try again." }
        if mismatch { return "Those did not match. Let's start again." }
        if case .new = step, mode == .create {
            return "You will type this PIN each time you open the app. If you forget it, the only way back in is to delete the app, which also deletes your scans."
        }
        return nil
    }

    private func handle(_ pin: String) {
        wrongCurrent = false
        mismatch = false
        switch step {
        case .current:
            guard PinStore.verify(pin) else {
                wrongCurrent = true
                return
            }
            if mode == .disable {
                PinStore.remove()
                dismiss()
            } else {
                step = .new
            }
        case .new:
            step = .confirm(first: pin)
        case .confirm(let first):
            if pin == first {
                PinStore.set(pin)
                dismiss()
            } else {
                mismatch = true
                step = .new
            }
        }
    }
}

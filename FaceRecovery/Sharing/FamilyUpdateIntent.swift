import AppIntents

/// Hands today's Family Update to Shortcuts, so a daily automation can pass it to Send Message.
/// Runs without opening the app, so the PIN lock never asks; turning Family updates off in
/// Settings is what stops it, and every automation built on it stops with it.
struct GetFamilyUpdateIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today's Family Update"
    static var description = IntentDescription(
        "Today's sleep reading and answers as a short message, ready to send to family or a friend."
    )
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard FamilyUpdate.Setting.enabled.isOn else { throw FamilyUpdateError.turnedOff }
        return .result(value: try FamilyUpdate.today(in: ScanStore.container.mainContext))
    }
}

enum FamilyUpdateError: Error, CustomLocalizedStringResourceConvertible {
    case turnedOff

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .turnedOff: "Family updates are turned off. You can turn them on in Face Recovery, Settings."
        }
    }
}

/// Makes the action show up in Shortcuts and Siri without the user building anything first.
struct FaceRecoveryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetFamilyUpdateIntent(),
            phrases: ["Get my family update from \(.applicationName)"],
            shortTitle: "Family Update",
            systemImageName: "person.2.fill"
        )
    }
}

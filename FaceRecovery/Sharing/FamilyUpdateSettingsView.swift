import SwiftData
import SwiftUI

/// Turns Family updates on and off, chooses what goes in them, shows today's message exactly as
/// it would be sent, and walks through setting up the Shortcuts automation once.
struct FamilyUpdateSettingsView: View {
    @Environment(\.openURL) private var openURL
    @Query private var scans: [FaceScan]
    @Query private var journalEntries: [JournalEntry]

    @AppStorage(FamilyUpdate.Setting.enabled.rawValue)
    private var isEnabled = FamilyUpdate.Setting.enabled.defaultValue
    @AppStorage(FamilyUpdate.Setting.sleepReading.rawValue)
    private var sleepReading = FamilyUpdate.Setting.sleepReading.defaultValue
    @AppStorage(FamilyUpdate.Setting.feeling.rawValue)
    private var feeling = FamilyUpdate.Setting.feeling.defaultValue
    @AppStorage(FamilyUpdate.Setting.sleep.rawValue)
    private var sleep = FamilyUpdate.Setting.sleep.defaultValue
    @AppStorage(FamilyUpdate.Setting.factors.rawValue)
    private var factors = FamilyUpdate.Setting.factors.defaultValue
    @AppStorage(FamilyUpdate.Setting.medicines.rawValue)
    private var medicines = FamilyUpdate.Setting.medicines.defaultValue

    private static let steps = [
        "Open the Shortcuts app and tap Automation at the bottom.",
        "Tap the + button, then choose Time of Day.",
        "Pick a time after your morning photo, such as 10:00. Choose Daily, then Run Immediately. Tap Next.",
        "Tap New Blank Automation. Search for Face Recovery and tap Get Today's Family Update.",
        "Search for Send Message, tap it, and choose who should get your update.",
        "Tap Done. Your update will now be sent every day at that time.",
    ]

    private var options: FamilyUpdate.Options {
        FamilyUpdate.Options(
            sleepReading: sleepReading, feeling: feeling, sleep: sleep,
            factors: factors, medicines: medicines
        )
    }

    private var todaysMessage: String {
        let dayStart = Calendar.current.startOfDay(for: .now)
        return FamilyUpdate.text(
            dayStart: dayStart,
            day: DayHistory.day(dayStart, from: scans),
            journal: journalEntries.first { $0.dayStart == dayStart },
            options: options
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Send family updates", isOn: $isEnabled)
                    .font(.title3.weight(.semibold))
                    .padding(.vertical, 6)
            } footer: {
                Text(isEnabled
                     ? "Updates go out from your own Messages app, at the time you choose in Shortcuts. Turn this off to stop them straight away."
                     : "Send a short message each day to family or a friend, so they know how you are. Nothing is sent until you turn this on and set it up below.")
                    .font(.body)
            }

            Section {
                Toggle("Sleep reading", isOn: $sleepReading)
                Toggle("How I feel", isOn: $feeling)
                Toggle("How I slept", isOn: $sleep)
                Toggle("Things since yesterday", isOn: $factors)
                Toggle("Medicines", isOn: $medicines)
            } header: {
                Text("What to include")
            } footer: {
                Text("Your photos and notes are never included.")
                    .font(.body)
            }
            .disabled(!isEnabled)

            Section {
                Text(todaysMessage)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.vertical, 4)
                ShareLink(item: todaysMessage) {
                    Label("Send a test now", systemImage: "paperplane")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            } header: {
                Text("Today's message")
            } footer: {
                Text("This is exactly what will be sent.")
                    .font(.body)
            }
            .disabled(!isEnabled)

            Section {
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1).")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        Text(step)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(index + 1). \(step)")
                }
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            } header: {
                Text("Set it up once")
            } footer: {
                Text("A family member can help with this. To stop updates later, turn off Send family updates above, or delete the automation in Shortcuts.")
                    .font(.body)
            }
            .disabled(!isEnabled)
        }
        .navigationTitle("Family updates")
    }
}

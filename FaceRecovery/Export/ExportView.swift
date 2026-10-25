import SwiftUI
import UIKit

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    let scans: [FaceScan]
    let journalEntries: [JournalEntry]

    @State private var isSharing = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private var researchGradeCount: Int { scans.filter(\.isResearchGrade).count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Face Scans", value: "\(scans.count)")
                    LabeledContent("Usable", value: "\(scans.filter(\.isUsable).count)")
                    LabeledContent("Research-grade", value: "\(researchGradeCount)")
                    LabeledContent("Journal entries", value: "\(journalEntries.count)")
                } footer: {
                    Text("Research-grade means the photo counted and its date was not changed by hand. All scans are exported; the pipeline filters.")
                }

                Section {
                    Button { share() } label: {
                        Label("Share export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isSharing)

                    if let statusMessage {
                        Text(statusMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Writes scans.json with every measurement, photo check and Journal Entry, plus the photo files. Sleep Predictions and baselines are not exported — the pipeline recomputes them so the app and the analysis can never disagree. The export holds your photos and medicines unprotected, so send it only somewhere you trust. The copy made for sharing is deleted from this phone as soon as the share sheet closes.")
                }

                Section {
                    Text("Builds expire after 7 days on a Personal Team and there is no iCloud on this tier. This export is the only backup of your scans.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Export")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Builds the folder only when it is about to be shared and deletes it when the share sheet
    /// closes, shared or cancelled, so a plain copy of every photo and Journal Entry never sits
    /// on the phone (ADR 0007).
    private func share() {
        statusMessage = nil
        let folder: URL
        do {
            folder = try ExportBuilder.build(scans: scans, journalEntries: journalEntries)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isSharing = true
        let presented = ShareSheet.present(folder) { completed in
            try? FileManager.default.removeItem(at: folder)
            isSharing = false
            statusMessage = completed
                ? "Export shared. The copy on this phone has been deleted."
                : "Not shared. The copy on this phone has been deleted."
        }
        if !presented {
            try? FileManager.default.removeItem(at: folder)
            isSharing = false
            errorMessage = "The share sheet could not be opened. Please try again."
        }
    }
}

/// `ShareLink` gives no signal when its sheet closes, which the export needs in order to delete
/// itself, so the share sheet is presented directly over whatever is on screen.
private enum ShareSheet {
    @MainActor
    static func present(_ url: URL, onClose: @escaping @MainActor (_ completed: Bool) -> Void) -> Bool {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              var top = scene.keyWindow?.rootViewController
        else { return false }
        while let presented = top.presentedViewController { top = presented }

        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in onClose(completed) }
        }
        top.present(controller, animated: true)
        return true
    }
}

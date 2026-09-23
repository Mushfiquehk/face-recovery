import SwiftUI

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    let scans: [FaceScan]

    @State private var folder: URL?
    @State private var errorMessage: String?

    private var researchGradeCount: Int { scans.filter(\.isResearchGrade).count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Face Scans", value: "\(scans.count)")
                    LabeledContent("Usable", value: "\(scans.filter(\.isUsable).count)")
                    LabeledContent("Research-grade", value: "\(researchGradeCount)")
                } footer: {
                    Text("Research-grade means usable and not Date-Adjusted. All scans are exported; the pipeline filters.")
                }

                Section {
                    if let folder {
                        ShareLink(item: folder) {
                            Label("Share export", systemImage: "square.and.arrow.up")
                        }
                        Text(folder.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Build export") { build() }
                    }

                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                } footer: {
                    Text("Writes scans.json with every Absolute Signal, Capture Quality and Scoring Run, plus the photo files. Recovery Scores and baselines are not exported — the pipeline recomputes them so the app and the analysis can never disagree.")
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

    private func build() {
        do {
            folder = try ExportBuilder.build(scans: scans)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

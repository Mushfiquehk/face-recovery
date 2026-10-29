import SwiftUI
import SwiftData
import PhotosUI

/// Submitting Face Scans for past days from existing photos. This is what makes baselining
/// meaningful on the first day rather than the fifteenth.
struct BackfillView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selection: [PhotosPickerItem] = []
    @State private var candidates: [Candidate] = []
    @State private var isLoading = false
    @State private var progress: Progress?

    private struct Candidate: Identifiable {
        let id = UUID()
        let image: UIImage
        /// Nil when the photo carried no EXIF capture date.
        let exifDate: Date?
        var date: Date
        /// True once the user edits the date, or immediately when there was no EXIF date to
        /// begin with — either way the date did not come from the photo.
        var isDateAdjusted: Bool
        var outcome: String?
    }

    private struct Progress {
        var completed: Int
        var total: Int
        var failures: [String]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(
                        selection: $selection,
                        maxSelectionCount: 30,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label(candidates.isEmpty ? "Choose photos" : "Choose different photos", systemImage: "photo.on.rectangle")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Morning photos of your face, up to 30 at a time. Each photo's own date is used. Changing a date marks that scan Date-Adjusted, which keeps it out of research exports.")
                }

                if isLoading {
                    HStack { ProgressView(); Text("Reading photos…") }
                }

                ForEach($candidates) { $candidate in
                    candidateRow($candidate)
                }

                if let progress {
                    Section("Progress") {
                        ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1))) {
                            Text(progress.completed == progress.total
                                 ? "All \(progress.total) read. Tap Done."
                                 : "\(progress.completed) of \(progress.total) read")
                        }
                        ForEach(progress.failures, id: \.self) { failure in
                            Text(failure).font(.callout).foregroundStyle(Palette.low)
                        }
                    }
                }
            }
            .navigationTitle("Add past photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(candidates.isEmpty ? "Add" : "Add \(candidates.count)") {
                        Task { await scanAll() }
                    }
                    .disabled(candidates.isEmpty || progress != nil)
                }
            }
            .onChange(of: selection) { _, newValue in
                Task { await load(newValue) }
            }
        }
    }

    private func candidateRow(_ candidate: Binding<Candidate>) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: candidate.wrappedValue.image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                DatePicker(
                    "Captured",
                    selection: Binding(
                        get: { candidate.wrappedValue.date },
                        set: { newDate in
                            candidate.wrappedValue.date = newDate
                            // Any date the user sets is, by definition, not the EXIF date.
                            if newDate != candidate.wrappedValue.exifDate {
                                candidate.wrappedValue.isDateAdjusted = true
                            }
                        }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()

                if candidate.wrappedValue.isDateAdjusted {
                    Label(
                        candidate.wrappedValue.exifDate == nil
                            ? "No capture date in this photo — Date-Adjusted"
                            : "Date-Adjusted",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(Palette.caution)
                }

                if let outcome = candidate.wrappedValue.outcome {
                    Text(outcome).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }

        var loaded: [Candidate] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else { continue }

            let exifDate = ExifReader.captureDate(from: data)
            loaded.append(
                Candidate(
                    image: image,
                    exifDate: exifDate,
                    date: exifDate ?? Date(),
                    isDateAdjusted: exifDate == nil
                )
            )
        }
        candidates = loaded.sorted { $0.date < $1.date }
    }

    /// Sequential, not concurrent: each photo is measured on the device, and reading thirty
    /// full-resolution photos at once would only compete for the same memory.
    private func scanAll() async {
        progress = Progress(completed: 0, total: candidates.count, failures: [])
        let service = ScoringService(modelContext: modelContext)

        for index in candidates.indices {
            let candidate = candidates[index]
            do {
                try await service.ingest(
                    image: candidate.image,
                    capturedAt: candidate.date,
                    isDateAdjusted: candidate.isDateAdjusted,
                    isBackfilled: true
                )
                candidates[index].outcome = "Read"
            } catch {
                candidates[index].outcome = "Failed"
                progress?.failures.append(
                    "\(candidate.date.formatted(date: .abbreviated, time: .shortened)): \(error.localizedDescription)"
                )
            }
            progress?.completed += 1
        }
    }
}

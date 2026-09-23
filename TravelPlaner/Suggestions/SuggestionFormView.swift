import SwiftUI
import SwiftData

struct SuggestionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var reason = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var category: PlaceCategory = .unusual
    @State private var errorMessage: String?
    let coordinator: SuggestionCoordinator

    var body: some View {
        NavigationStack {
            Form {
                Section("Place") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(PlaceCategory.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    TextField("Latitude", text: $latitude).keyboardType(.numbersAndPunctuation)
                    TextField("Longitude", text: $longitude).keyboardType(.numbersAndPunctuation)
                }
                Section("Why is it special?") { TextField("Reason", text: $reason, axis: .vertical).lineLimit(4...8) }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("Suggest a Place")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await submit() } }
                        .disabled(name.isEmpty || reason.isEmpty)
                }
            }
        }
    }

    private func submit() async {
        guard let lat = Double(latitude), let lon = Double(longitude) else { errorMessage = "Enter valid coordinates."; return }
        do {
            let suggestion = try PlaceSuggestion(name: name, coordinate: try GeoCoordinate(latitude: lat, longitude: lon), category: category, reason: reason)
            SwiftDataSuggestionStore(context: modelContext).record(suggestion)
            try await coordinator.submit(suggestion)
            dismiss()
        } catch { errorMessage = "The suggestion could not be submitted." }
    }
}

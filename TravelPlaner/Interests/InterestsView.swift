import SwiftData
import SwiftUI

struct InterestsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var selections: [PersistedInterestSelection]
    @State private var selected: Set<PlaceInterest> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Interests boost recommendations but never hide discoveries outside your choices.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Your interests") {
                    ForEach(PlaceInterest.allCases, id: \.self) { interest in
                        Toggle(interest.rawValue.localizedCapitalized, isOn: binding(for: interest))
                    }
                }
            }
            .navigationTitle("Interests")
            .onAppear { selected = selections.first?.interests ?? [] }
            .onChange(of: selected) { _, _ in save() }
        }
    }

    private func binding(for interest: PlaceInterest) -> Binding<Bool> {
        Binding(
            get: { selected.contains(interest) },
            set: { enabled in
                if enabled { selected.insert(interest) } else { selected.remove(interest) }
            }
        )
    }

    private func save() {
        let selection = selections.first ?? PersistedInterestSelection()
        if selections.isEmpty { modelContext.insert(selection) }
        selection.values = selected.map(\.rawValue).sorted()
        try? modelContext.save()
    }
}

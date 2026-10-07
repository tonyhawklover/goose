import SwiftUI

struct CustomQuote: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var attribution: String?
}

/// Quote preferences, kept in the app's own UserDefaults.
enum QuoteSettings {
    static let showKey = "showQuotes"
    static let includeBuiltInKey = "includeBuiltInQuotes"
    private static let customKey = "customQuotes"

    static var customQuotes: [CustomQuote] {
        get {
            guard let data = UserDefaults.standard.data(forKey: customKey),
                  let quotes = try? JSONDecoder().decode([CustomQuote].self, from: data) else { return [] }
            return quotes
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: customKey)
        }
    }

    static var includeBuiltIn: Bool {
        UserDefaults.standard.object(forKey: includeBuiltInKey) as? Bool ?? true
    }
}

struct QuotesSettingsView: View {
    @AppStorage(QuoteSettings.showKey) private var showQuotes = true
    @AppStorage(QuoteSettings.includeBuiltInKey) private var includeBuiltIn = true
    @State private var quotes = QuoteSettings.customQuotes
    @State private var editing: CustomQuote?

    var body: some View {
        Form {
            Section {
                Toggle("Show quotes", isOn: $showQuotes)
            } footer: {
                Text("Quotes appear under the goose on the main screen.")
            }

            if showQuotes {
                Section {
                    Toggle("Include Goose's quotes", isOn: $includeBuiltIn)
                } footer: {
                    if !includeBuiltIn && quotes.isEmpty {
                        Text("Add a quote of your own, or no quotes will show.")
                    } else {
                        Text("Turn this off to only see your own quotes.")
                    }
                }

                Section("Your Quotes") {
                    ForEach(quotes) { quote in
                        Button {
                            editing = quote
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(quote.text)
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                                if let attribution = quote.attribution {
                                    Text(attribution)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .tint(.primary)
                    }
                    .onDelete { offsets in
                        quotes.remove(atOffsets: offsets)
                    }

                    Button {
                        editing = CustomQuote(text: "")
                    } label: {
                        Label("Add a Quote", systemImage: "plus")
                    }
                }
            }
        }
        .navigationTitle("Quotes")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: quotes) { _, newValue in
            QuoteSettings.customQuotes = newValue
        }
        .sheet(item: $editing) { quote in
            QuoteEditor(quote: quote) { saved in
                if let index = quotes.firstIndex(where: { $0.id == saved.id }) {
                    quotes[index] = saved
                } else {
                    quotes.append(saved)
                }
            }
        }
    }
}

private struct QuoteEditor: View {
    let onSave: (CustomQuote) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var quote: CustomQuote
    @State private var attribution: String
    @FocusState private var quoteFocused: Bool

    init(quote: CustomQuote, onSave: @escaping (CustomQuote) -> Void) {
        self.onSave = onSave
        _quote = State(initialValue: quote)
        _attribution = State(initialValue: quote.attribution ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quote") {
                    TextField("Something worth remembering", text: $quote.text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($quoteFocused)
                }
                Section {
                    TextField("Who said it (optional)", text: $attribution)
                }
            }
            .navigationTitle("Your Quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = quote
                        saved.text = quote.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = attribution.trimmingCharacters(in: .whitespacesAndNewlines)
                        saved.attribution = name.isEmpty ? nil : name
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(quote.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { quoteFocused = true }
    }
}

import SwiftUI
import StoreKit

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var rules: BlockRulesManager

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SchedulesView()
                    } label: {
                        countedLabel("Schedules", icon: "calendar", count: rules.schedules.count)
                    }
                    NavigationLink {
                        DailyLimitsView()
                    } label: {
                        countedLabel("Daily Limits", icon: "hourglass", count: rules.limits.count)
                    }
                }

                Section {
                    NavigationLink {
                        StatsView()
                    } label: {
                        Label("Stats", systemImage: "chart.bar")
                    }
                    NavigationLink {
                        QuotesSettingsView()
                    } label: {
                        Label("Quotes", systemImage: "quote.opening")
                    }
                }

                Section {
                    NavigationLink {
                        DocumentView(title: "How to Use Goose", resource: "guide")
                    } label: {
                        Label("How to Use Goose", systemImage: "questionmark.circle")
                    }
                    NavigationLink {
                        DeveloperView()
                    } label: {
                        Label("About the Developer", systemImage: "person.crop.circle")
                    }
                }

                Section {
                    NavigationLink {
                        DocumentView(title: "Privacy Policy", resource: "privacy", webURL: AboutContent.privacyPolicyURL)
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                    NavigationLink {
                        LicensesView()
                    } label: {
                        Label("Open Source Licenses", systemImage: "doc.text")
                    }
                } header: {
                    Text("Legal")
                } footer: {
                    Text("Goose is provided as is, without warranty of any kind. Goose isn't affiliated with Apple.")
                }

                if AboutContent.sourceURL != nil || AboutContent.supportURL != nil {
                    Section {
                        if let url = AboutContent.sourceURL {
                            Link(destination: url) {
                                Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                            }
                        }
                        if let url = AboutContent.supportURL {
                            Link(destination: url) {
                                Label("Report a Problem", systemImage: "exclamationmark.bubble")
                            }
                        }
                    }
                }

                Section {
                } footer: {
                    Text("Goose \(version)")
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Goose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

extension InfoView {
    private func countedLabel(_ title: String, icon: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if count > 0 {
                Text("\(count)").foregroundStyle(.secondary)
            }
        }
    }
}

struct DeveloperView: View {
    @State private var canShowCoffeeLink = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let photoName = AboutContent.photoName {
                    Image(photoName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                } else {
                    Image("GooseMark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                }

                Text(AboutContent.developerName)
                    .font(.system(size: 26, weight: .semibold, design: .serif))

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(paragraphs(AboutContent.story).enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Goose is free, with no ads, no tracking, and no affiliate links.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if canShowCoffeeLink, let url = AboutContent.coffeeURL {
                    Link(destination: url) {
                        Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
                }
            }
            .padding(24)
        }
        .navigationTitle("About the Developer")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Links to outside payment are only allowed on the US App Store
            // (Epic v. Apple, 2025). Other storefronts still require in-app purchase.
            canShowCoffeeLink = await Storefront.current?.countryCode == "USA"
        }
    }

    private func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            Section {
                Text("Goose is open source under the Apache License 2.0.")
                NavigationLink("Apache License 2.0") {
                    LicenseTextView(title: "Apache License 2.0", text: Self.bundledText("LICENSE"))
                }
            } header: {
                Text("Goose")
            }

            Section {
                Text("Icon picker by Alessio Rubicini, under the MIT License.")
                NavigationLink("MIT License") {
                    LicenseTextView(title: "SFSymbolsPicker", text: Self.sfSymbolsPickerLicense)
                }
            } header: {
                Text("SFSymbolsPicker")
            }
        }
        .navigationTitle("Open Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func bundledText(_ name: String, ext: String? = nil) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    private static let sfSymbolsPickerLicense = """
    Copyright (c) 2023 Alessio Rubicini

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}

private struct LicenseTextView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Renders the Markdown files from docs/ that ship in the app bundle. Handles
/// only what those files use: headings, paragraphs, bullets, numbered steps
/// and inline formatting.
struct DocumentView: View {
    let title: String
    let resource: String
    var webURL: URL?

    private enum Block {
        case heading(String)
        case paragraph(String)
        case bullet(String)
        case step(String, String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
                if let webURL {
                    Link("View on the web", destination: webURL)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let text):
            Text(inline(text))
                .font(.system(.title3, design: .serif).weight(.semibold))
                .padding(.top, 10)
        case .paragraph(let text):
            Text(inline(text))
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•")
                Text(inline(text))
            }
        case .step(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number).monospacedDigit().foregroundStyle(.secondary)
                Text(inline(text))
            }
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private var blocks: [Block] {
        let source = LicensesView.bundledText(resource, ext: "md")
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("# ") {
                // The page title is already in the navigation bar.
                flushParagraph()
            } else if line.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("- ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty {
                flushParagraph()
                blocks.append(.step(String(line[...dot]), String(line[line.index(after: dot)...]).trimmingCharacters(in: .whitespaces)))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }
}

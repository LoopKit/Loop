import SwiftUI

struct FoodFinderSettingsView: View {
    @State private var isEnabled: Bool = UserDefaults.standard.foodFinderEnabled
    @State private var showAIConfig: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Enable/disable master switch
                sectionHeader(icon: "magnifyingglass.circle.fill", title: "FOODFINDER CONFIGURATION")
                settingsCard {
                    Toggle(isOn: Binding(get: { isEnabled }, set: { newVal in
                        isEnabled = newVal
                        UserDefaults.standard.foodFinderEnabled = newVal
                    })) {
                        Text("Enable FoodFinder").font(.title3.weight(.semibold))
                    }
                    Divider().padding(.vertical, 6)
                    Text("When enabled, FoodFinder will appear in this Treatments page to help you find critical food nutrition information.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                if isEnabled {
                    sectionHeader(icon: "magnifyingglass", title: "SEARCH OPTIONS")
                    settingsCard {
                        row(icon: "magnifyingglass", title: "Text Search", status: .available)
                        Divider()
                        row(icon: "barcode.viewfinder", title: "Barcode Scanning", status: .available)
                        Divider()
                        NavigationLink(destination: AISettingsView()) {
                            HStack {
                                row(icon: "sparkles", title: "AI Analysis", status: .available, showChevron: false)
                                Image(systemName: "chevron.right").foregroundColor(.secondary)
                            }
                        }
                    }

                    sectionHeader(icon: "brain.head.profile", title: "AI CONFIGURATION")
                    settingsCard {
                        configRow(icon: "brain.head.profile", title: "Provider", rightText: currentProvider())
                        Divider()
                        configRow(icon: "checkmark.seal", title: "Status", rightText: aiConfigured() ? "Configured" : "Not Configured", rightColor: aiConfigured() ? .green : .red)
                        Divider()
                        NavigationLink(destination: AISettingsView()) {
                            HStack { configRow(icon: "gearshape", title: "Reconfigure AI", rightText: "") ; Image(systemName: "chevron.right").foregroundColor(.secondary) }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("FoodFinder Settings")
    }

    // MARK: - Helpers
    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(.blue)
            Text(title).font(.headline).foregroundColor(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private enum Status { case available }

    private func row(icon: String, title: String, status: Status, showChevron: Bool = true) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(.blue)
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            Text("Available").font(.headline).foregroundColor(.green)
        }
    }

    private func configRow(icon: String, title: String, rightText: String, rightColor: Color = .secondary) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(.blue)
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            Text(rightText).font(.headline).foregroundColor(rightColor)
        }
    }

    private func currentProvider() -> String {
        // Prefer textSearchProvider, fall back to aiImageProvider
        let t = UserDefaults.standard.textSearchProvider
        if !t.isEmpty { return t.replacingOccurrences(of: " (Default)", with: "") }
        return UserDefaults.standard.aiImageProvider
    }

    private func aiConfigured() -> Bool {
        let provider = currentProvider().lowercased()
        if provider.contains("openai") { return !UserDefaults.standard.openAIAPIKey.isEmpty }
        if provider.contains("claude") { return !UserDefaults.standard.claudeAPIKey.isEmpty }
        if provider.contains("google") || provider.contains("gemini") { return !UserDefaults.standard.googleGeminiAPIKey.isEmpty }
        return false
    }
}

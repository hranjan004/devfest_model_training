//
//  SettingsView.swift
//  ucscdevfestapp
//
//  Server address (needed on a real phone, where localhost is not the Mac) and comment name.
//

import SwiftUI

struct SettingsView: View {
    @Environment(SightingStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppConfig.serverURLDefaultsKey) private var serverURL = ""
    @AppStorage("displayName") private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppConfig.bundledServerURL, text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Server address")
                } footer: {
                    Text("Leave empty to use \(AppConfig.bundledServerURL). On a phone, enter your Mac's address on the same Wi-Fi, for example http://192.168.1.20:8080.")
                }

                Section("Name shown on your comments") {
                    TextField("Anonymous", text: $displayName)
                }

                Section("Maps") {
                    LabeledContent("Provider", value: AppConfig.googleMapsAPIKey.isEmpty ? "Apple Maps (no Google key)" : "Google Maps")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                        Task { await store.refresh() }
                    }
                }
            }
        }
    }
}

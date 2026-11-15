//
//  SettingsView.swift
//  ucscdevfestapp
//
//  Where the model server lives, and whether it's answering.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WildlifeAPI.baseURLKey) private var baseURL = WildlifeAPI.defaultBaseURL
    @State private var status: Status = .checking

    enum Status: Equatable {
        case checking
        case live(String)
        case down(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://localhost:8081", text: $baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await check() } }
                } header: {
                    Text("Model server")
                } footer: {
                    Text("The simulator reaches your Mac at http://localhost:8081. On a phone, use your Mac’s Wi‑Fi address, for example http://192.168.1.20:8081.")
                }

                Section("Status") {
                    switch status {
                    case .checking:
                        HStack { ProgressView(); Text("Checking…") }
                    case .live(let version):
                        Label {
                            VStack(alignment: .leading) {
                                Text("Live")
                                Text(version).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(.green)
                        }
                    case .down(let message):
                        Label {
                            Text(message)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(Color.slug)
                        }
                    }
                    Button("Check again") { Task { await check() } }
                }

                Section("About the model") {
                    LabeledContent("Photo analysis", value: "Whole-photo classification")
                    LabeledContent("Trained model", value: "BioCLIP-v4, 34 classes")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await check() }
        }
    }

    private func check() async {
        status = .checking
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces)) else {
            status = .down("That isn’t a valid address.")
            return
        }
        do {
            let h = try await WildlifeAPI(baseURL: url).health()
            status = .live("\(h.modelVersion), \(h.detectorVersion)")
        } catch {
            status = .down(error.localizedDescription)
        }
    }
}

#Preview {
    SettingsView()
}

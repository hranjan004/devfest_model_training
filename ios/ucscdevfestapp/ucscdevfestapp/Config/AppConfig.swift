//
//  AppConfig.swift
//  ucscdevfestapp
//
//  Reads local settings from Secrets.plist (not committed, see Secrets.example.plist).
//

import Foundation

enum AppConfig {
    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }()

    static let serverURLDefaultsKey = "serverURL"
    static let fallbackServerURL = "http://localhost:8080"

    /// Google Maps key. Empty means the app falls back to Apple Maps.
    static var googleMapsAPIKey: String {
        let key = (secrets["GOOGLE_MAPS_API_KEY"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        return key.hasPrefix("YOUR_") ? "" : key
    }

    /// Server URL from Secrets.plist, used until the user sets one in Settings.
    static var bundledServerURL: String {
        let value = (secrets["API_BASE_URL"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? fallbackServerURL : value
    }

    static var serverURL: URL {
        let saved = UserDefaults.standard.string(forKey: serverURLDefaultsKey) ?? ""
        let text = saved.trimmingCharacters(in: .whitespaces).isEmpty ? bundledServerURL : saved
        return URL(string: text.trimmingCharacters(in: .whitespaces)) ?? URL(string: fallbackServerURL)!
    }

    /// Stable anonymous id so the server can remember this device's star ratings.
    static var deviceID: String {
        let key = "deviceID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    /// UCSC campus center, used when a sighting has no location yet.
    static let campusLatitude = 36.9916
    static let campusLongitude = -122.0583
}

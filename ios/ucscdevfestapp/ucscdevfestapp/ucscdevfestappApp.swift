//
//  ucscdevfestappApp.swift
//  ucscdevfestapp
//
//  Created by Dean Mcculloh on 11/14/26.
//

import SwiftUI
import GoogleMaps

@main
struct ucscdevfestappApp: App {
    init() {
        // Without a key in Secrets.plist the map views fall back to Apple Maps.
        if !AppConfig.googleMapsAPIKey.isEmpty {
            GMSServices.provideAPIKey(AppConfig.googleMapsAPIKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

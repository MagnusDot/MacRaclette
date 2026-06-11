//
//  MacRacletteApp.swift
//  MacRaclette
//
//  Created by Alois Marcellin on 10/06/2026.
//

import SwiftUI

@main
struct MacRacletteApp: App {
    @State private var monitor = RacletteMonitor()

    var body: some Scene {
        MenuBarExtra {
            RaclettePanelView(monitor: monitor)
        } label: {
            HStack(spacing: 4) {
                Image(monitor.visualState.menuBarAssetName)
                    .renderingMode(.original)
                Text(monitor.menuBarTitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

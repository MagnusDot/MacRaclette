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
                .frame(width: 340)
        } label: {
            HStack(spacing: 4) {
                RacletteIconView(state: monitor.visualState, size: 18)
                Text(monitor.menuBarTitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

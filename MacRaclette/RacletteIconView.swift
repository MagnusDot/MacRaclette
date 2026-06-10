//
//  RacletteIconView.swift
//  MacRaclette
//
//  Created by Alois Marcellin on 10/06/2026.
//

import SwiftUI

struct RacletteIconView: View {
    let state: RacletteVisualState
    var size: CGFloat = 18

    var body: some View {
        Image(state.assetName)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch state {
        case .unavailable:
            return "Capteurs indisponibles"
        case .cool:
            return "Temperature normale"
        case .melting:
            return "Raclette en chauffe"
        case .ready:
            return "Raclette prete"
        }
    }
}

extension RacletteVisualState {
    var assetName: String {
        switch self {
        case .unavailable:
            return "raclette-unavailable"
        case .cool:
            return "raclette-cool"
        case .melting:
            return "raclette-melting"
        case .ready:
            return "raclette-ready"
        }
    }
}

struct RacletteIconView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 12) {
            RacletteIconView(state: .unavailable, size: 28)
            RacletteIconView(state: .cool, size: 28)
            RacletteIconView(state: .melting, size: 28)
            RacletteIconView(state: .ready, size: 28)
        }
        .padding()
    }
}

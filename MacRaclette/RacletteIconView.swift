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
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / 24
            context.scaleBy(x: scale, y: scale)

            drawPlate(in: &context)
            drawCheese(in: &context)

            switch state {
            case .unavailable:
                drawSlash(in: &context)
            case .cool:
                drawThermalDot(in: &context)
            case .melting:
                drawDrip(in: &context)
                drawThermalDot(in: &context)
            case .ready:
                drawDrip(in: &context)
                drawCloche(in: &context)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityLabel)
    }

    private var primary: Color {
        switch state {
        case .unavailable:
            return .secondary
        case .cool:
            return .blue
        case .melting:
            return .yellow
        case .ready:
            return .orange
        }
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

    private func drawPlate(in context: inout GraphicsContext) {
        let plate = Path(ellipseIn: CGRect(x: 4, y: 16, width: 16, height: 4))
        context.fill(plate, with: .color(.secondary.opacity(0.22)))
        context.stroke(plate, with: .color(.secondary.opacity(0.55)), lineWidth: 1.2)
    }

    private func drawCheese(in context: inout GraphicsContext) {
        var cheese = Path()
        cheese.move(to: CGPoint(x: 5.5, y: 10.5))
        cheese.addLine(to: CGPoint(x: 17.5, y: 8))
        cheese.addLine(to: CGPoint(x: 19, y: 15.6))
        cheese.addLine(to: CGPoint(x: 6.4, y: 16.2))
        cheese.closeSubpath()

        context.fill(cheese, with: .color(primary.opacity(state == .cool ? 0.18 : 0.75)))
        context.stroke(cheese, with: .color(.primary.opacity(0.72)), lineWidth: 1.25)

        let holes = [
            CGRect(x: 9, y: 12.2, width: 1.6, height: 1.2),
            CGRect(x: 14.3, y: 11.4, width: 1.4, height: 1.4)
        ]

        for hole in holes {
            context.fill(Path(ellipseIn: hole), with: .color(.black.opacity(0.28)))
        }
    }

    private func drawDrip(in context: inout GraphicsContext) {
        var drip = Path()
        drip.move(to: CGPoint(x: 14.6, y: 15.1))
        drip.addCurve(to: CGPoint(x: 13.4, y: 20.5), control1: CGPoint(x: 15.4, y: 17), control2: CGPoint(x: 12.3, y: 18.4))
        drip.addCurve(to: CGPoint(x: 16.4, y: 17.2), control1: CGPoint(x: 15.2, y: 20.5), control2: CGPoint(x: 16.7, y: 19))
        drip.addCurve(to: CGPoint(x: 14.6, y: 15.1), control1: CGPoint(x: 16.2, y: 16.1), control2: CGPoint(x: 15.2, y: 15.5))
        context.fill(drip, with: .color(.orange.opacity(0.9)))
    }

    private func drawThermalDot(in context: inout GraphicsContext) {
        let dot = Path(ellipseIn: CGRect(x: 17, y: 4.2, width: 3.6, height: 3.6))
        context.fill(dot, with: .color(primary.opacity(state == .cool ? 0.65 : 0.95)))
    }

    private func drawCloche(in context: inout GraphicsContext) {
        var cloche = Path()
        cloche.move(to: CGPoint(x: 6.5, y: 10.5))
        cloche.addCurve(to: CGPoint(x: 18.5, y: 10.5), control1: CGPoint(x: 8, y: 4.8), control2: CGPoint(x: 17, y: 4.8))
        cloche.addLine(to: CGPoint(x: 18.5, y: 12.1))
        cloche.addLine(to: CGPoint(x: 6.5, y: 12.1))
        cloche.closeSubpath()

        context.fill(cloche, with: .color(.primary.opacity(0.12)))
        context.stroke(cloche, with: .color(.primary.opacity(0.72)), lineWidth: 1.15)
        context.fill(Path(ellipseIn: CGRect(x: 11.2, y: 4.6, width: 2, height: 2)), with: .color(.primary.opacity(0.72)))
    }

    private func drawSlash(in context: inout GraphicsContext) {
        var slash = Path()
        slash.move(to: CGPoint(x: 5, y: 5))
        slash.addLine(to: CGPoint(x: 19, y: 19))
        context.stroke(slash, with: .color(.secondary), lineWidth: 1.8)
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

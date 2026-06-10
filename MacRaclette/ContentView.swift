//
//  ContentView.swift
//  MacRaclette
//
//  Created by Alois Marcellin on 10/06/2026.
//

import SwiftUI

struct RaclettePanelView: View {
    @Bindable var monitor: RacletteMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            temperatureGauge
            statsGrid
            sensorList
            thresholdControl
            controls
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(headerAccent.opacity(0.16))
                RacletteIconView(state: monitor.visualState, size: 38)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(monitor.statusTitle)
                    .font(.headline)
                Text(monitor.statusSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var headerAccent: Color {
        switch monitor.visualState {
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

    private var temperatureGauge: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(monitor.hasSensors ? monitor.currentTemperature.formatted(.number.precision(.fractionLength(1))) : "--")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("C")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(monitor.trendLabel)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(monitor.trendColor)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.16))
                    Capsule()
                        .fill(monitor.isRacletteMode ? Color.orange : Color.blue)
                        .frame(width: proxy.size.width * monitor.gaugeProgress)
                }
            }
            .frame(height: 10)
        }
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            GridRow {
                StatCell(title: "Minimum", value: monitor.minimumTemperature.temperatureText)
                StatCell(title: "Moyenne", value: monitor.averageTemperature.temperatureText)
                StatCell(title: "Maximum", value: monitor.maximumTemperature.temperatureText)
            }
            GridRow {
                StatCell(title: "Pression", value: monitor.thermalStateLabel)
                StatCell(title: "Capteurs", value: "\(monitor.sensorReadings.count)")
                StatCell(title: "Depuis", value: monitor.uptimeLabel)
            }
        }
    }

    private var sensorList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capteurs")
                .font(.callout.weight(.semibold))

            if monitor.sensorReadings.isEmpty {
                Text(monitor.sensorError ?? "Aucun capteur detecte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(monitor.sensorReadings.prefix(10))) { sensor in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sensor.name)
                                        .font(.caption.weight(.semibold))
                                    Text(sensor.key)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(sensor.temperature.temperatureText)
                                        .font(.caption.monospacedDigit())
                                    Text(sensor.source.rawValue)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 134)
            }
        }
    }

    private var thresholdControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Seuil raclette")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(monitor.threshold.temperatureText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: $monitor.threshold, in: 50...95, step: 1) {
                Text("Seuil raclette")
            } minimumValueLabel: {
                Text("50")
            } maximumValueLabel: {
                Text("95")
            }
        }
    }

    private var controls: some View {
        HStack {
            Toggle("Cloche", isOn: $monitor.playsBell)
                .toggleStyle(.switch)
            Spacer()
            Button("Actualiser") {
                monitor.sampleNow()
            }
            Button("Réinitialiser") {
                monitor.resetStats()
            }
            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

private struct StatCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RaclettePanelView_Previews: PreviewProvider {
    static var previews: some View {
        RaclettePanelView(monitor: RacletteMonitor())
    }
}

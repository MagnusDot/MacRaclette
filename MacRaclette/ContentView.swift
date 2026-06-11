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
        VStack(alignment: .leading, spacing: 12) {
            header
            temperatureGauge
            heatSourcesSection
            fansSection
            statsGrid
            Divider()
            thresholdControl
            controls
        }
        .padding(16)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(headerAccent.opacity(0.15))
                RacletteIconView(state: monitor.visualState, size: 34)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.statusTitle)
                    .font(.headline)
                Text(monitor.statusSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private var headerAccent: Color {
        switch monitor.visualState {
        case .unavailable: return .secondary
        case .cool:        return .blue
        case .melting:     return .yellow
        case .ready:       return .orange
        }
    }

    // MARK: - Temperature gauge

    private var temperatureGauge: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(monitor.hasSensors
                     ? monitor.currentTemperature.formatted(.number.precision(.fractionLength(1)))
                     : "--")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("°C")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Label(monitor.trendLabel, systemImage: monitor.trendIcon)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(monitor.trendColor)
                    .labelStyle(.titleAndIcon)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(gaugeGradient)
                        .frame(width: proxy.size.width * monitor.gaugeProgress)
                        .animation(.spring(duration: 0.4), value: monitor.gaugeProgress)
                }
            }
            .frame(height: 10)
        }
    }

    private var gaugeGradient: LinearGradient {
        LinearGradient(
            colors: [.blue, .green, .yellow, .orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Heat sources

    private var heatSourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Heat Sources", icon: "flame.fill", color: .orange)

            if monitor.categorizedSensors.isEmpty {
                emptyLabel("No sensors detected")
            } else {
                VStack(spacing: 4) {
                    ForEach(monitor.categorizedSensors, id: \.category) { item in
                        HeatSourceRow(
                            category: item.category,
                            maxTemp: item.maxTemp,
                            threshold: monitor.threshold,
                            isHottest: item.category == monitor.hottestComponent
                        )
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Fans

    private var fansSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Fans", icon: "fan.fill", color: .blue)
                Spacer()
                if !monitor.fanReadings.isEmpty {
                    fanBoostButton
                }
            }

            if monitor.fanReadings.isEmpty {
                emptyLabel(monitor.fanError ?? "No fans detected")
            } else {
                VStack(spacing: 4) {
                    ForEach(monitor.fanReadings) { fan in
                        FanRow(fan: fan)
                    }
                }
                if monitor.fanBoostEnabled {
                    Label("Boost active — fans at maximum speed", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                } else if monitor.fanBoostUnavailable {
                    Label("Fan control unavailable on this Mac", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var fanBoostButton: some View {
        if monitor.fanBoostUnavailable {
            Label("Boost", systemImage: "arrow.up.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                .help("Fan control is not available on this Mac (Apple Silicon restricts SMC writes)")
        } else {
            Toggle(isOn: $monitor.fanBoostEnabled) {
                Label("Boost", systemImage: "arrow.up.circle.fill")
                    .font(.caption.weight(.semibold))
            }
            .toggleStyle(.button)
            .controlSize(.mini)
            .tint(.orange)
        }
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                StatCell(title: "Min",      value: monitor.minimumTemperature.temperatureText)
                StatCell(title: "Average",  value: monitor.averageTemperature.temperatureText)
                StatCell(title: "Max",      value: monitor.maximumTemperature.temperatureText)
            }
            GridRow {
                StatCell(title: "Pressure", value: monitor.thermalStateLabel,
                         valueColor: monitor.thermalStateColor)
                StatCell(title: "Sensors",  value: "\(monitor.sensorReadings.count)")
                StatCell(title: "Uptime",   value: monitor.uptimeLabel)
            }
        }
    }

    // MARK: - Threshold

    private var thresholdControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Raclette threshold", systemImage: "thermometer.sun")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(monitor.threshold.temperatureText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $monitor.threshold, in: 50...95, step: 1) {
                Text("Threshold")
            } minimumValueLabel: {
                Text("50°").font(.caption)
            } maximumValueLabel: {
                Text("95°").font(.caption)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $monitor.playsBell) {
                Label("Bell", systemImage: "bell")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer()

            Button(action: { monitor.sampleNow() }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            Button(action: { monitor.resetStats() }) {
                Label("Reset", systemImage: "clock.arrow.circlepath")
            }
            .controlSize(.small)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .controlSize(.small)
        }
    }

    // MARK: - Helpers

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Heat source row

private struct HeatSourceRow: View {
    let category: SensorCategory
    let maxTemp: Double
    let threshold: Double
    let isHottest: Bool

    private var progress: Double { min(max(maxTemp / max(threshold, 1), 0), 1) }

    private var barColor: Color {
        if maxTemp >= threshold { return .red }
        if progress >= 0.80    { return .orange }
        if progress >= 0.60    { return .yellow }
        return category.color
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: category.icon)
                .foregroundStyle(category.color)
                .frame(width: 14)

            Text(category.label)
                .font(.caption.weight(.medium))
                .frame(width: 52, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.13))
                    Capsule()
                        .fill(barColor)
                        .frame(width: proxy.size.width * progress)
                        .animation(.spring(duration: 0.4), value: progress)
                }
            }
            .frame(height: 6)

            Text(maxTemp.temperatureText)
                .font(.caption.monospacedDigit())
                .frame(width: 54, alignment: .trailing)

            if isHottest {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else {
                Color.clear.frame(width: 12)
            }
        }
    }
}

// MARK: - Fan row

private struct FanRow: View {
    let fan: FanReading

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "fan")
                .foregroundStyle(.blue)
                .frame(width: 14)

            Text(fan.name)
                .font(.caption.weight(.medium))
                .frame(width: 36, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.13))
                    Capsule()
                        .fill(fanBarColor)
                        .frame(width: proxy.size.width * fan.percentage)
                        .animation(.spring(duration: 0.4), value: fan.percentage)
                }
            }
            .frame(height: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(rpmText)
                    .font(.caption.monospacedDigit())
                Text(percentText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 66, alignment: .trailing)
        }
    }

    private var rpmText: String {
        let rpm = Int(fan.current.rounded())
        return rpm > 0 ? "\(rpm) RPM" : "Stopped"
    }

    private var percentText: String { "\(Int((fan.percentage * 100).rounded()))%" }

    private var fanBarColor: Color {
        if fan.percentage > 0.85 { return .red }
        if fan.percentage > 0.65 { return .orange }
        return .blue
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
    }
}

// MARK: - Stat cell

private struct StatCell: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Card style modifier

private extension View {
    func cardStyle() -> some View {
        self
            .padding(10)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Preview

struct RaclettePanelView_Previews: PreviewProvider {
    static var previews: some View {
        RaclettePanelView(monitor: RacletteMonitor())
    }
}

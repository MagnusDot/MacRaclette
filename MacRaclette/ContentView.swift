import SwiftUI

struct RaclettePanelView: View {
    @Bindable var monitor: RacletteMonitor

    var body: some View {
        VStack(spacing: 0) {
            hero
            PanelDivider()
            heatSources
            if !monitor.fanReadings.isEmpty {
                PanelDivider()
                fans
            }
            PanelDivider()
            statsRow
            PanelDivider()
            thresholdControl
            PanelDivider()
            footer
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(.thinMaterial)
        .tint(stateAccent)
    }

    private var stateAccent: Color {
        switch monitor.visualState {
        case .unavailable: return .secondary
        case .cool:        return .blue
        case .melting:     return .yellow
        case .ready:       return .orange
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(stateAccent.opacity(0.12))
                    RacletteIconView(state: monitor.visualState, size: 18)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 1) {
                    Text(monitor.statusTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(monitor.statusSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: monitor.trendIcon).font(.system(size: 9, weight: .bold))
                    Text(monitor.trendLabel).font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(monitor.trendColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(monitor.trendColor.opacity(0.1), in: Capsule())
            }
            .padding(.bottom, 14)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(monitor.hasSensors
                     ? monitor.currentTemperature.formatted(.number.precision(.fractionLength(1)))
                     : "—")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("°C")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [.blue, .green, .yellow, .orange, .red],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * monitor.gaugeProgress)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: monitor.gaugeProgress)
                }
            }
            .frame(height: 4)
        }
        .padding(16)
        .background(stateAccent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
        .padding(10)
        .animation(.easeInOut(duration: 0.4), value: monitor.visualState)
    }

    // MARK: - Heat sources

    private var heatSources: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Heat Sources")
            if monitor.categorizedSensors.isEmpty {
                Text("No sensors detected")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 5) {
                    ForEach(monitor.categorizedSensors.prefix(5), id: \.category) { item in
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
        .panelSection()
    }

    // MARK: - Fans

    private var fans: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Fans")
            VStack(spacing: 5) {
                ForEach(monitor.fanReadings) { FanRow(fan: $0) }
            }
        }
        .panelSection()
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            StatItem(label: "Min",      value: monitor.minimumTemperature.temperatureText)
            StatItem(label: "Average",  value: monitor.averageTemperature.temperatureText)
            StatItem(label: "Max",      value: monitor.maximumTemperature.temperatureText)
            Rectangle().fill(.primary.opacity(0.1)).frame(width: 0.5).padding(.vertical, 2).padding(.horizontal, 2)
            StatItem(label: "Pressure", value: monitor.thermalStateLabel, color: monitor.thermalStateColor)
            StatItem(label: "Sensors",  value: "\(monitor.sensorReadings.count)")
            StatItem(label: "Uptime",   value: monitor.uptimeLabel)
        }
        .panelSection()
    }

    // MARK: - Threshold

    private var thresholdControl: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Raclette threshold", systemImage: "thermometer.sun.fill")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(monitor.threshold.temperatureText)
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $monitor.threshold, in: 50...95, step: 1) {
                EmptyView()
            } minimumValueLabel: {
                Text("50°").font(.system(size: 9)).foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text("95°").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .panelSection()
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 2) {
            FooterButton("Refresh", icon: "arrow.clockwise") { monitor.sampleNow() }
            FooterButton("Reset",   icon: "clock.arrow.circlepath") { monitor.resetStats() }
            Spacer()
            FooterButton("Quit", destructive: true) { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK: - Layout helpers

private extension View {
    func panelSection() -> some View {
        self.padding(.horizontal, 16).padding(.vertical, 12)
    }
}

private struct PanelDivider: View {
    var body: some View {
        Divider().opacity(0.5)
    }
}

// MARK: - Reusable components

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }
}

private struct StatItem: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(0.3)
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FooterButton: View {
    let label: String
    var icon: String?
    var destructive: Bool
    let action: () -> Void

    init(_ label: String, icon: String? = nil, destructive: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let icon { Label(label, systemImage: icon) } else { Text(label) }
            }
        }
        .buttonStyle(FooterButtonStyle(destructive: destructive))
    }
}

private struct FooterButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(destructive ? Color.red : .secondary)
            .opacity(configuration.isPressed ? 0.5 : 1)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(configuration.isPressed ? Color.primary.opacity(0.06) : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Rows

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
                .font(.system(size: 11))
                .foregroundStyle(category.color)
                .frame(width: 14)

            Text(category.label)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 50, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(barColor)
                        .frame(width: proxy.size.width * progress)
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: progress)
                }
            }
            .frame(height: 4)

            Text(maxTemp.temperatureText)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 48, alignment: .trailing)

            Image(systemName: "flame.fill")
                .font(.system(size: 8))
                .foregroundStyle(.orange)
                .opacity(isHottest ? 1 : 0)
                .frame(width: 10)
        }
    }
}

private struct FanRow: View {
    let fan: FanReading

    private var barColor: Color {
        fan.percentage > 0.85 ? .red : fan.percentage > 0.65 ? .orange : .blue
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "fan")
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .frame(width: 14)

            Text(fan.name)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 38, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(barColor)
                        .frame(width: proxy.size.width * fan.percentage)
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: fan.percentage)
                }
            }
            .frame(height: 4)

            HStack(spacing: 4) {
                Text(fan.current > 0 ? "\(Int(fan.current.rounded())) RPM" : "Stopped")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                Text("\(Int((fan.percentage * 100).rounded()))%")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 82, alignment: .trailing)
        }
    }
}

// MARK: - Preview

#Preview {
    RaclettePanelView(monitor: RacletteMonitor())
}

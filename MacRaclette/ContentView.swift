import SwiftUI

struct RaclettePanelView: View {
    @Bindable var monitor: RacletteMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heroCard
            heatSourcesCard
            fansCard
            statsGrid
            thresholdCard
            footer
        }
        .padding(14)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial)
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().strokeBorder(specularStroke, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                    RacletteIconView(state: monitor.visualState, size: 20)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    Text(monitor.statusTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(monitor.statusSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Label(monitor.trendLabel, systemImage: monitor.trendIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(monitor.trendColor)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(specularStroke, lineWidth: 0.5))
            }
            .padding(.bottom, 10)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(monitor.hasSensors
                     ? monitor.currentTemperature.formatted(.number.precision(.fractionLength(1)))
                     : "--")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("°C")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [.blue, .green, .yellow, .orange, .red],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * monitor.gaugeProgress)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: monitor.gaugeProgress)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(heroBackground)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(specularStroke, lineWidth: 0.5))
                .shadow(color: heroShadowColor.opacity(0.15), radius: 12, y: 4)
        }
    }

    private var heroBackground: AnyShapeStyle {
        switch monitor.visualState {
        case .unavailable:
            return AnyShapeStyle(Color.secondary.opacity(0.08))
        case .cool:
            return AnyShapeStyle(LinearGradient(colors: [.blue.opacity(0.18), .cyan.opacity(0.06)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .melting:
            return AnyShapeStyle(LinearGradient(colors: [.yellow.opacity(0.20), .orange.opacity(0.08)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .ready:
            return AnyShapeStyle(LinearGradient(colors: [.orange.opacity(0.25), .red.opacity(0.10)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private var heroShadowColor: Color {
        switch monitor.visualState {
        case .unavailable: return .clear
        case .cool:        return .blue
        case .melting:     return .yellow
        case .ready:       return .orange
        }
    }

    // MARK: - Heat sources

    private var heatSourcesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Heat Sources", icon: "flame.fill", color: .orange)
                if monitor.categorizedSensors.isEmpty {
                    EmptyCardLabel("No sensors detected")
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
        }
    }

    // MARK: - Fans

    private var fansCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Fans", icon: "fan.fill", color: .blue)
                if monitor.fanReadings.isEmpty {
                    EmptyCardLabel("No fans detected")
                } else {
                    VStack(spacing: 5) {
                        ForEach(monitor.fanReadings) { FanRow(fan: $0) }
                    }
                }
            }
        }
    }

    // MARK: - Stats

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                StatCell(title: "Min",      value: monitor.minimumTemperature.temperatureText)
                StatCell(title: "Average",  value: monitor.averageTemperature.temperatureText)
                StatCell(title: "Max",      value: monitor.maximumTemperature.temperatureText)
            }
            GridRow {
                StatCell(title: "Pressure", value: monitor.thermalStateLabel, valueColor: monitor.thermalStateColor)
                StatCell(title: "Sensors",  value: "\(monitor.sensorReadings.count)")
                StatCell(title: "Uptime",   value: monitor.uptimeLabel)
            }
        }
    }

    // MARK: - Threshold

    private var thresholdCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Raclette threshold", systemImage: "thermometer.sun")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(monitor.threshold.temperatureText)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $monitor.threshold, in: 50...95, step: 1) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("50°").font(.caption2).foregroundStyle(.tertiary)
                } maximumValueLabel: {
                    Text("95°").font(.caption2).foregroundStyle(.tertiary)
                }
                .tint(.orange)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            GlassButton(label: "Refresh", icon: "arrow.clockwise") { monitor.sampleNow() }
            GlassButton(label: "Reset",   icon: "clock.arrow.circlepath") { monitor.resetStats() }
            Spacer()
            GlassButton(label: "Quit", role: .destructive) { NSApplication.shared.terminate(nil) }
        }
    }
}

// MARK: - Design primitives

private var specularStroke: LinearGradient {
    LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08)],
                   startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.regularMaterial.opacity(0.7))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(specularStroke, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.07), radius: 6, y: 3)
            }
    }
}

struct GlassButton: View {
    let label: String
    var icon: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Group {
                if let icon { Label(label, systemImage: icon) } else { Text(label) }
            }
            .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(GlassButtonStyle(role: role))
    }
}

private struct GlassButtonStyle: ButtonStyle {
    let role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(role == .destructive
                          ? Color.red.opacity(configuration.isPressed ? 0.22 : 0.12)
                          : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.07))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(specularStroke, lineWidth: 0.5))
            }
            .foregroundStyle(role == .destructive ? .red : .primary)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
    }
}

private struct EmptyCardLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            Image(systemName: category.icon).foregroundStyle(category.color).frame(width: 14)
            Text(category.label).font(.system(size: 11, weight: .medium)).frame(width: 50, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.12))
                    Capsule().fill(barColor)
                        .frame(width: proxy.size.width * progress)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
                }
            }
            .frame(height: 5)
            Text(maxTemp.temperatureText)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 50, alignment: .trailing)
            Circle().fill(isHottest ? Color.orange : .clear).frame(width: 5, height: 5)
                .shadow(color: isHottest ? .orange.opacity(0.8) : .clear, radius: 3)
        }
    }
}

private struct FanRow: View {
    let fan: FanReading

    private var barColor: Color {
        if fan.percentage > 0.85 { return .red }
        if fan.percentage > 0.65 { return .orange }
        return .blue
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "fan").foregroundStyle(.blue).frame(width: 14)
            Text(fan.name).font(.system(size: 11, weight: .medium)).frame(width: 38, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.12))
                    Capsule().fill(barColor)
                        .frame(width: proxy.size.width * fan.percentage)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: fan.percentage)
                }
            }
            .frame(height: 5)
            VStack(alignment: .trailing, spacing: 1) {
                Text(fan.current > 0 ? "\(Int(fan.current.rounded())) RPM" : "Stopped")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                Text("\(Int((fan.percentage * 100).rounded()))%")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .frame(width: 66, alignment: .trailing)
        }
    }
}

private struct StatCell: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                .textCase(.uppercase).kerning(0.4)
            Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(valueColor).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(specularStroke, lineWidth: 0.5))
        }
    }
}

// MARK: - Preview

#Preview {
    RaclettePanelView(monitor: RacletteMonitor()).frame(width: 360)
}

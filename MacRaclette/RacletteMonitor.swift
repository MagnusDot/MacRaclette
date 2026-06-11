import Foundation
import Observation
import SwiftUI

// MARK: - Supporting types

struct TemperatureSample: Identifiable, Equatable {
    let id = UUID()
    let temperature: Double
    let date: Date
}

enum RacletteVisualState { case unavailable, cool, melting, ready }

struct CategorizedSensors {
    let category: SensorCategory
    let sensors: [SensorReading]
    var maxTemp: Double { sensors.map(\.temperature).max() ?? 0 }
}

enum SensorCategory: String, Hashable, CaseIterable {
    case cpu, gpu, battery, memory, storage, system

    var label: String {
        switch self {
        case .cpu:     return "CPU"
        case .gpu:     return "GPU"
        case .battery: return "Battery"
        case .memory:  return "Memory"
        case .storage: return "Storage"
        case .system:  return "System"
        }
    }

    var icon: String {
        switch self {
        case .cpu:     return "cpu"
        case .gpu:     return "display"
        case .battery: return "battery.100"
        case .memory:  return "memorychip"
        case .storage: return "internaldrive"
        case .system:  return "thermometer.medium"
        }
    }

    var color: Color {
        switch self {
        case .cpu:     return .blue
        case .gpu:     return .purple
        case .battery: return .green
        case .memory:  return .cyan
        case .storage: return .orange
        case .system:  return Color(.systemGray)
        }
    }
}

extension Double {
    var temperatureText: String {
        formatted(.number.precision(.fractionLength(0...1))) + "°C"
    }
}

// MARK: - RacletteMonitor

@Observable
final class RacletteMonitor {
    var threshold: Double = 72

    private(set) var currentTemperature: Double = 0
    private(set) var sensorReadings: [SensorReading] = []
    private(set) var fanReadings: [FanReading] = []
    private(set) var history: [TemperatureSample] = []
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    private(set) var sensorError: String?

    private let startedAt = Date()
    private let hidReader = HIDTemperatureReader()
    private var smcReader: SMCReader?
    private var timer: Timer?

    init() {
        do { smcReader = try SMCReader() } catch { sensorError = error.localizedDescription }
        sampleSensors()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sampleSensors()
        }
    }

    deinit { timer?.invalidate() }

    // MARK: - Derived state

    var hasSensors: Bool { !sensorReadings.isEmpty }
    var isRacletteMode: Bool { currentTemperature >= threshold }
    var gaugeProgress: Double { min(max(currentTemperature / max(threshold, 1), 0), 1) }

    var visualState: RacletteVisualState {
        guard hasSensors else { return .unavailable }
        if isRacletteMode        { return .ready }
        if gaugeProgress >= 0.78 { return .melting }
        return .cool
    }

    var menuBarTitle: String {
        guard hasSensors else { return "Raclette ?" }
        return isRacletteMode ? "Raclette 🧀" : "\(Int(currentTemperature.rounded()))°C"
    }

    var statusTitle: String {
        guard hasSensors else { return "Sensors unavailable" }
        return isRacletteMode ? "Ready to serve 🧀" : "Temperature normal"
    }

    var statusSubtitle: String {
        guard hasSensors else { return sensorError ?? "No sensors readable." }
        if isRacletteMode { return "Raclette mode active — melt the cheese." }
        let culprit = categorizedSensors.first.map { " · \($0.category.label) is hottest" } ?? ""
        return "Trigger at \(threshold.temperatureText)\(culprit)."
    }

    var minimumTemperature: Double { history.map(\.temperature).min() ?? currentTemperature }
    var maximumTemperature: Double { history.map(\.temperature).max() ?? currentTemperature }
    var averageTemperature: Double {
        history.isEmpty ? currentTemperature
                        : history.reduce(0) { $0 + $1.temperature } / Double(history.count)
    }

    var trendLabel: String {
        switch temperatureTrend {
        case let t where t >  0.35: return "Rising"
        case let t where t < -0.35: return "Falling"
        default: return "Stable"
        }
    }

    var trendIcon: String {
        switch temperatureTrend {
        case let t where t >  0.35: return "arrow.up"
        case let t where t < -0.35: return "arrow.down"
        default: return "minus"
        }
    }

    var trendColor: Color {
        switch temperatureTrend {
        case let t where t >  0.35: return .orange
        case let t where t < -0.35: return .blue
        default: return .secondary
        }
    }

    var thermalStateLabel: String {
        switch thermalState {
        case .nominal:   return "Normal"
        case .fair:      return "Moderate"
        case .serious:   return "High"
        case .critical:  return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var thermalStateColor: Color {
        switch thermalState {
        case .nominal:   return .green
        case .fair:      return .yellow
        case .serious:   return .orange
        case .critical:  return .red
        @unknown default: return .secondary
        }
    }

    var uptimeLabel: String {
        let s = Int(Date().timeIntervalSince(startedAt))
        return s >= 60 ? "\(s / 60)m \(s % 60)s" : "\(s)s"
    }

    var categorizedSensors: [CategorizedSensors] {
        let grouped = Dictionary(grouping: sensorReadings, by: { category(for: $0) })
        return SensorCategory.allCases
            .compactMap { cat in grouped[cat].map { CategorizedSensors(category: cat, sensors: $0) } }
            .filter { !$0.sensors.isEmpty }
            .sorted { $0.maxTemp > $1.maxTemp }
    }

    var hottestComponent: SensorCategory? { categorizedSensors.first?.category }

    // MARK: - Actions

    func sampleNow() { sampleSensors() }

    func resetStats() {
        history = hasSensors ? [TemperatureSample(temperature: currentTemperature, date: Date())] : []
    }

    // MARK: - Private

    private func sampleSensors() {
        thermalState = ProcessInfo.processInfo.thermalState
        fanReadings  = smcReader?.readFanSensors() ?? []

        do {
            let readings = try allTemperatureReadings()
            sensorReadings = readings
            guard let hottest = readings.first else {
                sensorError        = "No temperature sensors readable."
                currentTemperature = 0
                return
            }
            sensorError        = nil
            currentTemperature = hottest.temperature
            history.append(TemperatureSample(temperature: hottest.temperature, date: Date()))
            if history.count > 180 { history.removeFirst(history.count - 180) }
        } catch {
            sensorError = error.localizedDescription
        }
    }

    private func allTemperatureReadings() throws -> [SensorReading] {
        let hid = hidReader.readTemperatureSensors().map { r in
            SensorReading(
                key: "HID.\(r.name)",
                name: r.name
                    .replacingOccurrences(of: "eACC", with: "Efficiency Cluster")
                    .replacingOccurrences(of: "pACC", with: "Performance Cluster")
                    .replacingOccurrences(of: "tcal", with: "Thermal"),
                temperature: r.temperature,
                source: .hid
            )
        }
        let smc = (try? smcReader?.readTemperatureSensors()) ?? []
        return (hid + smc).sorted {
            $0.temperature != $1.temperature ? $0.temperature > $1.temperature : $0.key < $1.key
        }
    }

    private func category(for sensor: SensorReading) -> SensorCategory {
        if sensor.source == .hid {
            let n = sensor.name.lowercased()
            if n.contains("cpu") || n.contains("eacc") || n.contains("pacc") ||
               n.contains("efficiency") || n.contains("performance") ||
               n.contains("e-core") || n.contains("p-core") || n.contains("die") { return .cpu }
            if n.contains("gpu") || n.contains("ane")              { return .gpu }
            if n.contains("battery") || n.contains("charger")      { return .battery }
            if n.contains("nand") || n.contains("ssd") || n.contains("storage") { return .storage }
            if n.contains("memory") || n.contains("dram")          { return .memory }
            return .system
        }
        let key = sensor.key.hasPrefix("SMC.") ? String(sensor.key.dropFirst(4)) : sensor.key
        guard key.count >= 2 else { return .system }
        switch key[key.index(key.startIndex, offsetBy: 1)] {
        case "C", "c", "j", "N", "n": return .cpu
        case "G", "g":                 return .gpu
        case "B", "b":                 return .battery
        case "M", "m":                 return .memory
        case "S", "s", "H", "h":      return .storage
        default:                       return .system
        }
    }

    private var temperatureTrend: Double {
        guard let first = history.suffix(8).first else { return 0 }
        return currentTemperature - first.temperature
    }
}

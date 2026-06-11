//
//  RacletteMonitor.swift
//  MacRaclette
//
//  Created by Alois Marcellin on 10/06/2026.
//

import AppKit
import Foundation
import Observation
import SwiftUI

// MARK: - Sensor category

enum SensorCategory: String, Hashable, CaseIterable {
    case cpu     = "cpu"
    case gpu     = "gpu"
    case battery = "battery"
    case memory  = "memory"
    case storage = "storage"
    case system  = "system"

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

// MARK: - Grouped sensors

struct CategorizedSensors {
    let category: SensorCategory
    let sensors: [SensorReading]
    var maxTemp: Double { sensors.map(\.temperature).max() ?? 0 }
}

// MARK: - RacletteMonitor

@Observable
final class RacletteMonitor {
    var threshold: Double = 72
    var playsBell = true
    /// Whether the user has requested fan boost. Reverts to false automatically if the hardware ignores it.
    var fanBoostEnabled: Bool = false {
        didSet {
            guard fanBoostEnabled else {
                smcReader?.resetFansToAuto()
                return
            }
            let worked = smcReader?.setFansToMax() ?? false
            if !worked {
                fanBoostEnabled = false
                fanBoostUnavailable = true
            }
        }
    }

    private(set) var currentTemperature: Double = 0
    private(set) var currentSensorName = "No sensor"
    private(set) var sensorReadings: [SensorReading] = []
    private(set) var fanReadings: [FanReading] = []
    private(set) var history: [TemperatureSample] = []
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    private(set) var sensorError: String?
    private(set) var fanError: String?
    /// Set to true the first time fan boost is attempted but the hardware doesn't honour it.
    private(set) var fanBoostUnavailable = false

    private let startedAt = Date()
    private let hidReader = HIDTemperatureReader()
    private var smcReader: SMCReader?
    private var timer: Timer?
    private var wasRacletteMode = false

    init() {
        do {
            smcReader = try SMCReader()
        } catch {
            sensorError = error.localizedDescription
        }
        sampleSensors()
        start()
    }

    deinit { timer?.invalidate() }

    // MARK: - Derived state

    var isRacletteMode: Bool { currentTemperature >= threshold }

    var visualState: RacletteVisualState {
        guard hasSensors else { return .unavailable }
        if isRacletteMode { return .ready }
        if gaugeProgress >= 0.78 { return .melting }
        return .cool
    }

    var hasSensors: Bool { !sensorReadings.isEmpty }

    var menuBarTitle: String {
        guard hasSensors else { return "Raclette ?" }
        return isRacletteMode ? "Raclette 🧀" : "\(Int(currentTemperature.rounded()))°C"
    }

    var statusTitle: String {
        guard hasSensors else { return "Sensors unavailable" }
        return isRacletteMode ? "Ready to serve 🧀" : "Temperature normal"
    }

    var statusSubtitle: String {
        guard hasSensors else { return sensorError ?? "No AppleSMC sensors readable." }
        if isRacletteMode {
            return "Raclette mode active — ring the bell, melt the cheese."
        }
        let hottest = categorizedSensors.first
        let culprit = hottest.map { " — \($0.category.label) is the hottest component" } ?? ""
        return "Trigger at \(threshold.temperatureText)\(culprit)."
    }

    var minimumTemperature: Double { history.map(\.temperature).min() ?? currentTemperature }
    var maximumTemperature: Double { history.map(\.temperature).max() ?? currentTemperature }
    var averageTemperature: Double {
        history.isEmpty ? currentTemperature : history.reduce(0) { $0 + $1.temperature } / Double(history.count)
    }

    var gaugeProgress: Double { min(max(currentTemperature / max(threshold, 1), 0), 1) }

    var trendLabel: String {
        let t = temperatureTrend
        if t > 0.35 { return "Rising" }
        if t < -0.35 { return "Falling" }
        return "Stable"
    }

    var trendIcon: String {
        let t = temperatureTrend
        if t > 0.35 { return "arrow.up" }
        if t < -0.35 { return "arrow.down" }
        return "minus"
    }

    var trendColor: Color {
        let t = temperatureTrend
        if t > 0.35 { return .orange }
        if t < -0.35 { return .blue }
        return .secondary
    }

    var thermalStateLabel: String {
        switch thermalState {
        case .nominal:  return "Normal"
        case .fair:     return "Moderate"
        case .serious:  return "High"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var thermalStateColor: Color {
        switch thermalState {
        case .nominal:  return .green
        case .fair:     return .yellow
        case .serious:  return .orange
        case .critical: return .red
        @unknown default: return .secondary
        }
    }

    var uptimeLabel: String {
        let s = Int(Date().timeIntervalSince(startedAt))
        return s >= 60 ? "\(s / 60)m \(s % 60)s" : "\(s)s"
    }

    // MARK: - Sensor categorization

    var categorizedSensors: [CategorizedSensors] {
        let grouped = Dictionary(grouping: sensorReadings, by: { sensorCategory(for: $0) })
        return SensorCategory.allCases.compactMap { cat -> CategorizedSensors? in
            guard let sensors = grouped[cat], !sensors.isEmpty else { return nil }
            return CategorizedSensors(category: cat, sensors: sensors)
        }
        .sorted { $0.maxTemp > $1.maxTemp }
    }

    var hottestComponent: SensorCategory? { categorizedSensors.first?.category }

    private func sensorCategory(for sensor: SensorReading) -> SensorCategory {
        if sensor.source == .hid {
            let n = sensor.name.lowercased()
            if n.contains("cpu") || n.contains("eacc") || n.contains("pacc") ||
               n.contains("efficiency") || n.contains("performance") ||
               n.contains("e-core") || n.contains("p-core") || n.contains("die") {
                return .cpu
            }
            if n.contains("gpu") || n.contains("ane") { return .gpu }
            if n.contains("battery") || n.contains("charger") { return .battery }
            if n.contains("nand") || n.contains("ssd") || n.contains("storage") { return .storage }
            if n.contains("memory") || n.contains("dram") { return .memory }
            return .system
        }

        // SMC key — strip "SMC." prefix then look at characters 0 and 1
        let rawKey = sensor.key.hasPrefix("SMC.") ? String(sensor.key.dropFirst(4)) : sensor.key
        guard rawKey.count >= 2 else { return .system }
        let ch1 = rawKey[rawKey.index(rawKey.startIndex, offsetBy: 1)]
        switch ch1 {
        case "C", "c", "j", "N", "n": return .cpu
        case "G", "g":                 return .gpu
        case "B", "b":                 return .battery
        case "M", "m":                 return .memory
        case "S", "s", "H", "h":      return .storage
        default:                       return .system
        }
    }

    // MARK: - Public actions

    func sampleNow() { sampleSensors() }

    func resetStats() {
        history = hasSensors ? [TemperatureSample(temperature: currentTemperature, date: Date())] : []
    }

    // MARK: - Private

    private func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sampleSensors()
        }
    }

    private func sampleSensors() {
        thermalState = ProcessInfo.processInfo.thermalState

        // Read fans
        fanReadings = smcReader?.readFanSensors() ?? []

        // Read temperatures
        do {
            let readings = try readAllTemperatureSensors()
            sensorReadings = readings

            guard let hottest = readings.first else {
                sensorError = "No temperature sensors readable via IOHID or AppleSMC."
                currentTemperature = 0
                currentSensorName = "No sensor"
                return
            }

            sensorError = nil
            currentTemperature = hottest.temperature
            currentSensorName = hottest.name
            history.append(TemperatureSample(temperature: hottest.temperature, date: Date()))
            if history.count > 180 { history.removeFirst(history.count - 180) }

            handleRacletteTransition()
        } catch {
            sensorError = error.localizedDescription
        }
    }

    private func readAllTemperatureSensors() throws -> [SensorReading] {
        let hidReadings = hidReader.readTemperatureSensors().map { r in
            SensorReading(
                key: "HID.\(r.name)",
                name: readableSensorName(r.name),
                temperature: r.temperature,
                source: .hid
            )
        }
        let smcReadings = (try? smcReader?.readTemperatureSensors()) ?? []
        return (hidReadings + smcReadings)
            .sorted { $0.temperature != $1.temperature ? $0.temperature > $1.temperature : $0.key < $1.key }
    }

    private func readableSensorName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "eACC", with: "Efficiency Cluster")
            .replacingOccurrences(of: "pACC", with: "Performance Cluster")
            .replacingOccurrences(of: "tcal", with: "Thermal")
    }

    private var temperatureTrend: Double {
        guard let first = history.suffix(8).first else { return 0 }
        return currentTemperature - first.temperature
    }

    private func handleRacletteTransition() {
        guard isRacletteMode, !wasRacletteMode else {
            wasRacletteMode = isRacletteMode
            return
        }
        wasRacletteMode = true
        guard playsBell else { return }
        NSSound(named: "Glass")?.play()
    }
}

// MARK: - Supporting types

struct TemperatureSample: Identifiable, Equatable {
    let id = UUID()
    let temperature: Double
    let date: Date
}

enum RacletteVisualState {
    case unavailable, cool, melting, ready
}

extension Double {
    var temperatureText: String {
        formatted(.number.precision(.fractionLength(0...1))) + "°C"
    }
}

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

@Observable
final class RacletteMonitor {
    var threshold: Double = 72
    var playsBell = true

    private(set) var currentTemperature: Double = 0
    private(set) var currentSensorName = "Aucun capteur"
    private(set) var sensorReadings: [SensorReading] = []
    private(set) var history: [TemperatureSample] = []
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    private(set) var sensorError: String?

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

    deinit {
        timer?.invalidate()
    }

    var isRacletteMode: Bool {
        currentTemperature >= threshold
    }

    var visualState: RacletteVisualState {
        guard hasSensors else {
            return .unavailable
        }

        if isRacletteMode {
            return .ready
        }

        if gaugeProgress >= 0.78 {
            return .melting
        }

        return .cool
    }

    var hasSensors: Bool {
        !sensorReadings.isEmpty
    }

    var menuBarTitle: String {
        guard hasSensors else {
            return "Raclette ?"
        }

        if isRacletteMode {
            return "Raclette"
        }

        return "\(Int(currentTemperature.rounded())) C"
    }

    var statusTitle: String {
        guard hasSensors else {
            return "Capteurs indisponibles"
        }

        return isRacletteMode ? "Pret a servir" : "Surveillance temperature"
    }

    var statusSubtitle: String {
        guard hasSensors else {
            return sensorError ?? "Aucune sonde AppleSMC lisible."
        }

        return isRacletteMode
            ? "Mode raclette actif: cloche, fromage fondu, service."
            : "\(currentSensorName) surveille. Declenchement a \(threshold.temperatureText)."
    }

    var minimumTemperature: Double {
        history.map(\.temperature).min() ?? currentTemperature
    }

    var maximumTemperature: Double {
        history.map(\.temperature).max() ?? currentTemperature
    }

    var averageTemperature: Double {
        let total = history.reduce(0) { $0 + $1.temperature }
        return history.isEmpty ? currentTemperature : total / Double(history.count)
    }

    var sampleCount: Int {
        history.count
    }

    var gaugeProgress: Double {
        min(max(currentTemperature / max(threshold, 1), 0), 1)
    }

    var trendLabel: String {
        let trend = temperatureTrend

        if trend > 0.35 {
            return "En hausse"
        }

        if trend < -0.35 {
            return "En baisse"
        }

        return "Stable"
    }

    var trendColor: Color {
        let trend = temperatureTrend

        if trend > 0.35 {
            return .orange
        }

        if trend < -0.35 {
            return .blue
        }

        return .secondary
    }

    var thermalStateLabel: String {
        switch thermalState {
        case .nominal:
            return "Normale"
        case .fair:
            return "Moderee"
        case .serious:
            return "Haute"
        case .critical:
            return "Critique"
        @unknown default:
            return "Inconnue"
        }
    }

    var uptimeLabel: String {
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        let minutes = elapsed / 60
        let seconds = elapsed % 60

        return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }

    func sampleNow() {
        sampleSensors()
    }

    func resetStats() {
        if hasSensors {
            history = [TemperatureSample(temperature: currentTemperature, date: Date())]
        } else {
            history = []
        }
    }

    private func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sampleSensors()
        }
    }

    private func sampleSensors() {
        thermalState = ProcessInfo.processInfo.thermalState

        do {
            let readings = try readAllTemperatureSensors()
            sensorReadings = readings

            guard let hottest = readings.first else {
                sensorError = "Aucun capteur de temperature lisible via IOHID ou AppleSMC."
                currentTemperature = 0
                currentSensorName = "Aucun capteur"
                return
            }

            sensorError = nil
            currentTemperature = hottest.temperature
            currentSensorName = hottest.name
            history.append(TemperatureSample(temperature: hottest.temperature, date: Date()))

            if history.count > 180 {
                history.removeFirst(history.count - 180)
            }

            handleRacletteTransition()
        } catch {
            sensorError = error.localizedDescription
        }
    }

    private func readAllTemperatureSensors() throws -> [SensorReading] {
        let hidReadings = hidReader.readTemperatureSensors().map { reading in
            SensorReading(
                key: "HID.\(reading.name)",
                name: readableSensorName(reading.name),
                temperature: reading.temperature,
                source: .hid
            )
        }

        let smcReadings = (try? smcReader?.readTemperatureSensors()) ?? []

        let readings = (hidReadings + smcReadings)
            .sorted { first, second in
                if first.temperature == second.temperature {
                    return first.key < second.key
                }

                return first.temperature > second.temperature
            }

        return readings
    }

    private func readableSensorName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "eACC", with: "Efficiency Cluster")
            .replacingOccurrences(of: "pACC", with: "Performance Cluster")
            .replacingOccurrences(of: "tcal", with: "Thermal")
    }

    private var temperatureTrend: Double {
        guard let first = history.suffix(8).first else {
            return 0
        }

        return currentTemperature - first.temperature
    }

    private func handleRacletteTransition() {
        guard isRacletteMode, !wasRacletteMode else {
            wasRacletteMode = isRacletteMode
            return
        }

        wasRacletteMode = true

        guard playsBell else {
            return
        }

        NSSound(named: "Glass")?.play()
    }
}

struct TemperatureSample: Identifiable, Equatable {
    let id = UUID()
    let temperature: Double
    let date: Date
}

enum RacletteVisualState {
    case unavailable
    case cool
    case melting
    case ready
}

extension Double {
    var temperatureText: String {
        formatted(.number.precision(.fractionLength(0...1))) + " C"
    }
}

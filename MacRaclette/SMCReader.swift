//
//  SMCReader.swift
//  MacRaclette
//
//  Created by Alois Marcellin on 10/06/2026.
//

import Foundation
import IOKit

// MARK: - Data models

struct SensorReading: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let name: String
    let temperature: Double
    let source: SensorSource
}

enum SensorSource: String, Equatable {
    case hid = "HID"
    case smc = "SMC"
}

struct FanReading: Identifiable, Equatable {
    let id: Int
    let name: String
    let current: Double   // RPM
    let minimum: Double   // RPM
    let maximum: Double   // RPM
    let target: Double?   // RPM (manual target, if set)

    /// 0…1 fraction of the speed range
    var percentage: Double {
        guard maximum > minimum else { return 0 }
        return min(max((current - minimum) / (maximum - minimum), 0), 1)
    }
}

// MARK: - Errors

enum SMCReaderError: LocalizedError {
    case serviceUnavailable
    case connectionFailed(kern_return_t)
    case callFailed(kern_return_t)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "AppleSMC service unavailable."
        case let .connectionFailed(code):
            return "Cannot open AppleSMC: \(errorMessage(for: code))."
        case let .callFailed(code):
            return "AppleSMC call failed: \(errorMessage(for: code))."
        case let .readFailed(key):
            return "Cannot read sensor \(key)."
        }
    }
}

// MARK: - SMCReader

final class SMCReader {
    private var connection: io_connect_t = 0

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            throw SMCReaderError.serviceUnavailable
        }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else {
            throw SMCReaderError.callFailed(result)
        }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: Temperature sensors

    func readTemperatureSensors() throws -> [SensorReading] {
        let keys = try allKeys()
        return keys
            .filter { $0.hasPrefix("T") }
            .compactMap { key -> SensorReading? in
                guard let value = try? readDouble(key: key), (-40...130).contains(value) else {
                    return nil
                }
                return SensorReading(key: "SMC.\(key)", name: sensorName(for: key), temperature: value, source: .smc)
            }
            .sorted { $0.temperature != $1.temperature ? $0.temperature > $1.temperature : $0.key < $1.key }
    }

    // MARK: Fan sensors

    func readFanSensors() -> [FanReading] {
        guard let rawCount = try? readUInt32(key: "FNum"), rawCount > 0 else { return [] }
        let count = min(Int(rawCount), 8)
        return (0..<count).compactMap { i -> FanReading? in
            guard let current = try? readDouble(key: "F\(i)Ac"),
                  let minimum = try? readDouble(key: "F\(i)Mn"),
                  let maximum = try? readDouble(key: "F\(i)Mx"),
                  maximum > 0 else { return nil }
            let target = try? readDouble(key: "F\(i)Tg")
            return FanReading(id: i, name: "Fan \(i + 1)", current: current, minimum: minimum, maximum: maximum, target: target)
        }
    }

    /// Attempt to set all fans to their maximum speed. Silently fails on Apple Silicon.
    func setFansToMax() {
        guard let rawCount = try? readUInt32(key: "FNum"), rawCount > 0 else { return }
        for i in 0..<min(Int(rawCount), 8) {
            if let maxRPM = try? readDouble(key: "F\(i)Mx") {
                try? writeKey("F\(i)Tg", fpe2Value: maxRPM)
            }
        }
    }

    /// Attempt to return all fans to automatic control. Silently fails on Apple Silicon.
    func resetFansToAuto() {
        guard let rawCount = try? readUInt32(key: "FNum"), rawCount > 0 else { return }
        for i in 0..<min(Int(rawCount), 8) {
            if let minRPM = try? readDouble(key: "F\(i)Mn") {
                try? writeKey("F\(i)Tg", fpe2Value: minRPM)
            }
        }
    }

    // MARK: Private — key enumeration

    private func allKeys() throws -> [String] {
        let count = Int(try readUInt32(key: "#KEY"))
        guard count > 0 else { return [] }
        return try (0..<count).map { try key(at: UInt32($0)) }
    }

    private func key(at index: UInt32) throws -> String {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.data8 = SMCCommand.readIndex.rawValue
        input.data32 = index
        try call(.handleEvent, input: &input, output: &output)
        return string(from: output.key)
    }

    // MARK: Private — value reading

    func readDouble(key: String) throws -> Double {
        let value = try readKey(key)
        switch value.info.dataTypeString.trimmingCharacters(in: .whitespaces) {
        case "sp78":
            guard value.bytes.count >= 2 else { throw SMCReaderError.readFailed(key) }
            let raw = Int16(bitPattern: UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
            return Double(raw) / 256.0
        case "fpe2":
            guard value.bytes.count >= 2 else { throw SMCReaderError.readFailed(key) }
            let raw = UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])
            return Double(raw) / 4.0
        case "flt":
            guard value.bytes.count >= 4 else { throw SMCReaderError.readFailed(key) }
            let raw = UInt32(value.bytes[0]) << 24 | UInt32(value.bytes[1]) << 16
                    | UInt32(value.bytes[2]) << 8  | UInt32(value.bytes[3])
            return Double(Float(bitPattern: raw))
        default:
            throw SMCReaderError.readFailed(key)
        }
    }

    private func readUInt32(key: String) throws -> UInt32 {
        let value = try readKey(key)
        let bytes = value.bytes
        if value.info.dataTypeString.trimmingCharacters(in: .whitespaces) == "ui32", bytes.count >= 4 {
            return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        }
        if bytes.count >= 2 { return UInt32(bytes[0]) << 8 | UInt32(bytes[1]) }
        if bytes.count >= 1 { return UInt32(bytes[0]) }
        throw SMCReaderError.readFailed(key)
    }

    private func readKey(_ key: String) throws -> SMCValue {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = code(from: key)
        input.data8 = SMCCommand.readKeyInfo.rawValue
        try call(.handleEvent, input: &input, output: &output)

        let keyInfo = output.keyInfo
        input.keyInfo.dataSize = keyInfo.dataSize
        input.keyInfo.dataType = keyInfo.dataType
        input.data8 = SMCCommand.readBytes.rawValue
        try call(.handleEvent, input: &input, output: &output)

        let bytes = output.bytesArray.prefix(Int(keyInfo.dataSize))
        return SMCValue(info: keyInfo, bytes: Array(bytes))
    }

    // MARK: Private — value writing

    private func writeKey(_ key: String, fpe2Value value: Double) throws {
        // Step 1: read key info to get dataSize / dataType
        var infoInput = SMCKeyData()
        var infoOutput = SMCKeyData()
        infoInput.key = code(from: key)
        infoInput.data8 = SMCCommand.readKeyInfo.rawValue
        try call(.handleEvent, input: &infoInput, output: &infoOutput)

        // Step 2: write
        var writeInput = SMCKeyData()
        var writeOutput = SMCKeyData()
        writeInput.key = code(from: key)
        writeInput.data8 = SMCCommand.writeBytes.rawValue
        writeInput.keyInfo.dataSize = infoOutput.keyInfo.dataSize
        writeInput.keyInfo.dataType = infoOutput.keyInfo.dataType

        let raw = UInt16(max(0, value) * 4.0)
        writeInput.bytes.0 = UInt8((raw >> 8) & 0xFF)
        writeInput.bytes.1 = UInt8(raw & 0xFF)
        try call(.handleEvent, input: &writeInput, output: &writeOutput)
    }

    // MARK: Private — IOKit call

    private func call(_ selector: SMCSelector, input: inout SMCKeyData, output: inout SMCKeyData) throws {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = withUnsafeMutablePointer(to: &input) { ip in
            withUnsafeMutablePointer(to: &output) { op in
                IOConnectCallStructMethod(connection, UInt32(selector.rawValue), ip, inputSize, op, &outputSize)
            }
        }
        guard result == kIOReturnSuccess else {
            throw SMCReaderError.connectionFailed(result)
        }
    }

    // MARK: Sensor names

    private func sensorName(for key: String) -> String {
        let names: [String: String] = [
            // CPU
            "TC0C": "CPU Core 0",
            "TC1C": "CPU Core 1",
            "TC2C": "CPU Core 2",
            "TC3C": "CPU Core 3",
            "TC0D": "CPU Diode",
            "TC0E": "CPU Proximity",
            "TC0F": "CPU Proximity 2",
            "TC0P": "CPU Proximity",
            "TC0H": "CPU Heatsink",
            "TC0G": "CPU Package",
            "TCAH": "CPU A Heatsink",
            "TCBH": "CPU B Heatsink",
            "Tj0P": "CPU Tjunction",
            "TN0D": "CPU Northbridge",
            "TN0P": "CPU Northbridge Prox",
            "TN0H": "CPU Northbridge Hsp",
            // GPU
            "TG0D": "GPU Diode",
            "TG0H": "GPU Heatsink",
            "TG0P": "GPU Proximity",
            "TG1D": "GPU Diode 2",
            "TGPH": "GPU Heatpipe",
            // Battery
            "TB0T": "Battery",
            "TB1T": "Battery 1",
            "TB2T": "Battery 2",
            "TB3T": "Battery 3",
            // Memory
            "TM0P": "Memory Proximity",
            "TM0S": "Memory Slot",
            "TM1P": "Memory Proximity 2",
            // Storage
            "TS0C": "SSD",
            "TS0D": "SSD Diode",
            "TS0P": "SSD Proximity",
            "TH0A": "HDD Bay A",
            "TH0B": "HDD Bay B",
            // Ambient / System
            "TA0P": "Ambient",
            "TA1P": "Ambient 2",
            "Th0H": "Main Heatsink",
            "Th1H": "Heatsink 2",
            "Tp0C": "Power Supply",
            "Tp0P": "Power Supply Prox",
            "Tm0P": "Mainboard Proximity",
            "TW0P": "Airport Proximity",
        ]
        return names[key] ?? key
    }
}

// MARK: - Private types

private enum SMCSelector: UInt8 {
    case handleEvent = 2
}

private enum SMCCommand: UInt8 {
    case readBytes    = 5
    case writeBytes   = 6
    case readIndex    = 8
    case readKeyInfo  = 9
}

private struct SMCValue {
    let info: SMCKeyInfoData
    let bytes: [UInt8]
}

private struct SMCVersion {
    var major: UInt8 = 0; var minor: UInt8 = 0
    var build: UInt8 = 0; var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0; var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0

    var dataTypeString: String { string(from: dataType) }
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

    var bytesArray: [UInt8] { withUnsafeBytes(of: bytes) { Array($0) } }
}

// MARK: - Helpers

private func code(from string: String) -> UInt32 {
    string.utf8.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
}

private func string(from code: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
        UInt8((code >>  8) & 0xFF), UInt8( code         & 0xFF)
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? ""
}

private func errorMessage(for code: kern_return_t) -> String {
    guard let ptr = mach_error_string(code) else { return "\(code)" }
    return "\(String(cString: ptr)) (\(code))"
}

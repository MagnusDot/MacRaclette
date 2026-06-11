//
//  SMCReader.swift
//  MacRaclette
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
    let current: Double
    let minimum: Double
    let maximum: Double

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
        case .serviceUnavailable:        return "AppleSMC service unavailable."
        case let .connectionFailed(c):   return "Cannot open AppleSMC: \(smcErrorString(c))."
        case let .callFailed(c):         return "AppleSMC call failed: \(smcErrorString(c))."
        case let .readFailed(key):       return "Cannot read sensor \(key)."
        }
    }
}

// MARK: - SMCReader

final class SMCReader {
    private var connection: io_connect_t = 0
    // Cached: on arm64, mode key may be lowercase "F0md" instead of "F0Md"
    private var fanModeKeyIsLower: Bool?

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCReaderError.serviceUnavailable }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCReaderError.callFailed(result) }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    // MARK: - Temperature

    func readTemperatureSensors() throws -> [SensorReading] {
        let keys = try allKeys()
        return keys
            .filter { $0.hasPrefix("T") }
            .compactMap { key -> SensorReading? in
                guard let value = try? readDouble(key: key), (-40...130).contains(value) else { return nil }
                return SensorReading(key: "SMC.\(key)", name: sensorName(for: key), temperature: value, source: .smc)
            }
            .sorted { $0.temperature != $1.temperature ? $0.temperature > $1.temperature : $0.key < $1.key }
    }

    // MARK: - Fan sensors

    func readFanSensors() -> [FanReading] {
        guard let rawCount = try? readUInt32(key: "FNum"), rawCount > 0 else { return [] }
        return (0..<min(Int(rawCount), 8)).compactMap { i -> FanReading? in
            guard let current = try? readDouble(key: "F\(i)Ac"),
                  let minimum = try? readDouble(key: "F\(i)Mn"),
                  let maximum = try? readDouble(key: "F\(i)Mx"),
                  maximum > 0 else { return nil }
            return FanReading(id: i, name: "Fan \(i + 1)", current: current, minimum: minimum, maximum: maximum)
        }
    }

    // MARK: - Fan boost (Stats-inspired implementation)

    /// Set all fans to maximum. Returns true when at least one fan was successfully switched to manual control.
    /// On Apple Silicon M1–M4 this uses the Ftst unlock sequence and may block ~3 s on first call.
    @discardableResult
    func setFansToMax() -> Bool {
        guard let rawCount = try? readUInt32(key: "FNum"), rawCount > 0 else { return false }
        var success = false
        for i in 0..<min(Int(rawCount), 8) {
            guard let maxRPM = try? readDouble(key: "F\(i)Mx") else { continue }
            if unlockFanControl(fanId: i) {
                setFanTargetRPM(fanId: i, rpm: maxRPM)
                success = true
            }
        }
        return success
    }

    /// Return all fans to automatic control.
    func resetFansToAuto() {
        resetFanControl()
    }

    // MARK: - Private: Apple Silicon fan unlock

    /// The mode key is "F0Md" on Intel, but "F0md" (lowercase) on some Apple Silicon generations.
    private func modeKey(for fanId: Int) -> String {
        #if arch(arm64)
        if fanModeKeyIsLower == nil {
            var probe = SMCKeyData()
            var out = SMCKeyData()
            probe.key = fourCC("F0md")
            probe.data8 = SMCCommand.readKeyInfo.rawValue
            let result = rawCall(&probe, output: &out)
            fanModeKeyIsLower = result == kIOReturnSuccess && out.keyInfo.dataSize > 0
        }
        return fanModeKeyIsLower! ? "F\(fanId)md" : "F\(fanId)Md"
        #else
        return "F\(fanId)Md"
        #endif
    }

    private func unlockFanControl(fanId: Int) -> Bool {
        #if arch(arm64)
        // M5+: direct mode write succeeds immediately
        if writeBytes(modeKey(for: fanId), bytes: [1]) { return true }

        // M1–M4: signal thermalmonitord via "Ftst" and wait for it to yield
        guard let ftstCurrent = rawReadByte("Ftst") else { return false }
        if ftstCurrent != 1 {
            guard writeWithRetry("Ftst", bytes: [1], maxAttempts: 100, delayMicros: 50_000) else { return false }
            usleep(3_000_000) // wait for thermalmonitord to hand over control
        }
        // Retry mode write — thermalmonitord may take several cycles to yield
        return writeWithRetry(modeKey(for: fanId), bytes: [1], maxAttempts: 300, delayMicros: 100_000)
        #else
        // Intel: write F{i}Md = 1 (forced), then set FS! bitmask
        _ = writeBytes("F\(fanId)Md", bytes: [1])
        let current = UInt16((try? readUInt32(key: "FS! ")) ?? 0)
        let newMode = current | (1 << fanId)
        return writeBytes("FS! ", bytes: [UInt8(newMode >> 8), UInt8(newMode & 0xFF)])
        #endif
    }

    private func resetFanControl() {
        #if arch(arm64)
        // Try Ftst reset first (M1–M4)
        if let current = rawReadByte("Ftst"), current != 0 {
            _ = writeWithRetry("Ftst", bytes: [0], maxAttempts: 10, delayMicros: 50_000)
            return
        }
        // M5+: reset mode keys directly
        let count = (try? readUInt32(key: "FNum")).map { Int($0) } ?? 0
        for i in 0..<min(count, 8) {
            _ = writeWithRetry(modeKey(for: i), bytes: [0], maxAttempts: 10, delayMicros: 50_000)
        }
        #else
        _ = writeBytes("FS! ", bytes: [0, 0])
        let count = (try? readUInt32(key: "FNum")).map { Int($0) } ?? 0
        for i in 0..<min(count, 8) { _ = writeBytes("F\(i)Md", bytes: [0]) }
        #endif
    }

    private func setFanTargetRPM(fanId: Int, rpm: Double) {
        let key = "F\(fanId)Tg"
        // Determine data type by reading current value
        guard let value = try? readKey(key) else { return }
        let dt = value.info.dataTypeString.trimmingCharacters(in: .whitespaces)
        if dt == "flt" {
            let raw = Float(rpm)
            var bytes = [UInt8](repeating: 0, count: 4)
            withUnsafeBytes(of: raw) { ptr in bytes = Array(ptr) }
            _ = writeWithRetry(key, bytes: bytes, maxAttempts: 10, delayMicros: 50_000)
        } else {
            // fpe2
            let raw = UInt16(max(0, rpm) * 4.0)
            _ = writeWithRetry(key, bytes: [UInt8(raw >> 8), UInt8(raw & 0xFF)], maxAttempts: 10, delayMicros: 50_000)
        }
    }

    // MARK: - Private: low-level write helpers

    @discardableResult
    private func writeBytes(_ key: String, bytes: [UInt8]) -> Bool {
        var infoIn = SMCKeyData()
        var infoOut = SMCKeyData()
        infoIn.key = fourCC(key)
        infoIn.data8 = SMCCommand.readKeyInfo.rawValue
        guard rawCall(&infoIn, output: &infoOut) == kIOReturnSuccess else { return false }

        var writeIn = SMCKeyData()
        var writeOut = SMCKeyData()
        writeIn.key = fourCC(key)
        writeIn.data8 = SMCCommand.writeBytes.rawValue
        writeIn.keyInfo = infoOut.keyInfo
        withUnsafeMutableBytes(of: &writeIn.bytes) { ptr in
            for (i, b) in bytes.prefix(32).enumerated() { ptr[i] = b }
        }
        return rawCall(&writeIn, output: &writeOut) == kIOReturnSuccess
    }

    /// Write bytes and verify by read-back, retrying until the value sticks or attempts run out.
    @discardableResult
    private func writeWithRetry(_ key: String, bytes: [UInt8], maxAttempts: Int, delayMicros: UInt32) -> Bool {
        for _ in 0..<maxAttempts {
            if writeBytes(key, bytes: bytes),
               let rb = rawReadBytes(key, count: bytes.count),
               rb.prefix(bytes.count).elementsEqual(bytes) {
                return true
            }
            usleep(delayMicros)
        }
        return false
    }

    private func rawReadByte(_ key: String) -> UInt8? {
        rawReadBytes(key, count: 1)?.first
    }

    private func rawReadBytes(_ key: String, count: Int) -> [UInt8]? {
        guard let val = try? readKey(key) else { return nil }
        return Array(val.bytes.prefix(count))
    }

    // MARK: - Private: key enumeration

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
        try call(&input, output: &output)
        return smcString(from: output.key)
    }

    // MARK: - Private: value reading

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
        input.key = fourCC(key)
        input.data8 = SMCCommand.readKeyInfo.rawValue
        try call(&input, output: &output)

        let keyInfo = output.keyInfo
        input.keyInfo.dataSize = keyInfo.dataSize
        input.keyInfo.dataType = keyInfo.dataType
        input.data8 = SMCCommand.readBytes.rawValue
        try call(&input, output: &output)

        let bytes = output.bytesArray.prefix(Int(keyInfo.dataSize))
        return SMCValue(info: keyInfo, bytes: Array(bytes))
    }

    // MARK: - Private: IOKit call

    @discardableResult
    private func rawCall(_ input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        let sz = MemoryLayout<SMCKeyData>.stride
        var outSz = sz
        return withUnsafeMutablePointer(to: &input) { ip in
            withUnsafeMutablePointer(to: &output) { op in
                IOConnectCallStructMethod(connection, UInt32(SMCSelector.handleEvent.rawValue), ip, sz, op, &outSz)
            }
        }
    }

    private func call(_ input: inout SMCKeyData, output: inout SMCKeyData) throws {
        let result = rawCall(&input, output: &output)
        guard result == kIOReturnSuccess else { throw SMCReaderError.connectionFailed(result) }
    }

    // MARK: - Sensor names

    private func sensorName(for key: String) -> String {
        let names: [String: String] = [
            "TC0C": "CPU Core 0", "TC1C": "CPU Core 1", "TC2C": "CPU Core 2", "TC3C": "CPU Core 3",
            "TC0D": "CPU Diode", "TC0E": "CPU Proximity", "TC0P": "CPU Proximity", "TC0H": "CPU Heatsink",
            "TC0G": "CPU Package", "TCAH": "CPU A Heatsink", "TCBH": "CPU B Heatsink",
            "Tj0P": "CPU Tjunction", "TN0D": "CPU Northbridge", "TN0P": "CPU Northbridge Prox",
            "TG0D": "GPU Diode", "TG0H": "GPU Heatsink", "TG0P": "GPU Proximity",
            "TG1D": "GPU Diode 2", "TGPH": "GPU Heatpipe",
            "TB0T": "Battery", "TB1T": "Battery 1", "TB2T": "Battery 2", "TB3T": "Battery 3",
            "TM0P": "Memory Proximity", "TM0S": "Memory Slot", "TM1P": "Memory Proximity 2",
            "TS0C": "SSD", "TS0D": "SSD Diode", "TS0P": "SSD Proximity",
            "TH0A": "HDD Bay A", "TH0B": "HDD Bay B",
            "TA0P": "Ambient", "TA1P": "Ambient 2",
            "Th0H": "Main Heatsink", "Th1H": "Heatsink 2",
            "Tp0C": "Power Supply", "Tm0P": "Mainboard Proximity", "TW0P": "Airport Proximity",
        ]
        return names[key] ?? key
    }
}

// MARK: - Private types

private enum SMCSelector: UInt8 { case handleEvent = 2 }
private enum SMCCommand:  UInt8 {
    case readBytes = 5, writeBytes = 6, readIndex = 8, readKeyInfo = 9
}

private struct SMCValue {
    let info: SMCKeyInfoData
    let bytes: [UInt8]
}

private struct SMCVersion {
    var major: UInt8 = 0; var minor: UInt8 = 0
    var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0; var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    var dataTypeString: String { smcString(from: dataType) }
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

private func fourCC(_ s: String) -> UInt32 {
    s.utf8.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
}

private func smcString(from code: UInt32) -> String {
    let bytes: [UInt8] = [
        UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
        UInt8((code >>  8) & 0xFF), UInt8( code         & 0xFF),
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? ""
}

private func smcErrorString(_ code: kern_return_t) -> String {
    guard let ptr = mach_error_string(code) else { return "\(code)" }
    return "\(String(cString: ptr)) (\(code))"
}

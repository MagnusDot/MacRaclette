import Foundation
import IOKit

// MARK: - Models

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

// MARK: - SMCReader

final class SMCReader {
    private var connection: io_connect_t = 0

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceUnavailable }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else { throw SMCError.openFailed(result) }
    }

    deinit { if connection != 0 { IOServiceClose(connection) } }

    func readTemperatureSensors() throws -> [SensorReading] {
        try allKeys()
            .filter { $0.hasPrefix("T") }
            .compactMap { key -> SensorReading? in
                guard let value = try? readDouble(key), (-40...130).contains(value) else { return nil }
                return SensorReading(key: "SMC.\(key)", name: sensorName(for: key), temperature: value, source: .smc)
            }
            .sorted { $0.temperature != $1.temperature ? $0.temperature > $1.temperature : $0.key < $1.key }
    }

    func readFanSensors() -> [FanReading] {
        guard let count = try? readUInt32("FNum"), count > 0 else { return [] }
        return (0..<min(Int(count), 8)).compactMap { i in
            guard let current = try? readDouble("F\(i)Ac"),
                  let minimum = try? readDouble("F\(i)Mn"),
                  let maximum = try? readDouble("F\(i)Mx"),
                  maximum > 0 else { return nil }
            return FanReading(id: i, name: "Fan \(i + 1)", current: current, minimum: minimum, maximum: maximum)
        }
    }

    // MARK: - Private

    private func allKeys() throws -> [String] {
        let count = Int(try readUInt32("#KEY"))
        guard count > 0 else { return [] }
        return try (0..<count).map { try keyAt(UInt32($0)) }
    }

    private func keyAt(_ index: UInt32) throws -> String {
        var input = SMCKeyData(), output = SMCKeyData()
        input.data8 = SMCCommand.readIndex.rawValue
        input.data32 = index
        try call(&input, output: &output)
        return smcString(from: output.key)
    }

    private func readDouble(_ key: String) throws -> Double {
        let value = try readKey(key)
        switch value.dataType.trimmingCharacters(in: .whitespaces) {
        case "sp78":
            guard value.bytes.count >= 2 else { throw SMCError.readFailed(key) }
            return Double(Int16(bitPattern: UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))) / 256.0
        case "fpe2":
            guard value.bytes.count >= 2 else { throw SMCError.readFailed(key) }
            return Double(UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])) / 4.0
        case "flt":
            guard value.bytes.count >= 4 else { throw SMCError.readFailed(key) }
            let raw = UInt32(value.bytes[0]) << 24 | UInt32(value.bytes[1]) << 16
                    | UInt32(value.bytes[2]) << 8  | UInt32(value.bytes[3])
            return Double(Float(bitPattern: raw))
        default:
            throw SMCError.readFailed(key)
        }
    }

    private func readUInt32(_ key: String) throws -> UInt32 {
        let value = try readKey(key)
        let b = value.bytes
        if value.dataType.trimmingCharacters(in: .whitespaces) == "ui32", b.count >= 4 {
            return UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
        }
        if b.count >= 2 { return UInt32(b[0]) << 8 | UInt32(b[1]) }
        if b.count >= 1 { return UInt32(b[0]) }
        throw SMCError.readFailed(key)
    }

    private func readKey(_ key: String) throws -> (dataType: String, bytes: [UInt8]) {
        var input = SMCKeyData(), output = SMCKeyData()
        input.key = fourCC(key)
        input.data8 = SMCCommand.readKeyInfo.rawValue
        try call(&input, output: &output)

        let info = output.keyInfo
        input.keyInfo = info
        input.data8 = SMCCommand.readBytes.rawValue
        try call(&input, output: &output)

        return (smcString(from: info.dataType), Array(output.bytesArray.prefix(Int(info.dataSize))))
    }

    private func call(_ input: inout SMCKeyData, output: inout SMCKeyData) throws {
        let sz = MemoryLayout<SMCKeyData>.stride
        var outSz = sz
        let result = withUnsafeMutablePointer(to: &input) { ip in
            withUnsafeMutablePointer(to: &output) { op in
                IOConnectCallStructMethod(connection, UInt32(SMCCommand.handleEvent.rawValue), ip, sz, op, &outSz)
            }
        }
        guard result == kIOReturnSuccess else { throw SMCError.callFailed(result) }
    }

    private func sensorName(for key: String) -> String {
        let names: [String: String] = [
            "TC0C": "CPU Core 0",  "TC1C": "CPU Core 1",  "TC2C": "CPU Core 2",  "TC3C": "CPU Core 3",
            "TC0D": "CPU Diode",   "TC0E": "CPU Proximity","TC0P": "CPU Proximity","TC0H": "CPU Heatsink",
            "TC0G": "CPU Package", "TCAH": "CPU A Heatsink","TCBH": "CPU B Heatsink",
            "Tj0P": "CPU Tjunction","TN0D": "CPU Northbridge","TN0P": "CPU Northbridge Prox",
            "TG0D": "GPU Diode",   "TG0H": "GPU Heatsink", "TG0P": "GPU Proximity","TG1D": "GPU Diode 2",
            "TB0T": "Battery",     "TB1T": "Battery 1",    "TB2T": "Battery 2",    "TB3T": "Battery 3",
            "TM0P": "Memory Proximity","TM0S": "Memory Slot","TM1P": "Memory Proximity 2",
            "TS0C": "SSD",         "TS0D": "SSD Diode",    "TS0P": "SSD Proximity",
            "TH0A": "HDD Bay A",   "TH0B": "HDD Bay B",
            "TA0P": "Ambient",     "TA1P": "Ambient 2",
            "Th0H": "Main Heatsink","Th1H": "Heatsink 2",
            "Tp0C": "Power Supply","Tm0P": "Mainboard Proximity","TW0P": "Airport Proximity",
        ]
        return names[key] ?? key
    }
}

// MARK: - Private types

private enum SMCError: LocalizedError {
    case serviceUnavailable, openFailed(kern_return_t), callFailed(kern_return_t), readFailed(String)

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:   return "AppleSMC service unavailable."
        case .openFailed(let c):    return "Cannot open AppleSMC: \(smcErrorString(c))."
        case .callFailed(let c):    return "AppleSMC call failed: \(smcErrorString(c))."
        case .readFailed(let key):  return "Cannot read SMC key \(key)."
        }
    }
}

private enum SMCCommand: UInt8 {
    case handleEvent = 2
    case readBytes   = 5
    case readIndex   = 8
    case readKeyInfo = 9
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    // SMCVersion (major, minor, build, reserved, release)
    var vers: (UInt8, UInt8, UInt8, UInt8, UInt16) = (0, 0, 0, 0, 0)
    // SMCPLimitData (version, length, cpuPLimit, gpuPLimit, memPLimit)
    var pLimit: (UInt16, UInt16, UInt32, UInt32, UInt32) = (0, 0, 0, 0, 0)
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
        UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
        UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
        UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8
    ) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

    var bytesArray: [UInt8] { withUnsafeBytes(of: bytes) { Array($0) } }
}

private func fourCC(_ s: String) -> UInt32 {
    s.utf8.reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
}

private func smcString(from code: UInt32) -> String {
    let b: [UInt8] = [UInt8((code>>24)&0xFF), UInt8((code>>16)&0xFF), UInt8((code>>8)&0xFF), UInt8(code&0xFF)]
    return String(bytes: b, encoding: .macOSRoman) ?? ""
}

private func smcErrorString(_ code: kern_return_t) -> String {
    guard let ptr = mach_error_string(code) else { return "\(code)" }
    return "\(String(cString: ptr)) (\(code))"
}

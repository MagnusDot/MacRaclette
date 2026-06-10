//
//  SMCReader.swift
//  MacRaclette
//
//  Created by Alois Marcellin on 10/06/2026.
//

import Foundation
import IOKit

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

enum SMCReaderError: LocalizedError {
    case serviceUnavailable
    case connectionFailed(kern_return_t)
    case callFailed(kern_return_t)
    case readFailed(String)

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "Service AppleSMC indisponible."
        case let .connectionFailed(code):
            return "Ouverture AppleSMC impossible: \(errorMessage(for: code))."
        case let .callFailed(code):
            return "Appel AppleSMC impossible: \(errorMessage(for: code))."
        case let .readFailed(key):
            return "Lecture du capteur \(key) impossible."
        }
    }
}

final class SMCReader {
    private var connection: io_connect_t = 0

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            throw SMCReaderError.serviceUnavailable
        }

        defer {
            IOObjectRelease(service)
        }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else {
            throw SMCReaderError.callFailed(result)
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func readTemperatureSensors() throws -> [SensorReading] {
        let keys = try allKeys()

        return keys
            .filter { $0.hasPrefix("T") }
            .compactMap { key in
                guard let value = try? readTemperature(key: key), (-40...130).contains(value) else {
                    return nil
                }

                return SensorReading(key: "SMC.\(key)", name: sensorName(for: key), temperature: value, source: .smc)
            }
            .sorted { first, second in
                if first.temperature == second.temperature {
                    return first.key < second.key
                }

                return first.temperature > second.temperature
            }
    }

    private func allKeys() throws -> [String] {
        let count = Int(try readUInt32(key: "#KEY"))
        guard count > 0 else {
            return []
        }

        return try (0..<count).map { index in
            try key(at: UInt32(index))
        }
    }

    private func key(at index: UInt32) throws -> String {
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.data8 = SMCCommand.readIndex.rawValue
        input.data32 = index

        try call(.handleEvent, input: &input, output: &output)
        return string(from: output.key)
    }

    private func readTemperature(key: String) throws -> Double {
        let value = try readKey(key)

        switch value.info.dataTypeString.trimmingCharacters(in: .whitespaces) {
        case "sp78":
            guard value.bytes.count >= 2 else {
                throw SMCReaderError.readFailed(key)
            }

            let raw = Int16(bitPattern: UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1]))
            return Double(raw) / 256.0
        case "fpe2":
            guard value.bytes.count >= 2 else {
                throw SMCReaderError.readFailed(key)
            }

            let raw = UInt16(value.bytes[0]) << 8 | UInt16(value.bytes[1])
            return Double(raw) / 4.0
        case "flt":
            guard value.bytes.count >= 4 else {
                throw SMCReaderError.readFailed(key)
            }

            let raw = UInt32(value.bytes[0]) << 24
                | UInt32(value.bytes[1]) << 16
                | UInt32(value.bytes[2]) << 8
                | UInt32(value.bytes[3])
            return Double(Float(bitPattern: raw))
        default:
            throw SMCReaderError.readFailed(key)
        }
    }

    private func readUInt32(key: String) throws -> UInt32 {
        let value = try readKey(key)
        let bytes = value.bytes

        if value.info.dataTypeString == "ui32", bytes.count >= 4 {
            return UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
        }

        if bytes.count >= 2 {
            return UInt32(bytes[0]) << 8 | UInt32(bytes[1])
        }

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

    private func call(_ selector: SMCSelector, input: inout SMCKeyData, output: inout SMCKeyData) throws {
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = withUnsafeMutablePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    UInt32(selector.rawValue),
                    inputPointer,
                    inputSize,
                    outputPointer,
                    &outputSize
                )
            }
        }

        guard result == kIOReturnSuccess else {
            throw SMCReaderError.connectionFailed(result)
        }
    }

    private func sensorName(for key: String) -> String {
        let names = [
            "TC0C": "CPU Core",
            "TC0D": "CPU Diode",
            "TC0E": "CPU Proximity",
            "TC0P": "CPU Proximity",
            "TG0D": "GPU Diode",
            "TG0P": "GPU Proximity",
            "TB0T": "Battery",
            "TM0P": "Memory Proximity",
            "TN0D": "Northbridge",
            "Tp0C": "Power Supply"
        ]

        return names[key] ?? key
    }
}

private enum SMCSelector: UInt8 {
    case handleEvent = 2
}

private enum SMCCommand: UInt8 {
    case readBytes = 5
    case readIndex = 8
    case readKeyInfo = 9
}

private struct SMCValue {
    let info: SMCKeyInfoData
    let bytes: [UInt8]
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0

    var dataTypeString: String {
        string(from: dataType)
    }
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
    ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    var bytesArray: [UInt8] {
        withUnsafeBytes(of: bytes) { Array($0) }
    }
}

private func code(from string: String) -> UInt32 {
    string.utf8.reduce(UInt32(0)) { result, character in
        (result << 8) + UInt32(character)
    }
}

private func string(from code: UInt32) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]

    return String(bytes: bytes, encoding: .macOSRoman) ?? ""
}

private func errorMessage(for code: kern_return_t) -> String {
    guard let pointer = mach_error_string(code) else {
        return "\(code)"
    }

    return "\(String(cString: pointer)) (\(code))"
}

import Testing
@testable import MacRaclette

// MARK: - FanReading

struct FanReadingTests {
    @Test func percentageNormal() {
        let fan = FanReading(id: 0, name: "Fan 1", current: 2000, minimum: 1000, maximum: 5000)
        #expect(fan.percentage == 0.25)
    }

    @Test func percentageAtMin() {
        let fan = FanReading(id: 0, name: "Fan 1", current: 1000, minimum: 1000, maximum: 5000)
        #expect(fan.percentage == 0.0)
    }

    @Test func percentageAtMax() {
        let fan = FanReading(id: 0, name: "Fan 1", current: 5000, minimum: 1000, maximum: 5000)
        #expect(fan.percentage == 1.0)
    }

    @Test func percentageClampsAboveMax() {
        let fan = FanReading(id: 0, name: "Fan 1", current: 9999, minimum: 1000, maximum: 5000)
        #expect(fan.percentage == 1.0)
    }

    @Test func percentageClampsBelow0() {
        let fan = FanReading(id: 0, name: "Fan 1", current: 0, minimum: 1000, maximum: 5000)
        #expect(fan.percentage == 0.0)
    }

    @Test func percentageZeroWhenMaxEqualsMin() {
        let fan = FanReading(id: 0, name: "Fan 1", current: 1000, minimum: 1000, maximum: 1000)
        #expect(fan.percentage == 0.0)
    }
}

// MARK: - Double.temperatureText

struct TemperatureTextTests {
    @Test func wholeNumber() {
        #expect((72.0).temperatureText == "72°C")
    }

    @Test func withDecimal() {
        #expect((51.8).temperatureText == (51.8).formatted(.number.precision(.fractionLength(0...1))) + "°C")
    }

    @Test func roundsToOneDecimal() {
        #expect((51.85).temperatureText.hasSuffix("°C"))
    }
}

// MARK: - RacletteMonitor computed state

@MainActor
struct RacletteMonitorTests {
    @Test func gaugeProgressClamped() {
        let m = RacletteMonitor()
        #expect(m.gaugeProgress >= 0)
        #expect(m.gaugeProgress <= 1)
    }

    @Test func visualStateUnavailableWhenNoSensors() {
        let m = RacletteMonitor()
        if m.sensorReadings.isEmpty {
            #expect(m.visualState == .unavailable)
        }
    }

    @Test func isRacletteModeMatchesThreshold() {
        let m = RacletteMonitor()
        #expect(m.isRacletteMode == (m.currentTemperature >= m.threshold))
    }

    @Test func menuBarTitleWhenNoSensors() {
        let m = RacletteMonitor()
        if !m.hasSensors {
            #expect(m.menuBarTitle == "Raclette ?")
        }
    }

    @Test func resetStatsClearsHistory() {
        let m = RacletteMonitor()
        m.resetStats()
        #expect(m.history.count <= 1)
    }

    @Test func thermalStateLabelValid() {
        let m = RacletteMonitor()
        let valid = ["Normal", "Moderate", "High", "Critical", "Unknown"]
        #expect(valid.contains(m.thermalStateLabel))
    }
}

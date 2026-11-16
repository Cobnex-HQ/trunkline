import XCTest
@testable import TrunklineCore

final class CoreTests: XCTestCase {
    // A parser accepting oversized payloads, or losing partial packets, breaks these tests.
    func testFramingHandlesFragmentationAndMultipleMessages() throws {
        let first = try PacketCodec.encode(.text("hello"))
        let second = try PacketCodec.encode(.key(code: 36, modifiers: 0))
        var parser = PacketParser()
        XCTAssertEqual(try parser.append(first.prefix(3)).count, 0)
        let messages = try parser.append(Data(first.dropFirst(3)) + second)
        XCTAssertEqual(messages, [.text("hello"), .key(code: 36, modifiers: 0)])
    }
    func testRejectsOversizedPacketBeforeBufferingBody() {
        var parser = PacketParser()
        XCTAssertThrowsError(try parser.append(Data([0x7f, 0xff, 0xff, 0xff])))
    }
    func testRejectsZeroLengthAndMalformedJSON() {
        var parser = PacketParser()
        XCTAssertThrowsError(try parser.append(Data([0, 0, 0, 0])))
        var another = PacketParser()
        XCTAssertThrowsError(try another.append(Data([0, 0, 0, 1, 0xff])))
    }
    // Removing the KDF or comparing against the wrong secret breaks these assertions.
    func testPasscodeIsSaltedAndVerifies() throws {
        let a = try PasscodeRecord(passcode: "62914582")
        let b = try PasscodeRecord(passcode: "62914582")
        XCTAssertNotEqual(a.salt, b.salt)
        XCTAssertNotEqual(a.digest, b.digest)
        XCTAssertTrue(a.verify("62914582"))
        XCTAssertFalse(a.verify("62914583"))
        XCTAssertThrowsError(try PasscodeRecord(passcode: "123"))
    }
    func testLockoutSurvivesNewConnectionAndExpires() {
        var limiter = AttemptLimiter()
        let now = Date(timeIntervalSince1970: 100)
        for _ in 0..<5 { limiter.recordFailure(at: now) }
        XCTAssertFalse(limiter.isAllowed(at: now.addingTimeInterval(1)))
        XCTAssertTrue(limiter.isAllowed(at: now.addingTimeInterval(61)))
        limiter.reset()
        XCTAssertTrue(limiter.isAllowed(at: now))
    }
    func testPairingRejectsMissingOrInvalidPinAndEndpoint() throws {
        let pin = String(repeating: "ab", count: 32)
        let pairing = try PairingDetails(host: "mac.local", port: 47995, fingerprint: pin)
        XCTAssertEqual(try PairingDetails.parse(pairing.link), pairing)
        XCTAssertThrowsError(try PairingDetails(host: "", port: 47995, fingerprint: pin))
        XCTAssertThrowsError(try PairingDetails(host: "mac.local", port: 0, fingerprint: pin))
        XCTAssertThrowsError(try PairingDetails(host: "mac.local", port: 47995, fingerprint: "abc"))
        XCTAssertThrowsError(try PairingDetails.parse("https://example.com"))
    }
    func testInputValidationRejectsNonFiniteAndUnboundedEvents() {
        XCTAssertFalse(WireMessage.pointer(x: .nan, y: 0, phase: .move).isValidInput)
        XCTAssertFalse(WireMessage.pointer(x: 1.1, y: 0, phase: .move).isValidInput)
        XCTAssertTrue(WireMessage.pointer(x: 0.5, y: 0.5, phase: .down).isValidInput)
        XCTAssertFalse(WireMessage.text(String(repeating: "a", count: 4097)).isValidInput)
        XCTAssertFalse(WireMessage.key(code: 999, modifiers: 0).isValidInput)
        XCTAssertFalse(WireMessage.scroll(dx: .infinity, dy: 1).isValidInput)
    }
    func testVideoUsesBinaryPayloadWithoutBase64Expansion() throws {
        let frame = VideoFrame(bytes: Data(repeating: 0xab, count: 1000), sps: Data([1,2,3]), pps: Data([4,5]), width: 1600, height: 1000)
        let packet = try PacketCodec.encode(.video(frame))
        XCTAssertLessThan(packet.count, 1050)
        var parser = PacketParser()
        XCTAssertEqual(try parser.append(packet), [.video(frame)])
    }
    func testStreamProfilesHaveBoundedBandwidthAndResolution() throws {
        XCTAssertEqual(StreamProfile.responsive.maximumWidth, 1280)
        XCTAssertEqual(StreamProfile.dataSaver.framesPerSecond, 30)
        for profile in StreamProfile.allCases {
            XCTAssertLessThanOrEqual(profile.maximumWidth, 1920)
            XCTAssertLessThanOrEqual(profile.bitrate, 20_000_000)
            var parser = PacketParser()
            XCTAssertEqual(try parser.append(PacketCodec.encode(.startStream(profile: profile))), [.startStream(profile: profile)])
        }
    }

}

final class AudioPacketTests: XCTestCase {
    func testAudioUsesValidatedStereoPCMWithoutBase64() throws {
        let audio = AudioPacket(samples: Data(repeating: 0, count: 1920), frameCount: 480)
        var parser = PacketParser()
        let encoded = try PacketCodec.encode(.audio(audio))
        XCTAssertLessThan(encoded.count, 1940)
        XCTAssertEqual(try parser.append(encoded), [.audio(audio)])
        XCTAssertThrowsError(try PacketCodec.encode(.audio(AudioPacket(samples: Data([1]), frameCount: 480))))
        XCTAssertThrowsError(try PacketCodec.encode(.audio(AudioPacket(samples: Data(), frameCount: -1))))
    }
}

final class KeyframeTests: XCTestCase {
    func testRecognizesIDRAndRejectsTruncatedNALUnits() {
        func frame(_ bytes: [UInt8]) -> VideoFrame { VideoFrame(bytes: Data(bytes), sps: Data([1]), pps: Data([2]), width: 1280, height: 800) }
        XCTAssertTrue(frame([0,0,0,2,0x65,0]).isKeyframe)
        XCTAssertFalse(frame([0,0,0,2,0x41,0]).isKeyframe)
        XCTAssertFalse(frame([0,0,0,8,0x65]).isKeyframe)
        XCTAssertTrue(frame([0,0,0,1,0x06,0,0,0,1,0x65]).isKeyframe)
    }
}

final class SessionProtocolTests: XCTestCase {
    func testTerminalOutputPreservesEscapeSequencesAndBinaryBytes() throws {
        let id = UUID()
        let bytes = Data([0x1b,0x5b,0x32,0x4a,0xff,0,0x0a])
        let message = WireMessage.terminalOutput(id: id, bytes: bytes, reset: true)
        var parser = PacketParser()
        XCTAssertEqual(try parser.append(PacketCodec.encode(message)), [message])
    }
    func testTerminalInputAndResizeHaveResourceLimits() {
        XCTAssertTrue(TerminalLimits.validInput(Data("\u{3}".utf8)))
        XCTAssertFalse(TerminalLimits.validInput(Data(repeating: 0, count: 16385)))
        XCTAssertTrue(TerminalLimits.validSize(columns: 120, rows: 40))
        XCTAssertFalse(TerminalLimits.validSize(columns: 0, rows: 40))
        XCTAssertFalse(TerminalLimits.validSize(columns: 10000, rows: 40))
    }
}

import XCTest
@testable import LittleWatch

final class AudioRuleEngineTests: XCTestCase {
    private let speakers = "uid-builtin-speaker"
    private let headphone = "uid-headphone"
    private let boya = "uid-boya"
    private let blackhole = "uid-blackhole"

    private var available: Set<String> {
        [speakers, headphone, boya, blackhole]
    }

    func testForbiddenDefaultTriggersCorrectionToLastManualSelection() {
        let target = AudioRuleEngine.correctionTarget(for: .init(
            currentDefaultUID: boya,
            forbiddenUIDs: [boya],
            lastManualUID: headphone,
            fallbackUID: speakers,
            availableUIDs: available
        ))

        XCTAssertEqual(target, headphone)
    }

    func testCorrectionFallsBackToBuiltInWhenManualSelectionDisconnected() {
        let target = AudioRuleEngine.correctionTarget(for: .init(
            currentDefaultUID: boya,
            forbiddenUIDs: [boya],
            lastManualUID: "uid-gone",
            fallbackUID: speakers,
            availableUIDs: available.subtracting([headphone])
        ))

        XCTAssertEqual(target, speakers)
    }

    func testNoCorrectionWhenDefaultIsAllowed() {
        let target = AudioRuleEngine.correctionTarget(for: .init(
            currentDefaultUID: headphone,
            forbiddenUIDs: [boya],
            lastManualUID: headphone,
            fallbackUID: speakers,
            availableUIDs: available
        ))

        XCTAssertNil(target)
    }

    func testNoCorrectionWhenNoValidTargetExists() {
        // 上次手选和内置扬声器都被禁掉时，不做纠正（避免无限循环）。
        let target = AudioRuleEngine.correctionTarget(for: .init(
            currentDefaultUID: boya,
            forbiddenUIDs: [boya, speakers, headphone],
            lastManualUID: headphone,
            fallbackUID: speakers,
            availableUIDs: available
        ))

        XCTAssertNil(target)
    }

    func testCorrectionSkipsForbiddenManualSelection() {
        // 用户手选耳机之后又把耳机禁了：不能切回被禁的耳机，回退内置。
        let target = AudioRuleEngine.correctionTarget(for: .init(
            currentDefaultUID: boya,
            forbiddenUIDs: [boya, headphone],
            lastManualUID: headphone,
            fallbackUID: speakers,
            availableUIDs: available
        ))

        XCTAssertEqual(target, speakers)
    }

    func testNilDefaultProducesNoCorrection() {
        let target = AudioRuleEngine.correctionTarget(for: .init(
            currentDefaultUID: nil,
            forbiddenUIDs: [boya],
            lastManualUID: headphone,
            fallbackUID: speakers,
            availableUIDs: available
        ))

        XCTAssertNil(target)
    }

    func testManualSelectionRecordedForAllowedDevice() {
        let recorded = AudioRuleEngine.recordedManualSelection(
            previousUID: speakers,
            newDefaultUID: headphone,
            forbiddenUIDs: [boya]
        )

        XCTAssertEqual(recorded, headphone)
    }

    func testManualSelectionKeptWhenDefaultFallsIntoForbiddenSet() {
        // BOYA 抢占默认输出时，不能把「上次手选」覆盖成 BOYA。
        let recorded = AudioRuleEngine.recordedManualSelection(
            previousUID: headphone,
            newDefaultUID: boya,
            forbiddenUIDs: [boya]
        )

        XCTAssertEqual(recorded, headphone)
    }

    func testManualSelectionKeptWhenDefaultDisappears() {
        let recorded = AudioRuleEngine.recordedManualSelection(
            previousUID: headphone,
            newDefaultUID: nil,
            forbiddenUIDs: []
        )

        XCTAssertEqual(recorded, headphone)
    }

    func testRuleStateTogglesAreDirectionIsolated() {
        var state = AudioRuleState()

        state = state.forbidding(boya, for: .output)
        XCTAssertTrue(state.forbiddenUIDs(for: .output).contains(boya))
        XCTAssertTrue(state.forbiddenUIDs(for: .input).isEmpty)

        state = state.forbidding(blackhole, for: .input)
        XCTAssertTrue(state.forbiddenUIDs(for: .input).contains(blackhole))
        XCTAssertEqual(state.forbiddenUIDs(for: .output), [boya])

        state = state.allowing(boya, for: .output)
        XCTAssertTrue(state.forbiddenUIDs(for: .output).isEmpty)

        state = state.recordingManualSelection(headphone, for: .output)
        state = state.recordingManualSelection(blackhole, for: .input)
        XCTAssertEqual(state.lastManualUID(for: .output), headphone)
        XCTAssertEqual(state.lastManualUID(for: .input), blackhole)
    }

    func testRuleStatePersistsThroughJSONRoundTrip() throws {
        var state = AudioRuleState()
        state = state.forbidding(boya, for: .output)
        state = state.forbidding(blackhole, for: .output)
        state = state.forbidding(blackhole, for: .input)
        state = state.recordingManualSelection(speakers, for: .output)

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AudioRuleState.self, from: data)

        XCTAssertEqual(decoded, state)
    }
}

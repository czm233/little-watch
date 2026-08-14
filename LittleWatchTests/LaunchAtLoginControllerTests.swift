import XCTest
@testable import LittleWatch

@MainActor
final class LaunchAtLoginControllerTests: XCTestCase {
    func testPreferenceStorePersistsSelection() throws {
        let suiteName = "LittleWatchTests.LaunchAtLogin.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LaunchAtLoginPreferenceStore(defaults: defaults)

        XCTAssertFalse(store.load())
        store.save(true)
        XCTAssertTrue(store.load())
        store.save(false)
        XCTAssertFalse(store.load())
    }

    func testEnablingRegistersMainAppAndPersistsSelection() throws {
        let fixture = try makeFixture()

        fixture.controller.setEnabled(true)

        XCTAssertEqual(fixture.service.registerCallCount, 1)
        XCTAssertTrue(fixture.controller.isEnabled)
        XCTAssertEqual(fixture.controller.registrationStatus, .enabled)
        XCTAssertTrue(fixture.preferenceStore.load())
    }

    func testDisablingUnregistersMainAppAndPersistsSelection() throws {
        let fixture = try makeFixture(initialStatus: .enabled)

        fixture.controller.setEnabled(false)

        XCTAssertEqual(fixture.service.unregisterCallCount, 1)
        XCTAssertFalse(fixture.controller.isEnabled)
        XCTAssertEqual(fixture.controller.registrationStatus, .notRegistered)
        XCTAssertFalse(fixture.preferenceStore.load())
    }

    func testApprovalStatusKeepsToggleEnabledAndExplainsNextStep() throws {
        let fixture = try makeFixture(registerResult: .requiresApproval)

        fixture.controller.setEnabled(true)

        XCTAssertTrue(fixture.controller.isEnabled)
        XCTAssertTrue(fixture.controller.requiresApproval)
        XCTAssertTrue(fixture.controller.statusDetail.contains("系统设置"))
    }

    func testRegistrationFailureRollsBackToggle() throws {
        let fixture = try makeFixture()
        fixture.service.registerError = TestError.registrationFailed

        fixture.controller.setEnabled(true)

        XCTAssertFalse(fixture.controller.isEnabled)
        XCTAssertFalse(fixture.preferenceStore.load())
        XCTAssertNotNil(fixture.controller.errorMessage)
    }

    private func makeFixture(
        initialStatus: LaunchAtLoginRegistrationStatus = .notRegistered,
        registerResult: LaunchAtLoginRegistrationStatus = .enabled
    ) throws -> Fixture {
        let suiteName = "LittleWatchTests.LaunchAtLogin.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let preferenceStore = LaunchAtLoginPreferenceStore(defaults: defaults)
        let service = MockLaunchAtLoginService(status: initialStatus, registerResult: registerResult)
        let controller = LaunchAtLoginController(service: service, preferenceStore: preferenceStore)
        return Fixture(controller: controller, service: service, preferenceStore: preferenceStore)
    }
}

@MainActor
private struct Fixture {
    let controller: LaunchAtLoginController
    let service: MockLaunchAtLoginService
    let preferenceStore: LaunchAtLoginPreferenceStore
}

private final class MockLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginRegistrationStatus
    var registerError: Error?
    var unregisterError: Error?
    var registerCallCount = 0
    var unregisterCallCount = 0
    var openSystemSettingsCallCount = 0

    private let registerResult: LaunchAtLoginRegistrationStatus

    init(
        status: LaunchAtLoginRegistrationStatus,
        registerResult: LaunchAtLoginRegistrationStatus
    ) {
        self.status = status
        self.registerResult = registerResult
    }

    func register() throws {
        registerCallCount += 1
        if let registerError { throw registerError }
        status = registerResult
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}

private enum TestError: LocalizedError {
    case registrationFailed

    var errorDescription: String? {
        "测试注册失败"
    }
}

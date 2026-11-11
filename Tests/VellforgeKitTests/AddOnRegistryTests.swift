import AppKit
import SwiftUI
import XCTest
@testable import VellforgeKit

@MainActor
private final class FakeAddOn: AddOn {
    let id: String
    let name: String
    let tagline = ""
    let summary = ""
    let symbolName = "circle"
    let permissions: [PermissionUse]
    private(set) var isRunning = false
    private(set) var starts = 0
    private(set) var stops = 0

    init(_ id: String, permissions: [PermissionUse] = []) {
        self.id = id
        self.name = id.capitalized
        self.permissions = permissions
    }

    func start() { isRunning = true; starts += 1 }
    func stop() { isRunning = false; stops += 1 }
    func menuItems() -> [NSMenuItem] { [] }
    func makeSettingsView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
final class AddOnRegistryTests: XCTestCase {

    private var defaults: UserDefaults!
    private var granted: Set<Permission> = []

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "VellforgeKitTests-\(UUID().uuidString)")
        granted = []
    }

    private func makeRegistry(_ addOns: [any AddOn]) -> AddOnRegistry {
        AddOnRegistry(addOns: addOns, defaults: defaults,
                      isGranted: { [unowned self] in self.granted.contains($0) })
    }

    private let needsAX = [PermissionUse(.accessibility, required: true, reason: "")]
    private let wantsScreen = [PermissionUse(.screenRecording, required: false, reason: "")]

    func testNothingRunsUntilSwitchedOn() {
        let snap = FakeAddOn("snap")
        let registry = makeRegistry([snap])
        registry.refresh()
        XCTAssertFalse(snap.isRunning)
        XCTAssertEqual(snap.starts, 0)
    }

    func testSwitchingOnStartsWhenNothingIsRequired() {
        let bar = FakeAddOn("bar", permissions: wantsScreen)
        let registry = makeRegistry([bar])
        registry.setEnabled(true, for: bar)
        XCTAssertTrue(bar.isRunning, "optional permissions must not hold an add-on back")
    }

    func testWaitsForRequiredPermissionThenStarts() {
        let snap = FakeAddOn("snap", permissions: needsAX)
        let registry = makeRegistry([snap])

        registry.setEnabled(true, for: snap)
        XCTAssertFalse(snap.isRunning)
        XCTAssertEqual(registry.missingPermissions(for: snap), [.accessibility])

        granted.insert(.accessibility)
        registry.refresh()
        XCTAssertTrue(snap.isRunning)
        XCTAssertEqual(snap.starts, 1)

        // Refreshing again must not start it twice.
        registry.refresh()
        XCTAssertEqual(snap.starts, 1)
    }

    func testRevokedPermissionStopsIt() {
        granted = [.accessibility]
        let scroll = FakeAddOn("scroll", permissions: needsAX)
        let registry = makeRegistry([scroll])
        registry.setEnabled(true, for: scroll)
        XCTAssertTrue(scroll.isRunning)

        granted = []
        registry.refresh()
        XCTAssertFalse(scroll.isRunning)
    }

    func testSwitchingOffStops() {
        let bar = FakeAddOn("bar")
        let registry = makeRegistry([bar])
        registry.setEnabled(true, for: bar)
        registry.setEnabled(false, for: bar)
        XCTAssertFalse(bar.isRunning)
        XCTAssertEqual(bar.stops, 1)
    }

    func testChoicesPersistInListOrderAndIgnoreUnknownIDs() {
        let snap = FakeAddOn("snap"), scroll = FakeAddOn("scroll"), bar = FakeAddOn("bar")
        let registry = makeRegistry([snap, scroll, bar])
        registry.setEnabled(true, for: bar)
        registry.setEnabled(true, for: snap)
        XCTAssertEqual(defaults.stringArray(forKey: AddOnRegistry.enabledKey), ["snap", "bar"])

        defaults.set(["bar", "retired-addon"], forKey: AddOnRegistry.enabledKey)
        let reloaded = makeRegistry([FakeAddOn("snap"), FakeAddOn("bar")])
        XCTAssertEqual(reloaded.enabledIDs, ["bar"])
    }

    func testRestartStopsAndStartsARunningAddOn() {
        let snap = FakeAddOn("snap")
        let registry = makeRegistry([snap])
        registry.setEnabled(true, for: snap)
        registry.restart(snap)
        XCTAssertTrue(snap.isRunning)
        XCTAssertEqual(snap.starts, 2)
        XCTAssertEqual(snap.stops, 1)
    }

    func testPermissionsInUseListsOnlySwitchedOnAddOns() {
        let snap = FakeAddOn("snap", permissions: needsAX)
        let scroll = FakeAddOn("scroll", permissions: needsAX)
        let bar = FakeAddOn("bar", permissions: wantsScreen)
        let registry = makeRegistry([snap, scroll, bar])
        registry.setEnabled(true, for: snap)
        registry.setEnabled(true, for: scroll)

        let inUse = registry.permissionsInUse()
        XCTAssertEqual(inUse.map(\.permission), [.accessibility])
        XCTAssertEqual(inUse.first?.users.map(\.id), ["snap", "scroll"])
    }

    func testStopAll() {
        let snap = FakeAddOn("snap"), bar = FakeAddOn("bar")
        let registry = makeRegistry([snap, bar])
        registry.setEnabled(true, for: snap)
        registry.setEnabled(true, for: bar)
        registry.stopAll()
        XCTAssertFalse(snap.isRunning)
        XCTAssertFalse(bar.isRunning)
    }
}

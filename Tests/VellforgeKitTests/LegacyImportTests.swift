import Foundation
import XCTest
@testable import VellforgeKit

final class LegacyImportTests: XCTestCase {

    func testCopiesOnlyListedKeys() {
        let old: [String: Any] = ["vellsnap.gap": 8.0,
                                  "vellsnap.dragSnap": false,
                                  "NSWindow Frame Preferences": "junk"]
        let copied = LegacyImport.valuesToCopy(from: old,
                                               keys: ["vellsnap.gap", "vellsnap.dragSnap"],
                                               alreadySet: { _ in false })
        XCTAssertEqual(Set(copied.keys), ["vellsnap.gap", "vellsnap.dragSnap"])
        XCTAssertEqual(copied["vellsnap.gap"] as? Double, 8)
        XCTAssertEqual(copied["vellsnap.dragSnap"] as? Bool, false)
    }

    func testNeverOverwritesWhatVellforgeAlreadyHas() {
        let old: [String: Any] = ["vellsnap.gap": 8.0, "vellsnap.layoutBar": false]
        let copied = LegacyImport.valuesToCopy(from: old,
                                               keys: ["vellsnap.gap", "vellsnap.layoutBar"],
                                               alreadySet: { $0 == "vellsnap.gap" })
        XCTAssertEqual(Set(copied.keys), ["vellsnap.layoutBar"])
    }

    func testMissingOldValuesAreSkipped() {
        let copied = LegacyImport.valuesToCopy(from: [:], keys: ["vellscroll.settings"],
                                               alreadySet: { _ in false })
        XCTAssertTrue(copied.isEmpty)
    }

    func testBinsOnlyAppsInAnApplicationsFolder() {
        let home = URL(fileURLWithPath: "/Users/someone")
        func safe(_ path: String) -> Bool {
            LegacyImport.isSafeToBin(URL(fileURLWithPath: path), home: home)
        }
        XCTAssertTrue(safe("/Applications/Vellsnap.app"))
        XCTAssertTrue(safe("/Users/someone/Applications/Vellscroll.app"))

        // A build folder or a download someone keeps on purpose: quit, don't bin.
        XCTAssertFalse(safe("/Users/someone/Mac app/build/Vellsnap.app"))
        XCTAssertFalse(safe("/Users/someone/Downloads/Vellbar.app"))
        // Not an app bundle at all.
        XCTAssertFalse(safe("/Applications"))
        XCTAssertFalse(safe("/Applications/Utilities"))
        // Path tricks resolve before the check.
        XCTAssertFalse(safe("/Applications/../Users/someone/Desktop/Vellsnap.app"))
    }
}

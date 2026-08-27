import Foundation
import XCTest

enum Fixtures {
    static func url(_ name: String) -> URL {
        // SPM copies the Fixtures directory verbatim into the test bundle.
        guard let u = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
                ?? Bundle.module.url(forResource: name, withExtension: nil) else {
            fatalError("fixture not found: \(name)")
        }
        return u
    }
    static func data(_ name: String) -> Data {
        try! Data(contentsOf: url(name))
    }
}

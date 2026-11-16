import XCTest
import Security
import LocalAuthentication
@testable import TrunklineCore

final class KeychainWriteTests: XCTestCase {
    // A regression removing the no-interaction context from either update or
    // first creation would let Security display UI during automatic migration.
    func testHostUpdateCannotRequestAuthenticationUI() {
        var attempted = false
        XCTAssertThrowsError(try SecretStore.write(Data("fixture".utf8), key: "host-passcode", update: { query, _ in
            attempted = true
            let context = (query as NSDictionary)[kSecUseAuthenticationContext] as? LAContext
            XCTAssertEqual(context?.interactionNotAllowed, true)
            return errSecInteractionNotAllowed
        }, add: { _, _ in XCTFail("Must not replace a denied credential"); return errSecSuccess }))
        XCTAssertTrue(attempted)
    }

    func testFirstHostCredentialRetainsAppACLAndCannotPrompt() throws {
        var added = false
        try SecretStore.write(Data("fixture".utf8), key: "identity-password", update: { _, _ in
            errSecItemNotFound
        }, add: { item, _ in
            added = true
            let values = item as NSDictionary
            XCTAssertEqual((values[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed, true)
            XCTAssertNotNil(values[kSecAttrAccess])
            XCTAssertNil(values[kSecAttrAccessible])
            XCTAssertEqual(values[kSecValueData] as? Data, Data("fixture".utf8))
            return errSecSuccess
        })
        XCTAssertTrue(added)
    }
}

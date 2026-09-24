import XCTest
@testable import StosSign_API
import StosSign_Common

final class VerificationTests: XCTestCase {
    func item(_ id: String, enabled: Bool = true) -> [String: Any] {
        ["id": "relationship-1", "type": "bundleIdCapabilities",
         "attributes": ["enabled": enabled, "settings": [["key": "preserve", "value": "unchanged"]]],
         "relationships": ["capability": ["data": ["type": "capabilities", "id": id]]]]
    }
    func testMergePreservesExistingSettings() throws {
        let merged = try CapabilityPayload.merged([item("APP_GROUPS")], adding: [CapabilityPayload.increasedMemory])
        XCTAssertEqual(merged.count, 2)
        let attributes = merged[0]["attributes"] as! [String: Any]
        XCTAssertEqual((attributes["settings"] as! [[String: String]])[0]["value"], "unchanged")
        XCTAssertTrue(CapabilityPayload.enabled(CapabilityPayload.increasedMemory, in: merged))
    }
    func testCompoundResourceIDAndReadOnlyFields() throws {
        let rows = try CapabilityPayload.normalize([["id": "APP_INCREASED_MEMORY_LIMIT",
            "attributes": ["enabled": true, "settings": NSNull(), "editable": true]]], appID: "APP")
        XCTAssertTrue(CapabilityPayload.enabled(CapabilityPayload.increasedMemory, in: rows))
        let payload = try CapabilityPayload.merged(rows, adding: [])
        XCTAssertNil((payload[0]["attributes"] as! [String: Any])["editable"])
        XCTAssertThrowsError(try CapabilityPayload.normalize([["id": "OTHER_INCREASED_MEMORY_LIMIT", "attributes": ["enabled": true]]], appID: "APP"))
    }
    func testMergeIsIdempotent() throws {
        let merged = try CapabilityPayload.merged([item(CapabilityPayload.increasedMemory, enabled: false)], adding: [CapabilityPayload.increasedMemory])
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(CapabilityPayload.enabled(CapabilityPayload.increasedMemory, in: merged))
    }
    func testUnknownSchemaFailsClosed() {
        XCTAssertThrowsError(try CapabilityPayload.merged([["id": "unknown"]], adding: [CapabilityPayload.increasedMemory]))
    }
    func testHTTPAndAPIErrorEnvelopes() {
        XCTAssertThrowsError(try AppleTransport.validate(status: 401, body: nil))
        XCTAssertThrowsError(try AppleTransport.validate(status: 200, body: ["errors": [["detail": "secret-canary"]]]))
        XCTAssertThrowsError(try AppleTransport.validate(status: 200, body: ["resultCode": 9100]))
        XCTAssertNoThrow(try AppleTransport.validate(status: 200, body: ["resultCode": 0]))
    }
    func testExplicitAccountDenialAndRedaction() {
        do {
            try AppleTransport.validate(status: 403, body: ["errors": [["detail": "Requires a paid account secret-canary"]]])
            XCTFail("Must reject")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("account restrictions"))
            XCTAssertFalse(error.localizedDescription.contains("secret-canary"))
        }
    }
    func testAppleAllowlist() {
        XCTAssertTrue(AppleTransport.permits(URL(string: "https://gsa.apple.com/grandslam/GsService2")!))
        for url in ["http://gsa.apple.com/", "https://gsa.apple.com.evil.invalid/", "https://evil.invalid/", "https://user@gsa.apple.com/"] {
            XCTAssertFalse(AppleTransport.permits(URL(string: url)!))
        }
    }
    func testStrictBoolean() {
        XCTAssertTrue(ProfileValidation.trueBoolean(true))
        for value in [false, 1, "true", NSNull()] as [Any] {
            XCTAssertFalse(ProfileValidation.trueBoolean(value))
        }
    }
    func profile() -> [String: Any] {
        ["ApplicationIdentifierPrefix": ["PREFIX"], "TeamIdentifier": ["TEAM"],
         "ExpirationDate": Date(timeIntervalSince1970: 4_070_908_800),
         "Entitlements": ["application-identifier": "PREFIX.com.example.LiveContainer3", ProfileValidation.entitlement: true]]
    }
    func testExactInstanceAndExpiry() throws {
        XCTAssertNoThrow(try ProfileValidation.verify(profile(), bundleID: "com.example.LiveContainer3", teamID: "TEAM"))
        XCTAssertThrowsError(try ProfileValidation.verify(profile(), bundleID: "com.example.LiveContainer2", teamID: "TEAM"))
        var expired = profile(); expired["ExpirationDate"] = Date.distantPast
        XCTAssertThrowsError(try ProfileValidation.verify(expired, bundleID: "com.example.LiveContainer3", teamID: "TEAM"))
    }
    func tlv(_ tag: UInt8, _ data: Data) -> Data {
        let length = data.count < 128 ? Data([UInt8(data.count)]) : Data([0x82, UInt8(data.count >> 8), UInt8(data.count & 255)])
        return Data([tag]) + length + data
    }
    func cms(_ payload: Data) -> Data {
        let dataOID = tlv(6, Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,1,7,1]))
        let signedOID = tlv(6, Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,1,7,2]))
        let encapsulated = tlv(0x30, dataOID + tlv(0xa0, tlv(4, payload)))
        let signed = tlv(0x30, tlv(2, Data([1])) + tlv(0x31, Data()) + encapsulated + tlv(0x31, Data()))
        return tlv(0x30, signedOID + tlv(0xa0, signed))
    }
    func testCMSPayloadAndMalformedLengths() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: profile(), format: .xml, options: 0)
        let decoded = try ProfileValidation.decodeCMS(cms(data))
        XCTAssertNoThrow(try ProfileValidation.verify(decoded, bundleID: "com.example.LiveContainer3", teamID: "TEAM"))
        XCTAssertThrowsError(try ProfileValidation.decodeCMS(Data([0x30, 0x84, 0xff])))
        XCTAssertThrowsError(try ProfileValidation.decodeCMS(data)) // plain plist isn't signed CMS
        XCTAssertThrowsError(try ProfileValidation.decodeCMS(cms(data).dropLast()))
        let der = cms(data)
        let headerSize = der[1] < 128 ? 2 : 2 + Int(der[1] & 0x7f)
        let ber = Data([0x30, 0x80]) + der.dropFirst(headerSize) + Data([0, 0])
        XCTAssertNoThrow(try ProfileValidation.decodeCMS(ber))
        XCTAssertThrowsError(try ProfileValidation.decodeCMS(ber.dropLast()))
    }
}

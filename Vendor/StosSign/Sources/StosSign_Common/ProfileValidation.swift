import Foundation
import CoreFoundation

public enum ProfileValidationError: String, LocalizedError {
    case malformed = "Profile is malformed or uses an unsupported CMS structure."
    case wrongInstance = "Profile belongs to another bundle ID or team. Select the exact LiveContainer instance."
    case expired = "Profile has expired. Regenerate it before signing."
    case missingEntitlement = "Apple's profile does not authorize Increased Memory Limit. A stale profile or account restriction is possible; do not claim success."
    public var errorDescription: String? { rawValue }
}

/// Reads CMS SignedData's encapsulated plist without scanning for XML markers.
/// This is payload validation, not CMS signer trust verification. Final macOS validation uses security/codesign.
public enum ProfileValidation {
    public static let entitlement = "com.apple.developer.kernel.increased-memory-limit"
    private struct Node {
        let tag: UInt8
        let bytes: Data
    }
    private static func nodes(_ data: Data) throws -> [Node] {
        guard data.count <= 16 * 1024 * 1024 else { throw ProfileValidationError.malformed }
        let bytes = [UInt8](data)
        var offset = 0
        func read(depth: Int) throws -> Node {
            guard depth < 24, offset + 2 <= bytes.count else { throw ProfileValidationError.malformed }
            let tag = bytes[offset]; offset += 1
            guard tag != 0 else { throw ProfileValidationError.malformed }
            var length = Int(bytes[offset]); offset += 1
            if length == 0x80 {
                // Apple CMS may use BER indefinite lengths for constructed values.
                guard tag & 0x20 != 0 else { throw ProfileValidationError.malformed }
                let start = offset
                while true {
                    guard offset + 2 <= bytes.count else { throw ProfileValidationError.malformed }
                    if bytes[offset] == 0 && bytes[offset + 1] == 0 {
                        let content = Data(bytes[start..<offset])
                        offset += 2
                        return Node(tag: tag, bytes: content)
                    }
                    _ = try read(depth: depth + 1)
                }
            }
            if length & 0x80 != 0 {
                let count = length & 0x7f
                guard count <= 4, offset + count <= bytes.count else { throw ProfileValidationError.malformed }
                length = 0
                for _ in 0..<count { length = length * 256 + Int(bytes[offset]); offset += 1 }
            }
            guard length <= bytes.count - offset else { throw ProfileValidationError.malformed }
            let content = Data(bytes[offset..<offset + length])
            offset += length
            return Node(tag: tag, bytes: content)
        }
        var result: [Node] = []
        while offset < bytes.count { result.append(try read(depth: 0)) }
        return result
    }
    private static func octets(_ node: Node, depth: Int = 0) throws -> Data {
        guard depth < 24 else { throw ProfileValidationError.malformed }
        if node.tag == 4 { return node.bytes }
        guard node.tag == 0x24 else { throw ProfileValidationError.malformed }
        return try nodes(node.bytes).reduce(into: Data()) { result, child in
            result.append(try octets(child, depth: depth + 1))
        }
    }
    public static func decodeCMS(_ data: Data) throws -> [String: Any] {
        let top = try nodes(data)
        guard top.count == 1, top[0].tag == 0x30 else { throw ProfileValidationError.malformed }
        let content = try nodes(top[0].bytes)
        // OID 1.2.840.113549.1.7.2 = signedData
        guard content.count == 2, content[0].tag == 6,
              content[0].bytes == Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,1,7,2]), content[1].tag == 0xa0 else { throw ProfileValidationError.malformed }
        let wrapper = try nodes(content[1].bytes)
        guard wrapper.count == 1, wrapper[0].tag == 0x30 else { throw ProfileValidationError.malformed }
        let signed = try nodes(wrapper[0].bytes)
        guard signed.count >= 4, signed[2].tag == 0x30 else { throw ProfileValidationError.malformed }
        let encapsulated = try nodes(signed[2].bytes)
        guard encapsulated.count == 2, encapsulated[0].tag == 6,
              encapsulated[0].bytes == Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,1,7,1]), encapsulated[1].tag == 0xa0 else { throw ProfileValidationError.malformed }
        let payload = try nodes(encapsulated[1].bytes)
        guard payload.count == 1 else { throw ProfileValidationError.malformed }
        guard let plist = try PropertyListSerialization.propertyList(from: octets(payload[0]), format: nil) as? [String: Any] else { throw ProfileValidationError.malformed }
        return plist
    }
    public static func trueBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) == CFBooleanGetTypeID() && number.boolValue
    }
    public static func verify(_ profile: [String: Any], bundleID: String, teamID: String, now: Date = Date()) throws {
        guard let entitlements = profile["Entitlements"] as? [String: Any],
              let prefixes = profile["ApplicationIdentifierPrefix"] as? [String],
              let appID = entitlements["application-identifier"] as? String,
              prefixes.contains(where: { appID == $0 + "." + bundleID }),
              (profile["TeamIdentifier"] as? [String])?.contains(teamID) == true else { throw ProfileValidationError.wrongInstance }
        guard let expiry = profile["ExpirationDate"] as? Date else { throw ProfileValidationError.malformed }
        guard expiry > now else { throw ProfileValidationError.expired }
        guard trueBoolean(entitlements[entitlement]) else { throw ProfileValidationError.missingEntitlement }
    }
}

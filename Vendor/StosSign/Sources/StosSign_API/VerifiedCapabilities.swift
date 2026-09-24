import Foundation
import StosSign_Common
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CapabilityPayload {
    public static let increasedMemory = "INCREASED_MEMORY_LIMIT"
    public static let memoryEntitlement = "com.apple.developer.kernel.increased-memory-limit"

    public static func capabilityID(_ item: [String: Any]) -> String? {
        let relationships = item["relationships"] as? [String: Any]
        let capability = relationships?["capability"] as? [String: Any]
        return (capability?["data"] as? [String: Any])?["id"] as? String
    }

    public static func normalize(_ items: [[String: Any]], appID: String) throws -> [[String: Any]] {
        try items.map { item in
            var result = item
            guard let attributes = item["attributes"] as? [String: Any],
                  attributes["enabled"] is Bool else { throw AppleAPIError.badServerResponse }
            if capabilityID(item) == nil {
                let prefix = appID + "_"
                let resourceID = item["id"] as? String ?? ""
                guard resourceID.hasPrefix(prefix), resourceID.count > prefix.count else {
                    throw AppleAPIError.badServerResponse
                }
                let id = String(resourceID.dropFirst(prefix.count))
                result["relationships"] = ["capability": ["data": ["type": "capabilities", "id": id]]]
            }
            return result
        }
    }

    public static func merged(_ existing: [[String: Any]], adding requested: [String]) throws -> [[String: Any]] {
        var result = existing
        // Missing relationships could mean an API schema change. Never silently erase them.
        guard existing.allSatisfy({ capabilityID($0) != nil && $0["attributes"] is [String: Any] }) else {
            throw AppleAPIError.badServerResponse
        }
        for id in Set(requested).sorted() {
            if let index = result.firstIndex(where: { capabilityID($0) == id }) {
                var attributes = result[index]["attributes"] as! [String: Any]
                attributes["enabled"] = true
                result[index]["attributes"] = attributes
            } else {
                result.append(["type": "bundleIdCapabilities",
                    "attributes": ["enabled": true, "settings": []],
                    "relationships": ["capability": ["data": ["type": "capabilities", "id": id]]]])
            }
        }
        // Echo writable settings only, never response-only editable/ownerType/responseId fields.
        return result.map { item in
            let attributes = item["attributes"] as! [String: Any]
            return ["type": "bundleIdCapabilities",
                    "attributes": ["enabled": attributes["enabled"] ?? false,
                                   "settings": attributes["settings"] is NSNull ? [] : (attributes["settings"] ?? [])],
                    "relationships": ["capability": ["data": ["type": "capabilities", "id": capabilityID(item)!]]]]
        }
    }

    public static func enabled(_ id: String, in items: [[String: Any]]) -> Bool {
        items.contains { capabilityID($0) == id && ($0["attributes"] as? [String: Any])?["enabled"] as? Bool == true }
    }
}

extension AppleAPI {
    public func readCapabilities(_ appID: AppID, team: Team, session: AppleAPISession) async throws -> [[String: Any]] {
        let url = v1URL.appendingPathComponent("bundleIds").appendingPathComponent(appID.identifier)
            .appendingPathComponent("bundleIdCapabilities")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let response = try await sendServicesRequest(originalRequest: request,
            additionalParameters: ["include": "capability", "limit": "200"], session: session, team: team)
        guard let items = response["data"] as? [[String: Any]] else { throw AppleAPIError.badServerResponse }
        if let next = (response["links"] as? [String: Any])?["next"], !(next is NSNull) {
            // Refuse a partial read instead of replacing unobserved capabilities.
            throw AppleAPIError.customError(code: -1, message: "Capability response is paginated. Update stopped to preserve existing capabilities.")
        }
        let normalized = try CapabilityPayload.normalize(items, appID: appID.identifier)
        _ = try CapabilityPayload.merged(normalized, adding: [])
        return normalized
    }

    func updateCapabilitiesVerified(_ appID: AppID, capabilities: [String], team: Team, session: AppleAPISession) async throws -> AppID {
        guard !appID.bundleIdentifier.contains("*") else { throw AppleAPIError.invalidBundleIdentifier }
        let before = try await readCapabilities(appID, team: team, session: session)
        if !capabilities.allSatisfy({ CapabilityPayload.enabled($0, in: before) }) {
            let merged = try CapabilityPayload.merged(before, adding: capabilities)
            let payload: [String: Any] = ["data": [
                "type": "bundleIds", "id": appID.identifier,
                "attributes": ["teamId": team.identifier],
                "relationships": ["bundleIdCapabilities": ["data": merged]]]]
            let url = v1URL.appendingPathComponent("bundleIds").appendingPathComponent(appID.identifier)
            _ = try await sendEditRequest(requestURL: url, body: payload, session: session, json: true, appendClientId: false)
        }
        let after = try await readCapabilities(appID, team: team, session: session)
        guard capabilities.allSatisfy({ CapabilityPayload.enabled($0, in: after) }) else {
            throw AppleAPIError.customError(code: -1, message: "Apple did not confirm the requested capability on readback. It may be disallowed, ignored, or not yet visible. No success was recorded.")
        }
        var updated = appID
        updated.features[CapabilityPayload.increasedMemory] = CapabilityPayload.enabled(CapabilityPayload.increasedMemory, in: after)
        // App ID capabilities and profile entitlements are different evidence. Do not fabricate entitlements.
        return updated
    }

    public func downloadProfileData(appID: AppID, team: Team, session: AppleAPISession) async throws -> Data {
        let response = try await sendRequestWithURL(
            requestURL: qhURL.appendingPathComponent("ios/downloadTeamProvisioningProfile.action"),
            additionalParameters: ["appIdId": appID.identifier, "DTDK_Platform": "ios"], session: session, team: team)
        guard let profile = response["provisioningProfile"] as? [String: Any] else { throw AppleAPIError.badServerResponse }
        if let data = profile["encodedProfile"] as? Data, !data.isEmpty { return data }
        if let encoded = profile["encodedProfile"] as? String, let data = Data(base64Encoded: encoded), !data.isEmpty { return data }
        throw AppleAPIError.badServerResponse
    }
}

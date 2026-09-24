//
//  AppIDViewModel.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
import SwiftUI
import StosSign_API
import StosSign_Auth
import StosSign_Common

@MainActor
class AppIDModel : ObservableObject, Hashable {
    nonisolated static func == (lhs: AppIDModel, rhs: AppIDModel) -> Bool {
        return lhs === rhs
    }
    
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
    
    let teamID: String
    @Published var isBusy = false
    var appID: AppID
    @Published var bundleID: String
    @Published var result: String = ""
    
    init(appID: AppID, teamID: String) {
        self.teamID = teamID
        self.appID = appID
        bundleID = appID.bundleIdentifier
    }
    
    func addIncreasedMemory() async throws {
        guard let team = DataManager.shared.model.team, let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }

        guard team.identifier == teamID else { throw "Team changed. Refresh App IDs before continuing." }
        guard !DataManager.shared.model.isOperationInProgress else { throw "Another Apple operation is running. Wait for it to finish." }
        DataManager.shared.model.isOperationInProgress = true
        defer { DataManager.shared.model.isOperationInProgress = false }
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        result = "[capability] Reading existing settings; requesting Increased Memory Limit.\n"
        do {
            session.anisetteData = try await AnisetteDataHelper.shared.getAnisetteData()
            appID = try await AppleAPI.shared.updateAppID(appID, capabilities: [CapabilityPayload.increasedMemory], team: team, session: session)
            result += "[capability] Enabled on Apple readback.\n[profile] Downloading team provisioning profile.\n"
            let data = try await AppleAPI.shared.downloadProfileData(appID: appID, team: team, session: session)
            let profile = try ProfileValidation.decodeCMS(data)
            try ProfileValidation.verify(profile, bundleID: bundleID, teamID: teamID)
            result += "[profile] Payload contains Boolean Increased Memory Limit for this instance and team; expiry valid.\n[signing] NOT VERIFIED. Reinstall this exact host with SideStore, then run scripts/verify_ipa.py on the final signed IPA. This app cannot inspect another installed app's signature."
        } catch {
            result += "[stopped] " + error.detailedDescription
            throw error
        }
    }
    
}

@MainActor
class AppIDViewModel : ObservableObject {
    @Published var appIDs : [AppIDModel] = []
    
    func fetchAppIDs() async throws {
        guard let team = DataManager.shared.model.team, let session = DataManager.shared.model.session else {
            throw "Please Login First"
        }
        
        guard !DataManager.shared.model.isOperationInProgress else { throw "Another Apple operation is running. Wait for it to finish." }
        DataManager.shared.model.isOperationInProgress = true
        defer { DataManager.shared.model.isOperationInProgress = false }
        session.anisetteData = try await AnisetteDataHelper.shared.getAnisetteData()
        let ids = try await AppleAPI.shared.fetchAppIDsForTeam(team: team, session: session)
        await MainActor.run {
            appIDs.removeAll()
            for id in ids {
                appIDs.append(AppIDModel(appID: id, teamID: team.identifier))
            }
        }
    }
}

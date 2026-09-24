//
//  Shared.swift
//  GetMoreRam
//
//  Created by s s on 2025/3/15.
//
import SwiftUI
import StosSign_API
import StosSign_Auth
import StosSign_Common

class AlertHelper<T> : ObservableObject {
    @Published var show = false
    private var result : T?
    private var c : CheckedContinuation<Void, Never>? = nil
    
    func open() async -> T? {
        await withCheckedContinuation { c in
            self.c = c
            Task { await MainActor.run {
                self.show = true
            }}
        }
        return self.result
    }
    
    func close(result: T?) {
        if let c {
            self.result = result
            c.resume()
            self.c = nil
        }
        DispatchQueue.main.async {
            self.show = false
        }

    }
}
typealias YesNoHelper = AlertHelper<Bool>

class InputHelper : AlertHelper<String> {
    @Published var initVal = ""
    
    func open(initVal: String) async -> String? {
        self.initVal = initVal
        return await super.open()
    }
    
    override func open() async -> String? {
        self.initVal = ""
        return await super.open()
    }
}

extension String: @retroactive Error {}
extension String: @retroactive LocalizedError {
    public var errorDescription: String? { return self }
        
//    private static var enBundle : Bundle? = {
//        let language = "en"
//        let path = Bundle.main.path(forResource:language, ofType: "lproj")
//        let bundle = Bundle(path: path!)
//        return bundle
//    }()
    
    var loc: String {
//        let message = NSLocalizedString(self, comment: "")
//        if message != self {
//            return message
//        }
//
//        if let forcedString = String.enBundle?.localizedString(forKey: self, value: nil, table: nil){
//            return forcedString
//        }else {
            return self
//        }
    }
    
    func localizeWithFormat(_ arguments: CVarArg...) -> String{
        String.localizedStringWithFormat(self.loc, arguments)
    }
    
}

class SharedModel: ObservableObject {
    @Published var isLogin = false
    @Published var isOperationInProgress = false
    @AppStorage("AnisetteServer") var anisetteServerURL = "http://127.0.0.1:6969"
    var session: AppleAPISession?
    var account: Account?
    var team: Team?
    
    init() {
        AnisetteDataHelper.shared.url = URL(string: anisetteServerURL)
    }
}

class DataManager {
    static let shared = DataManager()
    let model = SharedModel()
}

extension Error {
    var detailedDescription: String {
        // Never print arbitrary NSError.userInfo, decoding values, URLs, or server bodies.
        if let error = self as? ProfileValidationError { return error.localizedDescription }
        if let error = self as? AppleAPIError { return error.errorDescription ?? "Apple operation failed." }
        if let message = self as? String { return message }
        if let error = self as? SideStoreAccountImportError { return error.localizedDescription }
        if self is CancellationError { return "Cancelled." }
        let error = self as NSError
        if error.domain == NSURLErrorDomain { return "Network request failed (code \(error.code)). Check connectivity and local Anisette service." }
        return "Operation failed (code \(error.code)); sensitive details omitted."
    }
}

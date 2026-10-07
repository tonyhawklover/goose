//
//  ProfileManager.swift
//  Goose
//
//  Created by Oz Tamir on 22/08/2024.
//  Modified for Goose.
//

import Foundation
import FamilyControls
import ManagedSettings

class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var currentProfileId: UUID?
    
    init() {
        loadProfiles()
        ensureDefaultProfile()
        publishActiveProfile()
    }
    
    var currentProfile: Profile {
        (profiles.first(where: { $0.id == currentProfileId }) ?? profiles.first(where: { $0.name == "Default" }))!
    }
    
    func loadProfiles() {
        if let savedProfiles = UserDefaults.standard.data(forKey: "savedProfiles"),
           let decodedProfiles = try? JSONDecoder().decode([Profile].self, from: savedProfiles) {
            profiles = decodedProfiles
        } else {
            let defaultProfile = Profile(name: "Default", appTokens: [], categoryTokens: [], icon: "bell.slash")
            profiles = [defaultProfile]
            currentProfileId = defaultProfile.id
        }
        
        if let savedProfileId = UserDefaults.standard.string(forKey: "currentProfileId"),
           let uuid = UUID(uuidString: savedProfileId) {
            currentProfileId = uuid
            NSLog("Found currentProfile: \(uuid)")
        } else {
            currentProfileId = profiles.first?.id
            NSLog("No stored ID, using \(currentProfileId?.uuidString ?? "NONE")")
        }
    }
    
    func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: "savedProfiles")
        }
        UserDefaults.standard.set(currentProfileId?.uuidString, forKey: "currentProfileId")
        publishActiveProfile()
    }

    /// Mirrors the current profile's name into the App Group for the widget.
    private func publishActiveProfile() {
        guard let profile = profiles.first(where: { $0.id == currentProfileId }) ?? profiles.first else { return }
        GooseShared.activeProfileName = profile.name
    }
    
    func addProfile(newProfile: Profile) {
        profiles.append(newProfile)
        currentProfileId = newProfile.id
        saveProfiles()
    }
    
    func setCurrentProfile(id: UUID) {
        if profiles.contains(where: { $0.id == id }) {
            currentProfileId = id
            NSLog("New Current Profile: \(id)")
            saveProfiles()
        }
    }
    
    func deleteProfile(withId id: UUID) {
        guard profiles.count > 1 else { return }

        profiles.removeAll { $0.id == id }
        
        if currentProfileId == id {
            currentProfileId = profiles.first?.id
        }
        
        saveProfiles()
    }

    func updateProfile(
        id: UUID,
        name: String? = nil,
        appTokens: Set<ApplicationToken>? = nil,
        categoryTokens: Set<ActivityCategoryToken>? = nil,
        webDomainTokens: Set<WebDomainToken>? = nil,
        icon: String? = nil,
        unlockMethod: UnlockMethod? = nil,
        timerMinutes: Int? = nil
    ) {
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            if let name = name {
                profiles[index].name = name
            }
            if let appTokens = appTokens {
                profiles[index].appTokens = appTokens
            }
            if let categoryTokens = categoryTokens {
                profiles[index].categoryTokens = categoryTokens
            }
            if let webDomainTokens {
                profiles[index].webDomainTokens = webDomainTokens
            }
            if let icon = icon {
                profiles[index].icon = icon
            }
            if let unlockMethod {
                profiles[index].unlockMethod = unlockMethod
            }
            if let timerMinutes {
                profiles[index].timerMinutes = timerMinutes
            }
            
            if currentProfileId == id {
                currentProfileId = profiles[index].id
            }
            
            saveProfiles()
        }
    }
    
    private func ensureDefaultProfile() {
        if profiles.isEmpty {
            let defaultProfile = Profile(name: "Default", appTokens: [], categoryTokens: [], icon: "bell.slash")
            profiles.append(defaultProfile)
            currentProfileId = defaultProfile.id
            saveProfiles()
        } else if currentProfileId == nil {
            if let defaultProfile = profiles.first(where: { $0.name == "Default" }) {
                currentProfileId = defaultProfile.id
            } else {
                currentProfileId = profiles.first?.id
            }
            saveProfiles()
        }
    }
}

struct Profile: Identifiable, Codable {
    let id: UUID
    var name: String
    var appTokens: Set<ApplicationToken>
    var categoryTokens: Set<ActivityCategoryToken>
    var webDomainTokens: Set<WebDomainToken>
    var icon: String
    var unlockMethod: UnlockMethod
    var timerMinutes: Int


    init(
        name: String,
        appTokens: Set<ApplicationToken>,
        categoryTokens: Set<ActivityCategoryToken>,
        webDomainTokens: Set<WebDomainToken> = [],
        icon: String = "bell.slash",
        unlockMethod: UnlockMethod = .key,
        timerMinutes: Int = 30
    ) {
        self.id = UUID()
        self.name = name
        self.appTokens = appTokens
        self.categoryTokens = categoryTokens
        self.webDomainTokens = webDomainTokens
        self.icon = icon
        self.unlockMethod = unlockMethod
        self.timerMinutes = timerMinutes
    }

    var blockedCount: Int { appTokens.count + categoryTokens.count + webDomainTokens.count }

    /// Profiles saved before unlock methods or websites existed decode as tag
    /// profiles with no websites.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        appTokens = try c.decode(Set<ApplicationToken>.self, forKey: .appTokens)
        categoryTokens = try c.decode(Set<ActivityCategoryToken>.self, forKey: .categoryTokens)
        webDomainTokens = try c.decodeIfPresent(Set<WebDomainToken>.self, forKey: .webDomainTokens) ?? []
        icon = try c.decode(String.self, forKey: .icon)
        unlockMethod = try c.decodeIfPresent(UnlockMethod.self, forKey: .unlockMethod) ?? .key
        timerMinutes = try c.decodeIfPresent(Int.self, forKey: .timerMinutes) ?? 30
    }
}

// MARK: - Tags

/// An NFC tag or a QR code; both carry a code and follow the same rules.
/// Setting `assignedProfileID` makes it that profile's dedicated tag;
/// `TagRules` decides what that allows.
struct GooseTag: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case nfc, qr
    }

    let id: UUID
    var code: String
    var name: String
    var assignedProfileID: UUID?
    var kind: Kind

    init(name: String, assignedProfileID: UUID? = nil, kind: Kind = .nfc) {
        self.id = UUID()
        self.code = "GOOSE-\(UUID().uuidString.prefix(8))"
        self.name = name
        self.assignedProfileID = assignedProfileID
        self.kind = kind
    }

    var isGeneral: Bool { assignedProfileID == nil }

    /// Tags saved before QR codes existed decode as NFC.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        code = try c.decode(String.self, forKey: .code)
        name = try c.decode(String.self, forKey: .name)
        assignedProfileID = try c.decodeIfPresent(UUID.self, forKey: .assignedProfileID)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .nfc
    }
}

class TagManager: ObservableObject {
    @Published var tags: [GooseTag] = []

    init() {
        loadTags()
    }

    func addTag(_ tag: GooseTag) {
        tags.append(tag)
        saveTags()
    }

    func deleteTag(withId id: UUID) {
        tags.removeAll { $0.id == id }
        saveTags()
    }

    func hasDedicatedTag(profileID: UUID) -> Bool {
        tags.contains { $0.assignedProfileID == profileID }
    }

    func isValidScan(code: String, for profile: Profile) -> Bool {
        TagRules.isValidScan(code: code, profileID: profile.id, tags: tags)
    }

    private func loadTags() {
        if let data = UserDefaults.standard.data(forKey: "savedTags"),
           let decoded = try? JSONDecoder().decode([GooseTag].self, from: data) {
            tags = decoded
        }
        // No built-in tag on fresh installs: a hard-coded code would be public
        // in the source, and anyone could write it to a tag and unlock.
    }

    private func saveTags() {
        if let encoded = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(encoded, forKey: "savedTags")
        }
    }
}

/// Kept free of storage so the rules can be unit tested directly.
enum TagRules {
    /// Any registered tag works on a profile, unless that profile has a
    /// dedicated tag. Then only its dedicated tags work.
    static func isValidScan(code: String, profileID: UUID, tags: [GooseTag]) -> Bool {
        guard let scannedTag = tags.first(where: { $0.code == code }) else { return false }
        let profileHasDedicatedTag = tags.contains { $0.assignedProfileID == profileID }
        return !profileHasDedicatedTag || scannedTag.assignedProfileID == profileID
    }
}

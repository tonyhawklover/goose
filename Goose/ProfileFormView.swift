//
//  ProfileFormView.swift
//  Goose
//
//  Created by Oz Tamir on 23/08/2024.
//  Modified for Goose.
//

import SwiftUI
import SFSymbolsPicker
import FamilyControls

struct ProfileFormView: View {
    @EnvironmentObject private var appBlocker: AppBlocker
    @EnvironmentObject private var rules: BlockRulesManager
    @ObservedObject var profileManager: ProfileManager
    @State private var profileName: String
    @State private var profileIcon: String
    @State private var showSymbolsPicker = false
    @State private var showAppSelection = false
    @State private var activitySelection: FamilyActivitySelection
    @State private var showDeleteConfirmation = false
    @State private var unlockMethod: UnlockMethod
    @State private var timerMinutes: Int
    let profile: Profile?
    let onDismiss: () -> Void
    
    init(profile: Profile? = nil, profileManager: ProfileManager, onDismiss: @escaping () -> Void) {
        self.profile = profile
        self.profileManager = profileManager
        self.onDismiss = onDismiss
        _profileName = State(initialValue: profile?.name ?? "")
        _profileIcon = State(initialValue: profile?.icon ?? "bell.slash")
        _unlockMethod = State(initialValue: profile?.unlockMethod ?? .key)
        _timerMinutes = State(initialValue: profile?.timerMinutes ?? 30)
        
        var selection = FamilyActivitySelection()
        selection.applicationTokens = profile?.appTokens ?? []
        selection.categoryTokens = profile?.categoryTokens ?? []
        selection.webDomainTokens = profile?.webDomainTokens ?? []
        _activitySelection = State(initialValue: selection)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Button(action: { showSymbolsPicker = true }) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 56, height: 56)
                                Image(systemName: profileIcon)
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Profile Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Enter profile name", text: $profileName)
                                .font(.body.weight(.medium))
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Profile Details")
                } footer: {
                    Text("Tap the icon to change it.")
                }

                Section(header: Text("App Configuration")) {
                    Button(action: { showAppSelection = true }) {
                        HStack {
                            Text("Choose Apps and Websites")
                            Spacer()
                            let total = activitySelection.applicationTokens.count + activitySelection.categoryTokens.count + activitySelection.webDomainTokens.count
                            if total > 0 {
                                Text("\(total)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor, in: Capsule())
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("For your privacy, Apple only tells Goose how many apps, categories and websites you picked, not which ones.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                UnlockMethodSection(method: $unlockMethod, timerMinutes: $timerMinutes)
                
                if profile != nil {
                    Section(header: Text("Block History")) {
                        if appBlocker.history.isEmpty {
                            Text("No finished blocks yet. Each one shows up here when it ends.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(appBlocker.history.prefix(50)) { session in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(session.start.formatted(date: .abbreviated, time: .shortened))
                                            .font(.subheadline)
                                        Text(session.profileName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(formattedDuration(session.duration))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // The app always needs at least one profile.
                // Nor one that a running schedule or reached limit is blocking with.
                if let profile, profileManager.profiles.count > 1, !rules.isProfileInUseByActiveRule(profile.id) {
                    Section {
                        Button(action: { showDeleteConfirmation = true }) {
                            Text("Delete Profile")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle(profile == nil ? "Add Profile" : "Edit Profile")
            .navigationBarItems(
                leading: Button("Cancel", action: onDismiss),
                trailing: Button("Save", action: handleSave)
                    .disabled(profileName.isEmpty || (unlockMethod == .timer && timerMinutes < 1))
            )
            .sheet(isPresented: $showSymbolsPicker) {
                SymbolsPicker(selection: $profileIcon, title: "Pick an icon", autoDismiss: true)
            }
            .sheet(isPresented: $showAppSelection) {
                NavigationView {
                    FamilyActivityPicker(selection: $activitySelection)
                        .navigationTitle("Select Apps")
                        .navigationBarItems(trailing: Button("Done") {
                            showAppSelection = false
                        })
                }
            }
            .alert(isPresented: $showDeleteConfirmation) {
                Alert(
                    title: Text("Delete Profile"),
                    message: Text(profileHasRules
                        ? "Its schedules and daily limits will be deleted too."
                        : "Are you sure you want to delete this profile?"),
                    primaryButton: .destructive(Text("Delete")) {
                        if let profile = profile {
                            profileManager.deleteProfile(withId: profile.id)
                        }
                        onDismiss()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
    
    private var profileHasRules: Bool {
        guard let profile else { return false }
        return rules.schedules.contains { $0.profileID == profile.id } || rules.limits.contains { $0.profileID == profile.id }
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(minutes, 1))m"
        }
    }

    private func handleSave() {
        if let existingProfile = profile {
            profileManager.updateProfile(
                id: existingProfile.id,
                name: profileName,
                appTokens: activitySelection.applicationTokens,
                categoryTokens: activitySelection.categoryTokens,
                webDomainTokens: activitySelection.webDomainTokens,
                icon: profileIcon,
                unlockMethod: unlockMethod,
                timerMinutes: timerMinutes
            )
        } else {
            let newProfile = Profile(
                name: profileName,
                appTokens: activitySelection.applicationTokens,
                categoryTokens: activitySelection.categoryTokens,
                webDomainTokens: activitySelection.webDomainTokens,
                icon: profileIcon,
                unlockMethod: unlockMethod,
                timerMinutes: timerMinutes
            )
            profileManager.addProfile(newProfile: newProfile)
        }
        onDismiss()
    }
}

/// Shared by the profile editor and first-run setup.
struct UnlockMethodSection: View {
    @Binding var method: UnlockMethod
    @Binding var timerMinutes: Int

    var body: some View {
        Section {
            Picker("Unlock with", selection: $method) {
                ForEach(UnlockMethod.allCases) { method in
                    Text(method.label).tag(method)
                }
            }
            .pickerStyle(.segmented)

            if method == .timer {
                DurationWheel(minutes: $timerMinutes)
            }
        } header: {
            Text("Unlock With")
        } footer: {
            Text(Self.explanation(for: method))
        }
    }

    static func explanation(for method: UnlockMethod) -> String {
        switch method {
        case .key: return "Lock and unlock by scanning an NFC tag or a QR code you keep somewhere else. The most effective option."
        case .timer: return "Block for a set time. You can't unlock early, and apps unblock on their own when time is up."
        case .button: return "Lock and unlock with a tap. A gentle reminder rather than a hard block."
        }
    }
}

/// Hours and minutes, for timers and daily limits. Anything from a minute up
/// to a day.
struct DurationWheel: View {
    @Binding var minutes: Int

    private var hours: Binding<Int> {
        Binding { minutes / 60 } set: { minutes = $0 * 60 + minutes % 60 }
    }

    private var remainder: Binding<Int> {
        Binding { minutes % 60 } set: { minutes = (minutes / 60) * 60 + $0 }
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("Hours", selection: hours) {
                ForEach(0..<24, id: \.self) { Text("\($0) hr").tag($0) }
            }
            Picker("Minutes", selection: remainder) {
                ForEach(0..<60, id: \.self) { Text("\($0) min").tag($0) }
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 150)
    }
}

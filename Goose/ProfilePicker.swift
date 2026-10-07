//
//  ProfilePicker.swift
//  Goose
//
//  Created by Oz Tamir on 23/08/2024.
//  Modified for Goose.
//

import SwiftUI
import FamilyControls

struct ProfilesPicker: View {
    @ObservedObject var profileManager: ProfileManager
    @EnvironmentObject private var tagManager: TagManager
    @State private var showAddProfileView = false
    @State private var editingProfile: Profile?

    var body: some View {
        Group {
            // Profiles stay out of the way until there's more than one.
            if profileManager.profiles.count == 1, let only = profileManager.profiles.first {
                singleProfile(only)
            } else {
                profileGrid
            }
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 28)
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: -6)
        .sheet(item: $editingProfile) { profile in
            ProfileFormView(profile: profile, profileManager: profileManager) {
                editingProfile = nil
            }
        }
        .sheet(isPresented: $showAddProfileView) {
            ProfileFormView(profileManager: profileManager) {
                showAddProfileView = false
            }
        }
    }

    private func singleProfile(_ profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's Blocked")
                .font(.system(.headline, design: .rounded))

            Button {
                Haptics.impact(.light)
                editingProfile = profile
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: profile.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Color.accentColor.opacity(0.15)))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.blockedCount == 0 ? "Choose apps to block" : "\(profile.blockedCount) blocked")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Label(ProfileCell.unlockSummary(for: profile), systemImage: profile.unlockMethod.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
            }
            .buttonStyle(.plain)

            Button {
                showAddProfileView = true
            } label: {
                Label("Add another profile", systemImage: "plus.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }

    private var profileGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Profiles")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Text("Hold to edit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(profileManager.profiles) { profile in
                        // A tap gesture and a long press on the same view inside a
                        // ScrollView make the hold wait for the tap to fail, which
                        // felt like half a second. A Button with a simultaneous
                        // long press starts timing the moment the finger lands.
                        Button {
                            Haptics.impact(.light)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                profileManager.setCurrentProfile(id: profile.id)
                            }
                        } label: {
                            ProfileCell(
                                profile: profile,
                                isSelected: profile.id == profileManager.currentProfileId,
                                hasDedicatedTag: tagManager.hasDedicatedTag(profileID: profile.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.3).onEnded { _ in
                                Haptics.impact(.medium)
                                editingProfile = profile
                            }
                        )
                    }

                    ProfileCellBase(name: "New", icon: "plus", detail: nil, isSelected: false, isDashed: true)
                        .onTapGesture {
                            Haptics.impact(.light)
                            showAddProfileView = true
                        }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }
}

struct ProfileCellBase: View {
    let name: String
    let icon: String
    let detail: String?
    var detailIcon: String?
    let isSelected: Bool
    var isDashed: Bool = false
    var hasDedicatedTag: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }

                if hasDedicatedTag {
                    Image(systemName: "key.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.orange))
                        .offset(x: 4, y: -4)
                }
            }

            VStack(spacing: 2) {
                Text(name)
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if let detail {
                    HStack(spacing: 3) {
                        if let detailIcon {
                            Image(systemName: detailIcon)
                                .font(.system(size: 9, weight: .semibold))
                        }
                        Text(detail)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
        .frame(width: 100, height: 108)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    isSelected ? Color.accentColor : (isDashed ? Color.secondary.opacity(0.4) : Color.clear),
                    style: StrokeStyle(lineWidth: isSelected ? 2 : 1.5, dash: isDashed ? [5] : [])
                )
        )
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .shadow(color: isSelected ? Color.accentColor.opacity(0.25) : .clear, radius: 8, x: 0, y: 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
    }
}

struct ProfileCell: View {
    let profile: Profile
    let isSelected: Bool
    var hasDedicatedTag: Bool = false

    private var isSetUp: Bool { profile.blockedCount > 0 }

    static func unlockSummary(for profile: Profile) -> String {
        switch profile.unlockMethod {
        case .key: return "Tag or QR"
        case .timer: return formatMinutes(profile.timerMinutes)
        case .button: return "Button"
        }
    }

    var body: some View {
        ProfileCellBase(
            name: profile.name,
            icon: profile.icon,
            detail: isSetUp ? Self.unlockSummary(for: profile) : "Not set up",
            detailIcon: isSetUp ? profile.unlockMethod.icon : nil,
            isSelected: isSelected,
            hasDedicatedTag: hasDedicatedTag
        )
    }
}

// FineTune/Views/MediaControl/NowPlayingBarView.swift
import SwiftUI
import AppKit

/// Compact Liquid-Glass "Now Playing" & Universal Media media controller card inside FineTune's popup.
@MainActor
struct NowPlayingBarView: View {
    @Bindable var mediaController: MediaPlayerController
    let isPopupVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            headerRow
            playerCard
        }
        .onAppear {
            if isPopupVisible {
                mediaController.refreshAvailableTargets()
            }
        }
        .onChange(of: isPopupVisible) { _, visible in
            if visible {
                mediaController.refreshAvailableTargets()
            }
        }
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            SectionHeader(title: "Now Playing")
            if mediaController.isPinnedTarget {
                Text("PINNED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.accentPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(DesignTokens.Colors.accentPrimary.opacity(0.15))
                    )
            }
            Spacer()
            targetSelectorMenu
        }
    }

    // MARK: - Target Selector Menu (Universal Media Player List)

    private var targetSelectorMenu: some View {
        Menu {
            Button {
                mediaController.clearPinnedTarget()
            } label: {
                HStack {
                    Text("Auto (Smart Audio Detection)")
                    if !mediaController.isPinnedTarget {
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !mediaController.availableTargets.isEmpty {
                Divider()
                ForEach(mediaController.availableTargets, id: \.id) { target in
                    Button {
                        mediaController.selectTarget(target)
                    } label: {
                        HStack {
                            Text("\(target.displayName) — \(target.title)")
                            if mediaController.activeTarget?.id == target.id && mediaController.isPinnedTarget {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                mediaController.setActiveTargetFromFrontmost()
            } label: {
                Label("Pin Frontmost Tab / App", systemImage: "pin")
            }

            Button {
                mediaController.refreshAvailableTargets()
            } label: {
                Label("Refresh Media Players", systemImage: "arrow.clockwise")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mediaController.activeTarget?.isNativeApp == true ? "music.note" : "globe")
                    .font(.system(size: 10, weight: .medium))
                Text(mediaController.activeTarget?.displayName ?? "Auto")
                    .font(DesignTokens.Typography.pickerText)
                    .lineLimit(1)
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Select active media player or browser tab (Universal Media mode)")
    }

    // MARK: - Player Card

    private var playerCard: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            playerIconView

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(DesignTokens.Typography.rowNameBold)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(displaySubtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                mediaController.activatePlayingTarget()
            }
            .help("Click to bring active player or browser tab to front")

            transportButtons
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
                .fill(DesignTokens.Colors.eqCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Dimensions.rowRadius)
                        .strokeBorder(DesignTokens.Colors.eqCardBorder, lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var playerIconView: some View {
        ZStack(alignment: .bottomTrailing) {
            if let icon = mediaController.activeTarget?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(DesignTokens.Colors.deviceBadgeMonoFill)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Image(systemName: "music.quarternote.3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignTokens.Colors.deviceBadgeMonoForeground)
                    )
            }

            if mediaController.isPlayingState {
                Circle()
                    .fill(DesignTokens.Colors.vuGreen)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5)
                    )
                    .offset(x: 2, y: 2)
            }
        }
    }

    private var transportButtons: some View {
        HStack(spacing: 6) {
            if let target = mediaController.activeTarget, target.supportsFavorite {
                Button {
                    mediaController.favoriteTrack()
                } label: {
                    Image(systemName: mediaController.currentTrackInfo?.isFavorited == true ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(
                            mediaController.currentTrackInfo?.isFavorited == true
                                ? Color(nsColor: .systemPink)
                                : DesignTokens.Colors.interactiveDefault
                        )
                }
                .buttonStyle(.plain)
                .iconButtonStyle()
                .help("Favorite / Like Current Track")
            }

            Button {
                mediaController.previousTrack()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .iconButtonStyle()
            .help("Previous Track (F7)")

            Button {
                mediaController.playPauseToggle()
            } label: {
                Image(systemName: mediaController.isPlayingState ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(DesignTokens.Colors.glassFillStrong)
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .help("Play / Pause (F8)")

            Button {
                mediaController.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .iconButtonStyle()
            .help("Next Track (F9)")

            if mediaController.activeTarget != nil {
                Button {
                    mediaController.activatePlayingTarget()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .iconButtonStyle()
                .help("Bring Player / Tab to Front")
            } else {
                Button {
                    mediaController.refreshAvailableTargets()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .iconButtonStyle()
                .help("Scan for Open Media Tabs & Players")
            }
        }
    }

    private var displayTitle: String {
        if let info = mediaController.currentTrackInfo, !info.title.isEmpty {
            return info.title
        }
        if let target = mediaController.activeTarget {
            return target.title
        }
        return "No Active Media Player"
    }

    private var displaySubtitle: String {
        if let info = mediaController.currentTrackInfo {
            let sub = info.subtitleLine
            if !sub.isEmpty { return sub }
        }
        if let target = mediaController.activeTarget {
            return target.subtitle
        }
        return "Press F8 or open YouTube, Spotify, SoundCloud, Twitch, etc."
    }
}

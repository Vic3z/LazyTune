// FineTune/Views/Settings/Tabs/MediaControlTab.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct MediaControlTab: View {
    @Bindable var settings: SettingsManager
    @Bindable var accessibility: AccessibilityPermissionService
    @Bindable var mediaKeyStatus: MediaKeyStatus
    let mediaKeyMonitor: MediaKeyMonitor
    @Bindable var mediaController: MediaPlayerController

    @State private var strategySearchText: String = ""
    @State private var showStrategyBrowser: Bool = false

    private var filteredStrategies: [BSMediaStrategy] {
        let all = mediaController.strategyRegistry.strategies
        let query = strategySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                mediaKeysSection
                smartBehaviorSection
                strategiesSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .onChange(of: settings.appSettings.mediaPlayerControlEnabled) { _, _ in
            mediaKeyMonitor.reconcile()
        }
    }

    // MARK: - Media Keys & HUD

    private var mediaKeysSection: some View {
        SettingsSection("Universal Media Keys") {
            SettingsRow(
                "Control Any Media Player with F7 / F8 / F9",
                description: "Intercept Previous, Play/Pause, and Next keys so Apple Music never hijacks them, routing commands to active browser tabs (YouTube, SoundCloud, Twitch, etc.) and native players (Spotify, VLC, IINA, VOX, Tidal)"
            ) {
                Toggle("", isOn: $settings.appSettings.mediaPlayerControlEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            if !accessibility.isTrustedCached {
                SettingsRowDivider()
                AccessibilityPromptStrip(accessibility: accessibility)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }

            if mediaKeyStatus.isOffline {
                SettingsRowDivider()
                MediaKeyOfflineCard {
                    mediaKeyMonitor.reconcile()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            SettingsRowDivider()
            SettingsRow(
                "Now Playing Bar in Popup",
                description: "Show interactive mini-player and target switcher at the top of the FineTune popup"
            ) {
                Toggle("", isOn: $settings.appSettings.showNowPlayingInPopup)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            SettingsRowDivider()
            SettingsRow(
                "On-Screen Track HUD",
                description: "Show Tahoe-style notification pill with track title and artist on Play/Pause/Skip"
            ) {
                Toggle("", isOn: $settings.appSettings.showMediaHUD)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Smart Behavior & Auto-Pause

    private var smartBehaviorSection: some View {
        SettingsSection("Smart Playback & Auto-Pause") {
            SettingsRow(
                "Auto-Pause on Headphone Disconnect",
                description: "Automatically pause active browser tab or player when headphones or speakers unplug"
            ) {
                Toggle("", isOn: $settings.appSettings.autoPauseOnHeadphoneDisconnect)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            SettingsRowDivider()
            SettingsRow(
                "Auto-Pause on Mac Sleep / Lock",
                description: "Automatically pause active playback when macOS goes to sleep or locks session"
            ) {
                Toggle("", isOn: $settings.appSettings.autoPauseOnSleep)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            SettingsRowDivider()
            SettingsRow(
                "Pause Previous Player on Switch",
                description: "Automatically pause the old player when switching active tab or app"
            ) {
                Toggle("", isOn: $settings.appSettings.pausePreviousOnPlayerSwitch)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            SettingsRowDivider()
            SettingsRow(
                "Universal HTML5 Web Fallback",
                description: "Control any website with <video> or <audio> elements even without a dedicated strategy"
            ) {
                Toggle("", isOn: $settings.appSettings.universalHTML5FallbackEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Web Media Strategies

    private var strategiesSection: some View {
        let totalCount = mediaController.strategyRegistry.strategies.count
        let enabledCount = totalCount - settings.appSettings.disabledMediaStrategies.count

        return SettingsSection("Web Media Strategies (\(enabledCount)/\(totalCount) Enabled)") {
            SettingsRow(
                "Custom Strategy (.js)",
                description: "Import custom media strategy files or manage built-in web adapters"
            ) {
                HStack(spacing: 8) {
                    Button("Import .js…") {
                        importCustomStrategyFile()
                    }
                    .controlSize(.small)

                    Button(showStrategyBrowser ? "Hide List" : "Manage Strategies…") {
                        withAnimation(DesignTokens.Animation.quick) {
                            showStrategyBrowser.toggle()
                        }
                    }
                    .controlSize(.small)
                }
            }

            if showStrategyBrowser {
                SettingsRowDivider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Filter strategies (e.g. YouTube, SoundCloud, Twitch, Bandcamp)…", text: $strategySearchText)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)

                        Button("Enable All") {
                            settings.appSettings.disabledMediaStrategies.removeAll()
                        }
                        .controlSize(.small)
                    }

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredStrategies) { strategy in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 6) {
                                            Text(strategy.displayName)
                                                .font(.system(size: 12, weight: .medium))
                                            if strategy.isCustom {
                                                Text("CUSTOM")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .foregroundStyle(DesignTokens.Colors.accentPrimary)
                                            }
                                        }
                                        Text(strategy.fileName)
                                            .font(.system(size: 10))
                                            .foregroundStyle(DesignTokens.Colors.textTertiary)
                                    }
                                    Spacer()
                                    Toggle(
                                        "",
                                        isOn: Binding(
                                            get: { !settings.appSettings.disabledMediaStrategies.contains(strategy.id) },
                                            set: { enabled in
                                                if enabled {
                                                    settings.appSettings.disabledMediaStrategies.remove(strategy.id)
                                                } else {
                                                    settings.appSettings.disabledMediaStrategies.insert(strategy.id)
                                                }
                                            }
                                        )
                                    )
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                    .labelsHidden()
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 6)
                            }
                        }
                    }
                    .frame(height: 190)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    private func importCustomStrategyFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Custom Media Strategy"
        panel.allowedContentTypes = [.javaScript, .sourceCode, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = mediaController.strategyRegistry.importCustomStrategy(from: url)
            mediaController.refreshAvailableTargets()
        }
    }
}

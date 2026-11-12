// FineTune/Audio/Keys/MediaKeyEventDecoder.swift
import Foundation

nonisolated enum MediaKeyEvent: Equatable {
    case volumeUp(isRepeat: Bool)
    case volumeDown(isRepeat: Bool)
    case muteToggle
    case playPause
    case nextTrack
    case previousTrack

    var isVolumeEvent: Bool {
        switch self {
        case .volumeUp, .volumeDown, .muteToggle:
            return true
        case .playPause, .nextTrack, .previousTrack:
            return false
        }
    }

    var isPlaybackEvent: Bool {
        !isVolumeEvent
    }
}

protocol MediaKeyEventDecoding: Sendable {
    func decode(data1: Int) -> MediaKeyEvent?
}

/// Decodes `NSSystemDefined.data1` using `<IOKit/hidsystem/ev_keymap.h>`
/// constants: NX_KEYTYPE_SOUND_UP=0, SOUND_DOWN=1, MUTE=7, PLAY=16, NEXT=17, PREVIOUS=18, FAST=19, REWIND=20. Unknown subtypes → nil.
struct IOKitMediaKeyDecoder: MediaKeyEventDecoding {
    func decode(data1: Int) -> MediaKeyEvent? {
        let keyType = Int32((data1 & 0xFFFF0000) >> 16)
        let keyFlags = Int32(data1 & 0xFFFF)
        let isDown = ((keyFlags & 0xFF00) >> 8) == 0x0A
        let isRepeat = (keyFlags & 0xFF) != 0

        guard isDown else { return nil }

        switch keyType {
        case 0: return .volumeUp(isRepeat: isRepeat)
        case 1: return .volumeDown(isRepeat: isRepeat)
        case 7: return isRepeat ? nil : .muteToggle
        case 16: return isRepeat ? nil : .playPause
        case 17, 19: return isRepeat ? nil : .nextTrack
        case 18, 20: return isRepeat ? nil : .previousTrack
        default: return nil
        }
    }
}

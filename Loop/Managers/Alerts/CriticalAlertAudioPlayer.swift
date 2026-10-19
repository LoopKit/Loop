//
//  CriticalAlertAudioPlayer.swift
//  Loop
//
//  Plays critical-alert sounds via AVAudioPlayer to bypass the iOS
//  silent switch + DND when the build doesn't have the Critical Alerts
//  entitlement (or the user has disabled the permission).
//
//  Critical Alerts on iOS require an Apple-granted entitlement that
//  DIY/sideloaded builds can't obtain. Without it, UNNotificationSound's
//  .defaultCritical / .criticalSoundNamed are silently downgraded to a
//  regular notification — which the system muffles during DND, Focus
//  modes, or with the silent switch on. That can leave an urgent low
//  glucose alarm playing no sound at 3am.
//
//  This class plays the alert sound in-process via AVAudioPlayer with
//  the `.playback` audio session category, which ignores the silent
//  switch and Focus. System volume still applies (apps can't override
//  that, and shouldn't). The user-visible UNNotification still gets
//  scheduled in parallel; this class just emits the audio.
//

import AVFoundation
import AudioToolbox
import LoopKit
import MediaPlayer
import os.log
import UIKit

@MainActor
final class CriticalAlertAudioPlayer {
    private let log = OSLog(subsystem: "com.loopkit.Loop", category: "CriticalAlertAudioPlayer")

    private var player: AVAudioPlayer?
    private var stopTimer: Timer?
    private var vibrationTimer: Timer?

    /// How often to re-trigger the system vibration while the alert is
    /// active. The system vibrate pulse is brief (~0.4s), so we repeat it
    /// to keep buzzing for the life of the alarm.
    private let vibrationInterval: TimeInterval = 2.0

    /// System volume we force for the duration of a critical-alert burst.
    /// Max, because an urgent-low alarm (often at 3am, ringer turned all the
    /// way down) has to wake the wearer; the pre-alarm level is restored when
    /// the alarm stops. Only takes effect on builds without the Critical
    /// Alerts entitlement, which is the only path that reaches this player.
    private let boostedVolume: Float = 1.0

    /// Best-effort system-volume override (MPVolumeView slider trick). See
    /// `SystemVolumeBooster`.
    private let volumeBooster = SystemVolumeBooster()

    /// How long the alarm plays before stopping on its own. A short burst
    /// (a few loops of the ~0.84s tone) is attention-grabbing without being
    /// a runaway siren — the user-visible UNNotification persists, and the
    /// alert re-fires on the next critical-alert trigger if the condition
    /// holds.
    private let maxDuration: TimeInterval = 6

    /// True if we're currently looping audio for a critical alert.
    var isPlaying: Bool { player?.isPlaying ?? false }

    /// Start (or restart) looping playback of a bundled critical alert
    /// sound. Safe to call repeatedly — replaces any current playback.
    /// `soundnamed` is a bundled `.caf` filename (the alarm's configured
    /// sound, e.g. "bloom.caf"); it lives in Loop's main bundle so it's
    /// always present. We resolve it directly from the bundle rather than
    /// AlertManager's AlertSoundVendor-keyed `Library/Sounds/` lookup.
    /// Falls back to `critical.caf` if the named file is missing.
    /// With `boostVolume` false the sound plays once at the current volume, for
    /// non-critical alerts that only need to get past the silent switch.
    func play(soundNamed soundName: String = "critical.caf", boostVolume: Bool = true) {
        stop()

        // Vibration is volume-independent, so it's our primary "you missed
        // it" channel when the ringer is down. Start it up front and bound
        // everything (audio + vibration) to maxDuration, so the alarm still
        // buzzes even if audio setup below fails.
        startVibration()
        stopTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }

        let resource = (soundName as NSString).deletingPathExtension
        let ext = (soundName as NSString).pathExtension.isEmpty ? "caf" : (soundName as NSString).pathExtension
        let url = Bundle.main.url(forResource: resource, withExtension: ext)
            ?? Bundle.main.url(forResource: "critical", withExtension: "caf")
        guard let url else {
            os_log("Neither %{public}@ nor critical.caf found in main bundle; audio fallback unavailable", log: log, type: .error, soundName)
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            // .playback ignores the silent switch and Focus modes. It must
            // be mixable, though: a critical alert usually fires while the
            // app is backgrounded/locked, and iOS refuses to activate a
            // NON-mixable session from the background — that's the
            // `AVAudioSessionErrorCodeCannotInterruptOthers` ('!int', 560557684)
            // "Session activation failed" we were hitting. .duckOthers +
            // .mixWithOthers makes activation succeed in the background and
            // ducks/mixes our alarm over any other audio instead of
            // failing outright. Mixable .playback still plays at full volume
            // when nothing else is active and still bypasses the silent switch.
            try session.setCategory(.playback, mode: .default, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true, options: [])
            let volume = session.outputVolume
            os_log("Audio session active. category=%{public}@ otherAudioPlaying=%{public}@ outputVolume=%{public}.2f",
                   log: log, type: .info,
                   session.category.rawValue,
                   session.isOtherAudioPlaying ? "yes" : "no",
                   volume)
            // Without the Critical Alerts entitlement the system won't raise
            // an inaudible ringer for us, so force it up for the life of the
            // alarm (restored on stop). Best-effort — see SystemVolumeBooster.
            if boostVolume {
                volumeBooster.boost(to: boostedVolume)
            }

            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = boostVolume ? -1 : 0
            p.volume = 1.0
            p.prepareToPlay()
            guard p.play() else {
                os_log("AVAudioPlayer.play() returned false for %{public}@", log: log, type: .error, url.lastPathComponent)
                try? session.setActive(false, options: [.notifyOthersOnDeactivation])
                return
            }
            player = p
            if !boostVolume {
                stopTimer?.invalidate()
                stopTimer = Timer.scheduledTimer(withTimeInterval: p.duration, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.stop() }
                }
            }
            os_log("Started critical-alert audio playback (duration=%{public}.2fs playing=%{public}@)",
                   log: log, type: .info, p.duration, p.isPlaying ? "yes" : "no")
        } catch {
            os_log("Failed to start audio playback: %{public}@", log: log, type: .error, String(describing: error))
        }
    }

    private func startVibration() {
        // Fire immediately, then repeat for the life of the alarm. On
        // devices without a vibration motor (e.g. iPad) this is a no-op.
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: vibrationInterval, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    /// Stop playback if any. Safe to call when not playing.
    func stop() {
        guard player != nil || stopTimer != nil || vibrationTimer != nil else { return }
        player?.stop()
        player = nil
        stopTimer?.invalidate()
        stopTimer = nil
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        volumeBooster.restore()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        os_log("Stopped critical-alert audio playback", log: log, type: .info)
    }
}

/// Best-effort override of the system output volume.
///
/// iOS has no public API to set the hardware volume. `MPVolumeView` hosts a
/// `UISlider` that, when its value changes, drives the system volume — the
/// long-standing workaround. We use it ONLY for critical-alert audio on
/// builds without the Critical Alerts entitlement: without it an urgent-low
/// alarm can be silent when the ringer is down overnight, which is dangerous.
///
/// It's best-effort: the slider only populates once the hosting view is in an
/// on-screen window, so it may no-op when the app is fully backgrounded. The
/// alarm's audio and vibration run regardless — this only makes them louder
/// when it can. The pre-boost level is restored on `restore()`, unless the
/// user manually changed the volume in the meantime (we don't fight that).
@MainActor
private final class SystemVolumeBooster {
    private let volumeView = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
    private var savedVolume: Float?
    private var targetVolume: Float?
    /// Bumped on every boost/restore so a deferred slider write that's been
    /// superseded (e.g. the alarm was retracted within the populate delay)
    /// bails instead of leaving the volume stuck high.
    private var generation = 0

    func boost(to target: Float) {
        guard let window = Self.activeWindow() else { return }
        attach(to: window)
        generation &+= 1
        let gen = generation
        // The slider subview populates a runloop tick after the view enters
        // the hierarchy, so defer the read/write briefly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, gen == self.generation, let slider = self.slider() else { return }
            let current = slider.value
            guard current < target else { return }
            self.savedVolume = current
            self.targetVolume = target
            slider.setValue(target, animated: false)
        }
    }

    func restore() {
        generation &+= 1  // invalidate any pending boost write
        if let saved = savedVolume,
           let target = targetVolume,
           let slider = slider(),
           abs(slider.value - target) < 0.05 {  // skip if the user moved it
            slider.setValue(saved, animated: false)
        }
        savedVolume = nil
        targetVolume = nil
        volumeView.removeFromSuperview()
    }

    private func attach(to window: UIWindow) {
        volumeView.alpha = 0.0001
        volumeView.isUserInteractionEnabled = false
        if volumeView.superview !== window {
            volumeView.removeFromSuperview()
            window.addSubview(volumeView)
        }
    }

    private func slider() -> UISlider? {
        volumeView.subviews.compactMap { $0 as? UISlider }.first
    }

    private static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive }
        return active?.windows.first(where: { $0.isKeyWindow })
            ?? active?.windows.first
            ?? scenes.flatMap { $0.windows }.first
    }
}

//
//  StatusTableViewController+PodLoan.swift
//  Loop
//
//  The status screen while the pod is on the watch: the banner row, the reclaim prompts, and the
//  pump tile's countdown during a hand-over.
//

import UIKit
import SwiftUI
import LoopKitUI
import LoopUI

extension StatusTableViewController {

    /// The status row while the pod is on the watch; tapping it offers the reclaim.
    func podLoanedToWatchCell() -> UITableViewCell {
        let cell = UITableViewCell()
        cell.backgroundColor = .secondarySystemBackground
        let subtitle: String
        if deviceManager.isPodTakeoverInProgress {
            subtitle = NSLocalizedString("Handing the pod to Apple Watch…", comment: "The subtitle of the banner while the watch is taking over the pod")
        } else if deviceManager.isPodLoanReclaiming {
            subtitle = NSLocalizedString("Reclaiming the pod…", comment: "The subtitle of the banner while the phone is reclaiming the pod")
        } else {
            subtitle = NSLocalizedString("Apple Watch is controlling the pod. Tap to reclaim.", comment: "The subtitle of the banner indicating the pod is controlled by the watch")
        }
        cell.contentConfiguration = UIHostingConfiguration {
            HStack {
                Text(Image(systemName: "applewatch")).font(.title) + Text(" ")

                VStack(alignment: .leading) {
                    Text(NSLocalizedString("Sport Mode Active", comment: "The title of the banner indicating the pod is controlled by the watch"))
                        .font(.headline.bold())

                    Text(subtitle)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer()

                Text(Image(systemName: "chevron.right"))
                    .font(.headline)
            }
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(8)
            .background(Color.warning.cornerRadius(10))
            .padding([.top, .horizontal], 8)
        }
        .margins(.all, 0)
        return cell
    }

    func presentPodLoanReclaimPrompt() {
        let alert = UIAlertController(
            title: NSLocalizedString("Pod Is on the Watch", comment: "Title of the reclaim prompt when tapping the pump tile during a loan"),
            message: NSLocalizedString("Reclaim the pod to this phone? The watch's Sport Mode session will end and its records will be collected.", comment: "Message of the reclaim prompt"),
            preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Reclaim Now", comment: "Button to reclaim the pod from the watch"), style: .default) { [weak self] _ in
            self?.deviceManager.reclaimPodLoanFromWatch()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "Cancel the reclaim prompt"), style: .cancel))
        present(alert, animated: true)
    }

    func presentPodSettlingNotice() {
        let alert = UIAlertController(
            title: NSLocalizedString("Finishing Pod Handover", comment: "Title shown when the phone owns the pod but its connection is not re-established"),
            message: NSLocalizedString("Sport Mode has ended and this phone is back in control, but it is still reconnecting to the pod. Try again in a moment.", comment: "Message shown while the phone is re-establishing the pod connection after a reclaim"),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Dismiss the pod-settling notice"), style: .default))
        present(alert, animated: true)
    }

    // MARK: - Pod reclaim countdown

    private static let podReclaimCountdownInterval = TimeInterval(0.5)

    /// Re-presents the tile each second during a reclaim; its elapsed text does not advance on
    /// its own.
    func updatePodReclaimCountdown() {
        if deviceManager.isPodLoanReclaiming || deviceManager.isPodTakeoverInProgress {
            startPodReclaimCountdown()
        } else {
            stopPodReclaimCountdown()
        }
    }

    private func startPodReclaimCountdown() {
        guard podReclaimCountdownTimer == nil else { return }
        podReclaimCountdownTimer = Timer.scheduledTimer(withTimeInterval: Self.podReclaimCountdownInterval, repeats: true) { [weak self] timer in
            // Retire the timer once self is gone.
            guard let self = self else { timer.invalidate(); return }
            guard let hudView = self.hudView else { self.stopPodReclaimCountdown(); return }
            // Rebuild the label each tick.
            hudView.pumpStatusHUD.presentStatusHighlight(self.deviceManager.pumpStatusHighlight)
            // Reclaim progress rides the tile's lifecycle progress.
            hudView.pumpStatusHUD.lifecycleProgress = self.deviceManager.pumpLifecycleProgress
            if !self.deviceManager.isPodLoanReclaiming, !self.deviceManager.isPodTakeoverInProgress {
                self.stopPodReclaimCountdown()
            }
        }
    }

    private func stopPodReclaimCountdown() {
        podReclaimCountdownTimer?.invalidate()
        podReclaimCountdownTimer = nil
    }
}

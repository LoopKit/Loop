//
//  ChartsTableViewController.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopUI
import HealthKit
import os.log


enum RefreshContext: Equatable {
    /// Catch-all for lastLoopCompleted, recommendedTempBasal, lastTempBasal, preferences
    case status

    case glucose
    case insulin
    case carbs
    case targets

    case size(CGSize)
}

extension RefreshContext: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }

    private var rawValue: Int {
        switch self {
        case .status:
            return 1
        case .glucose:
            return 2
        case .insulin:
            return 3
        case .carbs:
            return 4
        case .targets:
            return 5
        case .size:
            // We don't use CGSize in our determination of hash nor equality
            return 6
        }
    }

    static func ==(lhs: RefreshContext, rhs: RefreshContext) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}

extension Set where Element == RefreshContext {
    /// Returns the size value in the set if one exists
    var newSize: CGSize? {
        guard let index = firstIndex(of: .size(.zero)),
            case .size(let size) = self[index] else
        {
            return nil
        }

        return size
    }

    /// Removes and returns the size value in the set if one exists
    ///
    /// - Returns: The size, if contained
    mutating func removeNewSize() -> CGSize? {
        guard case .size(let newSize)? = remove(.size(.zero)) else {
            return nil
        }

        return newSize
    }
}


/// Abstract class providing boilerplate setup for chart-based table view controllers
class ChartsTableViewController: UITableViewController, UIGestureRecognizerDelegate {

    private let log = OSLog(category: "ChartsTableViewController")

    override func viewDidLoad() {
        super.viewDidLoad()

        if let unit = self.deviceManager.loopManager.glucoseStore.preferredUnit {
            self.charts.setGlucoseUnit(unit)
        }

        let notificationCenter = NotificationCenter.default
        notificationObservers += [
            notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: UIApplication.shared, queue: .main) { [weak self] _ in
                self?.active = false
            },
            notificationCenter.addObserver(forName: UIApplication.didBecomeActiveNotification, object: UIApplication.shared, queue: .main) { [weak self] _ in
                self?.active = true
            }
        ]

        let gestureRecognizer = UILongPressGestureRecognizer()
        gestureRecognizer.delegate = self
        gestureRecognizer.minimumPressDuration = 0.1
        gestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        charts.gestureRecognizer = gestureRecognizer
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()

        if !visible {
            charts.didReceiveMemoryWarning()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        visible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        visible = false
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        log.debug("[reloadData] for view transition to size: %@", String(describing: size))
        reloadData(animated: false)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        charts.traitCollection = traitCollection
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - State

    weak var deviceManager: DeviceDataManager! {
        didSet {
            NotificationCenter.default.addObserver(self, selector: #selector(unitPreferencesDidChange(_:)), name: .HKUserPreferencesDidChange, object: deviceManager.loopManager.glucoseStore.healthStore)
        }
    }

    @objc private func unitPreferencesDidChange(_ note: Notification) {
        DispatchQueue.main.async {
            if let unit = self.deviceManager.loopManager.glucoseStore.preferredUnit {
                self.charts.setGlucoseUnit(unit)

                self.glucoseUnitDidChange()
            }
            self.log.debug("[reloadData] for HealthKit unit preference change")
            self.reloadData()
        }
    }

    func glucoseUnitDidChange() {
        // To override.
    }

    func createChartsManager() -> ChartsManager {
        fatalError("Subclasses must implement \(#function)")
    }

    lazy private(set) var charts = createChartsManager()

    // References to registered notification center observers
    var notificationObservers: [Any] = []

    var active: Bool {
        get {
            return UIApplication.shared.applicationState == .active
        }
        set {
            log.debug("[reloadData] for app change to active: %d, applicationState: %d", newValue, active)
            reloadData()
        }
    }

    var visible = false {
        didSet {
            log.debug("[reloadData] for view change to visible: %d", visible)
            reloadData()
        }
    }

    // MARK: - Data loading

    /// Refetches all data and updates the views. Must be called on the main queue.
    ///
    /// - Parameters:
    ///   - animated: Whether the updating should be animated if possible
    func reloadData(animated: Bool = false) {

    }

    // MARK: - UIGestureRecognizer

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        /// Only start the long-press recognition when it starts in a chart cell
        let point = gestureRecognizer.location(in: tableView)
        if let indexPath = tableView.indexPathForRow(at: point) {
            if let cell = tableView.cellForRow(at: indexPath), cell is ChartTableViewCell {
                return true
            }
        }

        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc func handlePan(_ gestureRecognizer: UIGestureRecognizer) {
        switch gestureRecognizer.state {
        case .possible, .changed:
            // Follow your dreams!
            break
        case .began, .cancelled, .ended, .failed:
            for case let row as ChartTableViewCell in self.tableView.visibleCells {
                let forwards = gestureRecognizer.state == .began
                UIView.animate(withDuration: forwards ? 0.2 : 0.5, delay: forwards ? 0 : 1, animations: {
                    let alpha: CGFloat = forwards ? 0 : 1
                    row.titleLabel?.alpha = alpha
                    row.subtitleLabel?.alpha = alpha
                })
            }
        @unknown default:
            break
        }
    }
}


fileprivate extension ChartsManager {
    func setGlucoseUnit(_ unit: HKUnit) {
        for case let chart as GlucoseChart in charts {
            chart.glucoseUnit = unit
        }
    }
}

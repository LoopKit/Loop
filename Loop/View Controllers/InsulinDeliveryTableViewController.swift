//
//  InsulinDeliveryTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/11/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKitUI
import LoopCore
import UIKit
import LoopKit

private let ReuseIdentifier = "Right Detail"


public final class InsulinDeliveryTableViewController: UITableViewController {

    @IBOutlet var needsConfigurationMessageView: ErrorBackgroundView!

    @IBOutlet weak var iobValueLabel: UILabel!

    @IBOutlet weak var iobDateLabel: UILabel!

    @IBOutlet weak var totalValueLabel: UILabel!

    @IBOutlet weak var totalDateLabel: UILabel!

    @IBOutlet weak var dataSourceSegmentedControl: UISegmentedControl!
    
    var deviceManager: DeviceDataManager? {
        didSet {
            doseStore = deviceManager?.loopManager.doseStore
        }
    }

    public var doseStore: DoseStore? {
        didSet {
            if let doseStore = doseStore {
                doseStoreObserver = NotificationCenter.default.addObserver(forName: nil, object: doseStore, queue: OperationQueue.main, using: { [weak self] (note) -> Void in

                    switch note.name {
                    case DoseStore.valuesDidChange:
                        if self?.isViewLoaded == true {
                            self?.reloadData()
                        }
                    default:
                        break
                    }
                })
            } else {
                doseStoreObserver = nil
            }
        }
    }

    private var updateTimer: Timer? {
        willSet {
            if let timer = updateTimer {
                timer.invalidate()
            }
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        state = .display
        
        let logDoseButton   = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(didTapLogDoseButton))
        navigationItem.rightBarButtonItems = [logDoseButton, self.editButtonItem]
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateTimelyStats(nil)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let updateInterval = TimeInterval(minutes: 5)
        let timer = Timer(
            fireAt: Date().dateCeiledToTimeInterval(updateInterval).addingTimeInterval(2),
            interval: updateInterval,
            target: self,
            selector: #selector(updateTimelyStats(_:)),
            userInfo: nil,
            repeats: true
        )
        updateTimer = timer

        RunLoop.current.add(timer, forMode: RunLoop.Mode.default)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        updateTimer = nil
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        if tableView.isEditing {
            tableView.endEditing(true)
        }
    }

    deinit {
        if let observer = doseStoreObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)

        if editing {
            let item = UIBarButtonItem(
                title: NSLocalizedString("Delete All", comment: "Button title to delete all objects"),
                style: .plain,
                target: self,
                action: #selector(confirmDeletion(_:))
            )
            navigationItem.setLeftBarButton(item, animated: true)
        } else {
            navigationItem.setLeftBarButton(nil, animated: true)
        }
    }
    
    @objc func didTapLogDoseButton(sender: AnyObject){
        guard let deviceManager = deviceManager else {
            return
        }
        
        tableView.endEditing(true)
        
        let bolusVC = BolusViewController.instance()
        bolusVC.deviceManager = deviceManager
        bolusVC.glucoseUnit = deviceManager.loopManager.glucoseStore.preferredUnit ?? .milligramsPerDeciliter
        bolusVC.enteredBolusInsulinModel = deviceManager.loopManager.insulinModelSettings?.model
        bolusVC.configuration = .logging
        
        let navigationWrapper = UINavigationController(rootViewController: bolusVC)
        present(navigationWrapper, animated: true)
    }

    // MARK: - Data

    private enum State {
        case unknown
        case unavailable(Error?)
        case display
    }

    private var state = State.unknown {
        didSet {
            if isViewLoaded {
                reloadData()
            }
        }
    }

    private enum DataSourceSegment: Int {
        case reservoir = 0
        case history
    }

    private enum Values {
        case reservoir([ReservoirValue])
        case history([PersistedPumpEvent])
    }

    // Not thread-safe
    private var values = Values.reservoir([]) {
        didSet {
            let count: Int

            switch values {
            case .reservoir(let values):
                count = values.count
            case .history(let values):
                count = values.count
            }

            if count > 0 {
                navigationItem.rightBarButtonItems?[1] = self.editButtonItem
            }
        }
    }

    private func reloadData() {
        switch state {
        case .unknown:
            break
        case .unavailable(let error):
            self.tableView.tableHeaderView?.isHidden = true
            self.tableView.tableFooterView = UIView()
            tableView.backgroundView = needsConfigurationMessageView

            if let error = error {
                needsConfigurationMessageView.errorDescriptionLabel.text = String(describing: error)
            } else {
                needsConfigurationMessageView.errorDescriptionLabel.text = nil
            }
        case .display:
            self.tableView.backgroundView = nil
            self.tableView.tableHeaderView?.isHidden = false
            self.tableView.tableFooterView = nil

            switch DataSourceSegment(rawValue: dataSourceSegmentedControl.selectedSegmentIndex)! {
            case .reservoir:
                doseStore?.getReservoirValues(since: Date.distantPast) { (result) in
                    DispatchQueue.main.async { () -> Void in
                        switch result {
                        case .failure(let error):
                            self.state = .unavailable(error)
                        case .success(let reservoirValues):
                            self.values = .reservoir(reservoirValues)
                            self.tableView.reloadData()
                        }
                    }

                    self.updateTimelyStats(nil)
                    self.updateTotal()
                }
            case .history:
                doseStore?.getPumpEventValues(since: Date.distantPast) { (result) in
                    DispatchQueue.main.async { () -> Void in
                        switch result {
                        case .failure(let error):
                            self.state = .unavailable(error)
                        case .success(let pumpEventValues):
                            self.values = .history(pumpEventValues)
                            self.tableView.reloadData()
                        }
                    }

                    self.updateTimelyStats(nil)
                    self.updateTotal()
                }
            }
        }
    }

    @objc func updateTimelyStats(_: Timer?) {
        updateIOB()
    }

    private lazy var iobNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()

        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2

        return formatter
    }()

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()

        formatter.dateStyle = .none
        formatter.timeStyle = .short

        return formatter
    }()

    private func updateIOB() {
        if case .display = state {
            doseStore?.insulinOnBoard(at: Date()) { (result) -> Void in
                DispatchQueue.main.async {
                    switch result {
                    case .failure:
                        self.iobValueLabel.text = "…"
                        self.iobDateLabel.text = nil
                    case .success(let iob):
                        self.iobValueLabel.text = self.iobNumberFormatter.string(from: iob.value)
                        self.iobDateLabel.text = String(format: NSLocalizedString("com.loudnate.InsulinKit.IOBDateLabel", value: "at %1$@", comment: "The format string describing the date of an IOB value. The first format argument is the localized date."), self.timeFormatter.string(from: iob.startDate))
                    }
                }
            }
        }
    }

    private func updateTotal() {
        if case .display = state {
            let midnight = Calendar.current.startOfDay(for: Date())

            doseStore?.getTotalUnitsDelivered(since: midnight) { (result) in
                DispatchQueue.main.async {
                    switch result {
                    case .failure:
                        self.totalValueLabel.text = "…"
                        self.totalDateLabel.text = nil
                    case .success(let result):
                        self.totalValueLabel.text = NumberFormatter.localizedString(from: NSNumber(value: result.value), number: .none)

                        self.totalDateLabel.text = String(format: NSLocalizedString("com.loudnate.InsulinKit.totalDateLabel", value: "since %1$@", comment: "The format string describing the starting date of a total value. The first format argument is the localized date."), DateFormatter.localizedString(from: result.startDate, dateStyle: .none, timeStyle: .short))
                    }
                }
            }
        }
    }

    private var doseStoreObserver: Any? {
        willSet {
            if let observer = doseStoreObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    @IBAction func selectedSegmentChanged(_ sender: Any) {
        reloadData()
    }

    @IBAction func confirmDeletion(_ sender: Any) {
        guard !deletionPending else {
            return
        }

        let confirmMessage: String

        switch DataSourceSegment(rawValue: dataSourceSegmentedControl.selectedSegmentIndex)! {
        case .reservoir:
            confirmMessage = NSLocalizedString("Are you sure you want to delete all reservoir values?", comment: "Action sheet confirmation message for reservoir deletion")
        case .history:
            confirmMessage = NSLocalizedString("Are you sure you want to delete all history entries?", comment: "Action sheet confirmation message for pump history deletion")
        }

        let sheet = UIAlertController(deleteAllConfirmationMessage: confirmMessage) {
            self.deleteAllObjects()
        }
        present(sheet, animated: true)
    }
        
    @IBAction func unwindFromBolusViewController(_ segue: UIStoryboardSegue) {
        guard let bolusViewController = segue.source as? BolusViewController else {
            return
        }

        if let bolus = bolusViewController.bolus, bolus > 0 {
            switch bolusViewController.configuration {
            case .logging:
                if let model = bolusViewController.enteredBolusInsulinModel {
                    self.deviceManager?.loopManager?.logOutsideInsulinDose(startDate: Date(), units: bolus, insulinModel: model)
                }
            // Enact the user-entered bolus
            default:
                self.deviceManager?.enactBolus(units: bolus) { _ in }
            }
        }
    }

    private var deletionPending = false

    private func deleteAllObjects() {
        guard !deletionPending else {
            return
        }

        deletionPending = true

        let completion = { (_: DoseStore.DoseStoreError?) -> Void in
            DispatchQueue.main.async {
                self.deletionPending = false
                self.setEditing(false, animated: true)
            }
        }

        switch DataSourceSegment(rawValue: dataSourceSegmentedControl.selectedSegmentIndex)! {
        case .reservoir:
            doseStore?.deleteAllReservoirValues(completion)
        case .history:
            doseStore?.deleteAllPumpEvents(completion)
        default:
            break
        }
    }

    // MARK: - Table view data source

    public override func numberOfSections(in tableView: UITableView) -> Int {
        switch state {
        case .unknown, .unavailable:
            return 0
        case .display:
            return 1
        }
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch values {
        case .reservoir(let values):
            return values.count
        case .history(let values):
            return values.count
        }
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifier, for: indexPath)

        if case .display = state {
            switch self.values {
            case .reservoir(let values):
                let entry = values[indexPath.row]
                let volume = NumberFormatter.localizedString(from: NSNumber(value: entry.unitVolume), number: .decimal)
                let time = timeFormatter.string(from: entry.startDate)

                cell.textLabel?.text = "\(volume) U"
                cell.detailTextLabel?.text = time
                cell.accessoryType = .none
                cell.selectionStyle = .none
            case .history(let values):
                let entry = values[indexPath.row]
                let time = timeFormatter.string(from: entry.date)

                cell.textLabel?.text = entry.title ?? NSLocalizedString("Unknown", comment: "The default title to use when an entry has none")
                cell.detailTextLabel?.text = time
                cell.accessoryType = entry.isUploaded ? .checkmark : .none
                cell.selectionStyle = .default
            }
        }

        return cell
    }

    public override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    public override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete, case .display = state {
            switch values {
            case .reservoir(let reservoirValues):
                var reservoirValues = reservoirValues
                let value = reservoirValues.remove(at: indexPath.row)
                self.values = .reservoir(reservoirValues)

                tableView.deleteRows(at: [indexPath], with: .automatic)

                doseStore?.deleteReservoirValue(value) { (_, error) -> Void in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.present(UIAlertController(with: error), animated: true)
                            self.reloadData()
                        }
                    }
                }
            case .history(let historyValues):
                var historyValues = historyValues
                let value = historyValues.remove(at: indexPath.row)
                self.values = .history(historyValues)

                tableView.deleteRows(at: [indexPath], with: .automatic)

                doseStore?.deletePumpEvent(value) { (error) -> Void in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.present(UIAlertController(with: error), animated: true)
                            self.reloadData()
                        }
                    }
                }
            default:
                break
            }
        }
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if case .display = state, case .history(let history) = values {
            let entry = history[indexPath.row]

            let vc = CommandResponseViewController(command: { (completionHandler) -> String in
                var description = [String]()

                description.append(self.timeFormatter.string(from: entry.date))

                if let title = entry.title {
                    description.append(title)
                }

                if let dose = entry.dose {
                    description.append(String(describing: dose))
                }

                if let raw = entry.raw {
                    description.append(raw.hexadecimalString)
                }

                return description.joined(separator: "\n\n")
            })

            vc.title = NSLocalizedString("Pump Event", comment: "The title of the screen displaying a pump event")

            show(vc, sender: indexPath)
        }
    }

}

fileprivate extension UIAlertController {
    convenience init(deleteAllConfirmationMessage: String, confirmationHandler handler: @escaping () -> Void) {
        self.init(
            title: nil,
            message: deleteAllConfirmationMessage,
            preferredStyle: .actionSheet
        )
        
        addAction(UIAlertAction(
            title: NSLocalizedString("Delete All", comment: "Button title to delete all objects"),
            style: .destructive,
            handler: { (_) in handler() }
        ))

        addAction(UIAlertAction(
            title: NSLocalizedString("Cancel", comment: "The title of the cancel action in an action sheet"),
            style: .cancel
        ))
    }
}


extension InsulinDeliveryTableViewController: IdentifiableClass {
}

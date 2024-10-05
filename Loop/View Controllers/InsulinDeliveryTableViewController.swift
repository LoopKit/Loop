//
//  InsulinDeliveryTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/30/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopCore
import LoopKit
import LoopKitUI

private let ReuseIdentifier = "Right Detail"


public final class InsulinDeliveryTableViewController: UITableViewController {
    
    private static let historicDataDisplayTimeInterval = TimeInterval.hours(24)

    @IBOutlet var needsConfigurationMessageView: ErrorBackgroundView!

    @IBOutlet weak var iobValueLabel: UILabel! {
        didSet {
            iobValueLabel.textColor = headerValueLabelColor
        }
    }

    @IBOutlet weak var iobDateLabel: UILabel!

    @IBOutlet weak var totalValueLabel: UILabel! {
        didSet {
            totalValueLabel.textColor = headerValueLabelColor
        }
    }

    @IBOutlet weak var totalDateLabel: UILabel!

    @IBOutlet weak var dataSourceSegmentedControl: UISegmentedControl! {
        didSet {
            let titleFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
            dataSourceSegmentedControl.setTitleTextAttributes([NSAttributedString.Key.font: titleFont], for: .normal)
            dataSourceSegmentedControl.setTitle(NSLocalizedString("Event History", comment: "Segmented button title for insulin delivery log event history"), forSegmentAt: 0)
            dataSourceSegmentedControl.setTitle(NSLocalizedString("Reservoir", comment: "Segmented button title for insulin delivery log reservoir history"), forSegmentAt: 1)
        }
    }
    
    public var enableEntryDeletion: Bool = true
    
    var loopDataManager: LoopDataManager!
    var doseStore: DoseStore! {
        didSet {
            if let doseStore = doseStore {
                doseStoreObserver = NotificationCenter.default.addObserver(forName: nil, object: doseStore, queue: OperationQueue.main, using: { [weak self] (note) -> Void in

                    switch note.name {
                    case DoseStore.valuesDidChange:
                        if self?.isViewLoaded == true {
                            Task { @MainActor in
                                await self?.reloadData()
                            }
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
    
    public var headerValueLabelColor: UIColor = .label

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
        
        if FeatureFlags.manualDoseEntryEnabled {
            let enterDoseButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(didTapEnterDoseButton))
            navigationItem.rightBarButtonItems = [enterDoseButton, editButtonItem]
        } else {
            dataSourceSegmentedControl.removeSegment(at: 2, animated: false)
        }
        if !FeatureFlags.insulinDeliveryReservoirViewEnabled {
            dataSourceSegmentedControl.removeSegment(at: 1, animated: false)
        }
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

        if editing && enableEntryDeletion {
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
    
    @objc func didTapEnterDoseButton(sender: AnyObject){
        guard let loopDataManager = loopDataManager else {
            return
        }

        tableView.endEditing(true)

        let viewModel = ManualEntryDoseViewModel(delegate: loopDataManager)
        let bolusEntryView = ManualEntryDoseView(viewModel: viewModel)
        let hostingController = DismissibleHostingController(rootView: bolusEntryView, isModalInPresentation: false)
        let navigationWrapper = UINavigationController(rootViewController: hostingController)
        hostingController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: navigationWrapper, action: #selector(dismissWithAnimation))
        self.present(navigationWrapper, animated: true)
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
                Task { @MainActor in
                    await reloadData()
                }
            }
        }
    }

    private enum DataSourceSegment: Int {
        case history = 0
        case reservoir
        case manualEntryDose
    }

    private enum Values {
        case reservoir([ReservoirValue])
        case history([PersistedPumpEvent])
        case manualEntryDoses([DoseEntry])
    }
    
    private enum HistorySection: Int {
        case today
        case yesterday
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
            case .manualEntryDoses(let values):
                count = values.count
            }

            if count > 0 && enableEntryDeletion {
                navigationItem.rightBarButtonItem = self.editButtonItem
            }
        }
    }

    private func reloadData() async {
        let sinceDate = Date().addingTimeInterval(-InsulinDeliveryTableViewController.historicDataDisplayTimeInterval)
        switch state {
        case .unknown:
            break
        case .unavailable(let error):
            self.tableView.tableHeaderView?.isHidden = true
            self.tableView.tableFooterView = UIView()
            tableView.backgroundView = needsConfigurationMessageView

            if let error = error {
                needsConfigurationMessageView.setErrorDescriptionLabel(with: String(describing: error))
            }
        case .display:
            self.tableView.backgroundView = nil
            self.tableView.tableHeaderView?.isHidden = false
            self.tableView.tableFooterView = nil

            guard let doseStore else {
                return
            }

            do {
                switch DataSourceSegment(rawValue: dataSourceSegmentedControl.selectedSegmentIndex)! {
                case .reservoir:
                    self.values = .reservoir(try await doseStore.getReservoirValues(since: sinceDate, limit: nil))
                case .history:
                    self.values = .history(try await self.getPumpEvents(since: sinceDate))
                case .manualEntryDose:
                    self.values = .manualEntryDoses(try await doseStore.getManuallyEnteredDoses(since: sinceDate))
                }
                self.tableView.reloadData()
                self.updateTimelyStats(nil)
                self.updateTotal()
            } catch {
                self.state = .unavailable(error)
            }
        }
    }

    private func getPumpEvents(since sinceDate: Date) async throws -> [PersistedPumpEvent] {
        let events = try await doseStore.getPumpEventValues(since: sinceDate)
        return events.filter { event in
            return event.dose != nil
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
    
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()

        formatter.dateStyle = .short
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true

        return formatter
    }()

    private func updateIOB() {
        if case .display = state {
            if let activeInsulin = loopDataManager.activeInsulin {
                self.iobValueLabel.text = self.iobNumberFormatter.string(from: activeInsulin.value)
                self.iobDateLabel.text = String(format: NSLocalizedString("com.loudnate.InsulinKit.IOBDateLabel", value: "at %1$@", comment: "The format string describing the date of an IOB value. The first format argument is the localized date."), self.timeFormatter.string(from: activeInsulin.startDate))
            } else {
                self.iobValueLabel.text = "…"
                self.iobDateLabel.text = nil
            }
        }
    }

    private func updateTotal() {
        Task { @MainActor in
            if case .display = state {
                if let result = await loopDataManager.totalDeliveredToday() {
                    self.totalValueLabel.text = NumberFormatter.localizedString(from: NSNumber(value: result.value), number: .none)
                    self.totalDateLabel.text = String(format: NSLocalizedString("com.loudnate.InsulinKit.totalDateLabel", value: "since %1$@", comment: "The format string describing the starting date of a total value. The first format argument is the localized date."), DateFormatter.localizedString(from: result.startDate, dateStyle: .none, timeStyle: .short))
                } else {
                    self.totalValueLabel.text = "…"
                    self.totalDateLabel.text = nil
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
        Task { @MainActor in
            await reloadData()
        }
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
        case .manualEntryDose:
            confirmMessage = NSLocalizedString("Are you sure you want to delete all logged dose entries?", comment: "Action sheet confirmation message for logged dose deletion")
        }

        let sheet = UIAlertController(deleteAllConfirmationMessage: confirmMessage) {
            Task {
                await self.deleteAllObjects()
            }
        }
        present(sheet, animated: true)
    }

    private var deletionPending = false

    private func deleteAllObjects() async {
        guard !deletionPending else {
            return
        }

        deletionPending = true

        let sinceDate = Date().addingTimeInterval(-InsulinDeliveryTableViewController.historicDataDisplayTimeInterval)

        switch DataSourceSegment(rawValue: dataSourceSegmentedControl.selectedSegmentIndex)! {
        case .reservoir:
            try? await doseStore?.deleteAllReservoirValues()
        case .history:
            try? await doseStore?.deleteAllPumpEvents()
        case .manualEntryDose:
            try? await doseStore?.deleteAllManuallyEnteredDoses(since: sinceDate)
        }
        self.deletionPending = false
        self.setEditing(false, animated: true)

    }

    // MARK: - Table view data source

    public override func numberOfSections(in tableView: UITableView) -> Int {
        switch state {
        case .unknown, .unavailable:
            return 0
        case .display:
            switch self.values {
            case .history(let values): return values.valuesBeforeToday.isEmpty ? 1 : 2
            default: return 1
            }
        }
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch values {
        case .reservoir(let values):
            return values.count
        case .history(let values):
            switch HistorySection(rawValue: section) {
            case .today: return values.valuesFromToday.count
            case .yesterday: return values.valuesBeforeToday.count
            case .none: return 0
            }
        case .manualEntryDoses(let values):
            return values.count
        }
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch state {
        case .display:
            switch self.values {
            case .history(let values):
                switch HistorySection(rawValue: section) {
                case .today:
                    guard let firstValue = values.valuesFromToday.first else { return nil }
                    return dateFormatter.string(from: firstValue.date).uppercased()
                case .yesterday:
                    guard let firstValue = values.valuesBeforeToday.first else { return nil }
                    return dateFormatter.string(from: firstValue.date).uppercased()
                case .none: return nil
                }
            default: return nil
            }
        default: return nil
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

                cell.textLabel?.text = String(format: NSLocalizedString("%1$@ U", comment: "Reservoir entry (1: volume value)"), volume)
                cell.textLabel?.textColor = .label
                cell.detailTextLabel?.text = time
                cell.accessoryType = .none
                cell.selectionStyle = .none
            case .history(let values):
                let filterValues: [PersistedPumpEvent]
                if HistorySection(rawValue: indexPath.section) == .today {
                    filterValues = values.valuesFromToday
                } else {
                    filterValues = values.valuesBeforeToday
                }
                let entry = filterValues[indexPath.row]
                let time = timeFormatter.string(from: entry.date)

                if let attributedText = entry.localizedAttributedDescription {
                    cell.textLabel?.attributedText = attributedText
                } else {
                    cell.textLabel?.text = NSLocalizedString("Unknown", comment: "The default description to use when an entry has no dose description")
                }
                
                cell.detailTextLabel?.text = time
                cell.accessoryType = entry.isUploaded ? .checkmark : .none
                cell.selectionStyle = .default
            case .manualEntryDoses(let values):
                let entry = values[indexPath.row]
                let time = timeFormatter.string(from: entry.startDate)
                let font = UIFont.preferredFont(forTextStyle: .body)

                let description = String(format: NSLocalizedString("Manual Dose: <b>%1$@</b> %2$@", comment: "Description of a bolus dose entry (1: value (? if no value) in bold, 2: unit)"), numberFormatter.string(from: entry.programmedUnits) ?? "?", DoseEntry.units.shortLocalizedUnitString(avoidLineBreaking: false))

                let attributedDescription = createAttributedDescription(from: description, with: font)
                cell.textLabel?.attributedText = attributedDescription
                cell.detailTextLabel?.text = time
                cell.selectionStyle = .default
            }
        }

        return cell
    }

    public override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return enableEntryDeletion
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
                            Task { @MainActor in
                                await self.reloadData()
                            }
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
                            Task { @MainActor in
                                await self.reloadData()
                            }
                        }
                    }
                }
            case .manualEntryDoses(let doses):
                var doses = doses
                let value = doses.remove(at: indexPath.row)
                self.values = .manualEntryDoses(doses)

                tableView.deleteRows(at: [indexPath], with: .automatic)
                doseStore?.deleteDose(value) { error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.present(UIAlertController(with: error), animated: true)
                            Task { @MainActor in
                                await self.reloadData()
                            }
                        }
                    }
                }
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
        else if case .display = state, case .manualEntryDoses(let doses) = values {
                let entry = doses[indexPath.row]

                let vc = CommandResponseViewController(command: { (completionHandler) -> String in
                    var description = [String]()
                    description.append(self.timeFormatter.string(from: entry.startDate))
                    description.append(String(describing: entry))

                    return description.joined(separator: "\n\n")
                })

                vc.title = NSLocalizedString("Logged Insulin Dose", comment: "The title of the screen displaying a manually entered insulin dose")

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

fileprivate var numberFormatter: NumberFormatter {
    let numberFormatter = NumberFormatter()
    numberFormatter.maximumFractionDigits = DoseEntry.unitsPerHour.maxFractionDigits
    return numberFormatter
}

fileprivate func createAttributedDescription(from description: String, with font: UIFont) -> NSAttributedString? {
    let descriptionWithFont = String(format:"<style>body{font-family: '-apple-system', '\(font.fontName)'; font-size: \(font.pointSize);}</style>%@", description)

    guard let attributedDescription = try? NSMutableAttributedString(data: descriptionWithFont.data(using: .utf16)!, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) else {
        return nil
    }

    attributedDescription.enumerateAttribute(.font, in: NSRange(location: 0, length: attributedDescription.length)) { value, range, stop in
        // bold font items have a dominate colour
        if let font = value as? UIFont,
           font.fontDescriptor.symbolicTraits.contains(.traitBold)
        {
            attributedDescription.addAttributes([.foregroundColor: UIColor.label], range: range)
        } else {
            attributedDescription.addAttributes([.foregroundColor: UIColor.secondaryLabel], range: range)
        }
    }

    return attributedDescription
}

extension PersistedPumpEvent {

    fileprivate var localizedAttributedDescription: NSAttributedString? {
        let font = UIFont.preferredFont(forTextStyle: .body)

        let eventTitle = title ?? NSLocalizedString("Unknown", comment: "Event title displayed when StoredPumpEvent.title is not set")

        if let dose = dose {
            switch dose.type {
            case .bolus:
                let description: String
                if let deliveredUnits = dose.deliveredUnits,
                   deliveredUnits != dose.programmedUnits
                {
                    description = String(format: NSLocalizedString("Interrupted %1$@: <b>%2$@</b> of %3$@ %4$@", comment: "Description of an interrupted bolus dose entry (1: title for dose type, 2: value (? if no value) in bold, 3: programmed value (? if no value), 4: unit)"), eventTitle, numberFormatter.string(from: deliveredUnits) ?? "?", numberFormatter.string(from: dose.programmedUnits) ?? "?", DoseEntry.units.shortLocalizedUnitString())
                } else {
                    description = String(format: NSLocalizedString("%1$@: <b>%2$@</b> %3$@", comment: "Description of a bolus dose entry (1: title for dose type, 2: value (? if no value) in bold, 3: unit)"), eventTitle, numberFormatter.string(from: dose.programmedUnits) ?? "?", DoseEntry.units.shortLocalizedUnitString(avoidLineBreaking: false))
                }

                return createAttributedDescription(from: description, with: font)
            case .basal, .tempBasal:
                let description = String(format: NSLocalizedString("%1$@: <b>%2$@</b> %3$@", comment: "Description of a basal temp basal dose entry (1: title for dose type, 2: value (? if no value) in bold, 3: unit)"), eventTitle, numberFormatter.string(from: dose.unitsPerHour) ?? "?", DoseEntry.unitsPerHour.shortLocalizedUnitString(avoidLineBreaking: false))
                return createAttributedDescription(from: description, with: font)
            case .suspend, .resume:
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.secondaryLabel
                ]
                return NSAttributedString(string: eventTitle, attributes: attributes)
            }
        } else {
            return createAttributedDescription(from: eventTitle, with: font)
        }
    }
}

extension InsulinDeliveryTableViewController: IdentifiableClass { }

fileprivate extension Array where Element == PersistedPumpEvent {
    var valuesFromToday: [PersistedPumpEvent] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return self.filter({ $0.date >= startOfDay})
    }
    
    var valuesBeforeToday: [PersistedPumpEvent] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return self.filter({ $0.date < startOfDay})
    }
}

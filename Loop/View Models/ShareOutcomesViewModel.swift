//
//  ShareOutcomesViewModel.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

@MainActor
final class ShareOutcomesViewModel: ObservableObject {
    enum State {
        case preparing(Double)
        case ready(OutcomesPackage)
        case sending(OutcomesPackage)
        case sent(OutcomesShareReceipt)
        case deleted
        case failed(String, package: OutcomesPackage?)
    }

    @Published private(set) var state: State = .preparing(0)
    @Published private(set) var receipts: [OutcomesShareReceipt]
    @Published private(set) var deletionError: String?
    @Published var note = ""

    static let maxNoteLength = 1000

    let change: SetupChange
    private let builder: OutcomesPackageBuilder
    private let client: OutcomesShareClient
    private let store: OutcomesShareReceipts
    private let now: () -> Date
    private var progress: Progress?
    private var packageURL: URL?
    /// The package under a readable name, for saving or sending a copy through the share sheet.
    @Published private(set) var copyURL: URL?
    private var copyDirectory: URL?
    private let deleteToken = OutcomesShareClient.makeDeleteToken()

    init(change: SetupChange,
         builder: OutcomesPackageBuilder,
         client: OutcomesShareClient = OutcomesShareClient(),
         store: OutcomesShareReceipts = OutcomesShareReceipts(),
         now: @escaping () -> Date = { Date() }) {
        self.change = change
        self.builder = builder
        self.client = client
        self.store = store
        self.now = now
        self.receipts = store.all
    }

    deinit {
        progress?.cancel()
        if let packageURL {
            try? FileManager.default.removeItem(at: packageURL)
        }
        if let copyDirectory {
            try? FileManager.default.removeItem(at: copyDirectory)
        }
    }

    var range: DateInterval {
        let end = now()
        return DateInterval(start: end.addingTimeInterval(-OutcomesPackageBuilder.duration), end: end)
    }

    var canEditNote: Bool {
        switch state {
        case .preparing, .ready, .failed(_, .some): return true
        case .sending, .sent, .deleted, .failed(_, .none): return false
        }
    }

    /// An earlier share of this same setup.
    var previousShare: OutcomesShareReceipt? {
        receipts.last { $0.changeDate == change.date }
    }

    func prepare() async {
        guard case .preparing = state, progress == nil else {
            return
        }
        let progress = Progress(totalUnitCount: 0)
        self.progress = progress
        let observation = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                if case .preparing = self?.state {
                    self?.state = .preparing(fraction)
                }
            }
        }
        defer { observation.invalidate() }

        let builder = builder, change = change, installID = store.installID, now = now()
        let result = await Task.detached(priority: .userInitiated) {
            Result { try builder.build(change: change, installID: installID, now: now, progress: progress) }
        }.value
        switch result {
        case .success(let package):
            packageURL = package.url
            copyURL = makeCopy(of: package, date: now)
            state = .ready(package)
        case .failure(let error):
            if !progress.isCancelled {
                state = .failed(error.localizedDescription, package: nil)
            }
        }
    }

    /// Links the package to a file named for the person, such as "Loop Outcomes 2026-11-25.zip".
    private func makeCopy(of package: OutcomesPackage, date: Date) -> URL? {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("OutcomesCopy-\(UUID().uuidString)", isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let url = directory.appendingPathComponent("Loop Outcomes \(formatter.string(from: date)).zip")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            copyDirectory = directory
            do {
                try fileManager.linkItem(at: package.url, to: url)
            } catch {
                try fileManager.copyItem(at: package.url, to: url)
            }
            return url
        } catch {
            try? fileManager.removeItem(at: directory)
            copyDirectory = nil
            return nil
        }
    }

    func cancel() {
        progress?.cancel()
    }

    func send() async {
        let package: OutcomesPackage
        switch state {
        case .ready(let ready), .failed(_, .some(let ready)):
            package = ready
        default:
            return
        }
        state = .sending(package)
        let note = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNoteLength))
        do {
            let receipt = try await client.submit(package, note: note, deleteToken: deleteToken)
            store.add(receipt)
            receipts = store.all
            state = .sent(receipt)
            try? FileManager.default.removeItem(at: package.url)
            packageURL = nil
        } catch {
            state = .failed(error.localizedDescription, package: package)
        }
    }

    func delete(_ receipt: OutcomesShareReceipt) async {
        deletionError = nil
        do {
            try await client.delete(receipt)
        } catch OutcomesShareError.server(404, _) {
            // Already gone from the server
        } catch {
            deletionError = error.localizedDescription
            return
        }
        store.remove(receipt)
        receipts = store.all
        if case .sent(let sent) = state, sent.id == receipt.id {
            state = .deleted
        }
    }
}

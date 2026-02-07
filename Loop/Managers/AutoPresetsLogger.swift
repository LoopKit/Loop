//
//  AutoPresetsLogger.swift
//  Loop
//
//  Created for Loop AutoPresets Feature
//

import Foundation

/// Simple file-based logger for AutoPresets debugging
/// Logs are written to Documents/AutoPresetsLog.txt
public class AutoPresetsLogger {

    // MARK: - Singleton

    public static let shared = AutoPresetsLogger()

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let logFileName = "AutoPresetsLog.txt"
    private let maxLogSize = 100_000  // ~100KB max before truncating old entries
    private let queue = DispatchQueue(label: "com.loopkit.AutoPresets.Logger", qos: .utility)

    private var logFileURL: URL? {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsURL.appendingPathComponent(logFileName)
    }

    // MARK: - Initialization

    private init() {
        // Create log file if it doesn't exist
        if let url = logFileURL, !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil, attributes: nil)
        }
    }

    // MARK: - Public Methods

    /// Whether debug logging is enabled (checked from settings)
    public var isEnabled: Bool {
        AutoPresetsStorage().settings.debugLoggingEnabled
    }

    /// Log a message with timestamp (only if debug logging is enabled)
    public func log(_ message: String, function: String = #function) {
        guard isEnabled else { return }
        queue.async { [weak self] in
            self?.writeLog(message, function: function)
        }
    }

    /// Get the full log contents
    public func getLogContents() -> String {
        guard let url = logFileURL,
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "(No logs available)"
        }
        return contents
    }

    /// Clear all logs
    public func clearLogs() {
        queue.async { [weak self] in
            guard let self = self, let url = self.logFileURL else { return }
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Get the log file URL (for sharing)
    public func getLogFileURL() -> URL? {
        return logFileURL
    }

    // MARK: - Private Methods

    private func writeLog(_ message: String, function: String) {
        guard let url = logFileURL else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())

        let logEntry = "[\(timestamp)] \(function): \(message)\n"

        // Append to file
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = logEntry.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }

        // Truncate if too large
        truncateIfNeeded()
    }

    private func truncateIfNeeded() {
        guard let url = logFileURL,
              let contents = try? String(contentsOf: url, encoding: .utf8),
              !contents.isEmpty
        else {
            return
        }

        // Remove entries older than 5 days
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 24 * 60 * 60)
        let lines = contents.components(separatedBy: "\n")
        var filteredLines: [String] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        for line in lines {
            guard !line.isEmpty else { continue }

            // Parse timestamp from line format: [2024-01-15 10:30:45.123] ...
            if line.hasPrefix("["),
               let closingBracket = line.firstIndex(of: "]"),
               closingBracket > line.index(line.startIndex, offsetBy: 1) {
                let timestampStart = line.index(after: line.startIndex)
                let timestampString = String(line[timestampStart..<closingBracket])

                if let entryDate = dateFormatter.date(from: timestampString) {
                    // Only keep entries from the last 5 days
                    if entryDate >= fiveDaysAgo {
                        filteredLines.append(line)
                    }
                } else {
                    // Keep lines we can't parse
                    filteredLines.append(line)
                }
            } else {
                // Keep lines without proper timestamp format
                filteredLines.append(line)
            }
        }

        var newContents = filteredLines.joined(separator: "\n")
        if !newContents.isEmpty && !newContents.hasSuffix("\n") {
            newContents += "\n"
        }

        // Also apply size limit if still too large
        if newContents.count > maxLogSize {
            let keepFrom = newContents.index(newContents.endIndex, offsetBy: -50_000, limitedBy: newContents.startIndex) ?? newContents.startIndex
            newContents = "[...truncated...]\n" + String(newContents[keepFrom...])
        }

        // Only write if we actually removed something
        if newContents.count < contents.count {
            try? newContents.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

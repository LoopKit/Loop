//
//  OutcomesShareClient.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import Security

struct OutcomesShareReceipt: Codable, Equatable, Identifiable {
    var id: String
    var deleteToken: String
    var sent: Date
    var changeDate: Date
    var days: Int
    var bytes: Int64
}

enum OutcomesShareError: LocalizedError {
    case server(status: Int, reason: String?)
    case invalidResponse
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .server(404, _):
            return NSLocalizedString("The server has no record of this share. It may already have been deleted.", comment: "Outcomes share error when deleting a share the server doesn't have")
        case .server(409, _):
            return NSLocalizedString("This setup was already shared in the last day.", comment: "Outcomes share error for a duplicate share")
        case .server(413, _):
            return NSLocalizedString("The share is too large for the server.", comment: "Outcomes share error when the upload is too large")
        case .server(429, _):
            return NSLocalizedString("Too many shares have been sent from this network recently. Please try again later.", comment: "Outcomes share error when rate limited")
        case .server(let status, let reason):
            return String(format: NSLocalizedString("The server couldn't accept the share (%1$d %2$@).", comment: "Outcomes share error with HTTP status (1) and reason (2)"), status, reason ?? "")
        case .invalidResponse:
            return NSLocalizedString("The server sent an unexpected response.", comment: "Outcomes share error for an unreadable response")
        case .network(let error):
            return error.localizedDescription
        }
    }
}

struct OutcomesShareClient {
    static let endpoint = URL(string: "https://ingest.loopkit.org/v1/outcomes")!
    static let apiKey = "7dd7414785560c0dd1ef802ac10c00b4"

    var session: URLSession = .shared
    var fileManager: FileManager = .default

    /// A retry with the same token returns the first attempt's receipt, if that one was stored.
    static func makeDeleteToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func submit(_ package: OutcomesPackage, note: String?, deleteToken: String) async throws -> OutcomesShareReceipt {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let bodyURL = fileManager.temporaryDirectory.appendingPathComponent("OutcomesUpload-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: bodyURL) }
        try writeBody(for: package, note: note, deleteToken: deleteToken, boundary: boundary, to: bodyURL)

        let (json, _) = try await send(request) { try await session.upload(for: $0, fromFile: bodyURL) }
        guard let id = json["id"] as? String else {
            throw OutcomesShareError.invalidResponse
        }
        return OutcomesShareReceipt(id: id, deleteToken: deleteToken, sent: Date(), changeDate: package.manifest.setup.changeDate, days: package.manifest.days, bytes: package.bytes)
    }

    func delete(_ receipt: OutcomesShareReceipt) async throws {
        var request = URLRequest(url: Self.endpoint.appendingPathComponent(receipt.id))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(receipt.deleteToken)", forHTTPHeaderField: "Authorization")
        _ = try await send(request) { try await session.data(for: $0) }
    }

    private func send(_ request: URLRequest, _ perform: (URLRequest) async throws -> (Data, URLResponse)) async throws -> ([String: Any], HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await perform(request)
        } catch {
            throw OutcomesShareError.network(error)
        }
        guard let response = response as? HTTPURLResponse else {
            throw OutcomesShareError.invalidResponse
        }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard response.statusCode == 200 else {
            throw OutcomesShareError.server(status: response.statusCode, reason: json["error"] as? String)
        }
        return (json, response)
    }

    // Written to a file so the package is never held in memory whole
    // The server checks the key, token and manifest before it reads the package, so the order matters
    private func writeBody(for package: OutcomesPackage, note: String?, deleteToken: String, boundary: String, to url: URL) throws {
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let output = try FileHandle(forWritingTo: url)
        defer { try? output.close() }

        func header(name: String, filename: String? = nil, contentType: String? = nil) -> Data {
            var header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\""
            if let filename {
                header += "; filename=\"\(filename)\""
            }
            header += "\r\n"
            if let contentType {
                header += "Content-Type: \(contentType)\r\n"
            }
            return Data((header + "\r\n").utf8)
        }

        try output.write(contentsOf: header(name: "client") + Data(Self.apiKey.utf8) + Data("\r\n".utf8))
        try output.write(contentsOf: header(name: "deleteToken") + Data(deleteToken.utf8) + Data("\r\n".utf8))
        if let note, !note.isEmpty {
            try output.write(contentsOf: header(name: "note", contentType: "text/plain; charset=utf-8") + Data(note.utf8) + Data("\r\n".utf8))
        }
        try output.write(contentsOf: header(name: "manifest", contentType: "application/json") + OutcomesPackageBuilder.manifestEncoder.encode(package.manifest) + Data("\r\n".utf8))
        try output.write(contentsOf: header(name: "package", filename: "outcomes.zip", contentType: "application/zip"))
        let input = try FileHandle(forReadingFrom: package.url)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
        try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }
}

/// The shares sent from this install, kept so they can be deleted later.
struct OutcomesShareReceipts {
    private let defaults: UserDefaults
    private static let receiptsKey = "com.loopkit.Loop.outcomesShareReceipts"
    private static let installIDKey = "com.loopkit.Loop.outcomesShareInstallID"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var all: [OutcomesShareReceipt] {
        defaults.data(forKey: Self.receiptsKey).flatMap { try? PropertyListDecoder().decode([OutcomesShareReceipt].self, from: $0) } ?? []
    }

    func add(_ receipt: OutcomesShareReceipt) {
        save(all + [receipt])
    }

    func remove(_ receipt: OutcomesShareReceipt) {
        save(all.filter { $0.id != receipt.id })
    }

    /// Random, and used only to link shares from the same install.
    var installID: String {
        if let id = defaults.string(forKey: Self.installIDKey) {
            return id
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.installIDKey)
        return id
    }

    private func save(_ receipts: [OutcomesShareReceipt]) {
        defaults.set(try? PropertyListEncoder().encode(receipts), forKey: Self.receiptsKey)
    }
}

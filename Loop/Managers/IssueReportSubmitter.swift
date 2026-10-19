//
//  IssueReportSubmitter.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation

struct IssueReport {
    struct Contact: Encodable {
        var name: String?
        var email: String?
        var zulip: String?
        var github: String?
    }

    struct Attachment {
        var filename: String
        var contentType: String
        var data: Data
    }

    var title: String?
    var description: String
    var contact: Contact?
    var context: [String: IssueReportContextValue]
    var attachments: [Attachment]
}

enum IssueReportContextValue: Encodable, Equatable {
    case string(String)
    case strings([String])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .strings(let value): try container.encode(value)
        }
    }
}

enum IssueReportSubmitterError: LocalizedError {
    case server(status: Int, reason: String?)
    case invalidResponse
    case network(Error)

    var isRetryable: Bool {
        switch self {
        case .server(let status, _): return status >= 500
        case .invalidResponse, .network: return true
        }
    }

    var errorDescription: String? {
        switch self {
        case .server(413, _):
            return NSLocalizedString("The report is too large. Try fewer or smaller screenshots.", comment: "Issue report error when the upload is too large")
        case .server(415, _):
            return NSLocalizedString("One of the attachments isn't a supported image type.", comment: "Issue report error when an attachment type is refused")
        case .server(429, _):
            return NSLocalizedString("Too many reports have been sent from this network recently. Please try again later.", comment: "Issue report error when rate limited")
        case .server(let status, let reason):
            return String(format: NSLocalizedString("The server couldn't accept the report (%1$d %2$@).", comment: "Issue report error with HTTP status (1) and reason (2)"), status, reason ?? "")
        case .invalidResponse:
            return NSLocalizedString("The server sent an unexpected response.", comment: "Issue report error for an unreadable response")
        case .network(let error):
            return error.localizedDescription
        }
    }
}

struct IssueReportSubmitter {
    static let endpoint = URL(string: "https://ingest.loopkit.org/v1/issues")!
    static let apiKey = "7dd7414785560c0dd1ef802ac10c00b4"

    var session: URLSession = .shared

    func submit(_ report: IssueReport) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try Self.body(for: report, boundary: boundary)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: body)
        } catch {
            throw IssueReportSubmitterError.network(error)
        }
        guard let response = response as? HTTPURLResponse else {
            throw IssueReportSubmitterError.invalidResponse
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard response.statusCode == 200 else {
            throw IssueReportSubmitterError.server(status: response.statusCode, reason: json?["error"] as? String)
        }
        guard let id = json?["id"] as? String else {
            throw IssueReportSubmitterError.invalidResponse
        }
        return id
    }

    static func body(for report: IssueReport, boundary: String) throws -> Data {
        struct Payload: Encodable {
            var title: String?
            var description: String
            var contact: IssueReport.Contact?
            var context: [String: IssueReportContextValue]
        }
        let payload = try JSONEncoder().encode(Payload(title: report.title, description: report.description, contact: report.contact, context: report.context))

        var body = Data()
        func appendPart(name: String, filename: String? = nil, contentType: String? = nil, data: Data) {
            var header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\""
            if let filename {
                header += "; filename=\"\(filename.replacingOccurrences(of: "\"", with: ""))\""
            }
            header += "\r\n"
            if let contentType {
                header += "Content-Type: \(contentType)\r\n"
            }
            body.append(Data((header + "\r\n").utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }

        appendPart(name: "client", data: Data(apiKey.utf8))
        appendPart(name: "report", contentType: "application/json", data: payload)
        for attachment in report.attachments {
            appendPart(name: "attachment", filename: attachment.filename, contentType: attachment.contentType, data: attachment.data)
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }
}

//
//  WildlifeAPI.swift
//  ucscdevfestapp
//
//  Client for the FastAPI service in hranjan004/devfest_model_training (api/main.py):
//  POST /v2/predict (multipart `file`), POST /v1/feedback, GET /healthz.
//
//  The simulator reaches a server on your Mac at http://localhost:8081. On a real phone,
//  set your Mac's LAN address (for example http://192.168.1.20:8081) in Settings.
//

import Foundation

struct WildlifeAPI {
    static let defaultBaseURL = "http://localhost:8081"
    static let baseURLKey = "apiBaseURL"

    var baseURL: URL
    var session: URLSession = .shared

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    /// Uses the address saved in Settings, falling back to localhost.
    static var current: WildlifeAPI {
        let raw = UserDefaults.standard.string(forKey: baseURLKey) ?? defaultBaseURL
        return WildlifeAPI(baseURL: URL(string: raw) ?? URL(string: defaultBaseURL)!)
    }

    enum APIError: LocalizedError {
        case unreachable(String)
        case rejected(String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .unreachable(let host):
                return "Can’t reach the model at \(host). Start the FastAPI service, or change its address in Settings."
            case .rejected(let detail): return detail
            case .badResponse: return "The model sent back something this app can’t read."
            }
        }
    }

    struct Health: Decodable {
        let ready: Bool
        let modelVersion: String
        let detectorVersion: String

        enum CodingKeys: String, CodingKey {
            case ready
            case modelVersion = "model_version"
            case detectorVersion = "detector_version"
        }
    }

    func health() async throws -> Health {
        var req = URLRequest(url: baseURL.appendingPathComponent("healthz"))
        req.timeoutInterval = 4
        do {
            let (data, _) = try await session.data(for: req)
            return try JSONDecoder().decode(Health.self, from: data)
        } catch is DecodingError {
            throw APIError.badResponse
        } catch {
            throw APIError.unreachable(baseURL.absoluteString)
        }
    }

    func predict(jpeg: Data) async throws -> PredictionResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: baseURL.appendingPathComponent("v2/predict"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: req, from: body)
        } catch {
            throw APIError.unreachable(baseURL.absoluteString)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError.rejected(detail ?? "The service rejected this photo (\(code)).")
        }
        do {
            return try JSONDecoder().decode(PredictionResponse.self, from: data)
        } catch {
            throw APIError.badResponse
        }
    }

    /// Sends a correction to the human review queue. It never retrains the model directly.
    func sendFeedback(predicted: String?, corrected: String) async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("v1/feedback"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "predicted_class_id": predicted.map { $0 as Any } ?? NSNull(),
            "corrected_class_id": corrected,
            "consent": true,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (_, response) = try? await session.data(for: req) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 202
    }
}

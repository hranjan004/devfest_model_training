//
//  APIClient.swift
//  ucscdevfestapp
//
//  Talks to the DEVFEST FastAPI backend (`/v3` endpoints).
//

import Foundation

struct APIError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

struct APIClient {
    static let shared = APIClient()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120   // the first identify call loads the model
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: config)
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: Endpoints

    func sightings() async throws -> [Animal] {
        struct Envelope: Codable { var sightings: [Animal] }
        let envelope: Envelope = try await send(request("GET", "/v3/sightings"))
        return envelope.sightings
    }

    func species() async throws -> [SpeciesInfo] {
        struct Envelope: Codable { var species: [SpeciesInfo] }
        let envelope: Envelope = try await send(request("GET", "/v3/species"))
        return envelope.species
    }

    func identify(jpeg: Data) async throws -> IdentifyResult {
        var req = request("POST", "/v3/identify")
        setMultipart(&req, fields: [:], jpeg: jpeg)
        return try await send(req)
    }

    func createSighting(
        jpeg: Data, name: String, description: String, latitude: Double?, longitude: Double?
    ) async throws -> Animal {
        var fields = ["name": name, "description": description]
        if let latitude, let longitude {
            fields["latitude"] = String(latitude)
            fields["longitude"] = String(longitude)
        }
        var req = request("POST", "/v3/sightings")
        setMultipart(&req, fields: fields, jpeg: jpeg)
        return try await send(req)
    }

    func rate(_ animal: Animal, stars: Int) async throws -> Animal {
        var req = request("POST", "/v3/sightings/\(animal.id)/ratings")
        setJSON(&req, ["stars": stars])
        return try await send(req)
    }

    func comments(for animal: Animal) async throws -> [Comment] {
        struct Envelope: Codable { var comments: [Comment] }
        let envelope: Envelope = try await send(request("GET", "/v3/sightings/\(animal.id)/comments"))
        return envelope.comments
    }

    func addComment(to animal: Animal, author: String, text: String) async throws -> Comment {
        var req = request("POST", "/v3/sightings/\(animal.id)/comments")
        setJSON(&req, ["author": author, "text": text])
        return try await send(req)
    }

    // MARK: Plumbing

    private func request(_ method: String, _ path: String) -> URLRequest {
        var req = URLRequest(url: URL(string: path, relativeTo: AppConfig.serverURL)!)
        req.httpMethod = method
        req.setValue(AppConfig.deviceID, forHTTPHeaderField: "X-Device-Id")
        return req
    }

    private func setJSON(_ req: inout URLRequest, _ body: [String: Any]) {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }

    private func setMultipart(_ req: inout URLRequest, fields: [String: String], jpeg: Data) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (key, value) in fields {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError(message: "Can't reach the server at \(AppConfig.serverURL.absoluteString). Start it with scripts/run_api.sh, or change the address in Settings.")
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError(message: "Unexpected response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(message: Self.serverMessage(data) ?? "The server returned an error (\(http.statusCode)).")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError(message: "The server sent data the app couldn't read.")
        }
    }

    /// FastAPI errors look like {"detail": {"error": ..., "detail": "..."}} or {"detail": "..."}.
    private static func serverMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let detail = json["detail"] as? [String: Any] { return detail["detail"] as? String }
        return json["detail"] as? String
    }
}

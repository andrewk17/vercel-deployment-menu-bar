import Foundation

enum APIError: LocalizedError {
    case invalidResponse(service: String, status: Int, message: String)
    case decodingFailure(service: String)

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(service, status, message):
            return "\(service) API error (\(status)): \(message)"
        case let .decodingFailure(service):
            return "Failed to decode response from \(service)."
        }
    }
}

/// Minimal bearer-token JSON GET shared by the provider clients.
struct HTTPClient {
    let service: String
    let baseURL: String
    var decoder = JSONDecoder()
    var session: URLSession = .shared
    /// Extracts a readable message from an error response body.
    var errorMessage: (Data) -> String? = { String(data: $0, encoding: .utf8) }

    func get<Response: Decodable>(
        _ path: String,
        query: [String: String?] = [:],
        token: String
    ) async throws -> Response {
        var components = URLComponents(string: baseURL + path)!
        let queryItems = query
            .compactMap { name, value in value.flatMap { $0.isEmpty ? nil : URLQueryItem(name: name, value: $0) } }
            .sorted { $0.name < $1.name }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse(service: service, status: -1, message: "No response")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = errorMessage(data) ?? "Unknown error"
            throw APIError.invalidResponse(service: service, status: httpResponse.statusCode, message: message)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decodingFailure(service: service)
        }
    }
}

import Foundation
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling, URLSessionTaskDelegate {
    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey],
              JSONSerialization.isValidJSONObject(message),
              let body = try? JSONSerialization.data(withJSONObject: message), body.count <= 65536,
              let configuration = Bundle(for: Self.self).object(forInfoDictionaryKey: "MeetingBusySafariBridge") as? [String: Any],
              let port = configuration["port"] as? Int, let token = configuration["token"] as? String,
              let endpoint = URL(string: "http://127.0.0.1:\(port)/state") else {
            context.cancelRequest(withError: NSError(domain: "MeetingBusySafari", code: 1)); return
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 3; settings.timeoutIntervalForResource = 3
        settings.connectionProxyDictionary = [:]
        let session = URLSession(configuration: settings, delegate: self, delegateQueue: nil)
        session.dataTask(with: request) { data, response, _ in
            defer { session.finishTasksAndInvalidate() }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count <= 65536,
                  let reply = try? JSONSerialization.jsonObject(with: data) else {
                context.cancelRequest(withError: NSError(domain: "MeetingBusySafari", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Open Meeting Busy and enable browser integration."])); return
            }
            let result = NSExtensionItem(); result.userInfo = [SFExtensionMessageKey: reply]
            context.completeRequest(returningItems: [result], completionHandler: nil)
        }.resume()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

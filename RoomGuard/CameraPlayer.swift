import Foundation
import UIKit
import SwiftUI

private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward the pairing credential to a redirect target.
        completionHandler(nil)
    }
}

@MainActor
final class CameraPlayer: ObservableObject {
    @Published var pairing: Pairing? = PairingStore.load()
    @Published var image: UIImage?
    @Published var status = "Ready to connect"
    @Published var watching = false
    @Published var isLive = false
    @Published var receivedFPS = 0
    @Published var error: String?
    private let redirectGuard = RedirectGuard()
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 86400
        return URLSession(configuration: config, delegate: redirectGuard, delegateQueue: nil)
    }()
    private var socket: URLSessionWebSocketTask?
    private var worker: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var lastFrame = Date.distantPast
    private var lastTimestamp: UInt64 = 0
    private var frameCount = 0
    private var counterStart = Date()
    private var active = true

    func pair(_ text: String) {
        do {
            let newPair = try Pairing.parse(text.trimmingCharacters(in: .whitespacesAndNewlines))
            try PairingStore.save(newPair)
            stop()
            pairing = newPair
            lastTimestamp = 0
            error = nil
            start()
        } catch { self.error = error.localizedDescription }
    }

    func forget() {
        stop()
        PairingStore.clear()
        pairing = nil
        lastTimestamp = 0
        status = "Ready to pair"
    }

    func setActive(_ value: Bool) {
        active = value
        if value && watching { connect() }
        if !value { disconnect(); status = "Paused in background" }
    }

    func start() {
        guard pairing != nil else { return }
        watching = true
        if active { connect() }
    }

    func stop() {
        watching = false
        disconnect()
        status = "Viewer paused"
    }

    private func disconnect() {
        worker?.cancel(); worker = nil
        watchdog?.cancel(); watchdog = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        image = nil; isLive = false; receivedFPS = 0
    }

    private func connect() {
        guard let pairing else { return }
        disconnect()
        status = "Connecting to your room…"
        worker = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.watching && self.active {
                var request = URLRequest(url: pairing.socketURL)
                request.setValue("Bearer " + pairing.token, forHTTPHeaderField: "Authorization")
                request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
                let task = self.session.webSocketTask(with: request)
                task.maximumMessageSize = 2_000_000
                self.socket = task
                task.resume()
                self.lastFrame = .distantPast
                self.counterStart = Date(); self.frameCount = 0
                do {
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        guard !Task.isCancelled else { break }
                        switch message {
                        case .data(let data):
                            let frame = try FrameDecoder.decode(data, key: pairing.keyData)
                            let now = Date()
                            guard frame.timestamp > self.lastTimestamp,
                                  abs(now.timeIntervalSince1970 - Double(frame.timestamp) / 1000) < 300,
                                  let picture = UIImage(data: frame.jpeg) else { throw ViewerError.invalidFrame }
                            self.lastTimestamp = frame.timestamp
                            self.lastFrame = now
                            self.image = picture
                            try await task.send(.string("ack"))
                            guard !Task.isCancelled else { break }
                            self.isLive = true
                            self.status = "Live from your PC"
                            self.frameCount += 1
                            let elapsed = now.timeIntervalSince(self.counterStart)
                            if elapsed >= 1 {
                                self.receivedFPS = min(30, Int((Double(self.frameCount) / elapsed).rounded()))
                                self.frameCount = 0; self.counterStart = now
                            }
                        case .string(let text):
                            self.image = nil; self.isLive = false; self.receivedFPS = 0
                            if let data = text.data(using: .utf8), let notice = try? JSONDecoder().decode(CameraNotice.self, from: data) {
                                self.status = String(notice.status.prefix(120))
                            } else { self.status = "Waiting for camera…" }
                        @unknown default: break
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        self.image = nil; self.isLive = false; self.receivedFPS = 0
                        if error is ViewerError {
                            self.status = "Frame verification failed. Check the clocks on both devices and pair again."
                        } else if let response = task.response as? HTTPURLResponse, response.statusCode == 401 {
                            self.status = "Pairing was reset. Scan the new code on your PC."
                        } else {
                            self.status = "Connection unavailable. Reconnecting automatically…"
                        }
                    }
                }
                task.cancel(with: .goingAway, reason: nil)
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.isLive && Date().timeIntervalSince(self.lastFrame) > 5 {
                    self.image = nil; self.isLive = false; self.receivedFPS = 0
                    self.status = "No recent video. Waiting for your PC…"
                }
            }
        }
    }
}

private struct CameraNotice: Decodable { let status: String }

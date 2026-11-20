import Foundation

/// Downloads a file and reports how far along it is.
///
/// `URLSession.download(from:)` says nothing until it is finished, which left
/// the pill reading "downloading" for however long five megabytes took — on a
/// slow link, long enough to look stuck. This wraps a download task so the
/// fraction can drive the pill's fill.
final class ProgressDownload: NSObject, URLSessionDownloadDelegate {
    private let configuration: URLSessionConfiguration
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<URL, Error>?
    private var onProgress: ((Double) -> Void)?
    private var destination: URL?

    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
    }

    func download(
        _ url: URL,
        to destination: URL,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        self.onProgress = onProgress
        self.destination = destination

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        defer { session.finishTasksAndInvalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session.downloadTask(with: url)
            self.task = task
            task.resume()
        }
    }

    /// Stops the transfer. The task reports `URLError.cancelled` through the
    /// delegate, so the caller gets one path for every ending.
    func cancel() {
        task?.cancel()
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // An unknown length (chunked response) reports -1: no progress to show.
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        let handler = onProgress
        DispatchQueue.main.async { handler?(fraction) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destination else {
            finish(.failure(URLError(.badURL)))
            return
        }
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Success is reported from didFinishDownloadingTo; this is the failure
        // path (and a no-op for a task that already finished).
        guard let error else { return }
        finish(.failure(error))
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

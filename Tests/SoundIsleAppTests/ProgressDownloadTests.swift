import Foundation
import XCTest
@testable import SoundIsle

final class ProgressDownloadTests: XCTestCase {
    /// The pill's fill is only worth drawing if the numbers arrive: this
    /// proves a download reports fractions, in order, ending at 1 — and that
    /// the bytes still land in the destination file.
    func testReportsProgressAndWritesTheFile() async throws {
        let payload = Data((0..<200_000).map { UInt8($0 % 251) })
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Length": "\(payload.count)"]
            )!
            return (response, payload)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("download-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: destination) }

        var fractions: [Double] = []
        let downloader = ProgressDownload(configuration: configuration)
        let written = try await downloader.download(
            URL(string: "https://example.test/release.zip")!,
            to: destination
        ) { fraction in
            fractions.append(fraction)
        }

        XCTAssertEqual(written, destination)
        XCTAssertEqual(try Data(contentsOf: destination), payload)
        XCTAssertFalse(fractions.isEmpty, "a download with a known size must report progress")
        XCTAssertEqual(fractions, fractions.sorted(), "progress must not jump backwards")
        XCTAssertEqual(fractions.last, 1.0)
    }

    func testAFailedResponseDoesNotProduceAFile() async throws {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("download-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: destination) }

        let downloader = ProgressDownload(configuration: configuration)
        do {
            _ = try await downloader.download(
                URL(string: "https://example.test/release.zip")!,
                to: destination
            ) { _ in }
            XCTFail("a 404 must throw")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }
}

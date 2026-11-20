import Foundation
import XCTest
@testable import SoundIsleCore

final class FLACArtworkTests: XCTestCase {
    private var tempDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = fm.temporaryDirectory
            .appendingPathComponent("FLACArtworkTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? fm.removeItem(at: tempDir) }
        try super.tearDownWithError()
    }

    private func writeFLAC(_ blocks: [(type: UInt8, payload: Data)]) throws -> URL {
        let url = tempDir.appendingPathComponent("test.flac")
        var data = Data("fLaC".utf8)
        for (index, block) in blocks.enumerated() {
            let isLast = index == blocks.count - 1
            let header = (isLast ? UInt8(0x80) : 0) | (block.type & 0x7F)
            var length = Data([0, 0, 0])
            let n = block.payload.count
            length[0] = UInt8((n >> 16) & 0xFF)
            length[1] = UInt8((n >> 8) & 0xFF)
            length[2] = UInt8(n & 0xFF)
            data.append(header)
            data.append(length)
            data.append(block.payload)
        }
        try data.write(to: url)
        return url
    }

    private func picturePayload(jpeg: Data) -> Data {
        var payload = Data()
        func int32(_ value: Int) { payload.append(contentsOf: [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]) }
        int32(3)                                    // front cover
        let mime = Data("image/jpeg".utf8)
        int32(mime.count); payload.append(mime)
        let description = Data()
        int32(description.count); payload.append(description)
        int32(500); int32(500); int32(24); int32(0) // width/height/depth/colors
        int32(jpeg.count); payload.append(jpeg)
        return payload
    }

    func testExtractsPictureBlock() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        let url = try writeFLAC([
            (0, Data(repeating: 0, count: 34)),          // STREAMINFO
            (6, picturePayload(jpeg: jpeg)),             // PICTURE
        ])

        XCTAssertEqual(FLACArtwork.pictureData(at: url), jpeg)
    }

    func testLastBlockFlagIsHonoured() throws {
        let url = try writeFLAC([
            (0x80 | 6, picturePayload(jpeg: Data([9, 9]))),  // last flag set
        ])

        XCTAssertEqual(FLACArtwork.pictureData(at: url), Data([9, 9]))
    }

    func testSkipsVorbisCommentBeforePicture() throws {
        let jpeg = Data([0xFF, 0xD9])
        let vorbis = Data("the comment".utf8)
        let url = try writeFLAC([
            (4, vorbis),
            (6, picturePayload(jpeg: jpeg)),
        ])

        XCTAssertEqual(FLACArtwork.pictureData(at: url), jpeg)
    }

    func testNoPictureBlockReturnsNil() throws {
        let url = try writeFLAC([
            (0, Data(repeating: 0, count: 34)),
            (4, Data("comment".utf8)),
        ])

        XCTAssertNil(FLACArtwork.pictureData(at: url))
    }

    func testNonFLACReturnsNil() throws {
        let url = tempDir.appendingPathComponent("notflac.flac")
        try Data("not really".utf8).write(to: url)

        XCTAssertNil(FLACArtwork.pictureData(at: url))
    }

    func testTruncatedPictureBlockReturnsNil() throws {
        // Picture block claims more payload than the file carries.
        let url = tempDir.appendingPathComponent("broken.flac")
        var data = Data("fLaC".utf8)
        data.append(0x80 | 6)
        data.append(contentsOf: [0, 0, 0x10])            // claims 16 bytes
        data.append(Data(repeating: 0, count: 4))        // type only
        try data.write(to: url)

        XCTAssertNil(FLACArtwork.pictureData(at: url))
    }
}

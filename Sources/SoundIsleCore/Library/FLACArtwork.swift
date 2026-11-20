import Foundation

/// Extracts the embedded picture from a FLAC file's native metadata blocks.
///
/// AVFoundation does not expose FLAC's METADATA_BLOCK_PICTURE as a metadata
/// item, so FLACs tagged with native (non-ID3) blocks — common for downloads
/// from bandcamp/Qobuz — come back without artwork through the AV reader.
/// The block layout is trivial, so a small parser is enough:
///
///     "fLaC" | block header (1 byte: last-flag + type, 3 bytes length)
///     ... blocks ...
///     PICTURE (type 6): type(4) mimeLen(4) mime descLen(4) desc
///                       width(4) height(4) depth(4) colors(4) dataLen(4) data
public enum FLACArtwork {
    /// Returns the embedded picture's bytes, or nil when the file is not a
    /// FLAC or carries no picture block.
    public static func pictureData(at url: URL) -> Data? {
        guard url.pathExtension.lowercased() == "flac",
              let raw = try? Data(contentsOf: url, options: .mappedIfSafe),
              raw.count >= 8,
              raw.prefix(4) == Data("fLaC".utf8)
        else { return nil }

        var offset = 4
        while offset + 4 <= raw.count {
            let header = raw[offset]
            let isLast = header & 0x80 != 0
            let type = header & 0x7F
            let length = Int(raw[offset + 1]) << 16
                | Int(raw[offset + 2]) << 8
                | Int(raw[offset + 3])
            let payloadStart = offset + 4
            guard payloadStart + length <= raw.count else { return nil }

            if type == 6, let picture = readPictureBlock(raw, range: payloadStart..<payloadStart + length) {
                return picture
            }
            if isLast { return nil }
            offset = payloadStart + length
        }
        return nil
    }

    private static func readPictureBlock(_ raw: Data, range: Range<Int>) -> Data? {
        // Fresh copy: a Data slice keeps its parent's indices, which would
        // make the 0-based cursor read (or crash) out of bounds.
        let bytes = Data(raw[range])
        var cursor = 0

        func takeInt32() -> Int? {
            guard cursor + 4 <= bytes.count else { return nil }
            let value = Int(bytes[cursor]) << 24 | Int(bytes[cursor + 1]) << 16
                | Int(bytes[cursor + 2]) << 8 | Int(bytes[cursor + 3])
            cursor += 4
            return value
        }

        func take(_ count: Int) -> Data? {
            guard count >= 0, cursor + count <= bytes.count else { return nil }
            let slice = bytes.subdata(in: cursor..<cursor + count)
            cursor += count
            return slice
        }

        _ = takeInt32()                       // picture type
        guard let mimeLength = takeInt32(), take(mimeLength) != nil,
              let descriptionLength = takeInt32(), take(descriptionLength) != nil
        else { return nil }
        // width, height, depth, colors
        guard takeInt32() != nil, takeInt32() != nil, takeInt32() != nil, takeInt32() != nil,
              let dataLength = takeInt32()
        else { return nil }
        return take(dataLength)
    }
}

//
//  MediaTests.swift
//  walkytalkyTests
//

import CryptoKit
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import walkytalky

struct MediaCryptoTests {
    @Test func encryptThenDecryptRoundTrips() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("hello walkytalky".utf8)

        let encrypted = try MediaCrypto.encrypt(plaintext, key: key)
        let decrypted = try MediaCrypto.decrypt(encrypted.uploadData, nonceBase64: encrypted.nonceBase64, key: key)

        #expect(decrypted == plaintext)
    }

    @Test func decryptFailsWithWrongKey() throws {
        let key = SymmetricKey(size: .bits256)
        let wrongKey = SymmetricKey(size: .bits256)
        let encrypted = try MediaCrypto.encrypt(Data("secret".utf8), key: key)

        #expect(throws: (any Error).self) {
            try MediaCrypto.decrypt(encrypted.uploadData, nonceBase64: encrypted.nonceBase64, key: wrongKey)
        }
    }

    @Test func decryptFailsIfCiphertextIsTampered() throws {
        let key = SymmetricKey(size: .bits256)
        var encrypted = try MediaCrypto.encrypt(Data("secret".utf8), key: key)
        encrypted = MediaCrypto.EncryptResult(
            uploadData: {
                var tampered = encrypted.uploadData
                // Data's subscript is absolute-index based, not always
                // zero-based (this can be a slice) — index via startIndex.
                tampered[tampered.startIndex] ^= 0xFF
                return tampered
            }(),
            nonceBase64: encrypted.nonceBase64
        )

        #expect(throws: (any Error).self) {
            try MediaCrypto.decrypt(encrypted.uploadData, nonceBase64: encrypted.nonceBase64, key: key)
        }
    }

    @Test func eachEncryptionUsesAFreshNonce() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = Data("same message twice".utf8)
        let a = try MediaCrypto.encrypt(plaintext, key: key)
        let b = try MediaCrypto.encrypt(plaintext, key: key)
        #expect(a.nonceBase64 != b.nonceBase64)
        #expect(a.uploadData != b.uploadData)
    }
}

struct ImageSanitizerTests {
    private func testJPEGData() -> Data {
        // Explicit scale 1, otherwise UIGraphicsImageRenderer defaults to the
        // simulator screen's scale (e.g. 3x -> a 24x24 image, not 8x8).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        return image.jpegData(compressionQuality: 1.0)!
    }

    @Test func strippedImageStillDecodesToTheSamePixelSize() {
        let original = testJPEGData()
        let stripped = ImageSanitizer.stripMetadata(from: original)
        #expect(stripped != nil)

        guard let stripped,
              let source = CGImageSourceCreateWithData(stripped as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            Issue.record("stripped data did not decode as an image")
            return
        }
        #expect(cgImage.width == 8)
        #expect(cgImage.height == 8)
    }

    @Test func strippedImageHasNoExifOrGPSMetadata() throws {
        // Embed GPS metadata into a JPEG the same way a camera capture would,
        // then confirm stripMetadata actually removes it.
        let original = testJPEGData()
        let sourceData = NSMutableData()
        let source = CGImageSourceCreateWithData(original as CFData, nil)!
        let destination = CGImageDestinationCreateWithData(sourceData, "public.jpeg" as CFString, 1, nil)!
        let gpsMetadata: [String: Any] = [kCGImagePropertyGPSDictionary as String: [
            kCGImagePropertyGPSLatitude as String: 37.0,
            kCGImagePropertyGPSLongitude as String: -122.0,
        ]]
        CGImageDestinationAddImageFromSource(destination, source, 0, gpsMetadata as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let withGPS = sourceData as Data

        // Sanity check the fixture actually carries GPS data before stripping.
        let beforeSource = CGImageSourceCreateWithData(withGPS as CFData, nil)!
        let beforeProps = CGImageSourceCopyPropertiesAtIndex(beforeSource, 0, nil) as? [String: Any]
        #expect(beforeProps?[kCGImagePropertyGPSDictionary as String] != nil)

        let stripped = try #require(ImageSanitizer.stripMetadata(from: withGPS))
        let afterSource = CGImageSourceCreateWithData(stripped as CFData, nil)!
        let afterProps = CGImageSourceCopyPropertiesAtIndex(afterSource, 0, nil) as? [String: Any]
        #expect(afterProps?[kCGImagePropertyGPSDictionary as String] == nil)

        // The JPEG encoder always repopulates a minimal, non-identifying Exif
        // block (pixel dimensions, color space) — that's not what stripping
        // is protecting against. What must be gone is anything that could
        // identify the person or device: camera make/model, lens info,
        // original capture timestamp.
        let exif = afterProps?[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(exif?[kCGImagePropertyExifDateTimeOriginal as String] == nil)
        let tiff = afterProps?[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        #expect(tiff?[kCGImagePropertyTIFFMake as String] == nil)
        #expect(tiff?[kCGImagePropertyTIFFModel as String] == nil)
    }

    @Test func stripMetadataBakesInOrientationInsteadOfDroppingIt() throws {
        // A wide (8x4) image, physically stored unrotated, but tagged with
        // EXIF orientation 6 ("rotate 90° CW to display correctly") — this
        // is how a real camera photo commonly looks: pixels as captured by
        // the (landscape) sensor, relying on the tag rather than
        // physically-rotated pixels to appear upright.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 4), format: format)
        let wideImage = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        }
        let cgImage = try #require(wideImage.cgImage)

        let taggedData = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(taggedData, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))

        // Sanity check the fixture: raw pixels are still 8x4 (unrotated) before stripping.
        let beforeSource = try #require(CGImageSourceCreateWithData(taggedData as CFData, nil))
        let beforeImage = try #require(CGImageSourceCreateImageAtIndex(beforeSource, 0, nil))
        #expect(beforeImage.width == 8)
        #expect(beforeImage.height == 4)

        let stripped = try #require(ImageSanitizer.stripMetadata(from: taggedData as Data))
        let afterSource = try #require(CGImageSourceCreateWithData(stripped as CFData, nil))
        let afterImage = try #require(CGImageSourceCreateImageAtIndex(afterSource, 0, nil))

        // Orientation 6 means "rotate 90° CW to display upright" — a
        // correct fix bakes that rotation into the pixels themselves,
        // swapping width/height. The bug this guards against: stripping
        // metadata without normalizing first just drops the tag, leaving
        // the output permanently sideways at the original 8x4.
        #expect(afterImage.width == 4)
        #expect(afterImage.height == 8)
    }
}

@MainActor
struct MediaStorageTests {
    @Test func writeReadDeleteRoundTrips() throws {
        let messageId = "test-\(UUID().uuidString)"
        let data = Data("plaintext media bytes".utf8)

        #expect(MediaStorage.exists(messageId: messageId) == false)
        try MediaStorage.write(data, messageId: messageId)
        #expect(MediaStorage.exists(messageId: messageId))
        #expect(MediaStorage.read(messageId: messageId) == data)

        MediaStorage.delete(messageId: messageId)
        #expect(MediaStorage.exists(messageId: messageId) == false)
    }
}

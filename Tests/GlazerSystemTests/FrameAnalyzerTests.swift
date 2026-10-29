import CoreVideo
import Testing

@testable import GlazerSystem

@Suite("FrameAnalyzer")
struct FrameAnalyzerTests {
    /// A 640×480 camera-format image with every pixel at `luma`.
    func image(luma: UInt8) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil, 640, 480, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        let image = try #require(buffer)
        #expect(status == kCVReturnSuccess)

        CVPixelBufferLockBaseAddress(image, [])
        defer { CVPixelBufferUnlockBaseAddress(image, []) }
        for plane in 0..<CVPixelBufferGetPlaneCount(image) {
            let base = try #require(CVPixelBufferGetBaseAddressOfPlane(image, plane))
            let size = CVPixelBufferGetBytesPerRowOfPlane(image, plane) * CVPixelBufferGetHeightOfPlane(image, plane)
            // Luma takes `luma`; chroma is neutral grey.
            memset(base, Int32(plane == 0 ? luma : 128), size)
        }
        return image
    }

    @Test("Brightness is the average luma", arguments: [(UInt8(0), 0.0), (255, 1.0), (51, 0.2)])
    func brightness(luma: UInt8, expected: Double) throws {
        #expect(abs(FrameAnalyzer.brightness(of: try image(luma: luma)) - expected) < 0.001)
    }

    @Test("An empty image has no faces")
    func noFaces() throws {
        let frame = FrameAnalyzer().analyze(try image(luma: 120), at: 3, includeSignatures: true)

        #expect(frame.faces.isEmpty)
        #expect(frame.timestamp == 3)
    }
}

@Suite("FrameAnalyzer, hands")
struct FrameAnalyzerHandTests {
    @Test("Hands are looked for only when asked, and an empty image has none")
    func noHands() throws {
        let image = try FrameAnalyzerTests().image(luma: 120)

        let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
        #expect(FrameAnalyzer().analyze(image, at: 0, includeSignatures: false, handArea: whole).hands.isEmpty)
        #expect(FrameAnalyzer().analyze(image, at: 0, includeSignatures: false).hands.isEmpty)
    }

    @Test("An area too small to read is skipped")
    func tinyArea() throws {
        let image = try FrameAnalyzerTests().image(luma: 120)

        #expect(FrameAnalyzer.hands(in: image, area: CGRect(x: 0.5, y: 0.5, width: 0.01, height: 0.01)).isEmpty)
    }

    @Test("No observations give no hands")
    func noObservations() {
        let size = CGSize(width: 1280, height: 720)
        #expect(FrameAnalyzer.readings(of: [], crop: CGRect(origin: .zero, size: size), imageSize: size).isEmpty)
    }
}

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

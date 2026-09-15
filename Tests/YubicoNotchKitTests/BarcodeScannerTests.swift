import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Testing

@testable import YubicoNotchKit

private let context = CIContext()

/// Renders `payload` as a QR code, enlarged for Vision.
///
/// `CIFilter.qrCodeGenerator()` emits one pixel per module and adds no quiet zone:
/// scaling up makes the modules detectable, and compositing over a white canvas that is
/// larger than the code gives it the margin a scanner needs.
private func qrCodeImage(payload: String, scale: CGFloat = 8) throws -> CGImage {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(payload.utf8)
    filter.correctionLevel = "M"
    let code = try #require(filter.outputImage)

    let scaled = code.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let margin = 4 * scale
    let canvas = CGRect(
        origin: .zero,
        size: CGSize(
            width: scaled.extent.width + margin * 2,
            height: scaled.extent.height + margin * 2
        )
    )
    let image = scaled
        .transformed(by: CGAffineTransform(translationX: margin, y: margin))
        .composited(over: CIImage(color: .white).cropped(to: canvas))
    return try #require(context.createCGImage(image, from: canvas))
}

private func blankImage(side: CGFloat = 240) throws -> CGImage {
    let extent = CGRect(x: 0, y: 0, width: side, height: side)
    let image = CIImage(color: .white).cropped(to: extent)
    return try #require(context.createCGImage(image, from: extent))
}

@Test func otpauthQRCodeIsDecoded() throws {
    let uri = "otpauth://totp/ACME:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=ACME"

    let payload = try BarcodeScanner.otpauthPayload(in: qrCodeImage(payload: uri))

    #expect(payload == uri)
}

@Test func webLinkQRCodeIsListedButNotSelected() throws {
    let image = try qrCodeImage(payload: "https://example.com")

    let payloads = try BarcodeScanner.qrPayloads(in: image)
    let otpauth = try BarcodeScanner.otpauthPayload(in: image)

    #expect(payloads == ["https://example.com"])
    #expect(otpauth == nil)
}

@Test func blankImageHasNoCode() throws {
    let image = try blankImage()

    let payloads = try BarcodeScanner.qrPayloads(in: image)
    let otpauth = try BarcodeScanner.otpauthPayload(in: image)

    #expect(payloads.isEmpty)
    #expect(otpauth == nil)
}

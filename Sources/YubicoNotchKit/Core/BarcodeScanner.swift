import CoreGraphics
import Vision

/// Reads QR codes out of still images with Vision.
public enum BarcodeScanner {

    /// Payloads of the QR codes found in `image`, in the order Vision reports them.
    ///
    /// The default revision of the running system is used on purpose: a fixed revision
    /// would keep an old detector on newer systems.
    public static func qrPayloads(in image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }

    /// First payload that is an `otpauth://` URI, `nil` when the image has none.
    public static func otpauthPayload(in image: CGImage) throws -> String? {
        try qrPayloads(in: image).first { $0.lowercased().hasPrefix(otpauthScheme) }
    }

    /// QR codes carrying anything else (a web link, a wifi credential) are ignored by
    /// `otpauthPayload(in:)`; the scheme is matched case-insensitively as URIs allow.
    private static let otpauthScheme = "otpauth://"
}

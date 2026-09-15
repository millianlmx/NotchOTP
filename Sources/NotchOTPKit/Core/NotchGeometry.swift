import CoreGraphics

/// Where the notch panel has to be placed, and how big it gets once expanded.
///
/// Pure value type: every input comes from `NSScreen`, so the multi-screen and
/// notch-less cases are testable without a display.
public struct NotchGeometry: Equatable, Sendable {

    /// Full frame of the screen hosting the notch, in global coordinates.
    public let screenFrame: CGRect
    /// The physical notch: the collapsed size of the panel.
    public let notchRect: CGRect
    /// The panel once expanded, hanging from the top edge and centred on the notch.
    public let expandedRect: CGRect

    /// Size of the expanded panel.
    public static let expandedSize = CGSize(width: 420, height: 340)

    /// Extra margin around the notch that still counts as hovering it.
    public static let hoverMargin: CGFloat = 4

    /// Fails when the screen has no notch (`auxiliaryTop*Area` are `nil` there,
    /// which is also the case for every external display).
    public init?(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?,
        expandedSize: CGSize = NotchGeometry.expandedSize
    ) {
        guard
            safeAreaTop > 0,
            let left = auxiliaryTopLeftArea,
            let right = auxiliaryTopRightArea,
            left.width > 0,
            right.width > 0
        else { return nil }

        let notchWidth = screenFrame.width - left.width - right.width
        guard notchWidth > 0 else { return nil }

        self.screenFrame = screenFrame
        self.notchRect = CGRect(
            x: left.maxX,
            y: screenFrame.maxY - safeAreaTop,
            width: notchWidth,
            height: safeAreaTop
        )

        let width = min(expandedSize.width, screenFrame.width)
        let height = min(expandedSize.height, screenFrame.height)
        let originX = min(
            max(notchRect.midX - width / 2, screenFrame.minX),
            screenFrame.maxX - width
        )
        self.expandedRect = CGRect(
            x: originX,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    /// Frame to use in the given state. Collapsed, the panel is exactly the notch:
    /// those pixels are not part of the display, so nothing shows.
    public func frame(expanded: Bool) -> CGRect {
        expanded ? expandedRect : notchRect
    }

    /// Hit area that counts as "the pointer is on the notch".
    public var hoverRect: CGRect {
        notchRect.insetBy(dx: -Self.hoverMargin, dy: -Self.hoverMargin)
    }
}

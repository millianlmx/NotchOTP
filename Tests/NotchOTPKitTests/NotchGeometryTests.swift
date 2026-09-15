import CoreGraphics
import Testing

@testable import NotchOTPKit

/// 14" MacBook Pro geometry: 1512×982 points, two menu bar areas of 656 points
/// around a 200 point notch.
private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
private let leftArea = CGRect(x: 0, y: 945, width: 656, height: 37)
private let rightArea = CGRect(x: 856, y: 945, width: 656, height: 37)

private func notchGeometry(
    screenFrame: CGRect = screen,
    safeAreaTop: CGFloat = 37,
    left: CGRect? = leftArea,
    right: CGRect? = rightArea
) -> NotchGeometry? {
    NotchGeometry(
        screenFrame: screenFrame,
        safeAreaTop: safeAreaTop,
        auxiliaryTopLeftArea: left,
        auxiliaryTopRightArea: right
    )
}

@Test func notchRectMatchesThePhysicalNotch() throws {
    let geometry = try #require(notchGeometry())
    #expect(geometry.notchRect == CGRect(x: 656, y: 945, width: 200, height: 37))
}

@Test func expandedPanelHangsFromTheTopEdgeCentredOnTheNotch() throws {
    let geometry = try #require(notchGeometry())
    let expanded = geometry.expandedRect
    #expect(expanded.width == NotchGeometry.expandedSize.width)
    #expect(expanded.height == NotchGeometry.expandedSize.height)
    #expect(expanded.maxY == screen.maxY)
    #expect(expanded.midX == geometry.notchRect.midX)
}

@Test func collapsedPanelIsExactlyTheNotch() throws {
    let geometry = try #require(notchGeometry())
    // Hidden behind the notch: same rect, no lip, nothing to draw.
    #expect(geometry.frame(expanded: false) == geometry.notchRect)
    #expect(geometry.frame(expanded: true) == geometry.expandedRect)
    #expect(!geometry.hoverRect.isEmpty)
}

@Test func screensWithoutNotchAreRejected() {
    #expect(notchGeometry(left: nil, right: nil) == nil)
    #expect(notchGeometry(safeAreaTop: 0) == nil)
    #expect(notchGeometry(safeAreaTop: -1) == nil)
}

@Test func expandedPanelIsClampedOnNarrowScreens() throws {
    let narrow = CGRect(x: 0, y: 0, width: 400, height: 982)
    let geometry = try #require(
        notchGeometry(
            screenFrame: narrow,
            left: CGRect(x: 0, y: 945, width: 100, height: 37),
            right: CGRect(x: 300, y: 945, width: 100, height: 37)
        )
    )
    #expect(geometry.expandedRect.minX == narrow.minX)
    #expect(geometry.expandedRect.width == narrow.width)
}

@Test func multipleScreensAreEachMeasuredFromTheirOwnFrame() throws {
    let external = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let geometry = try #require(
        notchGeometry(
            screenFrame: external,
            left: CGRect(x: -1920, y: 1043, width: 860, height: 37),
            right: CGRect(x: -60, y: 1043, width: 860, height: 37)
        )
    )
    #expect(geometry.notchRect.midX == external.midX)
    #expect(geometry.notchRect.maxY == external.maxY)
}

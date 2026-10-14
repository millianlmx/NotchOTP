import AppKit
import Testing

/// Tests that put the real panel on screen need a notched display: without one the window
/// controller reports `isAvailable == false` and never expands — true of an external
/// monitor as much as of a CI runner, so those tests are skipped rather than failed.
extension Trait where Self == ConditionTrait {
    static var requiresNotchedScreen: ConditionTrait {
        .enabled("needs a Mac with a notch") {
            await MainActor.run {
                NSScreen.screens.contains { screen in
                    screen.safeAreaInsets.top > 0
                        && (screen.auxiliaryTopLeftArea?.width ?? 0) > 0
                        && (screen.auxiliaryTopRightArea?.width ?? 0) > 0
                }
            }
        }
    }
}

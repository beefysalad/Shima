import CoreGraphics

public enum ScreenPick {
    /// Index of the first frame containing `point` (AppKit coordinates, so a point on the top edge of a
    /// frame counts via inclusive max), or `nil`.
    public static func index(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex { point.x >= $0.minX && point.x <= $0.maxX && point.y >= $0.minY && point.y <= $0.maxY }
    }

    /// The screen to open a window on: under the pointer, else the island's, else the main one.
    public static func choose(pointer: CGPoint, frames: [CGRect], island: Int?, main: Int?) -> Int? {
        index(containing: pointer, in: frames) ?? island ?? main
    }
}

/// Whether screen-bound services may work in the current desktop session.
public enum ScreenAvailability {
    public static func allowsWork(screenAwake: Bool, systemAwake: Bool,
                                  locked: Bool, sessionActive: Bool) -> Bool {
        screenAwake && systemAwake && !locked && sessionActive
    }
}

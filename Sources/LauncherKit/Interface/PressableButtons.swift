/// The actions of the buttons drawn while a test listens, by their
/// titles, so a test can press a panel's buttons as a keeper would and run
/// their own actions. Nothing is kept unless a test turns it on.
@MainActor
public enum PressableButtons {
    public static var isListening = false {
        didSet {
            actions = [:]
            fields = [:]
        }
    }
    /// What sets the words of each field drawn while a test listens, by its
    /// prompt, so a test can type into it as a keeper would.
    public private(set) static var fields: [String: (String) -> Void] = [:]

    public static func noteField(_ prompt: String, _ type: @escaping (String) -> Void) {
        guard isListening else { return }
        fields[prompt] = type
    }

    /// Types words into the field drawn with that prompt, in place of what
    /// it held; false if none was drawn.
    @discardableResult
    public static func type(_ words: String, into prompt: String) -> Bool {
        guard let field = fields[prompt] else { return false }
        field(words)
        return true
    }
    public private(set) static var actions: [String: () -> Void] = [:]

    public static func note(_ title: String, enabled: Bool, _ action: @escaping () -> Void) {
        guard isListening, enabled else { return }
        actions[title] = action
    }

    /// Forgets the action drawn under one title, so that only a drawing of
    /// it from now on can be pressed. The others stay as they were last
    /// drawn: a view drawn once is not drawn again only to be listened to.
    static func forget(_ title: String) {
        actions[title] = nil
    }

    /// Presses the button drawn with that title; false if none was drawn,
    /// or it was drawn disabled.
    @discardableResult
    public static func press(_ title: String) -> Bool {
        guard let action = actions[title] else { return false }
        action()
        return true
    }
}

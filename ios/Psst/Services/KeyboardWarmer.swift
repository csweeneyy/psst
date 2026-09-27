import UIKit

/// Loads the keyboard before anything asks for it.
///
/// The first `becomeFirstResponder` in an app's lifetime pays for launching
/// the keyboard extension process, which is the half second between the chat
/// sheet appearing and the keyboard arriving. Doing it once off-screen at
/// launch moves that cost somewhere nobody is looking.
enum KeyboardWarmer {
    @MainActor
    static func warm() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first else { return }

        let field = UITextField(frame: .zero)
        field.isHidden = true
        window.addSubview(field)
        field.becomeFirstResponder()
        field.resignFirstResponder()
        field.removeFromSuperview()
    }
}

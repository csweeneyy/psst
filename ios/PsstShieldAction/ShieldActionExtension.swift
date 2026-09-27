import ManagedSettings

/// What the buttons on the shield do.
///
/// "I did it" has to be one tap and has to work instantly, or the lockdown
/// stops being a commitment device and starts being a thing you resent. It
/// lowers the shield here rather than waking the app, because waking the app
/// is slow and can fail, and leaves a note for the app to pick up so the habit
/// is actually marked done in the store.
nonisolated class ShieldActionExtension: ShieldActionDelegate {
    private func resolve(
        _ action: ShieldAction,
        _ completion: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            if let habit = Lockdown.activeHabit() {
                Lockdown.recordCompletion(habit: habit)
            }
            LockdownService.lower()
            completion(.close)
        case .secondaryButtonPressed:
            completion(.close)
        @unknown default:
            completion(.none)
        }
    }

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        resolve(action, completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        resolve(action, completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        resolve(action, completionHandler)
    }
}

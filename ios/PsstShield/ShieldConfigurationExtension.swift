import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen you hit when you try to open something else.
///
/// Runs in a tight sandbox with no network and a short deadline: if it does not
/// return quickly the system shows its own generic blocker instead. So it reads
/// one string out of the shared defaults and builds a view, and does nothing
/// else.
nonisolated class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    private func configuration() -> ShieldConfiguration {
        let habit = Lockdown.activeName()
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor(white: 0.04, alpha: 0.86),
            icon: UIImage(systemName: "bell.badge.fill"),
            title: ShieldConfiguration.Label(
                text: habit,
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Your phone is yours again as soon as this is done.",
                color: UIColor(white: 1, alpha: 0.7)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "I did it",
                color: .black
            ),
            primaryButtonBackgroundColor: .white,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Not yet",
                color: UIColor(white: 1, alpha: 0.7)
            )
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration()
    }

    override func configuration(
        shielding webDomain: WebDomain,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration()
    }
}

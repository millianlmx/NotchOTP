import AppKit
import SwiftUI

/// The panes of the settings window, in the order the tab bar shows them.
public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case key
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "Général"
        case .key: "YubiKey"
        case .about: "À propos"
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .key: "key.horizontal"
        case .about: "info.circle"
        }
    }
}

/// Which pane the settings window shows.
///
/// The menu bar can ask for a specific pane ("À propos de NotchOTP"), and the window
/// outlives that request, so the selection lives here rather than in the view's state.
@MainActor
@Observable
public final class SettingsRoute {
    public var tab: SettingsTab

    public init(tab: SettingsTab = .general) {
        self.tab = tab
    }
}

/// Preferences window.
public struct SettingsView: View {

    @Bindable var settings: Settings
    @Bindable var route: SettingsRoute
    let launchAtLogin: LaunchAtLogin

    public init(
        settings: Settings,
        launchAtLogin: LaunchAtLogin,
        route: SettingsRoute = SettingsRoute()
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        self.route = route
    }

    public var body: some View {
        TabView(selection: $route.tab) {
            GeneralPane(settings: settings, launchAtLogin: launchAtLogin)
                .tabItem { Label(SettingsTab.general.title, systemImage: SettingsTab.general.symbol) }
                .tag(SettingsTab.general)

            YubiKeyPane(settings: settings)
                .tabItem { Label(SettingsTab.key.title, systemImage: SettingsTab.key.symbol) }
                .tag(SettingsTab.key)

            AboutPane()
                .tabItem { Label(SettingsTab.about.title, systemImage: SettingsTab.about.symbol) }
                .tag(SettingsTab.about)
        }
        // Tall enough for the Général pane, the tallest of the three, even when the tab
        // strip is drawn inside the content (it moves to the title bar on some setups).
        .frame(width: 480, height: 570)
    }
}

// MARK: - Général

private struct GeneralPane: View {

    @Bindable var settings: Settings
    let launchAtLogin: LaunchAtLogin

    var body: some View {
        // Read here, in `body`, so the pane follows the system state when it changes
        // (including from another app, e.g. Réglages Système).
        let launchAtLoginEnabled = launchAtLogin.isEnabled
        Form {
            Section {
                Toggle(
                    "Ouvrir à la connexion",
                    isOn: Binding(
                        get: { launchAtLoginEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                if launchAtLogin.needsApproval {
                    Button("Ouvrir Réglages Système…") {
                        LaunchAtLogin.openLoginItemsSettings()
                    }
                    .controlSize(.small)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "NotchOTP démarre dans la barre de menus : aucune fenêtre, aucune icône dans le Dock."
                    )
                    Text(launchAtLogin.statusDescription)
                        .foregroundStyle(.secondary)
                    if let error = launchAtLogin.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                Picker("Confirmation", selection: $settings.confirmationMethod) {
                    ForEach(Settings.ConfirmationMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                Text(settings.confirmationMethod.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } footer: {
                Text(
                    "Chaque code est confirmé à part : une empreinte, ou un double-clic sur le bouton latéral d'une Apple Watch à proximité. Chaque confirmation se fait avec un contexte biométrique neuf, pour qu'un doigt resté sur le capteur ne puisse pas répondre à la place du suivant."
                )
            }

            Section {
                Picker("Effacer le presse-papiers après", selection: $settings.clipboardClear) {
                    ForEach(Settings.ClipboardClear.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } footer: {
                Text(
                    "Le presse-papiers n'est vidé que si le code copié s'y trouve encore : un texte copié entre-temps n'est jamais touché."
                )
            }

            Section {
                Picker("Masquer les codes après", selection: $settings.revealTimeout) {
                    ForEach(Settings.RevealTimeout.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } footer: {
                Text(
                    "Un code confirmé disparaît de lui-même à la fin de sa fenêtre ; ce délai couvre ceux qui n'en ont pas, comme les codes HOTP. Le bouton Verrouiller du panneau, lui, referme tout de suite la session OATH : l'applet de la YubiKey se reverrouille, et il faut confirmer à nouveau."
                )
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin.refresh() }
    }
}

// MARK: - YubiKey

private struct YubiKeyPane: View {

    @Bindable var settings: Settings
    @State private var smartCardAccess = AppInfo.smartCardAccess

    var body: some View {
        Form {
            Section {
                Toggle("Mémoriser le mot de passe OATH dans le trousseau", isOn: $settings.rememberOATHPassword)
            } footer: {
                Text(
                    "À activer si l'applet OATH de ta YubiKey est protégée par un mot de passe : le panneau ouvre alors l'applet tout seul et liste tes comptes. Le mot de passe est stocké dans le trousseau de session et ne sert qu'à cela : les codes, eux, demandent chacun une confirmation."
                )
            }

            Section {
                LabeledContent("Carte à puce") {
                    Label(
                        smartCardAccess ? "Accessible" : "Non accessible",
                        systemImage: smartCardAccess ? "checkmark.circle" : "exclamationmark.triangle"
                    )
                    .foregroundStyle(smartCardAccess ? Color.primary : Color.orange)
                }
            } footer: {
                Text(
                    smartCardAccess
                        ? "L'app voit le lecteur de cartes à puce du Mac : branche une YubiKey pour la déverrouiller."
                        : "L'app ne voit aucun lecteur. Deux causes possibles : aucune YubiKey n'est branchée, ou cette copie n'a pas l'entitlement carte à puce — un binaire non signé ne voit jamais la clé, même branchée. Installe l'app produite par Scripts/build-app.sh pour lever le doute."
                )
            }
        }
        .formStyle(.grouped)
        .task {
            // The slot manager appears and disappears as the key is plugged in, so the
            // line is kept live while the pane is on screen.
            while !Task.isCancelled {
                smartCardAccess = AppInfo.smartCardAccess
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

// MARK: - À propos

private struct AboutPane: View {

    /// The bundle's icon. `NSImage(named:)` reads `CFBundleIconFile` from the app's own
    /// resources; the running application's icon is the fallback for code that runs
    /// outside a bundle (tests, `swift run`), where asking for "AppIcon" finds nothing.
    private var appIcon: NSImage {
        NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AppInfo.name)
                            .font(.title3.weight(.semibold))
                        Text("Version \(AppInfo.versionDescription)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 6)

                LabeledContent("Identifiant", value: AppInfo.bundleIdentifier)
            } footer: {
                if let copyright = AppInfo.copyright {
                    Text(copyright)
                }
            }
        }
        .formStyle(.grouped)
    }
}

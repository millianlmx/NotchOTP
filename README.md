# YubicoNotch

App macOS qui vit dans l'encoche : survoler l'encoche ouvre un panneau qui liste les
comptes de la YubiKey. **Un geste, un code** : chaque code est confirmé à part —
empreinte sur Touch ID, ou double-clic sur le bouton latéral d'une Apple Watch — avant
d'être calculé par la clé, affiché, et copié dans le presse-papiers.

C'est la mécanique d'Apple Pay : le panneau montre ce qui est sur la clé comme Wallet
montre les cartes, une feuille annonce ce qui est sur le point d'être copié, et rien ne
sort sans un geste délibéré.

Les secrets ne quittent jamais la clé : l'app ne stocke que des métadonnées (émetteur,
compte) et les codes calculés par la YubiKey.

## Prérequis

- macOS 14 ou plus récent, sur un Mac **avec encoche** (sur écran externe ou Mac sans
  encoche, seul l'icône de barre de menus est disponible).
- Une YubiKey branchée en USB-C, avec des identifiants OATH enregistrés
  (`Yubico Authenticator` ou `ykman oath accounts add`).
- Touch ID (sinon le mot de passe du Mac sert de repli).

## Construire et lancer

```bash
./Scripts/build-app.sh          # build release + YubicoNotch.app dans build/
open build/YubicoNotch.app
```

L'icône de l'app (`Resources/AppIcon.icns`) est un fichier généré : `build-app.sh`
l'appelle au premier build, et `./Scripts/make-icon.sh` la redessine seule. Le script
écrit un petit programme Swift dans un dossier temporaire, dessine le carré arrondi,
l'encoche évidée et la clé (SF Symbol `key.horizontal.fill`), puis emballe le tout avec
`iconutil`. Il laisse aussi un aperçu 512×512 dans `/tmp/YubicoNotch-AppIcon-512.png`.

Mode démo (clé factice avec de vrais codes TOTP calculés en local, Touch ID simulé)
pour voir le panneau sans matériel :

```bash
./Scripts/build-app.sh --debug
open build/YubicoNotch.app --args -demo      # clé factice + Touch ID simulé
open build/YubicoNotch.app --args -confirm   # vraie clé : panneau ouvert, premier compte demandé
```

`-confirm` sert à vérifier le parcours complet — liste des comptes, feuille de
confirmation, prompt biométrique embarqué, lecture du code — sans avoir à survoler
l'encoche :

```bash
log show --last 2m --predicate 'subsystem == "app.yubiconotch"' --style compact
```

Tests :

```bash
swift test
```

## Utilisation

Le panneau se replie **entièrement derrière l'encoche** : replié, il ne dessine rien du
tout. Passe la souris sur l'encoche pour l'ouvrir.

| État | Ce que fait l'app |
| --- | --- |
| Aucune clé | Le panneau invite à brancher la clé, et se met à jour dès qu'elle arrive |
| Clé détectée | Le panneau liste les comptes de l'applet OATH ; aucun code n'est affiché |
| Aucun compte | Écran d'accueil qui propose d'en enregistrer un |
| Compte choisi | Feuille de confirmation : le geste révèle le code **et** le copie |
| Mot de passe OATH | Champ de saisie dans le panneau, avec option « mémoriser dans le trousseau » |

### Gérer les comptes

- **Chercher** : `⌘F` (ou la loupe) filtre la liste par émetteur ou par compte.
- **Naviguer au clavier** : `↑` `↓` pour parcourir, `⏎` ou `⌘C` pour confirmer la ligne
  sélectionnée, `Échap` pour refermer la confirmation en cours, puis la recherche, puis le
  formulaire, puis le panneau. Les raccourcis s'activent quand le panneau a le clavier :
  le survol ne le prend jamais, un clic dedans si.
- **Renommer ou supprimer** : clic droit sur une ligne. La suppression demande
  confirmation dans le panneau — rien n'est effacé sans un second clic.
- **Ajouter un compte** : bouton `+` dans l'en-tête (la liste doit être affichée — donc
  l'applet OATH ouverte ; la clé est déjà branchée).
  Saisis l'émetteur, le compte et la clé base32, colle un lien `otpauth://` avec
  *Coller un lien*, ou lis un QR code affiché à l'écran avec *Scanner l'écran*.
  TOTP/HOTP, 6 ou 8 chiffres, période 30/60 s et contact physique obligatoire sont
  réglables.
- **Scanner l'écran** : le panneau se replie, tu traces un rectangle sur n'importe quel
  écran (Échap annule), et le QR code `otpauth://` qu'il contient remplit le formulaire.
  La première fois, macOS demande l'autorisation *Enregistrement de l'écran* ; si elle
  est refusée, la marche à suivre s'affiche dans le formulaire.
- Les identifiants qui exigent un contact physique le disent dans la feuille de
  confirmation : une fois le geste fait, la clé attend que tu la touches.
- Le presse-papiers est vidé après le délai choisi dans les réglages, et seulement si
  tu n'as pas copié autre chose entre-temps.
- Un code affiché disparaît à la fin de sa fenêtre, et après le délai choisi dans les
  réglages pour ceux qui n'en ont pas (HOTP). Rien n'est relu depuis la clé en
  arrière-plan : le code suivant demande un nouveau geste.
- `Verrouiller` efface les codes révélés et la liste, et referme la session OATH :
  l'applet de la clé se reverrouille. Le panneau reste verrouillé tant qu'il est ouvert —
  quitter l'encoche et y revenir relit la liste, et chaque code redemande son empreinte.
- Le verrouillage est aussi immédiat si tu verrouilles la session, si l'écran s'éteint ou
  si la clé est débranchée.

En mode Touch ID, une annulation laisse la feuille ouverte : reclique dessus pour
réessayer, ou *Annuler* (Échap) pour la refermer. En mode appui maintenu, relâche trop tôt
et recommence.

Réglages : icône ⚙ dans le panneau, ou menu de l'icône de barre de menus — trois onglets
(Général, YubiKey, À propos), dont l'ouverture à la connexion et l'état d'accès à la carte
à puce.

## Accessibilité

Les lignes sont des éléments annoncés à VoiceOver (« GitHub · prenom@exemple.com »,
valeur « 427391, encore 24 secondes sur 30 » ou « Code masqué. Confirmation requise »
tant que le code ne l'est pas), les boutons portent leurs libellés, et l'entrée en cascade
des codes est désactivée quand « Réduire les animations » est actif dans Réglages Système.

## Réglages

La fenêtre s'ouvre depuis l'icône ⚙ du panneau, ou depuis le menu de la barre de menus
(*Réglages…*, et *À propos de YubicoNotch* pour arriver directement sur le dernier
onglet). Trois onglets, dans la barre de titre :

| Onglet | Ce qu'on y règle |
| --- | --- |
| **Général** | Ouvrir à la connexion, mode de confirmation, délai d'effacement du presse-papiers, masquage des codes |
| **YubiKey** | Mémorisation du mot de passe OATH, et l'état de l'accès à la carte à puce |
| **À propos** | Nom, version et build, identifiant du bundle, copyright |

**Ouvrir à la connexion** passe par `SMAppService` (macOS 13+) : la case reflète l'état
réel de l'élément de connexion du système, pas une préférence à nous — la décocher depuis
Réglages Système → Général → Ouverture se voit donc ici. Quand macOS attend une
autorisation, la fenêtre propose d'ouvrir ce panneau, et une erreur d'enregistrement
s'affiche sous la case plutôt que d'être avalée.

**Carte à puce** (onglet YubiKey) est le premier endroit à regarder quand « la clé n'est
pas détectée ». *Accessible* veut dire que l'app voit le lecteur de cartes à puce du Mac :
il n'y a plus qu'à brancher une YubiKey. *Non accessible* veut dire que le processus ne
voit aucun lecteur — soit aucune clé n'est branchée, soit la copie lancée n'a pas
l'entitlement `com.apple.security.smartcard`, ce qui est le cas de tout binaire non signé
(y compris `swift run`). L'app produite par `Scripts/build-app.sh` l'a.

## Comment c'est fait

```
Sources/YubicoNotchKit/
  Model/        OATHAccount, OATHCode, OATHFailure, NewCredential (+ parsing otpauth://)
  Core/         NotchGeometry, CodeClock, Clipboard, Settings, Base32
  Auth/         BiometricGate (LocalAuthentication), OATHPasswordStore (trousseau)
  Key/          seam OATHSessionProtocol + adaptateur YubiKit, YubiKeyService
  UI/           NotchPanel, NotchWindowController, NotchShape, vues SwiftUI
  App/          AppController (encoche + barre de menus + fenêtre Réglages)
```

- **YubiKit 1.3.0** (`USBSmartCardConnection` + `OATHSession`) lit les codes ; l'applet
  OATH est sollicitée uniquement quand le panneau est visible.
- **Un geste, un code** : `YubiKeyService` ne connaît que quatre états — rien, `locked`
  (session fermée, ou verrouillée à la main : `lockedByUser`, qui empêche la liste de
  revenir toute seule quand le guetteur se reconnecte), `ready` (comptes listés),
  `unavailable` — plus la confirmation en cours (`pending` + `phase`). Lister la clé passe
  par `listCredentials()`, qui ne calcule rien ; le code d'un compte n'est demandé qu'après
  l'empreinte, et il disparaît à la fin de sa fenêtre. Rien n'est relu en arrière-plan.
- **Feuille de confirmation** (`CodeConfirmationView`) : le compte, le code masqué, le
  geste, et une coche verte quand le code est remis — puis elle se referme sur la liste,
  où la ligne confirmée montre son code et son compte à rebours.
- **Biométrie** (`Auth/BiometricGate`) : un `LAContext` **neuf par confirmation**, le
  précédent invalidé. C'est la seule construction où le code suivant redemande vraiment
  quelque chose : la réutilisation vit dans le contexte, et un contexte déjà satisfait
  répond en une dizaine de millisecondes (mesuré).
- **Horloge** : un seul `ticker` cadence tout ce qui défile — une seconde quand le panneau
  est à l'écran, cinq sinon — et `setPanelVisible` le **redémarre**. Sans ça, le sommeil en
  cours finissait sa sieste et les anneaux restaient figés jusqu'à six secondes après
  l'ouverture de l'encoche.
- **Fenêtre** : `NSPanel` borderless, non-activating, niveau `.statusBar`, placée
  exactement sur l'encoche grâce à `NSScreen.auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea` et `safeAreaInsets.top`. Elle ne vole jamais le focus
  clavier, sauf quand un champ texte (mot de passe OATH, ajout de compte) est à
  l'écran — ou pendant une confirmation, le temps que le prompt biométrique embarqué
  reçoive la pression du capteur.
- **Replié = invisible** : la fenêtre fait exactement la taille de l'encoche et n'y
  dessine rien. Les pixels de l'encoche n'existent pas de toute façon ; il ne doit donc
  rien y avoir qui dépasse, ni liseré ni ombre.
- **Apparence** : le panneau force `NSAppearance(named: .darkAqua)`. La dalle est noire
  comme l'encoche, donc ses couleurs sémantiques (`.primary`, `.secondary`) doivent se
  résoudre en clair — sinon, en mode clair, le texte s'affiche en noir sur noir.
  Contrôles natifs (`.bordered`, `.borderedProminent`), hiérarchie SF Pro, et
  `monospacedDigit()` pour les codes.
- **Survol** : moniteurs d'événements globaux (autres apps) **et** locaux (notre
  panneau), sinon un déplacement vers le panneau ouvert ne serait plus vu.

## Confirmation : un geste, un code

Réglages → *Général* → *Confirmation*.

Le panneau ne déverrouille pas la clé pour la session : il liste les comptes, et chaque
code est autorisé à part. Cliquer un compte ouvre une feuille qui annonce ce qui est sur
le point d'être copié — le compte, le code encore masqué — puis attend le geste.

**Touch ID** (défaut) — l'empreinte, ou un **double-clic sur le bouton latéral d'une Apple
Watch appairée à proximité** : `LAPolicyDeviceOwnerAuthenticationWithBiometricsOrCompanion`
(macOS 15+). Le contrôle biométrique d'Apple est **intégré au panneau** :
`LAAuthenticationView` (`LocalAuthenticationEmbeddedUI`, macOS 12+) est lié au `LAContext`
du gate, donc macOS dessine le prompt dedans — sous ton curseur, dans la feuille — au lieu
d'ouvrir sa propre alerte. Rien ne s'affiche ailleurs à l'écran.

**Et un contexte biométrique neuf à chaque code.** C'est là que tout se joue : la
réutilisation vit dans le `LAContext`. Un contexte qui a déjà reconnu un doigt répond à
l'évaluation suivante en **une dizaine de millisecondes, sans nouveau toucher** — mesuré
sur macOS 26, avec `touchIDAuthenticationAllowableReuseDuration` laissé à 0, qui ne couvre
que la réutilisation après un déverrouillage de la machine. C'est exactement ainsi qu'une
seule empreinte ouvrait tous les codes suivants. Chaque confirmation arme donc un contexte
qui n'a jamais rien authentifié, et invalide le précédent.

Si une confirmation passe sans que tu poses le doigt, le journal le dit — c'est la seule
façon de voir la fuite, et c'est pour ça que la durée de chaque évaluation y est
consignée :

```bash
log show --last 2m --predicate 'subsystem == "app.yubiconotch"' --style compact \
  | grep evaluatePolicy
```

**Appui maintenu** — l'autre geste, sans capteur : tu maintiens la cible appuyée environ
une seconde, l'anneau se remplit, le code arrive. Pour les Macs sans Touch ID, et pour qui
ne veut jamais voir de dialogue biométrique.

Trois conditions pour que le prompt embarqué fonctionne, apprises à la dure : la vue doit
être **dans une fenêtre** avant l'appel à `evaluatePolicy` (sinon macOS retombe sur son
alerte), le panneau doit pouvoir devenir **key** pendant le prompt (sinon le capteur n'est
pas relié), et la feuille ne doit pas se replier pendant l'authentification — le panneau
reste épinglé tant qu'une confirmation est en cours.

Une confirmation réussie copie le code *et* l'affiche dans la liste, avec son anneau de
compte à rebours. Un code déjà affiché se recopie d'un simple clic : l'empreinte qui l'a
autorisé couvre encore sa fenêtre. Les autres lignes restent masquées — il faut une
empreinte par code. Une confirmation annulée laisse la feuille ouverte : reclique dessus
pour réessayer, `Échap` ou *Annuler* pour la refermer.

Si l'applet OATH est protégée par un mot de passe, il est demandé à l'ouverture du panneau
(ou lu dans le trousseau s'il y est mémorisé) : il ne sert qu'à ouvrir l'applet et à lister
les comptes, jamais à autoriser un code.

Compromis : l'appui maintenu protège de la personne qui passe derrière toi, pas de
quelqu'un devant le Mac déverrouillé. Les secrets TOTP, eux, ne quittent jamais la
YubiKey, et le mot de passe OATH (s'il est activé sur la clé) reste demandé.

## Sécurité

- **Aucun code n'est calculé sans un geste.** Lister la clé ne lit que les noms des
  comptes (`listCredentials`) ; le code d'un compte n'est calculé que lorsque l'empreinte
  — ou le double-clic sur la Apple Watch, ou l'appui maintenu — l'a autorisé. C'est une
  propriété du modèle, et un test la tient : la clé ne reçoit aucune demande de code avant
  le geste.
- La liste des comptes — émetteur et nom, jamais un code — s'affiche dès que le panneau
  s'ouvre. C'est le compromis assumé du modèle Wallet : les cartes se voient, le numéro
  non.
- Le mot de passe OATH optionnel est stocké dans le **trousseau de session**
  (`kSecAttrAccessibleWhenUnlocked`) et ne sert qu'à ouvrir l'applet.
  Le trousseau protégé par biométrie (`SecAccessControl` + `kSecUseDataProtectionKeychain`)
  n'est pas utilisable ici : il exige une app signée avec un profil et renvoie
  `errSecMissingEntitlement` (-34018) sur une app signée ad hoc. Compromis assumé : ce
  mot de passe seul est inutile sans la clé physique.
- Verrouiller efface les codes révélés et la liste, vide le presse-papiers si le code
  copié y est encore, et referme la connexion pour reverrouiller l'applet.

## Signature et entitlements

`Resources/YubicoNotch.entitlements` porte `com.apple.security.smartcard`, requis dès que
l'app est mise dans un bac à sable. Le script signe en ad hoc (`SIGN_IDENTITY` permet de
passer une identité de développeur).

Cet entitlement n'est pas décoratif : mesuré sur macOS 26, un binaire **non signé** voit
`TKSmartCardSlotManager.default` à `nil` même quand la YubiKey est branchée et le lecteur
listé par le système — et YubiKit plante alors sur `assertionFailure` dans un build debug.
Signature ad hoc + entitlement suffit (vérifié). Conséquence : `swift test` ne peut pas
parler à la clé (binaire de test non signé), il faut passer par l'app (`-confirm`) pour
exercer le matériel.

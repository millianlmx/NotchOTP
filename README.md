# YubicoNotch

**Tes codes à usage unique, dans l'encoche du Mac — et une empreinte pour chacun.**

Survole l'encoche : le panneau s'ouvre sur la liste de tes comptes. Clique un compte,
pose le doigt : le code est copié. Les secrets ne quittent jamais la YubiKey, rien n'est
stocké, rien ne se synchronise, et **un code affiché ne s'obtient pas deux fois sans un
nouveau geste**.

<p align="center">
  <img src="docs/panel-list.png" width="420" alt="La liste : un code confirmé à gauche, les autres encore masqués">
  <img src="docs/panel-confirmation.png" width="420" alt="La feuille de confirmation : le compte, le code masqué, l'empreinte">
</p>

## Pourquoi celle-là

- **Elle vit dans l'encoche.** Pas de fenêtre, pas d'icône dans le Dock, pas de ⌘Tab. Elle
  est là quand tu la survoles, et invisible autrement — repliée, elle ne dessine rien du
  tout, ces pixels n'existent pas.
- **Tes codes ne traînent nulle part.** Une YubiKey calcule les TOTP/HOTP dans son applet
  OATH ; l'app ne reçoit que le résultat. Aucun secret sur le disque, aucune synchro, aucun
  compte en ligne.
- **Un geste, un code.** Le panneau n'ouvre pas une session : il liste tes comptes, et
  chaque code demande sa propre empreinte. Le prompt biométrique d'Apple est dessiné *dans*
  le panneau — aucune fenêtre système qui s'ouvre ailleurs.
- **Ça ne ment pas sur ce que ça lit.** Ouvrir le panneau ne fait que demander les *noms* à
  la clé ; le code n'est calculé qu'après ton geste, pour ce seul compte, et il disparaît à
  la fin de sa fenêtre.

## Ce qu'il te faut

| | |
| --- | --- |
| **Un Mac avec une encoche** | Sans encoche (ou sur écran externe), seule l'icône de barre de menus reste disponible |
| **macOS 14 ou plus récent** | et Touch ID, ou l'Apple Watch pour confirmer |
| **Une YubiKey en USB-C** | avec des identifiants OATH déjà enregistrés (`Yubico Authenticator` ou `ykman oath accounts add`) |

## Installation

```bash
git clone https://github.com/millianlmx/yubico_notch.git
cd yubico_notch
./Scripts/build-app.sh
open build/YubicoNotch.app
```

Puis glisse `YubicoNotch.app` dans **Applications** si tu veux qu'il reste — et coche
*Ouvrir à la connexion* dans les réglages : il démarrera discrètement dans la barre de
menus.

Il n'y a pas de `.xcodeproj` : SwiftPM construit, et le script assemble et signe le bundle
(une seule dépendance, [YubiKit](https://github.com/Yubico/yubikit-swift), épinglée en
1.3.0). La signature est ad hoc, avec l'entitlement carte à puce — c'est ce qui permet à
l'app de voir la clé, et c'est aussi pourquoi tu la construis toi-même plutôt que de la
télécharger.

Mode démo, pour voir le panneau sans matériel (clé factice, codes TOTP réellement calculés,
Touch ID simulé) :

```bash
./Scripts/build-app.sh --debug
open build/YubicoNotch.app --args -demo
```

## Utilisation

| État | Ce que fait l'app |
| --- | --- |
| Aucune clé | Le panneau invite à brancher la clé, et se met à jour dès qu'elle arrive |
| Clé détectée | Le panneau liste les comptes de l'applet OATH ; aucun code n'est affiché |
| Aucun compte | Écran d'accueil qui propose d'en enregistrer un |
| Compte choisi | Feuille de confirmation : l'empreinte révèle le code **et** le copie |
| Mot de passe OATH | Champ de saisie dans le panneau, avec option « mémoriser dans le trousseau » |

- **Chercher** : `⌘F` (ou la loupe) filtre la liste par émetteur ou par compte.
- **Naviguer au clavier** : `↑` `↓` pour parcourir, `⏎` ou `⌘C` pour confirmer la ligne
  sélectionnée, `Échap` pour refermer la confirmation, puis la recherche, puis le panneau.
  Les raccourcis s'activent quand le panneau a le clavier : le survol ne le prend jamais,
  un clic dedans si.
- **Renommer ou supprimer** : clic droit sur une ligne. La suppression demande confirmation
  dans le panneau — rien n'est effacé sans un second clic.
- **Ajouter un compte** : bouton `+` dans l'en-tête. Saisis l'émetteur, le compte et la clé
  base32, colle un lien `otpauth://`, ou lis un QR code affiché à l'écran avec *Scanner
  l'écran*. TOTP/HOTP, 6 ou 8 chiffres, période 30/60 s et contact physique obligatoire sont
  réglables.
- **Scanner l'écran** : le panneau se replie, tu traces un rectangle sur n'importe quel
  écran (Échap annule), et le QR code `otpauth://` qu'il contient remplit le formulaire. La
  première fois, macOS demande l'autorisation *Enregistrement de l'écran*.
- **Presse-papiers** : vidé après le délai choisi dans les réglages, et seulement si tu n'as
  pas copié autre chose entre-temps.
- **Verrouiller** : efface les codes révélés et la liste, et referme la session OATH —
  l'applet de la clé se reverrouille. Le panneau reste verrouillé tant qu'il est ouvert ;
  quitter l'encoche et y revenir relit la liste. Le verrouillage est aussi immédiat si tu
  verrouilles ta session, si l'écran s'éteint ou si la clé est débranchée.

## Un geste, un code

C'est la mécanique d'Apple Pay, transposée : le panneau montre ce qui est sur la clé comme
Wallet montre les cartes, une feuille annonce ce qui est sur le point d'être copié, et rien
ne sort sans un geste délibéré.

**Touch ID** (défaut) — une empreinte, ou un double-clic sur le bouton latéral d'une Apple
Watch appairée à proximité, **pour chaque code**. Le contrôle biométrique d'Apple est
intégré au panneau : macOS dessine son prompt dedans, jamais dans une alerte système.

Une finesse qui a coûté cher à trouver : la réutilisation vit dans le `LAContext`. Un
contexte qui a déjà reconnu un doigt répond à l'évaluation suivante en **une dizaine de
millisecondes, sans nouveau toucher** — autrement dit, une seule empreinte ouvrait tous les
codes suivants. Chaque confirmation invalide donc le contexte précédent et en arme un neuf,
avant même que la feuille existe. Mesuré après correctif : 1,40 s, 1,66 s, 1,32 s par code,
c'est-à-dire le capteur qui attend vraiment un doigt à chaque fois.

**Appui maintenu** — l'autre geste, sans capteur : tu maintiens la cible appuyée environ une
seconde, l'anneau se remplit, le code arrive. Pour les Macs sans Touch ID, et pour qui ne
veut jamais voir de dialogue biométrique.

Si une confirmation passait sans que tu poses le doigt, le journal le dirait :

```bash
log show --last 2m --predicate 'subsystem == "app.yubiconotch"' --style compact \
  | grep -E 'evaluatePolicy|fresh biometric'
```

## Réglages

L'icône ⚙ du panneau, ou le menu de la barre de menus (*Réglages…*). Trois onglets :

| Onglet | Ce qu'on y règle |
| --- | --- |
| **Général** | Ouvrir à la connexion, mode de confirmation, délai d'effacement du presse-papiers, masquage des codes |
| **YubiKey** | Mémorisation du mot de passe OATH, et l'état de l'accès à la carte à puce |
| **À propos** | Nom, version et build, identifiant du bundle, copyright |

**Ouvrir à la connexion** passe par `SMAppService` : la case reflète l'état réel de
l'élément de connexion du système, pas une préférence à nous. Quand macOS attend une
autorisation, la fenêtre propose d'ouvrir le bon panneau.

## Sécurité

- **Aucun code n'est calculé sans un geste.** Lister la clé ne lit que les noms des comptes ;
  le code d'un compte n'est calculé que lorsque l'empreinte — ou le double-clic sur l'Apple
  Watch, ou l'appui maintenu — l'a autorisé. Un test tient la propriété : la clé ne reçoit
  aucune demande de code avant le geste.
- La liste des comptes — émetteur et nom, jamais un code — s'affiche dès que le panneau
  s'ouvre. C'est le compromis assumé du modèle Wallet : les cartes se voient, le numéro non.
- Le mot de passe OATH optionnel est stocké dans le **trousseau de session** et ne sert qu'à
  ouvrir l'applet. Le trousseau protégé par biométrie n'est pas utilisable sur une app signée
  ad hoc (`errSecMissingEntitlement`, -34018). Compromis assumé : ce mot de passe seul est
  inutile sans la clé physique.
- Verrouiller efface les codes révélés et la liste, vide le presse-papiers si le code copié y
  est encore, et referme la connexion pour reverrouiller l'applet.

## Accessibilité

Les lignes sont annoncées à VoiceOver (« GitHub · prenom@exemple.com », valeur « 427391,
encore 24 secondes sur 30 » ou « Code masqué. Confirmation requise »), les boutons portent
leurs libellés, et les animations respectent « Réduire les animations ».

## Comment c'est fait

Deux cibles SwiftPM : `YubicoNotchKit` (toute la logique et les vues) et un exécutable de
vingt lignes. Le détail est dans ** [`docs/architecture.md`](docs/architecture.md)** — les
coutures qui rendent le service testable sans matériel, la machine à états, le fil
d'exécution, la fenêtre et le pointeur, la biométrie embarquée, l'entitlement carte à puce,
et les deux pièges des tests d'interaction AppKit.

Ce que l'app envoie réellement à la clé — les APDU de l'applet OATH, le calcul TOTP/HOTP, le
mot de passe, le parsing `otpauth://` et Base32 — est dans
**[`docs/protocols.md`](docs/protocols.md)**.

Tests :

```bash
swift test
```

## Dépannage

**« La clé n'est pas détectée »** — commence par Réglages → *YubiKey* → **Carte à puce**. Si
elle est *Non accessible*, le processus ne voit aucun lecteur : soit aucune clé n'est
branchée, soit la copie lancée n'a pas l'entitlement carte à puce — c'est le cas de tout
binaire non signé, `swift run` compris. L'app produite par `Scripts/build-app.sh` l'a.

**« Le Touch ID ne fait rien »** — la vue biométrique doit être dans une fenêtre et le
panneau capable de prendre le focus clavier pendant le prompt. C'est le cas dans l'app
construite ; en revanche `swift test` ne peut pas parler à la clé (binaire de test non
signé), d'où le drapeau `-confirm` qui exerce le vrai parcours :

```bash
open build/YubicoNotch.app --args -confirm
```

**Voir ce qui se passe** — tout est journalisé dans le log unifié :

```bash
log show --last 2m --predicate 'subsystem == "app.yubiconotch"' --style compact
```

## Soutenir

Cette app est écrite pour être utile, pas pour vendre quoi que ce soit : pas de compte, pas
de télémétrie, pas de version « pro ». Si elle te fait gagner du temps chaque jour, tu peux
m'offrir un café — ça finance les prochaines nuits passées à comprendre pourquoi macOS fait
ce qu'il fait.

<p align="center">
  <a href="https://buymeacoffee.com/millianlmx"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-millianlmx-ffdd00?logo=buymeacoffee&logoColor=black" alt="Buy Me a Coffee"></a>
</p>

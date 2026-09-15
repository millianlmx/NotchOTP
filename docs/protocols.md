# Protocoles

Ce que l'app envoie à la clé, ce qu'elle en reçoit, et ce qu'elle refuse d'avaler.

## Ce qui vit sur la clé

Une YubiKey expose une **applet OATH** : une petite base d'identifiants, chacun étant un
secret plus des métadonnées.

| Champ | Rôle |
| --- | --- |
| id | identifiant du credential sur la clé. Yubico le dérive de l'émetteur et du nom : renommer un compte **change son id** |
| issuer / name | le libellé. C'est tout ce que l'app lit sans autorisation |
| type | TOTP (période 30 ou 60 s) ou HOTP (compteur) |
| algorithm | SHA-1, SHA-256 ou SHA-512 |
| digits | 6 ou 8 |
| requiresTouch | la clé exigera un contact physique pour calculer ce code |

Le secret ne sort jamais : la clé calcule, l'app reçoit un code à six ou huit chiffres.

## Le transport

La YubiKey se présente comme un **lecteur de cartes à puce** (`system_profiler
SPSmartCardsDataType` la liste sous « Yubico YubiKey OTP+FIDO+CCID »). macOS l'expose via
`TKSmartCardSlotManager` ; YubiKit ouvre un `USBSmartCardConnection` puis sélectionne
l'applet OATH (`OATHSession.makeSession`). Tout le reste est du TLV par APDU.

Point d'attention : si `TKSmartCardSlotManager.default` est `nil` — aucune clé branchée, ou
processus sans l'entitlement carte à puce — YubiKit fait un `assertionFailure` (trap en
build debug) avant de jeter une erreur qui parle de « modèle de clé non supporté », ce qui
envoie sur une fausse piste. `USBYubiKeyConnector.connect()` teste donc le slot manager
**avant** d'appeler YubiKit, et jette `OATHFailure.readerUnavailable`, que le service traite
comme l'état de repos (aucune bannière d'erreur).

## Les commandes

| Opération | CLA | INS | P1 / P2 | Données |
| --- | --- | --- | --- | --- |
| Lister les identifiants | 0x00 | **0xa1** | 0 / 0 | — |
| Calculer un code | 0x00 | **0xa2** | 0 / **0x01** | TLV nom (0x71) + challenge (0x74) |
| Calculer une réponse HMAC | 0x00 | 0xa2 | 0 / 0 | TLV nom + challenge |
| Ajouter un identifiant | 0x00 | 0x01 | 0 / 0 | TLV du credential |
| Supprimer | 0x00 | 0x02 | 0 / 0 | TLV nom (0x71) |
| Définir le mot de passe | 0x00 | 0x03 | 0 / 0 | clé + challenge + réponse |
| Réinitialiser l'applet | 0x00 | 0x04 | 0xde / 0xad | — |
| Renommer | 0x00 | 0x05 | 0 / 0 | TLV nom + issuer |

**0xa1 est la commande qui compte** : elle liste les identifiants **sans calculer un seul
code**. C'est elle qui rend possible le modèle « aucun code sans autorisation » — et la
raison pour laquelle YubicoNotch n'utilise jamais `calculateCredentialCodes()`, qui
calculerait tout d'un coup.

## Le calcul d'un code

`0xa2` avec P2 = 1, en deux TLV :

```
nom (0x71) : l'identifiant du credential
challenge (0x74) :
    TOTP → temps_unix / période, en UInt64 big-endian
    HOTP → vide (la clé incrémente son compteur)
```

Réponse : un TLV (0x75) dont **le premier octet est le nombre de chiffres**, suivi du code
tronqué en UInt32 big-endian, que la clé a déjà formaté selon le nombre de chiffres.

La clé **n'a pas d'horloge** : c'est l'app qui passe l'horodatage. Les fenêtres TOTP sont
donc alignées sur l'epoch, ce qui permet d'afficher un compte à rebours juste sans jamais
avoir calculé le code (`CodeClock.window(period:now:)`).

Un credential `requiresTouch` fait attendre la commande jusqu'au contact physique : c'est la
phase `reading`, que l'interface annonce par « Touche la clé ».

## Le mot de passe de l'applet

L'applet OATH peut être protégée. Le mot de passe ne circule jamais tel quel : il est dérivé
par **PBKDF2** en une clé d'accès, et la commande `0x03` échange un défi/réponse. Tant que
l'applet est fermée, toute lecture répond `securityConditionNotSatisfied`, que l'app traduit
en `OATHFailure.passwordRequired`.

YubicoNotch stocke le **mot de passe** (pas la clé dérivée) dans le trousseau de session, et
le rejoue pour rouvrir l'applet. Le trousseau protégé par biométrie
(`SecAccessControl` + `kSecUseDataProtectionKeychain`) n'est pas utilisable ici : il exige
une app signée avec un profil et renvoie `errSecMissingEntitlement` (-34018) sur une
signature ad hoc. Compromis assumé, et documenté : ce mot de passe seul est inutile sans la
clé physique.

## `otpauth://`

L'URI standard des authentificateurs :

```
otpauth://totp/Emetteur:compte?secret=BASE32&issuer=Emetteur&algorithm=SHA1&digits=6&period=30
otpauth://hotp/compte?secret=BASE32&counter=0
```

Le parsing de YubicoNotch (`NewCredential.parse`) est **écrit à la main, sans
`URLComponents`** : re-encoder un secret, c'est le casser, et une URI peut arriver d'un QR
code imparfait.

- dans la *query*, `+` se décode comme un espace (jamais valide en base32) ; dans le *label*
  (le chemin), `+` reste littéral ;
- l'émetteur et le compte se séparent sur le **`:` brut, avant tout décodage** : un `%3A`
  reste donc une donnée, pas un séparateur ;
- l'ordre de validation est : schéma → hôte (`totp`/`hotp`, sinon `unsupportedType`) →
  secret → algorithme → chiffres → période/compteur → nom. Un type inconnu gagne donc sur
  un secret invalide, et le message le dit ;
- `requiresTouch` vaut toujours `false` au parsing (ça se règle dans le formulaire), et
  l'algorithme par défaut est SHA-1 ;
- le garde-fou « au moins 10 octets de secret » n'existe que dans `fromForm` (saisie
  manuelle), pas dans `parse` : un QR code qui déclare un secret court est accepté tel quel.

## Base32

Décodeur RFC 4648 maison (`Core/Base32.swift`), insensible à la casse, qui ignore espaces,
retours à la ligne et tirets — les secrets sont souvent recopiés par groupes :

- un padding présent doit **fermer un groupe de 8** : `MZXW6===` passe, `MZXW6=` renvoie
  `nil` même si les bits résiduels sont nuls ;
- après extraction des octets, il doit rester 0 à 4 bits résiduels, **et ils doivent être
  nuls** : `MZXW7` renvoie `nil` ;
- une entrée vide donne `Data()` vide. Ce sont les appelants qui refusent : `fromForm` exige
  au moins 10 octets, parce qu'un secret plus court n'est pas un secret.

## Ce que l'app voit, à chaque instant

| Moment | Ce que l'app a en main |
| --- | --- |
| panneau fermé | rien : la clé n'est pas sollicitée |
| panneau ouvert | les noms des comptes (applet ouverte) — aucun code |
| confirmation en cours | rien de plus |
| après le geste | **un** code, celui du compte confirmé, et il disparaît à la fin de sa fenêtre |
| verrouillé | rien : la session est fermée, la liste est effacée |

Le presse-papiers est vidé après le délai choisi, et seulement si le code copié s'y trouve
encore — un texte copié entre-temps n'est jamais touché.

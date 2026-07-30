# Installer Limits depuis un PC Windows **ARM64**

`INSTALL-IPHONE.md` décrit la voie normale : iTunes + Sideloadly, en USB. Elle suppose le
pilote noyau Apple `usbaapl64.sys`, qui n'existe qu'en x64 — **Windows on ARM n'émule pas les
pilotes noyau**. Sur un Vivobook S 15 (Snapdragon X Plus), Sideloadly se lancera et ne verra
jamais l'iPhone.

Ce document décrit la voie de contournement. **L'idée en une phrase** : faire faire le travail
à Linux, où le dialogue avec l'iPhone passe par `usbmuxd`, un démon en **espace utilisateur**
— aucun pilote noyau Apple requis, donc l'architecture ARM64 cesse d'être un problème.

```
iPhone ──USB──> Windows ARM64 ──usbipd (USB/IP)──> WSL2 Ubuntu arm64
                                                        │
                                                   usbmuxd (userspace)
                                                        │
                                                  Sideloader (signe avec
                                                   ton Apple ID gratuit)
                                                        │
                                        ┌───────────────┴───────────────┐
                                   SideStore.ipa                   Limits.ipa
                                (une seule fois)              (puis via SideStore,
                                                               sans PC, tous les 7 j)
```

## État de chaque maillon — vérifié le 2026-07-30

| Maillon | Statut | Ce qu'il faut savoir |
|---|---|---|
| **usbipd-win** | ✅ solide | v5.3.0 (2025-10-11) publie officiellement `usbipd-win_5.3.0_arm64.msi`. Le support ARM64 n'est plus expérimental. |
| **WSL2 + Ubuntu arm64** | ✅ standard | Non installé sur la machine aujourd'hui. Demande les droits administrateur. |
| **usbmuxd / libimobiledevice** | ✅ standard | Paquets Ubuntu. C'est le maillon qui rend l'ARM64 non pertinent. |
| **Sideloader** (Dadoum) | ⚠️ pre-release | `1.0-pre4` (2024-10-01) fournit `sideloader-cli-aarch64-linux-gnu.zip`. Dépôt **actif** (dernier push 2026-02-12, ~980 ★). C'est le signeur : il échange ton Apple ID contre un certificat de développement gratuit. |
| **SideStore** | ✅ très actif | `0.6.3` (2026-05-05), dépôt poussé le 2026-07-29. C'est lui qui **supprime le pèlerinage hebdomadaire** : après un setup initial par PC, il se re-signe sur l'appareil via un tunnel local. |
| ~~AltServer-Linux~~ | ❌ écarté | Dernière release **2022-04-17**, et son README liste toujours « Support Wi-Fi Refresh » en TODO. Il ne réglait donc pas le renouvellement, contrairement à ce qu'affirmait une première version de `INSTALL-IPHONE.md` §0. |

> **Aucun de ces maillons n'a été exécuté sur cette machine.** Le guide décrit ce que les
> sources officielles documentent ; chaque étape a un **point de contrôle** explicite pour
> s'arrêter net dès que la réalité diverge, plutôt que d'empiler des installations.

## Ce qui reste vrai malgré le contournement

Les limites du compte Apple gratuit ne changent pas : signature valable **7 jours**,
**3 apps** sideloadées maximum, ~**10 App IDs / 7 jours**. Limits en consomme **2** (l'app +
l'extension widget), SideStore **1** : on reste dans les clous.

**Tu saisis ton Apple ID et ton mot de passe toi-même**, dans l'outil, jamais dans une
conversation avec un agent. Avec la 2FA, prévois un **mot de passe d'application**
(https://account.apple.com → Connexion et sécurité).

---

## Étape 1 — WSL2 et Ubuntu *(administrateur, ~10 min + redémarrage)*

```powershell
wsl --install -d Ubuntu
```

Redémarrer, puis créer l'utilisateur Linux quand Ubuntu s'ouvre.

**Point de contrôle** : `wsl -l -v` affiche `Ubuntu … Running … 2` (la version **2** est
indispensable — l'USB/IP ne fonctionne pas en WSL 1).

## Étape 2 — usbipd-win *(administrateur, ~5 min)*

Télécharger **`usbipd-win_5.3.0_arm64.msi`** — bien la variante `arm64` — depuis
https://github.com/dorssel/usbipd-win/releases/latest et l'installer.

**Point de contrôle** : dans PowerShell, `usbipd list` répond et montre une liste
d'appareils.

## Étape 3 — Passer l'iPhone dans Linux

Brancher l'iPhone, **« Se fier à cet ordinateur »**, puis dans PowerShell **administrateur** :

```powershell
usbipd list
```

Repérer la ligne « Apple … iPhone » et noter son `BUSID` (ex. `2-4`), puis :

```powershell
usbipd bind --busid 2-4
usbipd attach --wsl --busid 2-4
```

`bind` ne se fait qu'une fois par appareil ; `attach` est à refaire **à chaque
rebranchement** (et après un redémarrage).

**Point de contrôle**, côté Ubuntu :

```bash
lsusb | grep -i apple
```

L'iPhone doit apparaître. S'il n'apparaît pas, inutile de continuer : c'est là que la
chaîne casse, et c'est une information nette à me remonter (avec la sortie de `usbipd list`).

## Étape 4 — Parler à l'iPhone depuis Linux

```bash
sudo apt update
sudo apt install -y usbmuxd libimobiledevice6 libimobiledevice-utils unzip
sudo systemctl start usbmuxd
idevice_id -l
```

**Point de contrôle — c'est LE test qui remplace A0** : `idevice_id -l` doit afficher l'UDID
de l'iPhone (une longue chaîne hexadécimale). Si oui, **le blocage ARM64 est contourné** :
tout ce qui suit est du sideload ordinaire.

En cas d'échec, `idevicepair pair` puis déverrouiller l'iPhone et accepter la demande de
confiance. Si `usbmuxd` ne voit rien alors que `lsusb` montre l'appareil, l'exécuter au
premier plan pour voir les erreurs : `sudo usbmuxd -f -v`.

> ⚠️ **Ne colle jamais l'UDID dans une conversation ni dans un commit** — c'est un
> identifiant d'appareil, et le dépôt est public. « `idevice_id -l` renvoie bien un UDID »
> suffit comme retour.

## Étape 5 — Installer SideStore *(une seule fois)*

Récupérer le signeur et l'IPA de SideStore :

```bash
# Sideloader CLI pour Linux arm64 (pre-release 1.0-pre4)
wget https://github.com/Dadoum/Sideloader/releases/download/1.0-pre4/sideloader-cli-aarch64-linux-gnu.zip
unzip sideloader-cli-aarch64-linux-gnu.zip && chmod +x sideloader

# SideStore 0.6.3
wget https://github.com/SideStore/SideStore/releases/latest/download/SideStore.ipa
```

Puis :

```bash
./sideloader install SideStore.ipa -i
```

L'outil demande l'**Apple ID** et le **mot de passe** (ou le mot de passe d'application si
2FA) : tu les saisis directement dans le terminal.

Sur l'iPhone, ensuite : Réglages → **Général → VPN et gestion de l'appareil** → faire
confiance au profil, et Réglages → **Confidentialité et sécurité → Mode développeur** →
activer (redémarrage).

**Point de contrôle** : SideStore s'ouvre sur l'iPhone.

## Étape 6 — Le fichier de pairing *(ce qui libère du PC)*

SideStore a besoin d'un fichier `.mobiledevicepairing` pour piloter l'appareil sans PC.
Deux façons de l'obtenir :

- avec Sideloader : `./sideloader tool run 0` ;
- ou avec `idevice_pair`, l'outil officiel de SideStore, en build **AArch64** — voir
  https://docs.sidestore.io/docs/advanced/pairing-file (SideStore n'accepte que le format
  `.mobiledevicepairing`).

Transférer le fichier sur l'iPhone et l'importer dans SideStore, puis activer **StosVPN**
(le tunnel local que SideStore utilise pour se rafraîchir seul ; il ne fait sortir aucun
trafic de l'appareil).

**Point de contrôle** : dans SideStore, l'appareil est appairé et le bouton « Refresh »
fonctionne **sans PC connecté**.

## Étape 7 — Installer Limits

Récupérer `Limits.ipa` depuis la
[Release v1.0](https://github.com/TristeTemps78/Limits/releases/tag/v1.0), le mettre sur
l'iPhone (Fichiers / AirDrop / partage réseau), puis dans SideStore : **+** → choisir
`Limits.ipa`.

⚠️ **Vérifier tout de suite que le widget est là** : appui long sur l'écran d'accueil → `+` →
« Limits ». Il doit y avoir **deux** widgets (« Limites d'usage » et « Diagnostic App
Group »). S'il n'y en a aucun, l'extension a sauté à la signature — c'est le point d'inconnue
de cette voie : SideStore signe l'app **et** son extension, mais nous ne l'avons jamais
vérifié sur un bundle contenant un widget. Sans widget, rien du protocole de test n'a de sens.

Enchaîner alors sur `TEST-PLAN.md`, à partir de **A1**.

## Ce que cette voie change au protocole de test

- **A0** n'est plus « installer iTunes + Sideloadly » mais l'étape 4 ci-dessus : `idevice_id -l`
  renvoie-t-il un UDID ?
- **C1** (« l'auto-refresh Sideloadly Wi-Fi a-t-il marché ? ») devient : **SideStore a-t-il
  re-signé Limits tout seul avant l'expiration des 7 jours ?** C'est mieux que la voie
  d'origine — plus de PC à laisser allumé sur le même réseau.
- **C2** est inchangé et reste le juge du gate M1 : après re-signature, le compteur du widget
  suit-il toujours celui de l'app ?

## Si la chaîne casse

| Où ça casse | Ce que ça veut dire | Repli |
|---|---|---|
| `usbipd attach` échoue | WSL 1, ou pilote non chargé | vérifier `wsl -l -v`, réinstaller le MSI **arm64** |
| `lsusb` ne voit pas l'iPhone | l'USB/IP ne passe pas | changer de câble/port (USB-A vs USB-C), refaire `bind` |
| `idevice_id -l` vide | `usbmuxd` ne dialogue pas | `sudo usbmuxd -f -v` et lire l'erreur ; refaire `idevicepair pair` |
| `sideloader install` échoue à l'authentification | 2FA / anisette | mot de passe d'application ; sinon c'est la limite connue d'une pre-release de 2024 |
| SideStore installe mais pas de widget | l'extension n'est pas signée | tenter `./sideloader install Limits.ipa -i` en direct (sans SideStore) : on perd le refresh sans PC, on garde le test |
| Tout échoue | — | PC x64 emprunté (`INSTALL-IPHONE.md` §0, voie 1) |

Sources : [usbipd-win](https://github.com/dorssel/usbipd-win) ·
[WSL — connecter des périphériques USB](https://learn.microsoft.com/en-us/windows/wsl/connect-usb) ·
[Sideloader](https://github.com/Dadoum/Sideloader) ·
[SideStore](https://github.com/SideStore/SideStore) ·
[SideStore — fichier de pairing](https://docs.sidestore.io/docs/advanced/pairing-file)

# Installer Limits sur iPhone — sans Mac, sans compte développeur payant

> Remplace la vidéo YouTube « Impactor » de 2019 : **Cydia Impactor est mort**. La
> méthode actuelle : IPA non signée produite par GitHub Actions → **Sideloadly** sur
> Windows la signe avec ton Apple ID gratuit et l'installe.

## Ce qu'il faut savoir avant (limites du compte gratuit — non contournables)

- L'app est signée pour **7 jours**. Après, elle refuse de se lancer tant qu'elle n'est
  pas re-signée (les données restent). Sideloadly sait re-signer **automatiquement en
  Wi-Fi** si le PC est allumé sur le même réseau.
- Maximum **3 apps sideloadées** en même temps ; ~**10 App IDs / 7 jours** (Limits en
  consomme 2 : app + extension widget).
- **Pas de notifications push serveur** — Limits n'utilise que des notifications
  locales, donc tout fonctionne.

## 1. Préparer le PC (une seule fois)

1. Installer **iTunes** et **iCloud** en version « classique » téléchargée depuis
   apple.com (pas les versions Microsoft Store — Sideloadly les gère mal).
2. Installer **Sideloadly** : https://sideloadly.io/ (Windows 64-bit).
3. Conseil compte : avec la 2FA Apple, Sideloadly peut demander un **mot de passe
   d'application** — à générer sur https://account.apple.com (Connexion et sécurité →
   Mots de passe d'app). **Tu saisis ton Apple ID toi-même dans Sideloadly ; ne le
   donne jamais à un agent/IA.**

## 2. Récupérer l'IPA

- Depuis GitHub : onglet **Actions** → dernier run vert → artefact `Limits-ipa`,
  ou **Releases** → `Limits.ipa` de la dernière version.
- En CLI : `gh run download --name Limits-ipa` dans le repo.

## 3. Installer

1. Brancher l'iPhone en USB → « Se fier à cet ordinateur » sur le téléphone.
2. Ouvrir Sideloadly : choisir l'iPhone, entrer l'Apple ID, glisser `Limits.ipa`.
3. **Ne pas cocher la suppression des PlugIns/extensions** (le widget est une
   extension — s'il est retiré, pas de widgets).
4. `Start`, saisir le mot de passe (ou mot de passe d'app) quand demandé.

## 4. Autoriser sur l'iPhone (première fois)

1. Réglages → **Général → VPN et gestion de l'appareil** → profil développeur (ton
   Apple ID) → **Faire confiance**.
2. iOS 16+ : Réglages → **Confidentialité et sécurité → Mode développeur** → activer
   (redémarrage demandé).
3. Lancer Limits, se connecter à Claude puis Codex, poser les widgets : appui long sur
   l'écran d'accueil → `+` → Limits (et sur l'écran verrouillé : personnaliser →
   widgets).

## 5. Renouvellement hebdomadaire

Dans Sideloadly : activer **Wi-Fi sideload / auto-refresh** (menu réglages). Tant que le
PC est allumé sur le même Wi-Fi au moins une fois par semaine, la re-signature est
automatique. Sinon : rebrancher l'USB et refaire l'étape 3 (2 min, données conservées).

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| « Unable to verify app » au lancement | certificat expiré (7 j) | re-signer via Sideloadly |
| Widget absent de la galerie | extensions retirées à l'install | réinstaller sans supprimer les PlugIns ; sinon essayer AltStore |
| Widget vide alors que l'app a des données | App Group cassé par la re-signature | cf. gate M1 dans TASKS.md — remonter l'info, fallback AltStore |
| Erreur Apple ID dans Sideloadly | 2FA | mot de passe d'application (cf. §1.3) |
| « Developer Mode required » | iOS 16+ | activer le Mode développeur (cf. §4.2) |
| Plus de 10 App IDs | trop d'installs dans la semaine | attendre l'expiration (7 j glissants) |

Alternative si Sideloadly pose problème : **AltStore** (AltServer pour Windows,
https://altstore.io) — même principe, gère bien les app groups, refresh Wi-Fi aussi.

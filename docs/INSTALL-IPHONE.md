# Installer Limits sur iPhone — sans Mac, sans compte développeur payant

> Remplace la vidéo YouTube « Impactor » de 2019 : **Cydia Impactor est mort**. La
> méthode actuelle : IPA non signée produite par GitHub Actions → **Sideloadly** sur
> Windows la signe avec ton Apple ID gratuit et l'installe.

## 0. ⚠️ Prérequis : le PC doit être **x64**, pas ARM64

**Le PC de Tristan est un ASUS Vivobook S 15 (Snapdragon X Plus, Windows 11 ARM64) — la
méthode décrite ci-dessous n'y fonctionnera très probablement pas.** Le problème n'est pas
Sideloadly, c'est la couche en dessous :

- parler à un iPhone en USB passe par le pilote **Apple Mobile Device USB** (`usbaapl64.sys`),
  installé par iTunes / l'app Apple Devices ; c'est un **pilote noyau** ;
- Windows on ARM émule les **applications** x64, **jamais les pilotes noyau** ;
- Apple n'a pas compilé les siens pour ARM64.

Conséquence : Sideloadly peut se lancer (application x64, émulée), mais l'iPhone ne sera pas
détecté. Et **le repli « tout en Wi-Fi » n'en est pas un** : la FAQ Sideloadly impose un
premier appairage **par USB** avant tout sideload sans fil.

> Statut : **fortement probable, pas encore constaté sur cette machine**. Le test qui tranche
> est en tête du protocole (`TEST-PLAN.md`, test **A0**) et prend 15 minutes.

### Les trois voies possibles

| Voie | Ce que ça coûte | Ce que ça règle — et ce que ça ne règle pas |
|---|---|---|
| **1. Un PC x64** (autre machine, prêt d'un proche) | rien à installer d'exotique, chemin documenté ci-dessous | Règle l'installation. **Ne règle pas le renouvellement** : le certificat gratuit expire tous les 7 jours et il faut ce PC à chaque fois, ou une re-signature manuelle hebdomadaire (cf. §5). |
| **2. WSL2 + `usbipd-win` + AltServer-Linux** sur l'ARM64 | installations système, droits admin, montage à faire | Contourne exactement le point de blocage : côté Linux, `usbmuxd` parle à l'iPhone **en espace utilisateur** (libusb), sans pilote noyau Apple. `usbipd-win` annonce le support **Windows 10/11 ARM64**, et AltServer-Linux publie des binaires **aarch64**. Permet aussi le renouvellement automatique depuis la même machine. ⚠️ Dernière release d'AltServer-Linux : **2024-04-17** — non vérifiée avec les iOS récents, et jamais testée ici. |
| **3. Renoncer au sideload** | — | Le code reste juste et testé, mais rien ne sera jamais prouvé sur device : le gate M1 resterait ouvert indéfiniment. |

Sources : [Sideloadly FAQ](https://sideloadly.io/faq.html) ·
[Microsoft Q&A — pilotes Apple et ARM64](https://learn.microsoft.com/en-us/answers/questions/3863362/apple-usb-tethering-is-not-working-on-my-windows11) ·
[usbipd-win (prérequis système)](https://github.com/dorssel/usbipd-win/blob/master/README.md) ·
[AltServer-Linux (releases)](https://github.com/NyaMisty/AltServer-Linux/releases)

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

## 6. Le test de dérisquage (gate M1) — 5 min, à faire au premier lancement

> Ce paragraphe reste la référence du gate M1. Il est le **test A2** du protocole complet
> `TEST-PLAN.md`, qui enchaîne ensuite les 6 autres critères (logins réels, dashboard,
> widgets, arrière-plan, notifications, J+7). Commence par là si tu viens de sideloader.

C'est **le** test qui décide de l'architecture du projet. Avec un Apple ID gratuit, les
App Groups ne sont pas créables dans le portail développeur et Sideloadly **remappe** les
identifiants à la re-signature : rien ne garantit a priori que l'app et le widget partagent
encore des données. L'app embarque donc un écran de diagnostic dédié.

**Réglages → Diagnostic App Group.** L'écran écrit une valeur horodatée avec un compteur
par **trois canaux indépendants**, puis affiche ce qu'il relit de chacun.

Ensuite : pose le widget « Diag App Group » sur l'écran d'accueil, appuie sur « Écrire
maintenant » dans l'app, et compare.

> **Le signal qui compte est la comparaison du compteur entre l'app et le widget.**
> Le widget ne fait **que lire**, jamais écrire : s'il affiche le numéro que l'app vient
> d'écrire, le partage inter-processus est réellement prouvé. À l'inverse,
> `UserDefaults(suiteName:)` ne renvoie **pas** `nil` quand l'entitlement manque sur iOS —
> il crée silencieusement un domaine isolé au processus. Ce canal peut donc afficher
> « écriture réussie » des deux côtés alors que rien n'est partagé. Ne te fie pas à
> l'absence d'erreur, fie-toi au compteur.

### Grille de lecture des messages

| Message affiché | Ce que ça veut dire |
|---|---|
| `Conteneur App Group introuvable (containerURL nil — entitlement perdu ?)` | **Le cas redouté.** L'entitlement App Group n'a pas survécu à la re-signature → verdict de gate négatif, on bascule sur « le widget fetch lui-même ». |
| `Fichier absent (…) — jamais écrit ou supprimé` | Le conteneur existe mais rien n'y a encore été écrit : appuie sur « Écrire maintenant » dans l'app d'abord. **Ce n'est pas un échec de l'App Group.** |
| `Clé absente — jamais écrite` | Idem pour le canal `UserDefaults` ; côté widget, ça signifie qu'il lit son **propre** domaine isolé → App Group probablement non partagé. |
| `JSON illisible/corrompu` | Écriture interrompue. Réessaie une écriture ; si ça persiste, signale-le. |
| `Entitlement Keychain manquant (errSecMissingEntitlement) — access group perdu à la re-signature` | Le partage Keychain est cassé. Non bloquant pour la v1 (les widgets n'ont pas besoin de token), mais à signaler. |
| `Item Keychain absent (errSecItemNotFound)` | Jamais écrit — écris d'abord depuis l'app. |
| `Accès refusé avant déverrouillage (errSecInteractionNotAllowed)` | Déverrouille l'iPhone puis réessaie ; l'item est censé être accessible après le premier déverrouillage. |

### Ce que j'attends comme retour

1. L'app démarre-t-elle ?
2. Les widgets sont-ils **posables** (écran d'accueil **et** écran verrouillé) ?
3. Le compteur affiché par le widget correspond-il à celui de l'app après « Écrire
   maintenant » puis « Recharger les timelines » ?
4. La ligne Keychain du widget affiche-t-elle une valeur ou une erreur ?
5. Après une re-signature (J+7 ou forcée), les données sont-elles conservées ?

La suite du protocole (logins, dashboard, widgets, arrière-plan, re-signature à J+7) est
dans `TEST-PLAN.md`, séances A à C.

Si le point 3 échoue, l'architecture bascule — c'est prévu et pré-câblé (le widget lit à
travers une abstraction, `SnapshotSource`), donc ça ne remet pas en cause le reste du code.

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

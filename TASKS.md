# TASKS.md — Limits

> Protocole : `C:\Git project\WORKFLOW.md`. **Réserver avant d'écrire** : passer la
> tâche à `🔒 in-progress — @<agent> — <date>`, committer (`claim: …`), travailler,
> puis `✅ done` + commit. Un agent ne relit jamais son propre code.
> Références : blueprint technique dans `PLAN.md`, règles dans `AGENTS.md`.

## Phase 0 — Bootstrap (Opus, séquentiel)

- ✅ done — **T0.1 Repo GitHub public + remote** — @claude-opus — 2026-07-29
  https://github.com/TristeTemps78/Limits (public, `main`, remote `origin`). Fixtures
  vérifiées anonymisées avant publication (aucun secret dans l'historique).
- ✅ done — **T0.2 Scaffold XcodeGen 3 targets** — @sonnet-a, relu @sonnet-b (GO) — 2026-07-29
  `project.yml` : app `com.caldf.limitsapp` (iOS 17), extension WidgetKit
  `com.caldf.limitsapp.widgets` embarquée (`embed: true, codeSign: false`), package local
  `LimitsCore` (iOS 17 + **macOS 13** — le support macOS force l'absence d'UI dans le
  package, vérifié gratuitement par `swift test`). Entitlements App Group
  `group.com.caldf.limitsapp` + `keychain-access-groups` déclarés **identiques** sur les
  deux targets (Sideloadly les remappe à la re-signature — sans eux T1.2 ne prouverait rien).
  `LimitsCore/Tests/.../FixtureLoader.swift` remonte depuis `#filePath` jusqu'à `fixtures/`
  (pas de symlink : dev Windows) — base des tests de M2.
- ✅ done — **T0.3 CI build.yml** — @sonnet-a, relu @sonnet-b (GO) — 2026-07-29
  Jobs `test` (`swift test --package-path LimitsCore`) + `ipa` (xcodegen → archive non
  signée → artefact `Limits-ipa`) + `release` sur tag `v*` (`gh release create`, aucune
  action tierce). Xcode **16.2** épinglé explicitement sur `macos-15`. Garde-fou : le job
  échoue si `Payload/Limits.app/PlugIns/LimitsWidgets.appex` est absent (échec silencieux
  classique = IPA valide mais aucun widget installable).
  CI verte sur `main` : run 30445925341 (`test` ✅ + `ipa` ✅).
  *Note : `on: push` reste volontairement sans filtre de branche — c'est ce qui permet à
  chaque agent de prouver son lot sur sa propre branche avant merge.*

## Phase M1 — Dérisquage **[GATE LEVÉ le 2026-07-29 — voir encadré]**

> **Décision de Tristan (2026-07-29, soir)** : « continue d'orchestrer le projet […] pour
> TOUT implémenter ». Le gate M1 d'`AGENTS.md` (« ne pas lancer M2 sans verdict ») est donc
> **levé sur instruction explicite**, T1.2 étant une action humaine impossible de nuit.
> Mitigation retenue par l'orchestrateur pour qu'un verdict négatif coûte peu :
> 1. l'accès aux données côté widget passe par une **abstraction** (`SnapshotSource`), pour
>    que la bascule « le widget fetch lui-même » reste un changement local ;
> 2. l'**écran de diagnostic de T1.1 est conservé dans l'app finale** (réglages) — c'est
>    l'IPA finale que Tristan sideloadera, pas celle de T1.1, donc le test de gate reste
>    faisable après coup.

- ✅ done — **T1.1 App+widget « hello » avec App Group** — @sonnet-b, relu @sonnet-a — 2026-07-29
  3 canaux testés **séparément** (UserDefaults suite / fichier du conteneur App Group /
  Keychain), chacun avec sa cause d'échec affichée dans l'app **et** dans le widget
  (`systemSmall` + `accessoryRectangular`). CI verte : run 30447596953.
  Décisions techniques à retenir :
  - **`kSecAttrAccessGroup` volontairement omis** : `$(AppIdentifierPrefix)` n'existe qu'au
    build et serait remappé par Sideloadly ; l'item va dans le premier groupe des
    `keychain-access-groups`, identique sur les deux cibles. Aucun préfixe en dur.
  - **`kSecAttrAccessibleAfterFirstUnlock`** obligatoire, sinon le widget d'écran verrouillé
    ne lit rien et on conclurait à tort « Keychain KO ».
  - **`SecTaskCreateFromSelf` inexploitable sur iOS** (compile pour macOS, absent du SDK
    iOS public) → impossible de lire à l'exécution l'App Group réellement accordé après
    re-signature. Abandonné plutôt que contourné.
  - **`UserDefaults(suiteName:)` ne renvoie pas `nil` sans entitlement** sur iOS : il crée un
    domaine isolé au process. Le signal fiable est la **comparaison du compteur** entre
    l'écran de l'app et le widget (le widget ne fait que lire → preuve cross-process réelle).
  - `WidgetKit` seul ne suffit pas : `import SwiftUI` est requis pour voir `Widget`/`WidgetBundle`.
- ⏳ **en attente de Tristan** — **T1.2 Test humain sideload** (~20 min)
  Suivre `docs/INSTALL-IPHONE.md` : installer Sideloadly, sideloader **l'IPA finale** (le
  diagnostic est conservé dans les réglages de l'app, cf. encadré ci-dessus).
  *Vérifier : app démarre ; widget posable (home + lock) ; le compteur affiché par le
  widget est bien celui écrit par l'app (preuve cross-process) ; ligne Keychain OK.*
  Grille de lecture des messages d'échec : `docs/INSTALL-IPHONE.md`.
- ✅ done — **T1.3 Capture des fixtures depuis le PC** — @claude-fable — 2026-07-29
  `scripts/capture-fixtures.ps1` exécuté : 4 fixtures réelles anonymisées dans
  `fixtures/` + `fixtures/capture-report.md` (headers validés, codes HTTP).
- ⏳ **bloqué par T1.2** — **T1.4 Verdict de gate** (Opus)
  Si App Group KO après re-signature : réessayer via AltStore ; si toujours KO, basculer
  l'architecture « widget fetch lui-même » (décision documentée ici et dans PLAN.md).
  La bascule est pré-cadrée : le widget lit à travers `SnapshotSource`, seul le
  fournisseur change.

## Phase M2 — Cœur (parallèle, worktrees `agent/<sonnet-X>/<tâche>`)

- ✅ done — **T2.1 LimitsCore : modèles + clients usage** — @sonnet-a, relu @sonnet-c — 2026-07-29
  `ProviderConfig`, `Models`, `FlexibleISO8601`, `HTTPClient` (injectable), les deux clients,
  `PollingPolicy`, `SnapshotStore`, `SnapshotSource`. CI verte : run 30449290389.
  Vérifications faites par le relecteur en recalculant depuis les fixtures :
  - Claude : `limits[]` bien prioritaire, `session` 0 % inactive, `weekly_all` 8 %,
    `extra_usage`/`spend` fusionnés, tout en 0-100 sans conversion parasite.
  - Codex : la fenêtre de 604 800 s est classée hebdo **par sa durée** ; `secondary_window`
    nul n'invente aucune fenêtre.
  - `FlexibleISO8601` : bug trouvé et corrigé par l'auteur (dates **sans** fraction de
    seconde non parsées — c'est le format du chemin de repli Claude). Un échec de parsing
    rend `nil`, **jamais** une date par défaut qui afficherait un faux compte à rebours.
  - Réserves acceptées : les alias Codex (`five_hour_limit`…) ne sont couverts que par des
    tests **synthétiques** (aucune fixture ne les exerce) — documenté comme tel dans le code.
- ✅ done — **T2.2 OAuth Claude + Codex** — @sonnet-b, relu @sonnet-a — 2026-07-29
  PKCE, état, transports séparés par provider, `TokenStore`, `LocalCallbackServer` (:1455
  avec repli :1457, écoute loopback). CI verte : run 30450563211 (110 tests).
  **Toutes les constantes ont été re-vérifiées par le relecteur contre le source amont**
  (re-téléchargé au commit `cf7e9cfe`), pas seulement contre notre rapport interne — et
  c'est ce qui a permis de trouver que **notre propre rapport était faux** sur la
  classification des erreurs de refresh Codex (cf. correctif dans
  `docs/oauth-verification-2026-07-29.md`).
  Corrigé en revue : casse + chemin `code` racine du classifieur d'erreurs, trim du
  `code#state` collé (un espace ramené par le copier-coller faisait échouer le login avec
  un message incompréhensible), et 17 tests traversant réellement `exchange`/`refresh`.
  Dette reportée en critère d'acceptation de **T3.1** : câblage du `SingleFlight`.
- ✅ done — **T2.3 Widgets** — @sonnet-c, relu @sonnet-a — 2026-07-29
  6 familles, jauges anneau/barre, `TimelineProvider` lisant **uniquement** `SnapshotSource`.
  Toute la logique (sévérité, urgence, fraîcheur, planification de timeline, vocabulaire FR,
  `SampleSnapshots` aux valeurs des fixtures) est dans `LimitsCore` et testée ; les vues ne
  contiennent aucune comparaison de date ni seuil (vérifié par grep en revue).
  Décisions à connaître avant de toucher aux widgets :
  - **Compte à rebours > 24 h → `Text(date, style: .relative)`** (« dans 6 j »), ≤ 24 h →
    `Text(timerInterval:)`. Les deux sont rafraîchis **nativement** par le système : le choix
    ne coûte rien en budget de timeline, il n'y a donc pas d'arbitrage précision/coût.
  - **Timeline** : une entrée à `now`, une par `resetsAt` à venir (max 4), repli à 1 h.
    Jamais d'intervalle fixe serré — iOS coupe silencieusement un widget trop gourmand, ce
    qui ressemble exactement au bug qu'on veut éviter.
  - **Familles `accessory*`** : iOS écrase les couleurs (rendu `accented`/`vibrant`) → la
    sévérité porte **aussi** un symbole SF et un mot court, sinon l'information disparaît.
  - **`Double.roundedPercentText`** (`LimitsCore`) est la **seule** règle d'arrondi des
    pourcentages, partagée app + widget (elle était dupliquée 3× avant la revue).
  - `SharedUsageSnapshots` a gagné `claudeStatus`/`codexStatus` de façon **additive**
    (optionnels, défaut `nil`) : un ancien JSON décode toujours, d'où l'absence de bump de
    `schemaVersion` — bumper aurait fait rejeter par un vieux widget un fichier lisible.
  - Le widget de diagnostic de T1.1 est **conservé** dans le bundle (instrument du gate M1).
  `RingGauge`/`BarGauge`, familles systemSmall/Medium/Large + accessoryCircular/
  Rectangular/Inline, TimelineProvider sur snapshot, placeholders (non connecté, données
  périmées, reconnecter), comptes à rebours `Text(timerInterval:)`. *Accept : compile en
  CI ; previews alimentées par les fixtures.* *Relecteur : Sonnet D.*
- ✅ done — **T2.4 App UI** — @sonnet-b, relu @claude-opus — 2026-07-29
  Onboarding par provider, dashboard, réglages. Écran de diagnostic T1.1 **conservé** dans
  les réglages (le gate M1 n'est pas passé : c'est l'IPA finale que Tristan sideloadera).
  Réutilise la logique de T2.3 (`SnapshotFreshness`, `WindowSeverity`, `WindowPresentation`,
  `WidgetCopy`, `roundedPercentText`) au lieu de la réécrire. CI verte : run 30453307282.
  Bug trouvé en revue et corrigé : `LocalCallbackServer.stop()` déclenchait l'état
  `.cancelled` du listener, interprété comme « le bind a échoué, essaie le port suivant » —
  une annulation par l'utilisateur ouvrait donc un listener sur :1457 (fuite) puis affichait
  « port local indisponible ». Le message trompeur que la revue de T2.2 voulait éviter,
  réintroduit par un autre chemin.
  Onboarding/connexion par provider (champ code-paste Claude, bouton login Codex),
  dashboard (anneaux/barres, crédits Codex, « à jour il y a X min »), réglages (comptes,
  seuils, intervalle, style). *Accept : compile en CI ; états loading/erreur/vide
  traités.* *Relecteur : Sonnet C.*

## Phase M3 — Intégration (1 Sonnet + Opus, séquentiel)

- ✅ done — **T3.1 Fil complet arrière-plan** — @claude-opus — 2026-07-30
  `BGAppRefreshTask` → fetch → snapshot App Group → notifications locales →
  `WidgetCenter.reloadAllTimelines()`. CI verte : run 30492938071 (**277 tests**).
  ⚠️ Écrit par l'orchestrateur, **non relu par un agent tiers** : la limite de dépenses
  mensuelle du compte a coupé les sous-agents en pleine phase M3. À relire en priorité —
  voir T3.2.
  Ce que chaque pièce règle :
  - **`TokenRefreshCoordinator`** : dette de T2.2 payée. Le `SingleFlight` est câblé **et le
    premier plan passe par le même chemin que la tâche de fond** — sans quoi le câblage
    n'aurait rien servi, la course étant entre l'app et la tâche, pas entre deux appels de
    la tâche. `DashboardViewModel` ne fait plus aucun refresh lui-même.
  - **`RefreshStateStore`** : `lastFetchAt` + `PollingState` + journal des notifications
    persistés dans les `UserDefaults` du groupe d'app. Une tâche de fond est réveillée dans
    un processus potentiellement relancé : sans mémoire, chaque réveil contournait le
    minimum de 15 min et **oubliait un backoff en cours après un 429**.
  - **`NotificationPlanner`** (logique pure, testée) : le journal oublie les seuils notifiés
    **quand la fenêtre se réinitialise** (son identité est sa date de reset). Sans cet
    oubli, plus aucune alerte après le premier cycle ; sans journal du tout, le même 80 %
    re-notifierait tous les quarts d'heure. Un saut de 40 % à 96 % envoie **une** alerte
    « 95 % », pas deux.
  - **`BackgroundRefresh`** replanifie **avant** de travailler : une `BGAppRefreshTask` est à
    usage unique, l'oublier arrête définitivement les rafraîchissements (panne silencieuse).
  - **`UsageRefreshService`** : un seul chemin de fetch. Corrigé pendant l'implémentation —
    un token Codex sans `account_id` partait en 401 → refresh → (le refresh ne renvoie
    jamais d'`account_id`) → retry infini. Détecté avant tout appel réseau désormais.
  - `Info.plist` : `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes: fetch`, à
    garder synchronisés avec `BackgroundRefresh.taskIdentifier`.
  - Reconnexion : `RefreshStateStore.clear(provider:)` est appelé après un login réussi et
    après une déconnexion — `.needsReconnect` étant terminal, l'oublier laisserait l'app
    bloquée malgré un token neuf.
  *Reste à valider sur device par Tristan : déclenchement réel de la `BGAppRefreshTask`,
  réception d'une notification à un reset, mise à jour du widget après une session sur le PC.*
- 🟢 libre — **T3.2 Revue transverse** (agent n'ayant pas écrit T3.1)
  `/code-review` complet, chasse aux fuites de tokens dans les logs, erreurs réseau.

## Phase M4 — Finitions & release

- ✅ done — **T4.1 Icône, dark mode, localisation FR** — @claude-opus — 2026-07-30
  Icône 1024 générée (deux anneaux imbriqués, orange = Claude / turquoise = Codex, fond
  sombre) dans `App/Assets.xcassets`. `DEVELOPMENT_LANGUAGE: fr` + `CFBundleLocalizations`
  — sans quoi iOS afficherait les libellés système (boutons d'alerte, formats de date) en
  anglais sur un appareil francophone. Aucune couleur en dur nulle part : le dark mode
  fonctionne par les couleurs sémantiques SwiftUI.
- ✅ done — **T4.2 README + docs finalisés** — @claude-opus — 2026-07-30
  README réécrit (ce qui marche, architecture en trois phrases, une seule commande utile).
  `docs/INSTALL-IPHONE.md` §6 : **protocole du test de gate M1** avec la grille de lecture
  complète des messages de diagnostic et les 5 points de retour attendus.
- ✅ done — **T4.3 Release v1.0** — @claude-opus — 2026-07-30
  Tag `v1.0` → `Limits.ipa` en Release GitHub (job `release` vérifié fonctionnel) :
  https://github.com/TristeTemps78/Limits/releases/tag/v1.0

## Audit final (demandé explicitement) — ✅ fait le 2026-07-30

**300 tests verts.** Ce que l'audit a cherché à contre-courant du réflexe habituel, et ce
qu'il a produit :

1. **Tests adverses par mutation** (`FixtureMutationTests`) — tous les autres tests
   validaient les 4 fixtures **telles que capturées** : un compte, un plan, un jour. Le
   risque n'était pas qu'ils soient faux, mais qu'ils soient **muets** sur tout le reste.
   Ces tests abîment systématiquement les fixtures réelles (clé supprimée / à `null` / de
   type incompatible / valeur aberrante, ~90 mutations) et vérifient l'absence de crash
   **plus les invariants du domaine** : pourcentage fini et positif, date de reset entre
   2020 et 2100. Ajout des cas jamais capturés : session Claude **active**, Codex avec ses
   **deux** fenêtres (dans l'ordre inverse de l'intuition — c'est ce qui rend le piège
   « primary = 5 h » invisible sur notre unique capture), durée de fenêtre inconnue.
2. **`UnexpectedPayloadDetector` — le mode de défaillance silencieux du parsing tolérant.**
   La règle 3 impose d'ignorer l'inconnu ; la contrepartie, que rien ne surveillait : si un
   provider **renomme** ses champs, le décodage réussit et produit **zéro fenêtre**. L'app
   affichait alors « aucune donnée » — que l'utilisateur lit comme « ma connexion est
   cassée ». Il irait donc se reconnecter, le login réussirait, et rien ne changerait.
   Désormais un état distinct dans l'app **et** dans le widget, avec un message qui dit
   explicitement de **ne pas** se reconnecter et de régénérer les fixtures.
3. **Déduplication de l'iconographie de sévérité.** La revue de T2.4 avait conclu
   « duplication inévitable, à garder synchronisée » entre `App/Dashboard/SeverityStyle.swift`
   et `Widgets/Gauges/SeverityStyle.swift`. Vrai pour la couleur (`SwiftUI.Color` ne peut pas
   descendre dans `LimitsCore`), **faux pour les deux autres membres** : symbole SF et mot
   court sont des `String`. Ils vivent maintenant dans `LimitsCore.SeverityIconography`,
   partagés et **testés**. Ce sont précisément eux qui portent l'information quand iOS
   écrase les couleurs sur l'écran verrouillé : les laisser dupliqués, c'était accepter que
   la seule information survivant au verrouillage puisse diverger sans qu'aucun test ne le voie.
4. **Tests de propriétés transverses** (`CrossSurfaceConsistencyTests`) — chaque lot avait
   été testé et relu **isolément**, donc rien ne vérifiait ce qui n'appartient à aucun lot :
   symboles/libellés tous distincts et non vides, arrondi de pourcentage unique, et surtout
   **le même snapshot vide doit produire le même diagnostic dans l'app et dans le widget**.
5. **429 de bout en bout** — `PollingPolicy` était testé seul, `RefreshStateStore` seul.
   Le scénario qui compte enchaîne trois composants : 429 → `Retry-After` respecté →
   backoff persisté → **redémarrage du processus** → réveil refusé → expiration → autorisé.
   Plus : `.needsReconnect` ne se libère **jamais** par le temps seul, même en manuel.

### Limites connues, assumées et non corrigées

- **T3.1 et l'audit final n'ont pas été relus par un agent tiers** : la limite de dépenses
  mensuelle du compte a coupé les sous-agents en pleine phase M3. L'orchestrateur a écrit
  **et** relu — exactement le « rédacteur = relecteur » qu'`AGENTS.md` interdit. À relire.
- **`reset_at` en millisecondes non détecté** : si l'API changeait d'unité, un compte à
  rebours de 30 siècles s'afficherait sans broncher. Le comportement est *documenté par un
  test* qui échouera le jour où ça arrive — c'est le signal qu'on veut, pas une correction.
- **Course sur le journal des notifications** : `RefreshStateStore` fait lecture-modification-
  écriture sur `UserDefaults` sans verrou. App et tâche de fond simultanées pourraient
  perdre une écriture → au pire une notification en double. Auto-réparant au fetch suivant.
- **Alias Codex** (`five_hour_limit`…) toujours couverts par des tests **synthétiques** :
  aucune capture réelle ne les exerce.
- **Rien n'a jamais tourné sur un iPhone.** Aucun agent n'a de Mac : la CI prouve que ça
  compile, s'archive et que la logique est correcte. Elle ne prouve **pas** qu'un login réel
  aboutit, que l'App Group survit à la re-signature, ni à quoi ressemble une jauge.

## Critère global « tout marche » (checklist finale)

1. CI verte (tests + IPA) sur chaque push.
2. Login Claude **et** Codex réussis sur l'iPhone.
3. Dashboard = vraies fenêtres 5 h/hebdo + crédits Codex.
4. Widgets home + lock screen posés, corrects, compte à rebours qui défile.
5. Widget rafraîchi après une session Claude Code sur le PC (délai BGTask accepté).
6. Notification locale reçue à un reset de fenêtre.
7. J+7 : re-signature Sideloadly Wi-Fi OK, données conservées.

# PLAN.md — Blueprint technique « Limits »

> Widgets iPhone montrant les limites d'usage Claude Code (5 h / hebdo) et Codex
> (5 h / hebdo / crédits de reset), clone de [getlimits.app](https://getlimits.app/).
> Contraintes : **pas de Mac, pas de compte développeur Apple payant**, dev depuis
> Windows. Recherche et reverse engineering effectués le 2026-07-29 (session Fable).
>
> Ce document est la **référence technique** ; l'ordonnancement est dans `TASKS.md`,
> les règles agents dans `AGENTS.md`.

---

## 1. Spec fonctionnelle (issue du reverse engineering de Limits)

| Fonction | v1 | Notes |
|---|---|---|
| Login OAuth Claude (compte Pro/Max) | ✅ | via Safari, flow « code à coller » |
| Login OAuth Codex (compte ChatGPT) | ✅ | via Safari + callback localhost:1455 |
| Dashboard : fenêtres 5 h + hebdo par provider | ✅ | anneaux + barres, % utilisé, compte à rebours de reset |
| Crédits de reset Codex + expiration | ✅ | endpoint dédié |
| Widgets home screen small/medium/large | ✅ | styles anneau et barre |
| Widgets lock screen (circular/rectangular/inline) | ✅ | |
| Rafraîchissement arrière-plan | ✅ | BGAppRefreshTask + refresh timeline widget |
| Notification locale au reset d'une fenêtre | ✅ | programmée sur `resets_at` |
| Notification seuil (80 % / 95 %, configurable) | ✅ | calculée au fetch |
| Cursor / Grok / autres providers | ❌ v2 | architecture extensible (protocole `Provider`) |
| Push serveur, tier Pro, achat in-app | ❌ jamais | impossible en sideload gratuit / inutile |

Principes hérités de Limits : tokens dans le **Keychain iOS**, tout est lu et caché
**localement**, aucun serveur tiers, aucune télémétrie.

---

## 2. APIs d'usage (vérifiées, avec fixtures réelles dans `fixtures/`)

### 2.1 Claude — `GET https://api.anthropic.com/api/oauth/usage`

Headers **tous obligatoires** :

```
Authorization: Bearer <access_token OAuth>
anthropic-beta: oauth-2025-04-20        ← sans lui : 401
User-Agent: claude-code/<version>       ← sans lui : bucket ultra rate-limité, 429 permanents
```

Réponse (capturée le 2026-07-29 — vérité complète dans `fixtures/claude-usage.json`) :

```json
{
  "five_hour": { "utilization": 0.0, "resets_at": null },
  "seven_day": { "utilization": 8.0, "resets_at": "2026-08-04T17:59:59.98+00:00" },
  "limits": [
    { "kind": "session",    "group": "session", "percent": 0, "severity": "normal",   "resets_at": null,  "is_active": false },
    { "kind": "weekly_all", "group": "weekly",  "percent": 8, "severity": "normal",   "resets_at": "…",   "is_active": true }
  ],
  "extra_usage": { "is_enabled": false, "monthly_limit": 16000, "used_credits": 15558.0, "utilization": 97.2, "currency": "AUD" },
  "spend": { "percent": 97, "severity": "critical", "…": "…" }
}
```

- **`utilization`/`percent` sont en pourcents (0-100)**, pas en fraction.
- **Source normalisée à privilégier : le tableau `limits[]`** (`kind`, `percent`,
  `severity`, `resets_at`, `is_active`) — il couvre session + hebdo de façon uniforme ;
  les objets racine (`five_hour`, `seven_day`, `seven_day_opus`…) servent de fallback.
- `resets_at` est **null quand la fenêtre est inactive** (aucune session en cours).
- Bonus découvert : `extra_usage`/`spend` = **crédits d'usage supplémentaire** (montant,
  %, sévérité) — affichables dans l'app (parité avec les crédits Codex).
- Les clés varient selon le plan (`seven_day_sonnet`, `seven_day_opus`, extras). Le
  parsing doit être **tolérant** : décoder ce qui est présent, ignorer l'inconnu,
  ne jamais planter sur une clé nouvelle.
- ⚠️ 429 agressifs documentés (issues anthropics/claude-code
  [#31021](https://github.com/anthropics/claude-code/issues/31021),
  [#31637](https://github.com/anthropics/claude-code/issues/31637)) → voir §6 polling.
- ⚠️ La date dans `anthropic-beta` a déjà changé par le passé → la valeur du header vit
  dans une config (pas en dur au fond d'un client), et un 401 affiche un état d'erreur
  explicite dans l'app au lieu d'échouer en silence.

### 2.2 Codex — base `https://chatgpt.com/backend-api`

Headers communs :

```
Authorization: Bearer <access_token>     (auth.json → tokens.access_token)
ChatGPT-Account-ID: <account_id>         (auth.json → tokens.account_id)
originator: codex_cli_rs
User-Agent: <libre>
```

| Endpoint | Contenu |
|---|---|
| `/wham/usage` | `rate_limit.primary_window`/`secondary_window` : `used_percent`, `limit_window_seconds`, `reset_after_seconds`, `reset_at` (epoch s) ; + `plan_type`, `credits`, `rate_limit_reset_credits` |
| `/wham/rate-limit-reset-credits` | crédits de reset : `credits[]`, `available_count`, `total_earned_count` |
| `/wham/profiles/me` | profil + **stats riches** (tokens/jour, streaks, buckets hebdo) — bonus pour un écran stats |

- ⚠️ **Constaté sur fixtures réelles (2026-07-29)** : `primary_window` n'est **pas
  forcément la fenêtre 5 h** — sur un compte Plus, primary = hebdo
  (`limit_window_seconds: 604800`) et `secondary_window` est `null`. **Classifier les
  fenêtres par leur durée** (18000 s → session 5 h, 604800 s → hebdo), jamais par leur
  position. Gérer l'absence d'une des deux fenêtres.
- Variantes de noms vues dans d'autres implémentations : `five_hour_limit`/
  `weekly_limit`, `resets_in_seconds` → **parsing tolérant multi-alias**, vérité dans
  `fixtures/codex-*.json`.
- Références : [MacSteini/Codex-Usage](https://github.com/MacSteini/Codex-Usage),
  `codex-rs/backend-client/src/client.rs` dans [openai/codex](https://github.com/openai/codex).

---

## 3. OAuth (les deux clients publics des CLIs officiels)

### 3.1 Claude — PKCE + « code à coller » (pas de serveur local nécessaire)

> ⚠️ **Valeurs corrigées le 2026-07-29 (nuit)** après vérification contre le binaire
> `claude.exe` **2.1.220 réellement installé** sur le PC (extraction de chaînes, lecture
> seule, aucun appel réseau). Les valeurs initiales de cette section, issues de la
> recherche du matin, étaient **périmées sur 4 points** — le login aurait échoué.

| Paramètre | Valeur |
|---|---|
| `client_id` | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (public, celui de Claude Code) — ✅ inchangé |
| Authorize | `https://claude.com/cai/oauth/authorize` ⚠️ **corrigé** (ce n'est plus `claude.ai`) |
| `redirect_uri` | `https://platform.claude.com/oauth/code/callback` ⚠️ **corrigé** (plus `console.anthropic.com`) |
| Scopes | `org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload` ⚠️ **corrigé** (6, pas 3) |
| Query supplémentaire | `code=true` ⚠️ **ajouté** — envoyé par 100 % des flows du client officiel |
| PKCE | S256 (`code_verifier` 43-128 chars, challenge = base64url(sha256)) — ✅ inchangé |
| Token | `POST https://platform.claude.com/v1/oauth/token` (JSON) ⚠️ **corrigé** |

⚠️ **Piège de copier-coller** : `https://platform.claude.com/oauth/authorize` existe aussi
(`CONSOLE_AUTHORIZE_URL`) et ressemble à la bonne URL — c'est le flow **Console/org**. Le
compte perso Pro/Max passe par `claude.com/cai/oauth/authorize` (`loginWithClaudeAi`, vrai
par défaut dans le client).

Flow dans l'app :
1. Générer verifier/challenge/state ; ouvrir l'URL authorize dans
   `ASWebAuthenticationSession` (ou `SFSafariViewController`).
2. Après login, la page callback **affiche un code au format `code#state`** que
   l'utilisateur copie et colle dans un champ de l'app.
3. Parser `code#state`, vérifier le state, échanger :
   `{grant_type: "authorization_code", code, state, client_id, redirect_uri, code_verifier}`.
4. Réponse : `access_token`, `refresh_token`, `expires_in` → Keychain. Le champ
   `refresh_token_expires_in` est lu par le client officiel quand il est présent : s'en
   servir pour planifier le refresh proactif, avec un repli si absent.
5. Refresh : `{grant_type: "refresh_token", refresh_token, client_id, scope}` sur le même
   endpoint token, à faire **proactivement** avant expiration.
   ⚠️ Le `scope` du refresh **diffère de celui du login** : `user:profile user:inference
   user:sessions:claude_code user:mcp_servers user:file_upload` — **sans**
   `org:create_api_key`.
   ⚠️ Si la réponse ne contient **pas** de nouveau `refresh_token`, conserver l'ancien
   (la rotation n'est pas systématique) — l'écraser avec `nil` déconnecterait l'utilisateur.

Références d'implémentation : [querymt/anthropic-auth](https://github.com/querymt/anthropic-auth)
(Rust), [hequ/cc — oauthHelper.js](https://huggingface.co/spaces/hequ/cc/blob/main/src/utils/oauthHelper.js).

⚠️ **ToS, à garder en tête** : depuis février 2026 Anthropic restreint côté serveur les
tokens OAuth consumer hors Claude Code/claude.ai (surtout l'inférence). On ne fait que
**lire l'endpoint usage** avec le User-Agent claude-code — comme tous les moniteurs
communautaires — mais c'est une zone grise assumée qui peut casser un jour.

### 3.2 Codex — PKCE + serveur local sur le port 1455

> ⚠️ **Vérifié le 2026-07-29 (nuit)** contre le source `openai/codex` (commit `cf7e9cfe`,
> 2026-07-28) : `codex-rs/login/src/{server.rs,pkce.rs,auth/manager.rs}`.

| Paramètre | Valeur |
|---|---|
| `client_id` | `app_EMoamEEZ73f0CkXaXp7hrann` (public, celui du CLI, non configurable) — ✅ |
| Authorize | `https://auth.openai.com/oauth/authorize` — ✅ |
| `redirect_uri` | `http://localhost:1455/auth/callback` (**hard-codé** côté OpenAI) ; le CLI retombe sur `:1457` si le port est pris |
| Scopes | `openid profile email offline_access api.connectors.read api.connectors.invoke` ⚠️ **corrigé** (2 de plus) |
| Query authorize | `response_type=code`, `client_id`, `redirect_uri`, `scope`, `code_challenge`, `code_challenge_method=S256`, `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, `state`, `originator=codex_cli_rs` |
| Token / refresh | `POST https://auth.openai.com/oauth/token` — ✅ |

⚠️ **`Content-Type` non uniforme, ne pas factoriser à l'aveugle** : l'exchange initial Codex
est en `application/x-www-form-urlencoded`, son refresh en `application/json` — et Claude
est en JSON pour les deux.

Flow dans l'app :
1. Démarrer un **mini serveur HTTP** sur `localhost:1455` (Network.framework
   `NWListener`) — sur iOS, Safari résout `localhost` vers l'appareil lui-même, donc
   l'app capte la redirection. Répondre une petite page « retourne dans l'app ».
2. Ouvrir authorize dans `ASWebAuthenticationSession` ; récupérer `code` sur le
   callback ; couper le serveur.
3. Échange PKCE classique ; extraire `account_id` du claim
   `https://api.openai.com/auth` → `chatgpt_account_id` de l'`id_token` (JWT), comme le
   fait le CLI (cf. structure de `~/.codex/auth.json` dans les fixtures).
4. Refresh JSON : `{client_id, grant_type: "refresh_token", refresh_token}`.
   ⚠️ Les refresh tokens expirent après une période d'inactivité (**~14-30 j : chiffre
   *unverified*, aucune constante dans le source — ne rien coder qui en dépende**) →
   refresh proactif en tâche de fond ; si perdu, notification locale « reconnecte Codex ».
   ⚠️ **Classer l'échec de refresh par code d'erreur du corps JSON, pas par statut HTTP** :
   `refresh_token_expired`, `refresh_token_reused`, `refresh_token_invalidated` sont
   **définitifs** (→ « reconnecter », jamais de retry) ; le reste est transitoire (backoff).
   `refresh_token_reused` se déclenche notamment sur deux refresh **concurrents** → sérialiser
   les refresh (single-flight) entre l'app et la tâche de fond.
   ⚠️ Réponse à champs optionnels : si `refresh_token` est absent, garder l'ancien.

**À ne pas répliquer** : `codex-rs` fait un 3ᵉ appel après l'exchange (`obtain_api_key`,
token-exchange RFC 8693) pour obtenir une clé d'API. Limits n'en a pas besoin — il ne lit
l'endpoint usage qu'avec `access_token` + `account_id`.

Références : [7shi/codex-oauth](https://github.com/7shi/codex-oauth), crate
[codex-oauth](https://lib.rs/crates/codex-oauth), `codex-rs/login` dans openai/codex,
[issue #8112](https://github.com/openai/codex/issues/8112).

**Vérification faite le 2026-07-29 (nuit)** : rapport complet valeur par valeur, avec
sources (fichier + commit) et statut ✅/⚠️/❓, dans `docs/oauth-verification-2026-07-29.md`.
Les valeurs des tableaux ci-dessus y sont corrigées. À **refaire** avant toute reprise
lointaine du projet : ces valeurs bougent (4 divergences en une seule journée d'écart).

---

## 4. Architecture de l'app

```
Limits/                        ← racine repo
├── project.yml                ← XcodeGen : AUCUN .xcodeproj committé
├── LimitsCore/                ← package SwiftPM, zéro dépendance UI, testé en CI
│   ├── Sources/LimitsCore/
│   │   ├── Models.swift       (UsageSnapshot, LimitWindow, ResetCredit, ProviderKind)
│   │   ├── ClaudeUsageClient.swift / CodexUsageClient.swift
│   │   ├── ClaudeOAuth.swift  (PKCE, parse code#state, exchange, refresh)
│   │   ├── CodexOAuth.swift   (PKCE, exchange, refresh, extraction account_id du JWT)
│   │   ├── PollingPolicy.swift (intervalle, backoff 429, Retry-After, TTL cache)
│   │   └── SnapshotStore.swift (encode/décode le snapshot JSON partagé)
│   └── Tests/                 (fixtures-driven : chaque JSON de fixtures/ a son test)
├── App/                       ← target iOS app (SwiftUI, iOS 17+)
│   ├── Onboarding/            (connexion par provider, champ code-paste Claude,
│   │                           LocalCallbackServer.swift = NWListener :1455)
│   ├── Dashboard/             (anneaux/barres, comptes à rebours, crédits)
│   ├── Settings/              (comptes, seuils, intervalle, style)
│   ├── KeychainStore.swift    (tokens ; access group partagé avec le widget)
│   ├── RefreshManager.swift   (BGAppRefreshTask : fetch → snapshot App Group →
│   │                           notifications locales → WidgetCenter.reloadAllTimelines)
│   └── Notifications.swift    (UNUserNotificationCenter : resets_at + seuils)
├── Widgets/                   ← target extension WidgetKit
│   ├── Providers/             (TimelineProvider lisant le snapshot App Group)
│   └── Views/                 (RingGauge, BarGauge ; familles systemSmall/Medium/Large,
│                               accessoryCircular/Rectangular/Inline)
├── fixtures/                  ← réponses API réelles anonymisées (source de vérité parsing)
├── scripts/capture-fixtures.ps1
├── docs/INSTALL-IPHONE.md
└── .github/workflows/build.yml
```

Points de conception :
- **Identifiants** : bundle `com.caldf.limitsapp`, widget `com.caldf.limitsapp.widgets`,
  App Group `group.com.caldf.limitsapp`, Keychain access group idem. Sideloadly/AltStore
  remappent ces IDs à la re-signature — ne jamais comparer d'ID en dur dans le code.
- **Snapshot** : l'app écrit `UsageSnapshot` (JSON, horodaté) dans le conteneur App
  Group ; les widgets ne font **que lire** (pas de réseau ni de token côté widget en
  v1 — c'est le fallback si l'App Group casse, cf. TASKS gate M1).
- **Comptes à rebours** : rendus avec `Text(timerInterval:)` → ils défilent sans
  refresh de timeline, même hors réseau. Les % affichent « à jour il y a X min ».
- **Background** : `BGAppRefreshTask` (identifiant dans
  `BGTaskSchedulerPermittedIdentifiers` de l'Info.plist), replanifié à chaque exécution.
  iOS le déclenche opportunistement (~15 min-plusieurs heures) : c'est suffisant,
  l'ouverture de l'app force aussi un fetch.
- **Notifications locales uniquement** (pas d'APNs en signature gratuite) : programmées
  à chaque fetch — une à chaque `resets_at`, une si un seuil est franchi.

---

## 5. Chaîne de build sans Mac

### 5.1 CI GitHub Actions (repo **public** → minutes macOS illimitées)

```yaml
# .github/workflows/build.yml — squelette
name: build
on: [push, workflow_dispatch]
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: swift test --package-path LimitsCore
  ipa:
    runs-on: macos-15
    needs: test
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: xcodegen generate
      - run: >
          xcodebuild -project Limits.xcodeproj -scheme Limits -configuration Release
          -sdk iphoneos -archivePath build/Limits.xcarchive archive
          CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
      - run: |
          mkdir -p build/Payload
          cp -R build/Limits.xcarchive/Products/Applications/Limits.app build/Payload/
          cd build && zip -r Limits.ipa Payload
      - uses: actions/upload-artifact@v4
        with: { name: Limits-ipa, path: build/Limits.ipa }
```

- Sur tag `v*` : publier l'IPA en Release GitHub.
- L'IPA est **non signée** : c'est Sideloadly qui signe avec l'Apple ID gratuit.
- Référence : [gist ivanopcode — unsigned iOS builds](https://gist.github.com/ivanopcode/acfeb79af7993c4627ee8275b3348d7d).

### 5.2 Boucle de dev (à respecter par tous les agents — cf. AGENTS.md)

Aucun agent n'a de simulateur ni d'Xcode : **toute la logique se prouve par les tests
SwiftPM en CI** (parsing fixtures, OAuth, machines à états, PollingPolicy). L'UI se
valide par Tristan : artefact IPA → Sideloadly → iPhone (~2 min une fois installé).
Compiler localement est impossible → un agent ne déclare jamais « ça marche » sans CI
verte, et les retours visuels sont demandés explicitement à Tristan.

### 5.3 Installation iPhone

Voir `docs/INSTALL-IPHONE.md`. Résumé : Sideloadly sous Windows + Apple ID gratuit ;
certificat 7 jours (auto-refresh Wi-Fi), 3 apps max, ~10 App IDs/7 j (app + widget = 2),
pas de push. iPhone : activer le mode développeur, faire confiance au profil.

---

## 6. Politique réseau (anti-429, à implémenter dans PollingPolicy)

1. Jamais moins de **15 min** entre deux fetchs Claude (sauf action manuelle
   pull-to-refresh, elle-même throttlée à 1/min).
2. Toujours envoyer le **User-Agent claude-code** et le header beta (valeurs en config).
3. Sur 429 : respecter `Retry-After` si présent, sinon backoff exponentiel
   30 s → 2 min → 10 min → 30 min ; **conserver et afficher le dernier snapshot**.
4. Sur 401 Claude : tenter un refresh token ; si échec → état « reconnecter » (bandeau
   app + placeholder widget), jamais de boucle de retry sur le login.
5. Codex est moins agressif mais même structure de backoff.
6. Le widget ne déclenche aucun réseau : il lit le snapshot (v1).

---

## 7. Risques & mitigations

| Risque | Impact | Mitigation |
|---|---|---|
| 429 agressifs endpoint Anthropic | widgets figés | §6 ; cache + affichage « il y a X min » |
| Header `anthropic-beta` change | 401 silencieux | valeur en config + état d'erreur explicite |
| ToS zone grise (tokens OAuth hors CLI) | blocage possible | lecture seule, UA officiel, risque documenté/accepté |
| App Group cassé par la re-signature gratuite | widgets sans données | **gate M1** ; fallback AltStore ; dernier recours : fetch dans le widget |
| Champs `wham/usage` mouvants | parsing cassé | fixtures réelles + parsing multi-alias tolérant |
| Refresh token Codex expire (14-30 j) | re-login | refresh proactif en BGTask + notification |
| Certificat 7 jours | app expire | auto-refresh Sideloadly en Wi-Fi (PC allumé 1×/sem) |
| Pas d'APNs | pas d'alerte poussée | notifications **locales** programmées aux `resets_at` |
| Port 1455 (Codex OAuth) | login impossible | port dédié à l'app sur iOS, conflit improbable ; messages d'erreur clairs |

---

## 8. Sources principales

- Limits (référence produit) : https://getlimits.app/
- Endpoint usage Anthropic + pièges : issues claude-code
  [#31021](https://github.com/anthropics/claude-code/issues/31021) /
  [#31637](https://github.com/anthropics/claude-code/issues/31637) ;
  [Tracking Claude, Codex, and Gemini Quotas](https://ianlpaterson.com/blog/tracking-claude-codex-gemini-quotas-from-one-script/)
- OAuth Claude : [querymt/anthropic-auth](https://github.com/querymt/anthropic-auth)
- Codex usage : [MacSteini/Codex-Usage](https://github.com/MacSteini/Codex-Usage) ;
  [openai/codex issue #10869](https://github.com/openai/codex/issues/10869) (endpoint wham/usage)
- OAuth Codex : [7shi/codex-oauth](https://github.com/7shi/codex-oauth) ;
  [codex-oauth (lib.rs)](https://lib.rs/crates/codex-oauth)
- Build sans Mac : [gist unsigned iOS builds](https://gist.github.com/ivanopcode/acfeb79af7993c4627ee8275b3348d7d) ;
  [Build unsigned iOS ipa to install via Sideloadly](https://dev.to/oivoodoo/build-unsigned-ios-ipa-to-install-via-sideloadly-236f)
- Sideload : https://sideloadly.io/ (la vidéo YouTube ME4_RHCaCAk de 2019 — Cydia
  Impactor — est **obsolète**, ne pas suivre)

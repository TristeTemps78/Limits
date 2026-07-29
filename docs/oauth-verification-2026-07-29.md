# Vérification OAuth Claude / Codex — 2026-07-29

Méthode : sources amont uniquement, lues en clair.
- **Codex** : dépôt GitHub `openai/codex`, fichiers `codex-rs/login/src/{server.rs,pkce.rs,success_page.rs,token_data.rs,auth/{default_client.rs,manager.rs}}`,
  récupérés via `gh api repos/openai/codex/contents/...` (HEAD au commit `cf7e9cfe6a196d14a34a4a2e10265143df336781`, 2026-07-28T15:45:34Z — donc 1 jour avant la recherche PLAN.md).
- **Claude** : extraction de chaînes (`grep -a`, lecture seule, aucune requête réseau) depuis le binaire **réellement installé sur cette machine**,
  le binaire local du CLI, `claude --version` → **2.1.220** (fichier daté 2026-07-26T11:17:47, donc le CLI qui tourne aujourd'hui,
  3 jours avant la recherche PLAN.md — c'est la source la plus fraîche possible sans compte Anthropic interne). C'est un bundle JS minifié
  (Bun standalone exe) : les extraits ci-dessous sont des citations littérales de ce bundle, pas de la reconstruction.

Aucun endpoint OAuth ni d'usage n'a été appelé. Aucun credential utilisé.

---

## Divergences — À CORRIGER EN PRIORITÉ

### 1. Claude — domaine `redirect_uri` (manuel) : CHANGÉ

- **PLAN.md** : `https://console.anthropic.com/oauth/code/callback`
- **Constaté** : `https://platform.claude.com/oauth/code/callback`
- **Source** : `claude.exe` v2.1.220, objet de config production littéral :
  `MANUAL_REDIRECT_URL:"https://platform.claude.com/oauth/code/callback"`
- **Correction** : remplacer partout dans `LimitsCore/ClaudeOAuth.swift` (à écrire) et dans PLAN.md §3.1.

### 2. Claude — domaine du `token endpoint` : CHANGÉ

- **PLAN.md** : `POST https://console.anthropic.com/v1/oauth/token`
- **Constaté** : `POST https://platform.claude.com/v1/oauth/token`
- **Source** : même objet de config, `TOKEN_URL:"https://platform.claude.com/v1/oauth/token"`, et confirmé dans le
  code d'appel réel : `await No.post(Os().TOKEN_URL,a,{headers:{"Content-Type":"application/json"},timeout:30000})`.
- **Correction** : idem, tout `console.anthropic.com` → `platform.claude.com` pour le token endpoint.

### 3. Claude — URL `authorize` (flow Pro/Max « claude.ai ») : DIFFÉRENTE DE CE QUI ÉTAIT ATTENDU

- **PLAN.md** : `https://claude.ai/oauth/authorize`
- **Constaté** : `https://claude.com/cai/oauth/authorize`
- **Détail important** : `claude.ai` existe bien comme `CLAUDE_AI_ORIGIN` dans la config, mais **n'est plus utilisé pour construire
  l'URL authorize** du login CLI. La fonction qui construit l'URL (`buildAuthUrl`, nom minifié `mno`) fait :
  ```js
  let u = o ? Os().CLAUDE_AI_AUTHORIZE_URL : Os().CONSOLE_AUTHORIZE_URL, d = new URL(u);
  ```
  avec l'objet de config production :
  ```js
  CONSOLE_AUTHORIZE_URL:"https://platform.claude.com/oauth/authorize",
  CLAUDE_AI_AUTHORIZE_URL:"https://claude.com/cai/oauth/authorize",
  CLAUDE_AI_ORIGIN:"https://claude.ai",
  ```
  Le paramètre `loginWithClaudeAi` (variable `o`) vaut **`true` par défaut** dans le flow de login interactif standard
  (`loginWithClaudeAi:Ur??!0` — `Ur` est un override optionnel, `!0` = `true`) : c'est bien le flow qu'un compte Pro/Max
  personnel emprunte (par opposition à `CONSOLE_AUTHORIZE_URL`, utilisé pour les comptes Console/API org).
- **Correction** : l'authorize URL à utiliser côté app est `https://claude.com/cai/oauth/authorize`, **pas**
  `claude.ai/oauth/authorize`.
- Statut : ⚠️ divergent, haute confiance (lu dans le code de construction de l'URL lui-même, pas une doc).

### 4. Claude — scopes : PLUS LARGES QUE DOCUMENTÉ

- **PLAN.md** : `org:create_api_key user:profile user:inference`
- **Constaté** (flow de login standard, pas `inferenceOnly`, pas de client OAuth personnalisé) :
  `org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload`
  (6 scopes, dédupliqués — `user:profile` apparaît dans les deux listes sources et n'est gardé qu'une fois).
- **Source**, définition littérale des constantes :
  ```js
  rYf=[tYf,X0e]                                  // ["org:create_api_key","user:profile"]
  trt=[X0e,Hq,"user:sessions:claude_code","user:mcp_servers","user:file_upload"]
                                                  // ["user:profile","user:inference","user:sessions:claude_code",
                                                  //  "user:mcp_servers","user:file_upload"]
  Oki=Co([...rYf,...trt])                        // union dédupliquée = scope du login standard
  ```
  et usage dans `buildAuthUrl` : `let p = c ? c.scopes : i ? [Hq] : Oki; d.searchParams.append("scope", p.join(" "))`
  (`i` = `inferenceOnly`, faux dans le flow de login normal → on tombe sur `Oki`).
- **Correction** : demander les 6 scopes ci-dessus, pas seulement 3. Un scope en moins ne fera pas planter l'auth
  côté serveur a priori (OAuth scope réduit = juste moins de droits), mais autant coller à ce que fait le vrai
  client pour éviter une régression de fonctionnalité silencieuse (p.ex. si l'endpoint usage venait à exiger
  `user:sessions:claude_code`).
- Statut : ⚠️ divergent, haute confiance.

### 5. Claude — paramètre `code=true` non documenté dans PLAN.md

- Absent de PLAN.md. **Systématiquement ajouté** par le client réel à la requête authorize, **avant** même la
  branche manuelle/serveur-local :
  ```js
  d.searchParams.append("code","true");
  d.searchParams.append("client_id", c?.clientId ?? Os().CLIENT_ID);
  d.searchParams.append("response_type","code");
  d.searchParams.append("redirect_uri", n ? Os().MANUAL_REDIRECT_URL : `http://localhost:${r}/callback`);
  ```
- Comportement exact non documenté côté serveur (pas de commentaire dans le bundle), mais il est envoyé par
  100 % des flows du client officiel (manuel et local-callback) — à répliquer telle quelle par prudence.
- Statut : ⚠️ paramètre supplémentaire confirmé, sémantique serveur non vérifiable depuis le client.

### 6. Claude — le refresh envoie un `scope`, pas documenté dans PLAN.md

- **PLAN.md** : `{grant_type: "refresh_token", refresh_token, client_id}`
- **Constaté** :
  ```js
  let s = {
    grant_type: "refresh_token",
    refresh_token: e,
    client_id: n ?? Os().CLIENT_ID,
    scope: (Array.isArray(t) && t.length ? t : trt).join(" ")
  };
  if (r !== void 0) s.expires_in = r;
  await No.post(Os().TOKEN_URL, s, {headers:{"Content-Type":"application/json"}, timeout:30000});
  ```
  où `trt` (scope par défaut du refresh) = `user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload`
  (note : **sans** `org:create_api_key`, contrairement au scope initial de login).
- **Correction** : ajouter `"scope": "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"`
  au corps du refresh JSON.
- Statut : ⚠️ divergent, haute confiance.

### 7. Codex — deux paramètres authorize non documentés dans PLAN.md (mais anticipés comme « susceptibles d'avoir bougé »)

Confirmés présents dans `codex-rs/login/src/server.rs::build_authorize_url` (commit `cf7e9cfe`, 2026-07-28) :

```rust
let mut query = vec![
    ("response_type", "code"),
    ("client_id", client_id),
    ("redirect_uri", redirect_uri),
    ("scope", "openid profile email offline_access api.connectors.read api.connectors.invoke"),
    ("code_challenge", pkce.code_challenge),
    ("code_challenge_method", "S256"),
    ("id_token_add_organizations", "true"),
    ("codex_cli_simplified_flow", "true"),
    ("state", state),
    ("originator", originator().value),   // = "codex_cli_rs"
];
// + "allowed_workspace_id" si login restreint à un workspace (non pertinent pour un compte perso)
```

- `id_token_add_organizations=true` et `codex_cli_simplified_flow=true` : **présents**, PLAN.md les citait déjà
  comme exemples plausibles — confirmés à l'identique. ✅ (dans le sens où PLAN avait bien anticipé leur existence)
- `originator=codex_cli_rs` : présent, confirme aussi le header `originator` (§2.2 PLAN.md). ✅
- **Scope divergent** : PLAN.md dit `openid profile email offline_access`, le code envoie en plus
  `api.connectors.read api.connectors.invoke`. **Correction** : scope complet à envoyer =
  `openid profile email offline_access api.connectors.read api.connectors.invoke`.
- Pas de paramètre `prompt` dans le flow par défaut (contrairement à ce que PLAN.md envisageait comme possible).
- Statut : ⚠️ scope Codex divergent (2 scopes en plus), reste confirmé.

---

## Tableau valeur par valeur

| Domaine | Paramètre | Attendu (PLAN.md) | Constaté | Source | Statut |
|---|---|---|---|---|---|
| Claude | `client_id` | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` | identique | `claude.exe` 2.1.220, `CLIENT_ID:"9d1c250a-e61b-44d9-88ed-5944d1962f5e"` (config prod littérale) | ✅ confirmé |
| Claude | authorize URL (Pro/Max) | `https://claude.ai/oauth/authorize` | `https://claude.com/cai/oauth/authorize` | `claude.exe`, `buildAuthUrl` + `CLAUDE_AI_AUTHORIZE_URL` | ⚠️ divergent |
| Claude | `redirect_uri` (manuel) | `https://console.anthropic.com/oauth/code/callback` | `https://platform.claude.com/oauth/code/callback` | `claude.exe`, `MANUAL_REDIRECT_URL` | ⚠️ divergent |
| Claude | scopes | `org:create_api_key user:profile user:inference` | + `user:sessions:claude_code user:mcp_servers user:file_upload` (6 au total) | `claude.exe`, constantes `rYf`/`trt`/`Oki` + usage dans `buildAuthUrl` | ⚠️ divergent |
| Claude | PKCE | S256, verifier 43-128 | S256 confirmé (`code_challenge_method","S256"` en dur) ; longueur non revérifiée côté Claude (mais c'est côté app, pas côté serveur, donc géré par nous) | `claude.exe`, `buildAuthUrl` | ✅ confirmé (partiel — c'est notre propre génération) |
| Claude | token endpoint | `POST https://console.anthropic.com/v1/oauth/token` (JSON) | `POST https://platform.claude.com/v1/oauth/token`, JSON, `Content-Type: application/json`, timeout 30 s côté client | `claude.exe`, `TOKEN_URL` + fonction `uJi` (exchange) | ⚠️ divergent (domaine) |
| Claude | body exchange | `{grant_type:"authorization_code", code, state, client_id, redirect_uri, code_verifier}` | identique + `expires_in` optionnel si fourni | `claude.exe`, fonction `uJi` : `{grant_type:"authorization_code",code:e,redirect_uri:...,client_id:...,code_verifier:r,state:t}` | ✅ confirmé (structure) |
| Claude | format code callback | `code#state` | confirmé, split sur `"#"`, 1ʳᵉ occurrence | `claude.exe`, plusieurs occurrences de `re.split("#")` avec message d'erreur "Invalid code. Please make sure the full code was copied" si l'un des deux est vide | ✅ confirmé |
| Claude | refresh body | `{grant_type:"refresh_token", refresh_token, client_id}` | + `scope` obligatoire (join espace, défaut = 5 scopes sans `org:create_api_key`) + `expires_in` optionnel | `claude.exe`, fonction `AFe` (refresh) | ⚠️ divergent (scope manquant) |
| Claude | header `anthropic-beta` | `oauth-2025-04-20` | identique | `claude.exe`, constante `RI="oauth-2025-04-20"`, exportée `OAUTH_BETA_HEADER:()=>RI` | ✅ confirmé |
| Claude | `User-Agent` | `claude-code/<version>` | format confirmé : `` `claude-code/${e.ccVersion}` `` | `claude.exe` | ✅ confirmé |
| Claude | version CLI actuelle | `2.1.220` (valeur fixtures) | `2.1.220` — c'est la version **installée et exécutée aujourd'hui** sur cette machine (`claude --version`) | commande locale `claude --version`, fichier daté 2026-07-26 | ✅ confirmé, à jour |
| Claude | usage endpoint | `GET https://api.anthropic.com/api/oauth/usage` | présent tel quel dans le binaire | `claude.exe`, chaîne littérale `api/oauth/usage` | ✅ confirmé |
| Codex | `client_id` | `app_EMoamEEZ73f0CkXaXp7hrann` | identique | `codex-rs/login/src/auth/manager.rs`, `pub const CLIENT_ID` ; aussi dans `codex-rs/tui/src/onboarding/auth.rs` | ✅ confirmé |
| Codex | authorize URL | `https://auth.openai.com/oauth/authorize` | identique (`DEFAULT_ISSUER` + `/oauth/authorize`) | `codex-rs/login/src/server.rs`, `DEFAULT_ISSUER` + `build_authorize_url` | ✅ confirmé |
| Codex | `redirect_uri` | `http://localhost:1455/auth/callback` | identique par défaut ; **fallback** `:1457` si `:1455` occupé après tentative d'annulation d'un serveur précédent | `codex-rs/login/src/server.rs`, `DEFAULT_PORT=1455`, `FALLBACK_PORT=1457` (« keep in sync with the Codex CLI Hydra redirect URI allow-list ») | ✅ confirmé + info supplémentaire |
| Codex | scopes | `openid profile email offline_access` | + `api.connectors.read api.connectors.invoke` (6 mots au total) | `codex-rs/login/src/server.rs`, `build_authorize_url` | ⚠️ divergent |
| Codex | PKCE | S256, verifier 43-128 | confirmé : verifier = base64url(64 octets aléatoires, sans padding) ≈ 86 chars ; challenge = base64url(SHA256(verifier)) | `codex-rs/login/src/pkce.rs` | ✅ confirmé |
| Codex | paramètres authorize additionnels | non spécifiés précisément | `id_token_add_organizations=true`, `codex_cli_simplified_flow=true`, `originator=codex_cli_rs`, `state` ; pas de `prompt` | `codex-rs/login/src/server.rs::build_authorize_url` | ✅ confirmé (anticipés par PLAN, valeurs exactes obtenues) |
| Codex | token/refresh endpoint | `POST https://auth.openai.com/oauth/token` | identique | `codex-rs/login/src/server.rs` (`{issuer}/oauth/token`) et `manager.rs` (`REFRESH_TOKEN_URL = "https://auth.openai.com/oauth/token"`) | ✅ confirmé |
| Codex | body exchange initial | non détaillé dans PLAN | `application/x-www-form-urlencoded` (PAS JSON) : `grant_type=authorization_code&code=...&redirect_uri=...&client_id=...&code_verifier=...` (pas de `state` dans ce corps) | `codex-rs/login/src/server.rs::exchange_code_for_tokens` | ✅ confirmé (précision importante, non couverte par PLAN) |
| Codex | body refresh | `{client_id, grant_type:"refresh_token", refresh_token}` | identique, mais en JSON (`Content-Type: application/json`), pas form-urlencoded | `codex-rs/login/src/auth/manager.rs::request_chatgpt_token_refresh` | ✅ confirmé (structure), précision Content-Type ajoutée |
| Codex | `account_id` | claim `https://api.openai.com/auth` → `chatgpt_account_id` de l'`id_token` | identique | `codex-rs/login/src/success_page.rs::jwt_auth_claims` + `server.rs::persist_tokens_async` | ✅ confirmé |
| Codex | header `originator` | `codex_cli_rs` | identique, constante `DEFAULT_ORIGINATOR` | `codex-rs/login/src/auth/default_client.rs` | ✅ confirmé |
| Codex | refresh token TTL (14-30 j) | affirmé dans PLAN.md | **non trouvé** de constante numérique dans `codex-rs` ; seuls des codes d'erreur qualitatifs existent (`refresh_token_expired`, `refresh_token_reused`, `refresh_token_invalidated`) | recherche dans `manager.rs` (2622 lignes) | ❓ non vérifiable depuis le code client — marquer « unverified » |

---

## Pièges d'implémentation relevés

1. **Claude : token exchange en JSON, Codex : token exchange en form-urlencoded.** Ne pas copier-coller le
   client HTTP entre les deux providers — `Content-Type` différent dès le premier appel.
   - Claude (`code` initial ET `refresh_token`) : toujours `application/json`.
   - Codex `code` initial (`exchange_code_for_tokens`) : `application/x-www-form-urlencoded`.
   - Codex refresh (`request_chatgpt_token_refresh`) : `application/json` (différent de son propre exchange initial !).
2. **Codex refresh : `id_token`/`access_token`/`refresh_token` sont tous `Option<String>` dans la réponse.**
   Le refresh token n'est pas forcément retourné (rotation non systématique) — ne pas écraser le refresh token
   stocké si absent de la réponse. Idem côté Claude : `let{access_token:c,refresh_token:u=e,...}=l` — si le
   serveur ne renvoie pas de nouveau `refresh_token`, le client réutilise l'ancien (`u=e` = valeur par défaut).
3. **Codex : gestion des échecs de refresh par code d'erreur, pas juste par statut HTTP.**
   `manager.rs::classify_refresh_token_failure` lit `error.code` (ou `error` string, ou `error.error`) dans le
   corps JSON et distingue trois cas définitifs (→ ne jamais retry, forcer un nouveau login) :
   - `refresh_token_expired` → message « expiré »
   - `refresh_token_reused` → réutilisation détectée (le refresh token a déjà servi — normal si deux instances
     de l'app tentent un refresh concurrent, à éviter avec un verrou/single-flight côté `RefreshManager`)
   - `refresh_token_invalidated` → révoqué côté serveur
   Un statut 401 générique ou l'un de ces trois codes = échec **permanent** (bandeau « reconnecter »).
   Tout le reste = échec **transitoire** (retry avec backoff, cf. PollingPolicy).
4. **Codex : le port 1455 peut retomber sur 1457.** `bind_server` tente d'abord d'annuler un éventuel serveur
   de login existant sur `:1455` (requête `GET /cancel`), puis après 10 tentatives (200 ms d'intervalle,
   soit ~2 s) bascule sur `:1457` si `:1455` reste occupé. Sur iOS (process unique par app), ce cas est rare
   mais pas impossible (autre app tenant déjà le port) — prévoir au moins un message d'erreur clair plutôt
   qu'un blocage silencieux ; répliquer le fallback `:1457` est optionnel mais fidèle au client officiel.
5. **Claude : le paramètre `code=true` est ajouté à TOUTES les variantes du flow authorize** (manuel et
   local-callback), avant même le choix `redirect_uri`. À inclure systématiquement.
6. **Claude : la variable qui choisit `CLAUDE_AI_AUTHORIZE_URL` vs `CONSOLE_AUTHORIZE_URL` s'appelle
   `loginWithClaudeAi` et vaut `true` par défaut dans le flow interactif standard.** C'est cette bascule
   qui distingue le compte perso (Pro/Max, ce que veut l'app) du compte Console/API org — bien confirmer
   dans l'implémentation qu'on prend la branche `CLAUDE_AI_AUTHORIZE_URL`, pas `CONSOLE_AUTHORIZE_URL`
   (`https://platform.claude.com/oauth/authorize`, qui existe aussi et ressemble trompeusement à la bonne URL).
7. **Codex : `codex-rs` fait aussi un 3ᵉ appel réseau après l'exchange** — `obtain_api_key`, un
   token-exchange RFC 8693 (`grant_type=urn:ietf:params:oauth:grant-type:token-exchange`) qui échange
   l'`id_token` contre une clé de style « API key » (utilisée par le CLI pour un usage API direct, pas pour
   `/wham/usage`). **Cet appel n'est pas nécessaire pour Limits** (l'app ne lit que l'endpoint usage avec
   `access_token` + `account_id`), à ne pas répliquer — mentionné ici seulement pour ne pas être surpris si on
   recroise cette route en lisant le code source.
8. **Claude : scope du refresh ≠ scope du login initial.** Le refresh redemande explicitement les scopes
   (`user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload`, sans
   `org:create_api_key`) — si l'app stocke les scopes accordés au login, il faut les rejouer tels quels au
   refresh (ou reproduire ce sous-ensemble par défaut), pas réutiliser le scope initial à 6 entrées.

---

## Ce qui n'a PAS pu être vérifié (à marquer « unverified »)

- **Durée de vie exacte du refresh token Codex (14-30 j)** — aucune constante numérique trouvée dans
  `codex-rs`. Le comportement est bien géré côté client (3 codes d'erreur distincts, cf. piège n°3), mais le
  chiffre lui-même vient d'une politique serveur non visible depuis le code. Ne pas coder de logique qui
  dépende d'un nombre de jours précis ; se fier au retour d'erreur serveur.
- **Sémantique exacte du paramètre `code=true` côté serveur Claude** — confirmé présent dans 100 % des
  requêtes authorize du client officiel, mais aucun commentaire ni doc trouvés expliquant ce qu'il change
  côté backend. À inclure par précaution, comportement non garanti si omis.
- **`refresh_token_expires_in` (Claude)** — le champ existe et est lu par le client (`l.refresh_token_expires_in`
  dans `AFe`), mais je n'ai pas pu observer une valeur réelle (aucun appel réseau effectué). Ne pas supposer
  une durée fixe ; lire ce champ s'il est présent dans la réponse et s'en servir pour planifier le refresh
  proactif, avec un fallback raisonnable s'il est absent.
- **`CONSOLE_AUTHORIZE_URL` (`https://platform.claude.com/oauth/authorize`)** — confirmé exister et être
  utilisé pour le flow Console/org, mais je n'ai pas vérifié dans quel contexte l'app Limits pourrait en avoir
  besoin (a priori jamais, l'app cible exclusivement les comptes Pro/Max) ; mentionné seulement pour éviter
  une confusion de copier-coller.
- **Contenu exact de la réponse token Claude au-delà de `access_token`/`refresh_token`** — le code client
  (`uJi`) retourne `l.data` brut sans lister tous les champs ; je n'ai pas pu observer une réponse réelle
  (pas d'appel réseau autorisé). PLAN.md suppose `access_token, refresh_token, expires_in` — cohérent avec
  l'usage qu'en fait `AFe` pour le refresh (`expires_in`), donc probable, mais pas observé directement pour
  l'exchange initial. Traiter avec parsing tolérant (déjà la règle du projet, AGENTS.md §3).
- **Version exacte de `codex` CLI correspondant à ces valeurs** — je n'ai pas de binaire Codex installé
  localement pour recouper (contrairement à Claude Code) ; tout vient du code source GitHub au commit
  `cf7e9cfe` (2026-07-28), donc très frais, mais je n'ai pas pu confirmer qu'aucune release taggée plus
  ancienne n'est celle réellement utilisée par les utilisateurs Codex visés par l'app. À reconfirmer si
  possible en installant le CLI Codex avant l'implémentation T2.2.

---

## Résumé actionnable pour l'agent T2.2

À corriger dans `PLAN.md` §3.1 et dans le futur `LimitsCore/ClaudeOAuth.swift` :
- authorize = `https://claude.com/cai/oauth/authorize` (pas `claude.ai`)
- redirect_uri = `https://platform.claude.com/oauth/code/callback` (pas `console.anthropic.com`)
- token endpoint = `https://platform.claude.com/v1/oauth/token` (pas `console.anthropic.com`)
- scope = `org:create_api_key user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload`
- ajouter `code=true` aux query params de l'authorize URL
- refresh body = `{grant_type:"refresh_token", refresh_token, client_id, scope:"user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"}`

À corriger dans `PLAN.md` §3.2 et `LimitsCore/CodexOAuth.swift` :
- scope = `openid profile email offline_access api.connectors.read api.connectors.invoke`
- authorize query complet = `response_type=code&client_id=...&redirect_uri=...&scope=...&code_challenge=...&code_challenge_method=S256&id_token_add_organizations=true&codex_cli_simplified_flow=true&state=...&originator=codex_cli_rs`
- exchange initial en `application/x-www-form-urlencoded`, refresh en `application/json` (ne pas uniformiser)
- gérer les 3 codes d'erreur de refresh (`refresh_token_expired`/`refresh_token_reused`/`refresh_token_invalidated`) comme échecs permanents

Tout le reste du tableau ci-dessus est ✅ confirmé et n'a pas besoin de changer.

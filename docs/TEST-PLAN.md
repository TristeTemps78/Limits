# TEST-PLAN.md — valider Limits sur un vrai iPhone

Limits v1.0 compile, s'archive et passe 300 tests en CI. Rien de tout ça ne prouve qu'un
login aboutit, que l'App Group survit à la re-signature Sideloadly, qu'iOS réveille un jour
la tâche de fond, ni à quoi ressemble une jauge à 3 h du matin sur un écran verrouillé.
**Ce document est la seule façon de le savoir.** Il couvre les 7 critères de la checklist
finale de `TASKS.md`, en trois séances :

| Séance | Quand | Durée | Ce qu'elle décide |
|---|---|---|---|
| **A** | J0, iPhone en main | ~1 h (dont **A0**, 15 min) | d'abord si le PC voit l'iPhone, puis le gate M1 (T1.2), les deux logins, l'affichage |
| **B** | quelques heures plus tard → J+1 | 10 min de gestes, le reste est de l'attente | l'arrière-plan et les notifications |
| **C** | J+7, à la re-signature | ~10 min | ce qui survit à un renouvellement de certificat |

Installation : `INSTALL-IPHONE.md` §1-5. Grille de lecture du diagnostic App Group :
`INSTALL-IPHONE.md` §6 — elle n'est pas recopiée ici, une grille dupliquée finit par diverger.

## Ce dont tu as besoin

- L'iPhone, le PC, et l'IPA de la
  [Release v1.0](https://github.com/TristeTemps78/Limits/releases/tag/v1.0).
  ⚠️ **Le Vivobook S 15 est sous Windows ARM64** : pas de pilote USB Apple utilisable, donc
  ni iTunes ni Sideloadly. Le montage de contournement est dans **`SIDELOAD-ARM64.md`** et
  doit être fait **avant** tout le reste — c'est l'objet du test **A0**.
- Un poste où lancer une **vraie session Claude Code** (pour B2) et de quoi comparer les
  chiffres : `/usage` dans Claude Code.
- Les comptes Claude Pro/Max et ChatGPT Plus/Pro. **Tu saisis tes identifiants toi-même,
  jamais dans une conversation avec un agent.**

## Comment me rendre les résultats

Colle ce tableau rempli — un `ça marche` global ne permet pas de rendre le verdict T1.4, et
un `ça marche pas` sans le message affiché ne permet pas de savoir quoi corriger.

```
| ID  | PASS / FAIL / BLOQUÉ | ce que j'ai vu |
|-----|----------------------|----------------|
| A0  |                      |                |
| A1  |                      |                |
| A2  |                      |                |
| A3  |                      |                |
| A4  |                      |                |
| A5  |                      |                |
| A6  |                      |                |
| A7  |                      |                |
| A8  |                      |                |
| A9  |                      |                |
| A10 |                      |                |
| A11 |                      |                |
| B1  |                      |                |
| B2  |                      |                |
| B3  |                      |                |
| B4  |                      |                |
| B5  |                      |                |
| C1  |                      |                |
| C2  |                      |                |
| C3  |                      |                |
```

`BLOQUÉ` est un résultat valable et utile : il dit « pas testable dans ces conditions », ce
qui n'est pas la même information que `FAIL`. Les captures d'écran sont les bienvenues —
**rogne ce qui montre une adresse e-mail ou un identifiant de compte**, le dépôt est public.

---

# Séance A — J0, iPhone en main (~45 min)

## A0 — ✅ **PASS le 2026-07-30** — le PC peut-il parler à l'iPhone ?

> `idevice_id -l` renvoie un appareil, `idevicepair validate` → SUCCESS, `ideviceinfo` répond :
> **iPhone 15 (iPhone15,4) sous iOS 26.0.1**. Le blocage ARM64 est contourné pour de bon
> (`SIDELOAD-ARM64.md`, « Où on en est »). Le reste du protocole est exécutable.

*Procédure conservée ci-dessous pour la reproduire après un redémarrage ou un
rebranchement — `usbipd attach` est à refaire à chaque fois.*

### Rappel de la procédure · *préalable à tout*

Le PC de Tristan est un **ASUS Vivobook S 15 sous Windows ARM64** (Snapdragon X Plus). Le
pilote USB Apple est un **pilote noyau x64**, et Windows on ARM n'émule pas les pilotes
noyau : l'iPhone risque de n'être jamais détecté. Détail et voies de sortie :
`INSTALL-IPHONE.md` §0. **Ce test décide si les 19 autres sont seulement exécutables.**

**Voie retenue** : WSL2 + `usbipd-win` + signature sous Linux — le montage complet, avec un
point de contrôle par étape, est dans **`SIDELOAD-ARM64.md`**.

**Le geste qui tranche**, une fois les étapes 1 à 4 de ce guide passées, côté Ubuntu :

```bash
idevice_id -l
```

**Attendu** : un UDID s'affiche. Le blocage ARM64 est alors contourné, et tout ce qui suit
redevient du sideload ordinaire. *(Ne recopie pas l'UDID dans ton retour : « ça renvoie bien
un UDID » suffit — le dépôt est public.)*

**Si rien ne s'affiche** : le tableau « Si la chaîne casse » de `SIDELOAD-ARM64.md` dit où
regarder selon l'étape qui a lâché. **Ne teste rien d'autre**, tout le reste en dépend :
marque **A1 à C3 = BLOQUÉ**, ce qui est une information exacte — le produit n'est pas en
cause, la chaîne d'installation l'est.

## A1 — Installation et premier lancement · *critère 1*

**Gestes** : `INSTALL-IPHONE.md` §1-4 (Sideloadly, sans décocher les PlugIns ; confiance au
profil ; Mode développeur), puis lancer Limits.

**Attendu** : deux onglets en bas, **« Tableau de bord »** et **« Réglages »**. Le tableau de
bord affiche **« Aucun compte connecté »**. Appui long sur l'écran d'accueil → `+` → chercher
« Limits » : **deux** widgets doivent apparaître dans la galerie, **« Limites d'usage »** et
**« Diagnostic App Group »**.

**Si ça échoue** : aucun widget dans la galerie = l'extension a été retirée à l'installation
(cf. §3.3 et le tableau de dépannage). Rien ne sert de continuer sans widgets — c'est la
moitié du produit.

## A2 — Le gate App Group · *T1.2, la question qui décide de l'architecture*

**Gestes** : suivre `INSTALL-IPHONE.md` §6 intégralement. En résumé :
Réglages → **« Diagnostic App Group (T1.1) »** → **« Écrire maintenant »** → noter le
**Compteur** → poser le widget « Diagnostic App Group » sur l'écran d'accueil → revenir dans
l'app → **« Recharger les timelines des widgets »** → comparer.

**Attendu** : les trois canaux (**UserDefaults**, **Fichier App Group**, **Keychain**) en
lecture OK dans l'app, et le widget affiche `Defaults : #N`, `Fichier : #N`, `Keychain : #N`
avec **le même N que l'app**.

**À noter dans ton retour** : les trois canaux **séparément**, et le N de chaque côté. Un
canal peut réussir et les deux autres échouer — c'est exactement pour ça qu'ils sont testés
indépendamment.

> Le signal qui compte est **la comparaison du compteur**, pas l'absence de message d'erreur :
> sur iOS, `UserDefaults(suiteName:)` ne renvoie pas `nil` quand l'entitlement manque, il
> crée un domaine isolé au processus. Le canal peut donc afficher « écriture réussie » des
> deux côtés alors que rien n'est partagé. Si le N du widget ne bouge pas quand celui de
> l'app avance, l'App Group est mort, quoi que disent les lignes vertes.

**Si ça échoue** : c'est prévu, pas dramatique. Voir « Ce que chaque échec déclenche » en fin
de document. La ligne Keychain n'est **pas bloquante** pour la v1 (les widgets n'ont besoin
d'aucun token) mais doit être remontée telle quelle.

## A3 — Login Claude · *critère 2*

**Gestes** : Réglages → section **Comptes** → carte **Claude** → **« Se connecter »**. La
fenêtre de connexion s'ouvre. Une fois connecté, la page finale affiche un code au format
`xxxx#yyyy` : le copier **en entier**, revenir dans l'app, le coller dans
**« Colle le code ici (xxxx#yyyy) »**, puis **« Valider le code »**.

**Attendu** : la carte passe à **« Compte connecté. »** avec la pastille verte « Connecté ».

**Ce qu'il faut regarder de près** (c'est un flux inhabituel, sans redirection automatique) :
- le code est-il réellement **sélectionnable et copiable** depuis la vue web sur iPhone ?
- le collage fonctionne-t-il même si iOS ajoute un espace en fin ? (le trim est censé le
  rattraper — si un message d'erreur apparaît sur un code visiblement bon, dis-le)

**Si ça échoue** : recopier le message affiché en rouge **mot pour mot**. Les messages sont
distincts selon la cause, c'est ce qui permet de localiser le problème sans device.

## A4 — Login Codex · *critère 2 — le test le plus risqué après A2*

**Gestes** : Réglages → carte **Codex** → **« Se connecter »**. Une fenêtre de connexion
ChatGPT s'ouvre. Se connecter, autoriser, **puis ne rien faire** : le retour est automatique.

**Attendu** : la fenêtre se ferme d'elle-même, la carte passe par « En attente de la connexion
dans le navigateur… » puis « Connexion en cours… » puis **« Compte connecté. »**

**Pourquoi c'est le point faible** : contrairement à Claude, ce flux repose sur un petit
serveur qui écoute **à l'intérieur de l'app** sur `127.0.0.1:1455` (repli `:1457`), et la
page de connexion tourne dans un **processus séparé** d'iOS qui doit réussir à le joindre.
Ça marche sur un Mac ; sur iOS, personne ici ne l'a jamais vu tourner.

**Distinguer les deux échecs possibles**, ils n'ont pas la même conséquence :

| Ce que tu vois | Ce que ça dit |
|---|---|
| « Impossible de recevoir la réponse de connexion (port local indisponible). Réessaie. » | le serveur local n'a pas pu se lier au port, ou a été fermé trop tôt |
| la page reste blanche / « Safari ne peut pas ouvrir la page » après autorisation | la redirection n'atteint pas l'app : **c'est le scénario qui condamne ce flux sur iOS** |
| « Impossible d'identifier le compte ChatGPT dans la réponse. Réessaie. » | le login a marché, c'est la lecture de l'`id_token` qui coince |

**Important si tu réessaies** : appuyer sur **« Annuler »** avant de relancer. Sortir de
l'écran en cours de tentative annule aussi proprement. Enchaîner sans annuler laisse le
port occupé et le deuxième essai échouera pour une raison qui n'est pas la vraie.

## A5 — Le dashboard dit-il vrai ? · *critère 3*

**Gestes** : onglet **Tableau de bord**.

**Attendu** — pour Claude : **« Session (5 h) »** et **« Hebdomadaire »**, chacune avec sa
jauge, son pourcentage et **« Reset dans … »** (ou **« Fenêtre inactive »** si aucune session
n'est en cours — c'est normal, pas un bug). Pour Codex : ses fenêtres, plus
**« Crédits de reset disponibles : N »** s'il y en a. En haut de chaque carte,
**« à jour il y a N min »**.

**La vérification qui compte** : lancer `/usage` dans Claude Code sur le PC et **comparer les
pourcentages**. C'est la seule chose au monde qui prouve que le parsing dit vrai sur un compte
réel — les 300 tests ne valident que 4 fixtures capturées un jour donné, sur un compte, avec
un plan. Un écart de plus d'un point de pourcentage est un `FAIL`, même petit : il signifie
qu'on ne lit pas le bon champ.

**À noter aussi** : un chiffre manifestement absurde (un pourcentage au-dessus de 100, une
date de reset dans plusieurs siècles) est un `FAIL` intéressant — le second est le bug
`reset_at` en millisecondes documenté dans `TASKS.md`.

## A6 — Widgets écran d'accueil · *critère 4*

**Gestes** : poser **« Limites d'usage »** en **petit**, puis en **moyen**, puis en **grand**.

**Attendu** : petit = une jauge (la fenêtre la plus urgente) + le compte à rebours ; moyen =
les deux providers côte à côte ; grand = le détail des deux. En bas, **« à jour … »**.

**La vérification qui compte** : le pourcentage du widget doit être **exactement** celui du
dashboard, au chiffre près. L'arrondi est partagé entre l'app et le widget — un écart
signifierait qu'il ne l'est plus.

## A7 — Widgets écran verrouillé · *critère 4*

**Gestes** : verrouiller → appui long → Personnaliser → l'écran verrouillé → ajouter les
widgets Limits : le **circulaire**, le **rectangulaire**, et **la ligne au-dessus de l'heure**
(inline).

**Attendu** : les trois affichent une donnée lisible, pas un carré vide.

**Ce qu'il faut vérifier spécifiquement** : iOS **écrase les couleurs** sur l'écran verrouillé
(rendu monochrome). L'urgence doit donc rester lisible **sans couleur**, via le symbole et le
mot : `✓` pour OK, `⚠` **Attention** au-dessus de 80 %, `⛔` **Critique** au-dessus de 95 %.
Si tu ne peux pas dire d'un coup d'œil, écran verrouillé, si une fenêtre est en danger, c'est
un `FAIL` — c'est précisément la raison d'être de ce widget.

## A8 — Les comptes à rebours défilent · *critère 4*

**Attendu** : une échéance **à moins de 24 h** défile toute seule, seconde par seconde, sans
rien toucher (« Reset dans 2:14:33 »). Au-delà de 24 h, c'est un libellé relatif figé
(« Reset dans 6 j ») — **c'est voulu**, pas un compte à rebours cassé.

**À noter** : une fenêtre dont l'heure de reset est passée doit afficher
**« Réinitialisation attendue »**, jamais un compte à rebours négatif.

## A9 — Autoriser les notifications

**Gestes** : Réglages → section **Notifications** → **« Autoriser les notifications »** →
accepter la demande système.

L'app ne demande jamais cette autorisation au premier lancement, volontairement : un prompt
système sans contexte se fait refuser, et un refus est pénible à rattraper.

**Sans ce PASS, les tests B3, B4 et B5 ne veulent rien dire** — ne les interprète pas.

## A10 — Réseau coupé · *robustesse*

**Gestes** : mode avion → tirer vers le bas sur le tableau de bord.

**Attendu** : les derniers chiffres **restent affichés** (jamais d'écran vide), plus un bandeau
orange **« Erreur réseau — nouvelle tentative dans N s. »**. Aucun crash. Désactiver le mode
avion, retirer vers le bas : les chiffres se remettent à jour.

## A11 — L'anti-429 fait son travail · *comportement attendu, pas un bug*

**Gestes** : tirer pour rafraîchir, puis **recommencer dans les 30 secondes**.

**Attendu** : une alerte titrée **« Rafraîchissement »** disant
**« Merci de patienter encore N s avant de rafraîchir à nouveau. »** Le minimum entre deux
rafraîchissements manuels est de 60 s ; en automatique, 15 min.

**C'est un `PASS` quand le rafraîchissement est refusé.** Un `FAIL` serait qu'il parte quand
même (on brûle du quota et on risque un 429), ou qu'il ne se passe **rien du tout** sans
explication — un pull-to-refresh silencieux passe pour une app cassée.

---

# Séance B — l'arrière-plan (quelques heures plus tard → J+1)

Ces tests ne se forcent pas : sans Xcode, on ne peut pas déclencher une `BGAppRefreshTask` à
la demande. iOS la programme de façon **opportuniste** — de 15 minutes à plusieurs heures
selon la batterie, le réseau et l'usage de l'app. Il faut donc laisser faire et revenir voir.

## B1 — La tâche de fond tourne-t-elle vraiment ? · *critère 5*

**Gestes** :
1. Ouvrir l'app (elle rafraîchit), **noter l'heure**.
2. Repasser à l'écran d'accueil — c'est ce passage en arrière-plan qui planifie la tâche.
3. Ne plus toucher à l'app pendant **au moins 2 h**. Laisser le téléphone vivre sa vie.
4. **Regarder le widget sans ouvrir l'app.** ← le point important : l'ouvrir déclenche un
   rafraîchissement et détruit la mesure.

**Comment lire le résultat**, dans le pied du widget :

| Ce que tu lis | Verdict |
|---|---|
| « à jour il y a 20 min » après 2 h d'attente | **PASS** — iOS nous a réveillés |
| « à jour il y a 2 h » + bandeau **« Données pas encore actualisées »** | le fond n'a pas tourné (le bandeau apparaît au-delà de 30 min) |
| bandeau **« Données non rafraîchies depuis un moment »** | plus de 6 h sans succès : le fond ne tourne pas du tout |

**Si c'est un `FAIL`** : ce n'est pas bloquant pour le produit — l'app est correcte dès qu'on
l'ouvre, seuls les widgets vieillissent. Mais dis-le, ça change ce qu'on peut promettre. Un
`FAIL` peut aussi venir du mode économie d'énergie : précise s'il était actif.

## B2 — Le widget suit une vraie session PC · *critère 5*

**Gestes** : noter le pourcentage affiché par le widget, faire une vraie session Claude Code
sur le PC (assez longue pour bouger le compteur), puis regarder le widget dans l'heure — **sans
ouvrir l'app**.

**Attendu** : le pourcentage monte tout seul. C'est le scénario d'usage réel du produit : voir
sur son téléphone ce qu'on est en train de consommer sur son PC.

## B3 — Notification de réinitialisation · *critère 6*

Celle-ci est programmée **à l'avance**, à l'heure de reset de la fenêtre — elle arrive donc
même si l'app n'a pas tourné depuis longtemps. La fenêtre 5 h de Claude donne une échéance à
quelques heures : il suffit d'attendre la première.

**Attendu**, texte littéral : titre **« Claude — limite réinitialisée »**, corps
**« Ta fenêtre « Session (5 h) » repart de zéro. »**

**`FAIL` intéressant** : recevoir cette notification pour un reset **déjà passé** au lancement
suivant (une alerte en retard de plusieurs heures).

## B4 — Notification de seuil · *conditionnel*

Celle-ci ne peut être constatée qu'**au moment d'un fetch**, donc seulement si le fond tourne
(B1) ou si tu ouvres l'app au bon moment.

**Gestes** : Réglages → **« Seuil d'alerte »**, curseur réglable de 50 à 100 %. Descendre le
seuil **juste sous un usage réel en cours**, puis attendre un rafraîchissement.

**Attendu** : titre **« Claude — 80 % atteint »** (le nombre suit ton réglage), corps
**« Fenêtre « Session (5 h) » à N %. »**

**Si aucune de tes fenêtres ne dépasse 50 %** : marquer **BLOQUÉ**, ne pas chercher à
simuler. Le curseur ne descend pas plus bas, c'est délibéré.

## B5 — Pas de notification en double

**Attendu** : après B3 ou B4, **aucune répétition** du même seuil aux rafraîchissements
suivants (toutes les 15 min, ce serait insupportable). Le seuil ne doit se ré-annoncer
qu'après une **réinitialisation** de la fenêtre — c'est-à-dire au cycle suivant.

**`FAIL`** : la même alerte revient plusieurs fois pour la même fenêtre.

---

# Séance C — J+7, la re-signature

Le certificat gratuit expire au bout de 7 jours. **C'est la re-signature qui casse les App
Groups, pas l'installation initiale** : un A2 réussi à J0 ne vaut pas verdict tant que C2
n'est pas passé.

## C1 — Le renouvellement Wi-Fi a-t-il marché ? · *critère 7*

> **Voie ARM64 (celle qui est en place)** : il n'y a plus de PC dans la boucle. Le test
> devient **« SideStore a-t-il re-signé Limits tout seul avant l'expiration ? »** — ouvrir
> SideStore et vérifier que Limits n'est pas expiré, sans rien brancher.
> *(Sur un PC x64 emprunté, ce test serait au contraire **BLOQUÉ par construction** : le
> renouvellement suppose la machine allumée sur le même Wi-Fi chaque semaine.)*

**Attendu** : avec l'auto-refresh Sideloadly activé (§5) et le PC allumé sur le même Wi-Fi,
l'app se relance sans rien rebrancher. **`FAIL`** : « Unable to verify app » au lancement — il
faut alors rebrancher l'USB et refaire §3 (2 min, les données sont conservées).

## C2 — Qu'est-ce qui a survécu ? · *critère 7 — le vrai verdict du gate*

**Gestes**, dans cet ordre :
1. Lancer l'app : les deux comptes sont-ils toujours **« Compte connecté. »** ? (si non, le
   Keychain n'a pas survécu → il faut se reconnecter à chaque re-signature, c'est-à-dire
   toutes les semaines)
2. Le dashboard affiche-t-il encore les derniers chiffres connus ?
3. **Refaire A2 en entier.** Le compteur du widget suit-il toujours celui de l'app ?

**C'est ce point 3 qui rend le verdict T1.4.**

## C3 — Les widgets sont-ils toujours là ? · *critère 7*

**Attendu** : toujours posés sur l'écran d'accueil et l'écran verrouillé, et affichant des
données — pas **« App Group indisponible »**, pas **« Aucune donnée »**.

---

# Ce que chaque échec déclenche

| Échec | Conséquence |
|---|---|
| **A0 KO** (iPhone invisible depuis Linux) | Rien n'est testable, et **le produit n'est pas en cause**. Reprendre au maillon qui a lâché (`SIDELOAD-ARM64.md`, « Si la chaîne casse ») ; en dernier recours, PC x64 emprunté. Tant que ce n'est pas réglé, le gate M1 reste ouvert. |
| **A2 ou C2 KO** (le compteur du widget ne suit pas) | Verdict de gate **négatif**. On tente d'abord **AltStore**, qui gère mieux les app groups. Si ça résiste : bascule vers « le widget fetch lui-même ». C'est pré-câblé — le widget lit à travers `SnapshotSource`, seul le fournisseur change, rien d'autre du code n'est remis en cause. |
| **A2 ligne Keychain KO** | Non bloquant en v1 : les widgets n'ont besoin d'aucun token. À signaler, ça peut vouloir dire une reconnexion par semaine (cf. C2.1). |
| **A4 KO** (redirection non captée) | Le flux OAuth Codex est à repenser sur iOS — le serveur loopback est le point faible. Claude reste utilisable seul entre-temps : l'app fonctionne avec un seul provider connecté. |
| **A5 écart de pourcentage** | Le parsing lit le mauvais champ sur ton compte. Il faut régénérer les fixtures (`scripts/capture-fixtures.ps1`) et corriger le décodeur — les tests actuels valident un cas qui n'est pas le tien. |
| **B1 KO** | Dégradation, pas blocage : l'app est juste à l'ouverture, les widgets vieillissent. Change ce qu'on promet, pas l'architecture. |
| **A1 KO** (pas de widget dans la galerie) | Réinstaller sans retirer les PlugIns ; sinon AltStore. Rien d'autre n'est testable avant. |

# Couverture des 7 critères de `TASKS.md`

| # | Critère | Tests |
|---|---|---|
| 0 | *(préalable)* le PC voit-il l'iPhone ? | **A0** — bloquant sur PC ARM64 |
| 1 | CI verte (tests + IPA) | déjà acquis · A1 pour l'installabilité |
| 2 | Login Claude **et** Codex | A3, A4 |
| 3 | Dashboard = vraies fenêtres + crédits | A5 |
| 4 | Widgets home + lock, comptes à rebours | A6, A7, A8 |
| 5 | Widget rafraîchi après une session PC | B1, B2 |
| 6 | Notification locale à un reset | A9, B3, B4, B5 |
| 7 | J+7 : re-signature OK, données conservées | C1, C2, C3 |
| — | Gate M1 (T1.2 → verdict T1.4) | **A2, puis C2** |

# Ce qui n'est pas testable sur device, et pourquoi

À dire clairement plutôt qu'à laisser croire que tout a été vérifié :

- **L'état « Format d'API inattendu — mise à jour requise »** : il faudrait qu'un provider
  renomme ses champs pour le déclencher. Il n'est couvert que par des tests automatisés.
- **Le vrai 429** : on ne va pas le provoquer pour le voir (règle 7 d'AGENTS.md). A11 teste
  le garde-fou qui l'évite, ce qui n'est pas la même chose que tester la réaction à un 429.
- **La course sur le journal des notifications** (app et tâche de fond simultanées) : au pire
  une notification en double, auto-réparée au fetch suivant. Non reproductible à la main.
- **Les alias de champs Codex** (`five_hour_limit`…) : aucune capture réelle ne les exerce,
  seulement des tests synthétiques. Si Codex renvoie ces variantes sur ton compte, A5 le
  révélera sous la forme d'une fenêtre manquante.

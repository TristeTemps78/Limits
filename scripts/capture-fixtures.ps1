# capture-fixtures.ps1 — capture les réponses RÉELLES des endpoints d'usage
# Claude Code & Codex, les anonymise, et les écrit dans fixtures/.
#
# À exécuter UNIQUEMENT sur le PC de Tristan (lit ~\.claude\.credentials.json et
# ~\.codex\auth.json). JAMAIS en CI. Les fixtures produites sont committées : elles
# sont la source de vérité du parsing dans LimitsCore (cf. AGENTS.md §3).
#
# Usage : powershell -ExecutionPolicy Bypass -File scripts\capture-fixtures.ps1

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoRoot = Split-Path -Parent $PSScriptRoot
$fixturesDir = Join-Path $repoRoot 'fixtures'
New-Item -ItemType Directory -Force -Path $fixturesDir | Out-Null

# ---------------------------------------------------------------- credentials ---
$claudeCredPath = Join-Path $env:USERPROFILE '.claude\.credentials.json'
$codexAuthPath  = Join-Path $env:USERPROFILE '.codex\auth.json'

if (-not (Test-Path $claudeCredPath)) { throw "Introuvable : $claudeCredPath (lance 'claude' et connecte-toi)" }
if (-not (Test-Path $codexAuthPath))  { throw "Introuvable : $codexAuthPath (lance 'codex login')" }

$claudeCreds  = Get-Content $claudeCredPath -Raw | ConvertFrom-Json
$claudeToken  = $claudeCreds.claudeAiOauth.accessToken
$codexAuth    = Get-Content $codexAuthPath -Raw | ConvertFrom-Json
$codexToken   = $codexAuth.tokens.access_token
$codexAccount = $codexAuth.tokens.account_id

if (-not $claudeToken)  { throw 'Token Claude absent de .credentials.json' }
if (-not $codexToken)   { throw 'Token Codex absent de auth.json' }

# Avertit si le token Claude est expiré (expiresAt en millisecondes epoch)
$claudeExpiresAt = $claudeCreds.claudeAiOauth.expiresAt
if ($claudeExpiresAt) {
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    if ($nowMs -gt [long]$claudeExpiresAt) {
        Write-Warning "Token Claude expiré — lance une commande 'claude' pour le rafraîchir, puis relance ce script."
    }
}

# Version de Claude Code locale pour le User-Agent (fallback si introuvable)
$claudeVersion = '2.0.0'
try {
    $v = & claude --version
    if ("$v" -match '(\d+\.\d+\.\d+)') { $claudeVersion = $Matches[1] }
} catch {}
Write-Host "User-Agent Claude : claude-code/$claudeVersion"

# -------------------------------------------------------------- anonymisation ---
# Remplace récursivement les valeurs des clés sensibles. Les clés structurelles du
# parsing (utilization, resets_at, used_percent, windows, credits...) ne matchent pas.
$redactPattern = '(?i)email|name|account|user|org|phone|picture|address|^sub$|^id$|uuid|token|session'

function Sanitize($obj) {
    if ($null -eq $obj) { return }
    if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
        foreach ($item in $obj) { Sanitize $item }
        return
    }
    if ($obj -is [PSCustomObject]) {
        foreach ($prop in $obj.PSObject.Properties) {
            $isLeaf = ($prop.Value -is [string]) -or ($prop.Value -is [ValueType])
            if ($isLeaf) {
                if ($prop.Name -match $redactPattern -and $prop.Value -is [string] -and $prop.Value.Length -gt 0) {
                    $prop.Value = 'REDACTED'
                }
            } else {
                Sanitize $prop.Value
            }
        }
    }
}

# -------------------------------------------------------------------- capture ---
$script:report = @()

function Capture([string]$name, [string]$url, [hashtable]$headers, [string]$userAgent) {
    $outPath = Join-Path $fixturesDir "$name.json"
    try {
        $resp = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -UserAgent $userAgent -TimeoutSec 30
        Sanitize $resp
        $resp | ConvertTo-Json -Depth 20 | Out-File $outPath -Encoding utf8
        $script:report += "| ``$name`` | **200 OK** | $url |"
        Write-Host "[OK]   $name -> $outPath"
    } catch {
        $status = '(réseau)'
        try { if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode } } catch {}
        $script:report += "| ``$name`` | **ERREUR $status** | $url |"
        Write-Host "[FAIL] $name : HTTP $status — $($_.Exception.Message)"
    }
}

$claudeHeaders = @{
    'Authorization'  = "Bearer $claudeToken"
    'anthropic-beta' = 'oauth-2025-04-20'
}
Capture 'claude-usage' 'https://api.anthropic.com/api/oauth/usage' $claudeHeaders "claude-code/$claudeVersion"

$codexHeaders = @{
    'Authorization'      = "Bearer $codexToken"
    'ChatGPT-Account-ID' = $codexAccount
    'originator'         = 'codex_cli_rs'
}
Capture 'codex-usage'   'https://chatgpt.com/backend-api/wham/usage'                    $codexHeaders 'codex_cli_rs'
Capture 'codex-credits' 'https://chatgpt.com/backend-api/wham/rate-limit-reset-credits' $codexHeaders 'codex_cli_rs'
Capture 'codex-profile' 'https://chatgpt.com/backend-api/wham/profiles/me'              $codexHeaders 'codex_cli_rs'

# --------------------------------------------------------------------- rapport ---
$reportPath = Join-Path $fixturesDir 'capture-report.md'
$lines = @(
    '# Rapport de capture des fixtures'
    ''
    "Capture du $(Get-Date -Format 'yyyy-MM-dd HH:mm') (locale). User-Agent Claude : ``claude-code/$claudeVersion``."
    "Headers Claude : ``anthropic-beta: oauth-2025-04-20``. Headers Codex : ``ChatGPT-Account-ID`` + ``originator: codex_cli_rs``."
    ''
    '| Fixture | Statut | Endpoint |'
    '|---|---|---|'
) + $script:report + @(
    ''
    'Valeurs sensibles remplacées par `REDACTED` (clés email/nom/compte/ids/tokens).'
    'Régénération : `powershell -ExecutionPolicy Bypass -File scripts\capture-fixtures.ps1`.'
)
$lines -join "`n" | Out-File $reportPath -Encoding utf8
Write-Host "Rapport : $reportPath"

# Gungeon modpack launcher: the desktop shortcut runs this. It brings the modpack up to date from
# github.com/Kewz4/gungeon-modpack (manifest.txt: "sha256 path" per line, paths relative to BepInEx), then starts the game.
# Nothing is running yet, so every file can be replaced. No internet: the game starts as it is after a few seconds.
#   -Game     folder with EtG.exe (default: the folder above BepInEx)
#   -BepInEx  the BepInEx folder to update (default: the folder this script is in, two levels up)
#   -Doorstop load BepInEx from -BepInEx through launch options (a mod manager profile; the game folder has no BepInEx)
#   -GameArgs extra arguments for EtG.exe
param([string]$Game, [string]$BepInEx, [switch]$Doorstop, [string]$GameArgs = '')
$ErrorActionPreference = 'Stop'
$base = 'https://raw.githubusercontent.com/Kewz4/gungeon-modpack/main/'
if (-not $BepInEx) { $BepInEx = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path) }
if (-not $Game) { $Game = Split-Path -Parent $BepInEx }
$curl = Join-Path $env:SystemRoot 'System32\curl.exe'
$log = Join-Path $BepInEx 'modpack\launcher.log'
function Note($m) { try { Add-Content $log ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $m) } catch { } }

function Sha256($f) { (Get-FileHash $f -Algorithm SHA256).Hash.ToLower() }

try {
    if ((Test-Path $curl) -and -not (Test-Path (Join-Path $BepInEx 'config\modpack-no-autoupdate')) -and -not (Get-Process EtG -ErrorAction SilentlyContinue)) {
        $manifest = & $curl -s -f -L --connect-timeout 4 -m 8 ($base + 'manifest.txt?t=' + [DateTime]::UtcNow.Ticks)
        if ($LASTEXITCODE -eq 0 -and $manifest) {
            $changed = 0; $failed = 0
            foreach ($line in $manifest) {
                $line = "$line".Trim()
                if ($line -notmatch '^([0-9a-f]{64}) (.+)$') { continue }
                $hash = $Matches[1]; $rel = $Matches[2].Trim().Replace('\', '/')
                if ($rel.Contains('..') -or $rel -notmatch '^(plugins|patchers|config|modpack)/') { continue }
                $local = Join-Path $BepInEx $rel.Replace('/', '\')
                if ((Test-Path $local) -and (Sha256 $local) -eq $hash) { continue }
                $tmp = "$local.download"
                try {
                    New-Item -ItemType Directory -Force (Split-Path -Parent $local) | Out-Null
                    # ?v= : GitHub keeps files cached for a few minutes; a new fingerprint is a new address
                    & $curl -s -f -L --connect-timeout 4 -m 120 -o $tmp ($base + 'BepInEx/' + [Uri]::EscapeUriString($rel) + '?v=' + $hash)
                    if ($LASTEXITCODE -ne 0 -or (Sha256 $tmp) -ne $hash) { throw 'download failed or did not match' }
                    Move-Item $tmp $local -Force
                    $changed++
                } catch { $failed++; Note "could not update ${rel}: $_"; Remove-Item $tmp -ErrorAction SilentlyContinue }
            }
            Note "update check: $changed updated, $failed failed"
        } else { Note 'update check skipped (no connection)' }
    }
} catch { Note "update check failed: $_" }

if ($Doorstop) { $GameArgs = ('--doorstop-enable true --doorstop-target "' + (Join-Path $BepInEx 'core\BepInEx.Preloader.dll') + '" ' + $GameArgs).Trim() }
$exe = Join-Path $Game 'EtG.exe'
if ($GameArgs) { Start-Process $exe -WorkingDirectory $Game -ArgumentList $GameArgs } else { Start-Process $exe -WorkingDirectory $Game }

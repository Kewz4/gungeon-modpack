# Gungeon modpack launcher: the desktop shortcut runs this. It brings the modpack up to date from
# github.com/Kewz4/gungeon-modpack (manifest.txt: "sha256 path" per line, paths relative to BepInEx), then starts the game.
# Nothing is running yet, so every file can be replaced. No internet: the game starts as it is after a few seconds.
# A small window shows what it is doing, so a double-click visibly does something.
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

# .NET directly: Get-FileHash lives in a module that some PCs (PowerShell 7 installed alongside) fail to load here.
function Sha256($f)
{
    $s = [IO.File]::OpenRead($f)
    try { -join ([Security.Cryptography.SHA256]::Create().ComputeHash($s) | ForEach-Object { $_.ToString('x2') }) }
    finally { $s.Dispose() }
}

# ---------- status window ----------
$form = $null; $label = $null
try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $form = New-Object System.Windows.Forms.Form -Property @{
        Text = 'Enter the Gungeon Modpack'; ClientSize = New-Object System.Drawing.Size(380, 96); FormBorderStyle = 'FixedDialog'
        MaximizeBox = $false; MinimizeBox = $false; ControlBox = $false; StartPosition = 'CenterScreen'; TopMost = $true
        BackColor = [System.Drawing.Color]::FromArgb(250, 247, 242)
    }
    try { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon((Join-Path $Game 'EtG.exe')) } catch { }
    $label = New-Object System.Windows.Forms.Label -Property @{
        Dock = 'Fill'; TextAlign = 'MiddleCenter'; Font = New-Object System.Drawing.Font('Segoe UI', 10)
        ForeColor = [System.Drawing.Color]::FromArgb(91, 74, 58); Text = 'Checking for modpack updates...'
    }
    $form.Controls.Add($label)
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
} catch { $form = $null }
function Status($text) { if ($form) { $label.Text = $text; [System.Windows.Forms.Application]::DoEvents() } }
function Done { if ($form) { $form.Close(); $form.Dispose() } }

if (Get-Process EtG -ErrorAction SilentlyContinue) {
    Status 'The game is already running.'
    Start-Sleep -Milliseconds 1800
    Done
    exit
}

# ---------- update ----------
try {
    if ((Test-Path $curl) -and -not (Test-Path (Join-Path $BepInEx 'config\modpack-no-autoupdate'))) {
        $manifest = & $curl -s -f -L --connect-timeout 4 -m 8 ($base + 'manifest.txt?t=' + [DateTime]::UtcNow.Ticks)
        if ($LASTEXITCODE -eq 0 -and $manifest) {
            # First what needs downloading, so the window can count.
            $todo = @()
            foreach ($line in $manifest) {
                $line = "$line".Trim()
                if ($line -notmatch '^([0-9a-f]{64}) (.+)$') { continue }
                $hash = $Matches[1]; $rel = $Matches[2].Trim().Replace('\', '/')
                if ($rel.Contains('..') -or $rel -notmatch '^(plugins|patchers|config|modpack)/') { continue }
                $local = Join-Path $BepInEx $rel.Replace('/', '\')
                if ((Test-Path $local) -and (Sha256 $local) -eq $hash) { continue }
                $todo += ,@($hash, $rel, $local)
            }
            $changed = 0; $failed = 0
            foreach ($t in $todo) {
                $hash, $rel, $local = $t
                Status ("Updating the modpack ({0} of {1})...`n{2}" -f ($changed + $failed + 1), $todo.Count, (Split-Path -Leaf $rel))
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
            if ($failed -gt 0) { Status "Some updates didn't download; they'll be tried next time.`nStarting the game..." }
            elseif ($changed -gt 0) { Status "Modpack updated. Starting the game..." }
            else { Status "Modpack is up to date. Starting the game..." }
        } else { Note 'update check skipped (no connection)'; Status "Couldn't check for updates (no connection).`nStarting the game..." }
    }
} catch { Note "update check failed: $_"; Status 'Starting the game...' }

# ---------- start ----------
try {
    if ($Doorstop) { $GameArgs = ('--doorstop-enable true --doorstop-target "' + (Join-Path $BepInEx 'core\BepInEx.Preloader.dll') + '" ' + $GameArgs).Trim() }
    $exe = Join-Path $Game 'EtG.exe'
    if ($GameArgs) { Start-Process $exe -WorkingDirectory $Game -ArgumentList $GameArgs } else { Start-Process $exe -WorkingDirectory $Game }
    Start-Sleep -Milliseconds 1500
    Done
} catch {
    Note "could not start the game: $_"
    Done
    try { [void][System.Windows.Forms.MessageBox]::Show("The game could not be started:`n$($_.Exception.Message)", 'Enter the Gungeon Modpack', 'OK', 'Error') } catch { }
}

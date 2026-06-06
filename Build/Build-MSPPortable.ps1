<#
.SYNOPSIS
    Bundle the entire MSP Toolkit into a single self-extracting .ps1
    you can drop on a USB stick.
.DESCRIPTION
    Walks the repository, embeds every .ps1 / .psm1 / .psd1 / .json / .yml
    file as a base64 blob, and emits MSPToolkit.Portable.ps1 in dist/.

    At runtime the portable file:
      1. Creates %TEMP%\MSPToolkit_<hash>\ (idempotent -- reuses if hash matches)
      2. Decodes every embedded file
      3. Imports the module
      4. Launches the GUI (or console fallback)
      5. Optionally cleans up on exit (default: keep for fast re-launch)

    Also produces:
      - dist\MSPToolkit.zip            -- same content as a normal zip
      - dist\MSPToolkit.Portable.bat   -- double-click launcher that
        bypasses PowerShell execution policy
      - dist\MSPToolkit.Portable.exe   -- if PS2EXE is installed

.PARAMETER OutputDir
    Where to drop the artifacts. Defaults to <repo>\dist.
.PARAMETER SkipZip
    Skip the .zip output.
.PARAMETER SkipExe
    Skip the .exe (PS2EXE) output even if PS2EXE is available.
.PARAMETER Sign
    Attempt to sign the portable .ps1 using a code-signing cert from
    Cert:\CurrentUser\My.
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputDir,
    [switch]$SkipZip,
    [switch]$SkipExe,
    [switch]$Sign
)

$ErrorActionPreference = 'Stop'

function ConvertTo-MSPHex {
    param([Parameter(Mandatory)] [byte[]]$Bytes)
    ([BitConverter]::ToString($Bytes)).Replace('-','')
}

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) { $OutputDir = Join-Path $repoRoot 'dist' }
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

Write-Host "Bundling MSP Toolkit from $repoRoot" -ForegroundColor Cyan
Write-Host "Output: $OutputDir" -ForegroundColor Cyan

$include = @(
    'Core\*.psm1','Core\*.psd1',
    'Integrations\*.psm1',
    'MSP_Tier3_Toolkit\*.ps1','MSP_Tier3_Toolkit\*\*.ps1',
    'GUI\*.ps1',
    'Tools\*.ps1',
    'Templates\*.json',
    'Playbooks\*.json',
    'assets\*',
    'config.json',
    'USB_DEPLOYMENT.md'
)

$files = @()
foreach ($pat in $include) {
    $files += Get-ChildItem -Path (Join-Path $repoRoot $pat) -File -ErrorAction SilentlyContinue
}
$files = $files | Sort-Object FullName -Unique

if (-not $files.Count) { throw 'No files matched the include patterns.' }
Write-Host "Bundling $($files.Count) files..." -ForegroundColor Yellow

$manifest = New-Object System.Collections.Generic.List[pscustomobject]
$bundleHasher = [System.Security.Cryptography.SHA256]::Create()
$concat = New-Object System.IO.MemoryStream
foreach ($f in $files) {
    $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\','/')
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $b64   = [Convert]::ToBase64String($bytes)
    $sha   = ConvertTo-MSPHex -Bytes ([System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes))
    $manifest.Add([pscustomobject]@{ Path=$rel; Bytes=$bytes.Length; SHA256=$sha; B64=$b64 })
    $concat.Write($bytes, 0, $bytes.Length)
}
$concat.Position = 0
$bundleHash = (ConvertTo-MSPHex -Bytes ($bundleHasher.ComputeHash($concat))).Substring(0,16)

Write-Host "Bundle hash: $bundleHash" -ForegroundColor Gray

$payloadSb = New-Object System.Text.StringBuilder
[void]$payloadSb.Append('@{')
foreach ($m in $manifest) {
    $escPath = $m.Path -replace "'","''"
    [void]$payloadSb.AppendLine()
    [void]$payloadSb.Append("'$escPath' = '$($m.B64)';")
}
[void]$payloadSb.Append('}')

$header = @'
<#
    Sentinel Recon Portable -- self-extracting single-file bundle.

    Drop on a USB stick or drag-and-drop onto any Windows 10/11 box.
    Double-click SentinelRecon.Portable.bat (alongside this file), or right-
    click this .ps1 and pick "Run with PowerShell".

    On launch:
      1. Extracts to %TEMP%\SentinelRecon_<hash>\
      2. Re-uses the same folder on subsequent runs (fast)
      3. Launches the GUI; falls back to console if no display

    BUNDLE HASH: __BUNDLE_HASH__
    BUNDLED ON:  __BUILD_DATE__
    FILE COUNT:  __FILE_COUNT__
#>

[CmdletBinding()]
param(
    [switch]$Console,
    [switch]$ApiOnly,
    [switch]$Extract,
    [string]$ExtractTo,
    [switch]$KeepOpen,
    [switch]$NoSplash
)

$ErrorActionPreference = 'Stop'
$bundleHash = '__BUNDLE_HASH__'
$buildDate  = '__BUILD_DATE__'

if (-not $ExtractTo) {
    $ExtractTo = Join-Path $env:TEMP "SentinelRecon_$bundleHash"
}

Write-Host ""
Write-Host "  SENTINEL RECON PORTABLE" -ForegroundColor Cyan
Write-Host "  Bundle: $bundleHash (built $buildDate)" -ForegroundColor DarkGray
Write-Host "  Extract: $ExtractTo" -ForegroundColor DarkGray
Write-Host ""

$marker = Join-Path $ExtractTo '.bundle-hash'
$needExtract = $true
if ((Test-Path $marker) -and (Get-Content $marker -ErrorAction SilentlyContinue) -eq $bundleHash) {
    Write-Host "  Cached copy is current -- skipping extract." -ForegroundColor Green
    $needExtract = $false
}

if ($needExtract) {
    if (Test-Path $ExtractTo) { Remove-Item -Recurse -Force $ExtractTo }
    New-Item -ItemType Directory -Path $ExtractTo -Force | Out-Null

    $payload = __PAYLOAD__

    Write-Host "  Extracting $($payload.Count) files..." -ForegroundColor Yellow
    foreach ($k in $payload.Keys) {
        $target = Join-Path $ExtractTo $k
        $dir = Split-Path -Parent $target
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllBytes($target, [Convert]::FromBase64String($payload[$k]))
    }
    Set-Content -Path $marker -Value $bundleHash -Encoding UTF8
    Write-Host "  Done." -ForegroundColor Green
}

if ($Extract) { Write-Host "Extract-only mode complete: $ExtractTo"; return }

$guiPath  = Join-Path $ExtractTo 'GUI\MSPToolkit.GUI.ps1'
$apiPath  = Join-Path $ExtractTo 'Tools\Start-MSPApi.ps1'
$modPath  = Join-Path $ExtractTo 'Core\MSPToolkit.psd1'

if ($ApiOnly) {
    & $apiPath -OpenBrowser
    return
}

if ($Console) {
    Write-Host "  Importing module..." -ForegroundColor Yellow
    Import-Module $modPath -Force
    Write-Host "  Imported. Available commands:" -ForegroundColor Green
    Get-Command -Module MSPToolkit | Format-Table Name, ModuleName
    if ($KeepOpen) { Read-Host "Press Enter to exit" }
    return
}

try {
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Write-Host "  Launching GUI..." -ForegroundColor Green
    $splashArg = if ($NoSplash) { '-NoSplash' } else { '' }
    & $guiPath -ToolkitRoot $ExtractTo $splashArg
} catch {
    Write-Host "  WPF unavailable -- starting API + opening browser." -ForegroundColor Yellow
    & $apiPath -OpenBrowser
}

if ($KeepOpen) { Read-Host "Press Enter to exit" }
'@

$final = $header
$final = $final.Replace('__BUNDLE_HASH__', $bundleHash)
$final = $final.Replace('__BUILD_DATE__', (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$final = $final.Replace('__FILE_COUNT__', "$($files.Count)")
$final = $final.Replace('__PAYLOAD__', $payloadSb.ToString())

$portablePath = Join-Path $OutputDir 'SentinelRecon.Portable.ps1'
$bom   = [byte[]](0xEF,0xBB,0xBF)
$bytes = [System.Text.Encoding]::UTF8.GetBytes($final)
[System.IO.File]::WriteAllBytes($portablePath, $bom + $bytes)
$portableSizeMB = [math]::Round((Get-Item $portablePath).Length / 1MB, 2)
Write-Host "Wrote $portablePath ($portableSizeMB MB)" -ForegroundColor Green

if ($Sign) {
    try {
        $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Select-Object -First 1
        if (-not $cert) {
            Write-Warning "No code-signing certificate found in CurrentUser\My. Skip -Sign or import a cert first."
        } else {
            Set-AuthenticodeSignature -FilePath $portablePath -Certificate $cert | Out-Null
            Write-Host "Signed: $portablePath" -ForegroundColor Green
        }
    } catch {
        Write-Warning "Signing failed: $($_.Exception.Message)"
    }
}

$batPath = Join-Path $OutputDir 'SentinelRecon.Portable.bat'
$batBody = @'
@echo off
REM Sentinel Recon Portable launcher.
REM Bypasses execution policy and STA-marshals so WPF works.
setlocal
set HERE=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%HERE%SentinelRecon.Portable.ps1" %*
'@
Set-Content -LiteralPath $batPath -Value $batBody -Encoding ASCII
Write-Host "Wrote $batPath" -ForegroundColor Green

if (-not $SkipZip) {
    $zipPath = Join-Path $OutputDir 'SentinelRecon.zip'
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    $tempStage = Join-Path $env:TEMP "MSPToolkitStage_$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $tempStage -Force | Out-Null
    foreach ($f in $files) {
        $rel = $f.FullName.Substring($repoRoot.Length).TrimStart('\','/')
        $dest = Join-Path $tempStage $rel
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    }
    Compress-Archive -Path "$tempStage\*" -DestinationPath $zipPath -Force
    Remove-Item -Recurse -Force $tempStage
    $zipMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)
    Write-Host "Wrote $zipPath ($zipMB MB)" -ForegroundColor Green
}

if (-not $SkipExe -and (Get-Module -ListAvailable -Name PS2EXE)) {
    try {
        Import-Module PS2EXE -Force
        $exePath = Join-Path $OutputDir 'SentinelRecon.Portable.exe'
        Invoke-PS2EXE -InputFile $portablePath -OutputFile $exePath -STA -NoConsole:$false `
                      -Title 'Sentinel Recon' -Company 'Sentinel' -Version '25.0.0.0'
        Write-Host "Wrote $exePath" -ForegroundColor Green
    } catch {
        Write-Host "PS2EXE wrap failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} elseif (-not $SkipExe) {
    Write-Host "PS2EXE not installed -- skipping .exe. (Install-Module PS2EXE to enable.)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "BUNDLE SUMMARY" -ForegroundColor Cyan
Write-Host "  Files bundled: $($files.Count)"
Write-Host "  Bundle hash:   $bundleHash"
Write-Host "  Portable .ps1: $portablePath"
Write-Host "  Launcher .bat: $batPath"
Write-Host ""
Write-Host "To use: copy these two files to a USB stick and double-click the .bat" -ForegroundColor Green
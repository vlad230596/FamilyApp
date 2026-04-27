[CmdletBinding()]
param(
    [string]$FlutterSdkPath,
    [string]$Run
)

$ErrorActionPreference = 'Stop'

function Add-ToPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
    $alreadyExists = ($env:Path -split [System.IO.Path]::PathSeparator) |
        Where-Object { $_.TrimEnd('\') -ieq $resolvedPath }

    if (-not $alreadyExists) {
        $env:Path = "$resolvedPath$([System.IO.Path]::PathSeparator)$env:Path"
    }
}

function Test-FlutterSdkPath {
    param([string]$Path)

    if (-not $Path) {
        return $false
    }

    Test-Path -LiteralPath (Join-Path $Path 'bin\flutter.bat')
}

function Read-FlutterSdkPathFromJson {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $settings = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $value = $settings.'dart.flutterSdkPath'

    if (-not $value) { return $null }

    [Environment]::ExpandEnvironmentVariables($value)
}

function Resolve-FlutterSdkPath {
    if (Test-FlutterSdkPath -Path $FlutterSdkPath) {
        return $FlutterSdkPath
    }

    $settingsFiles = @(
        (Join-Path $PSScriptRoot '..\.vscode\settings.json'),
        (Join-Path $env:APPDATA 'Code\User\settings.json'),
        (Join-Path $env:APPDATA 'Code - Insiders\User\settings.json'),
        (Join-Path $env:APPDATA 'VSCodium\User\settings.json')
    )

    foreach ($settingsFile in $settingsFiles) {
        $path = Read-FlutterSdkPathFromJson -Path $settingsFile
        if (Test-FlutterSdkPath -Path $path) {
            return $path
        }
    }

    return $null
}

$resolvedFlutterSdkPath = Resolve-FlutterSdkPath

if (-not $resolvedFlutterSdkPath) {
    throw 'Could not find Flutter SDK. Set dart.flutterSdkPath in VS Code settings or pass -FlutterSdkPath C:\path\to\flutter.'
}

$resolvedFlutterSdkPath = (Resolve-Path -LiteralPath $resolvedFlutterSdkPath).Path
$flutterBin = Join-Path $resolvedFlutterSdkPath 'bin'
$dartBin = Join-Path $resolvedFlutterSdkPath 'bin\cache\dart-sdk\bin'

$env:FLUTTER_ROOT = $resolvedFlutterSdkPath
Add-ToPath -Path $flutterBin
Add-ToPath -Path $dartBin

Write-Host "Flutter SDK: $env:FLUTTER_ROOT"
Write-Host "flutter: $((Get-Command flutter).Source)"
Write-Host "dart: $((Get-Command dart -ErrorAction SilentlyContinue).Source)"

if ($Run) {
    Invoke-Expression $Run
    exit $LASTEXITCODE
}

param([ValidateSet('test', 'apk', 'run')][string]$Action = 'apk')
$ErrorActionPreference = 'Stop'
$workspacePath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$toolPath = Join-Path $workspacePath 'work'
$flutterPath = Join-Path $toolPath 'toolchain\flutter\bin\flutter.bat'
if (-not (Test-Path $flutterPath)) { $flutterPath = (Get-Command flutter -ErrorAction Stop).Source }
if (Test-Path (Join-Path $toolPath 'pub-cache')) { $env:PUB_CACHE = Join-Path $toolPath 'pub-cache' }
if (Test-Path (Join-Path $toolPath 'gradle')) { $env:GRADLE_USER_HOME = Join-Path $toolPath 'gradle' }
if (Test-Path (Join-Path $toolPath 'android-sdk')) { $env:ANDROID_HOME = Join-Path $toolPath 'android-sdk'; $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME }
$env:JAVA_HOME = (Join-Path $toolPath 'toolchain\android-studio\jbr')
Push-Location $PSScriptRoot
try {
    & $flutterPath pub get
    if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
    switch ($Action) {
        'test' { & $flutterPath test }
        'apk' { & $flutterPath build apk --debug }
        'run' { & $flutterPath run }
    }
    if ($LASTEXITCODE -ne 0) { throw "Flutter $Action failed. See the output above." }
} finally { Pop-Location }


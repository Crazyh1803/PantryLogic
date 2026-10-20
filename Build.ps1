param([ValidateSet('test', 'apk', 'aab', 'run', 'studio')][string]$Action = 'apk')
$ErrorActionPreference = 'Stop'

function Find-CommandPath([string[]]$Names) {
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) { return $command.Source }
    }
    return $null
}

function ConvertTo-GradlePath([string]$Path) {
    return ([System.IO.Path]::GetFullPath($Path) -replace '\\', '/')
}

$workspacePath = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$toolPath = Join-Path $workspacePath 'work'
$bundledFlutterPath = Join-Path $toolPath 'toolchain\flutter\bin\flutter.bat'
$flutterPath = if (Test-Path $bundledFlutterPath) {
    $bundledFlutterPath
} else {
    Find-CommandPath @('flutter.bat', 'flutter')
}
if (-not $flutterPath) {
    $existingProperties = Join-Path $PSScriptRoot 'android\local.properties'
    if (Test-Path $existingProperties) {
        $sdkLine = Get-Content $existingProperties | Where-Object { $_ -match '^\s*flutter\.sdk\s*=' } | Select-Object -Last 1
        if ($sdkLine) {
            $configuredSdk = ($sdkLine -replace '^\s*flutter\.sdk\s*=\s*', '').Replace('\\', '\').Replace('\:', ':')
            $configuredFlutter = Join-Path $configuredSdk 'bin\flutter.bat'
            if (Test-Path $configuredFlutter) { $flutterPath = $configuredFlutter }
        }
    }
}
if (-not $flutterPath) {
    throw 'Flutter was not found. Install Flutter or restore work\toolchain\flutter.'
}

# A relocated checkout may still use the original portable Flutter installation.
# Discover its sibling tools instead of mixing it with another Studio install.
$flutterRoot = Split-Path (Split-Path $flutterPath -Parent) -Parent
$sdkToolPath = Split-Path (Split-Path $flutterRoot -Parent) -Parent
if (Test-Path (Join-Path $sdkToolPath 'toolchain\android-studio\bin\studio64.exe')) {
    $toolPath = $sdkToolPath
}

$bundledAndroidSdk = Join-Path $toolPath 'android-sdk'
if (Test-Path $bundledAndroidSdk) {
    $env:ANDROID_HOME = $bundledAndroidSdk
    $env:ANDROID_SDK_ROOT = $bundledAndroidSdk
}
if (-not $env:ANDROID_HOME -and $env:ANDROID_SDK_ROOT) {
    $env:ANDROID_HOME = $env:ANDROID_SDK_ROOT
}
$defaultAndroidSdk = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Android\Sdk' } else { $null }
if (-not $env:ANDROID_HOME -and $defaultAndroidSdk -and (Test-Path $defaultAndroidSdk)) {
    $env:ANDROID_HOME = $defaultAndroidSdk
    $env:ANDROID_SDK_ROOT = $defaultAndroidSdk
}
if (-not $env:ANDROID_SDK_ROOT -and $env:ANDROID_HOME) {
    $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
}

$bundledJava = Join-Path $toolPath 'toolchain\android-studio\jbr'
if (Test-Path $bundledJava) { $env:JAVA_HOME = $bundledJava }
# Android unit-test configuration requires plugin sources and outputs on one drive.
$env:PUB_CACHE = Join-Path $PSScriptRoot '.pub-cache'
if (Test-Path (Join-Path $toolPath 'gradle')) { $env:GRADLE_USER_HOME = Join-Path $toolPath 'gradle' }

$flutterRoot = Split-Path (Split-Path $flutterPath -Parent) -Parent
& (Join-Path $PSScriptRoot 'tools\Repair-FlutterGradleTests.ps1') -FlutterRoot $flutterRoot
$localPropertiesPath = Join-Path $PSScriptRoot 'android\local.properties'
$managedPropertiesPattern = if ($env:ANDROID_HOME) {
    '^\s*(flutter\.sdk|sdk\.dir)\s*='
} else {
    '^\s*flutter\.sdk\s*='
}
$localProperties = if (Test-Path $localPropertiesPath) {
    @(Get-Content $localPropertiesPath | Where-Object { $_ -notmatch $managedPropertiesPattern })
} else {
    @()
}
$localProperties += "flutter.sdk=$(ConvertTo-GradlePath $flutterRoot)"
if ($env:ANDROID_HOME) {
    $localProperties += "sdk.dir=$(ConvertTo-GradlePath $env:ANDROID_HOME)"
}
[System.IO.File]::WriteAllLines(
    $localPropertiesPath,
    $localProperties,
    [System.Text.UTF8Encoding]::new($false)
)

Push-Location $PSScriptRoot
try {
    & $flutterPath pub get
    if ($LASTEXITCODE -ne 0) {
        if ($Action -eq 'studio') {
            Write-Warning 'Dependency resolution failed. Opening Android Studio so it can retry.'
        } else {
            throw 'Dependency resolution failed.'
        }
    }

    switch ($Action) {
        'test' { & $flutterPath test }
        'apk' { & $flutterPath build apk --debug }
        'aab' { & $flutterPath build appbundle --release }
        'run' { & $flutterPath run }
        'studio' {
            & (Join-Path $PSScriptRoot 'tools\Initialize-StudioProject.ps1') -ProjectPath $PSScriptRoot
            $studioCandidates = @(
                $env:STUDIO_EXE,
                (Join-Path $toolPath 'toolchain\android-studio\bin\studio64.exe')
            )
            if ($env:ProgramFiles) {
                $studioCandidates += Join-Path $env:ProgramFiles 'Android\Android Studio\bin\studio64.exe'
            }
            if (${env:ProgramFiles(x86)}) {
                $studioCandidates += Join-Path ${env:ProgramFiles(x86)} 'Android\Android Studio\bin\studio64.exe'
            }
            if ($env:LOCALAPPDATA) {
                $studioCandidates += Join-Path $env:LOCALAPPDATA 'Programs\Android Studio\bin\studio64.exe'
            }
            $studioCandidates = $studioCandidates | Where-Object { $_ -and (Test-Path $_) }
            $studioPath = $studioCandidates | Select-Object -First 1
            if (-not $studioPath) {
                $studioPath = Find-CommandPath @('studio64.exe', 'studio.exe')
            }
            if (-not $studioPath -and $env:LOCALAPPDATA) {
                $toolboxRoot = Join-Path $env:LOCALAPPDATA 'JetBrains\Toolbox\apps\AndroidStudio'
                $studioPath = Get-ChildItem $toolboxRoot -Filter studio64.exe -File -Recurse -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1 -ExpandProperty FullName
            }
            if (-not $studioPath) {
                throw 'Android Studio was not found. Install it or set STUDIO_EXE to studio64.exe.'
            }
            $portableProperties = Join-Path $toolPath 'studio-2026.1.4.properties'
            if (-not $env:STUDIO_PROPERTIES -and
                $studioPath -eq (Join-Path $toolPath 'toolchain\android-studio\bin\studio64.exe') -and
                (Test-Path $portableProperties)) {
                $env:STUDIO_PROPERTIES = $portableProperties
            }
            Write-Host "Opening Android Studio: $studioPath"
            Start-Process -FilePath $studioPath -ArgumentList ('"{0}"' -f $PSScriptRoot) -WindowStyle Hidden
        }
    }
    if ($Action -ne 'studio' -and $LASTEXITCODE -ne 0) {
        throw "Flutter $Action failed. See the output above."
    }
} finally {
    Pop-Location
}

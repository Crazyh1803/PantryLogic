$ErrorActionPreference = 'Stop'
$projectPath = Split-Path $PSScriptRoot -Parent
$logPath = Join-Path ([System.IO.Path]::GetTempPath()) 'PantryLogic-launch.log'
$exitCode = 0
Start-Transcript -Path $logPath -Force | Out-Null
try {
    Write-Host "Opening Pantry Logic from $projectPath"
    & (Join-Path $projectPath 'Build.ps1') -Action studio
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode

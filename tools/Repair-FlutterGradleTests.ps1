param([Parameter(Mandatory = $true)][string]$FlutterRoot)
$ErrorActionPreference = 'Stop'

# Some Flutter SDKs import JUnit from Gradle's private, shaded classes.
# Use the kotlin-test dependency already declared by Flutter instead.
$testPath = Join-Path $FlutterRoot 'packages\flutter_tools\gradle\src\test\kotlin\DeeplinkTest.kt'
if (-not (Test-Path $testPath)) { return }
$source = [System.IO.File]::ReadAllText($testPath)
$oldImport = 'import org.gradle.internal.impldep.org.junit.Assert.assertThrows'
if (-not $source.Contains($oldImport)) { return }
$oldAssertion = 'assertThrows(NullPointerException::class.java)'
if (-not $source.Contains($oldAssertion)) {
    throw "Flutter DeeplinkTest.kt has changed; inspect it before applying the Gradle test repair."
}
$source = $source.Replace($oldImport, 'import kotlin.test.assertFailsWith')
$source = $source.Replace($oldAssertion, 'assertFailsWith<NullPointerException>')
[System.IO.File]::WriteAllText($testPath, $source, [System.Text.UTF8Encoding]::new($false))
Write-Host 'Repaired Flutter DeeplinkTest to use kotlin.test.assertFailsWith.'

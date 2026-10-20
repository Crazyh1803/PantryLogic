param([Parameter(Mandatory = $true)][string]$ProjectPath)
$ErrorActionPreference = 'Stop'
$ideaPath = Join-Path $ProjectPath '.idea'
$modulesPath = Join-Path $ideaPath 'modules.xml'
$gradlePath = Join-Path $ideaPath 'gradle.xml'
if ((Test-Path $modulesPath) -and (Test-Path $gradlePath)) {
    [xml]$gradle = Get-Content $gradlePath -Raw
    $androidProject = $gradle.SelectSingleNode('//option[@name="externalProjectPath" and @value="$PROJECT_DIR$/android"]')
    [xml]$modules = Get-Content $modulesPath -Raw
    $changed = $false
    foreach ($module in @($modules.SelectNodes('//module'))) {
        # Let Android Gradle own its modules. A manually registered Java root
        # conflicts with Android Studio's Gradle compilation checks.
        if ($androidProject -and $module.filepath -in @(
            '$PROJECT_DIR$/.idea/PantryLogic.iml',
            '$PROJECT_DIR$/pantry_logic.iml'
        )) {
            $module.ParentNode.RemoveChild($module) | Out-Null
            $changed = $true
        }
    }
    if ($changed) { $modules.Save($modulesPath) }
}
$workspacePath = Join-Path $ideaPath 'workspace.xml'
if (Test-Path $workspacePath) {
    [xml]$workspace = Get-Content $workspacePath -Raw
    $manager = $workspace.SelectSingleNode('/project/component[@name="RunManager"]')
    if ($manager -and $manager.GetAttribute('selected') -eq 'Android App.app') {
        $manager.SetAttribute('selected', 'Flutter.Pantry Logic')
        $workspace.Save($workspacePath)
    }
}

param([Parameter(Mandatory = $true)][string]$ProjectPath)
$ErrorActionPreference = 'Stop'
$ideaPath = Join-Path $ProjectPath '.idea'
$modulesPath = Join-Path $ideaPath 'modules.xml'
$modulePath = Join-Path $ProjectPath 'pantry_logic.iml'
if ((Test-Path $modulesPath) -and (Test-Path $modulePath)) {
    [xml]$modules = Get-Content $modulesPath -Raw
    foreach ($module in $modules.SelectNodes('//module')) {
        if ($module.filepath -eq '$PROJECT_DIR$/.idea/PantryLogic.iml') {
            $module.SetAttribute('fileurl', 'file://$PROJECT_DIR$/pantry_logic.iml')
            $module.SetAttribute('filepath', '$PROJECT_DIR$/pantry_logic.iml')
            $modules.Save($modulesPath)
        }
    }
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

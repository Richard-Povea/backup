

$parentFolder = $SettingsObject.library + "/" + $ParentFolderName
$projectFolder = Find-FolderByPrefix -parentFolderUrl $parentFolder -prefix $Code
if (-not $projectFolder) {
    throw "No se encontró ninguna carpeta que comience con '$Code' en '$parentFolder'."
}

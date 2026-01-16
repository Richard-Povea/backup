Get-Content settings.env | ForEach-Object {
  $name, $value = $_.split('=')
  if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains('#')) {
    # skip empty or comment line in ENV file
    return
  }
  Set-Content env:\$name $value
}

# ----------------------- Conexión ----------------------------
$SettingsObject = Get-Content -Path .\config.json | ConvertFrom-Json
$SiteUrl = $SettingsObject.site
Write-Host "Conectando a $SiteUrl..." -ForegroundColor Cyan
Connect-PnPOnline -Url $SiteUrl -ClientId $env:CLIENT_ID

# ----------------------- Planner ----------------------------
. .\planner.ps1
$tasks = Get-PlannerTasksInBucket `
  -groupName $SettingsObject.groupName `
  -plannerName $SettingsObject.plannerName `
  -bucketName $SettingsObject.bucketName
$Code = 6050

# ------------------------- Backup -------------------------------
. .\utils.ps1
$projectParentFolder = python .\utils.py $Code
$parentFolder = $SettingsObject.library + "/" + $projectParentFolder
$folderName = Find-FolderByPrefix `
  -parentFolderUrl $parentFolder `
  -prefix $Code
if (-not $folderName) {
    throw "No se encontró ninguna carpeta que comience con '$Code' en '$parentFolder'."
}

# ------------------------- Delete -------------------------------
Write-Host "Eliminando la carpeta del proyecto $folderName" -ForegroundColor Yellow
Remove-PnPFolder -Name $folderName -Folder $parentFolder -Recycle

# ----------------------- Desconexión ----------------------------
Disconnect-PnPOnline

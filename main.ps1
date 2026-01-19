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

# ----------------------- Backup List ----------------------------
. .\lists.ps1

$itemsLeftBackup = Get-LeftBackups -ListName $SettingsObject.backupLibrary
if ($itemsLeftBackup.Count -eq 0){
  Write-Host "No hay items para hacer Backup"
  exit 0
}
Write-Host "Items para modificar: $($itemsLeftBackup.Count)" -ForegroundColor Yellow
if ($itemsLeftBackup.Count -eq 1){
  $currentItem = $itemsLeftBackup
}else{
  $currentItem = $itemsLeftBackup[0]
}
# ------------------------- Backup -------------------------------
$code = $currentItem["Title"]
Write-Host "Descarga del proyecto $code en proceso." -ForegroundColor Green
Set-PnPListItem `
  -List $SettingsObject.backupLibrary `
  -Identity $currentItem.Id `
  -Values @{$SettingsObject.backupColumn = $SettingsObject.inProcess}
. .\utils.ps1
$projectParentFolder = python .\utils.py $code
$parentFolder = $SettingsObject.library + "/" + $projectParentFolder
# Busca el nombre de la carpeta a partir del código
$folderName = Find-FolderByPrefix `
  -parentFolderUrl $parentFolder `
  -prefix $code
if (-not $folderName) {
    throw "No se encontró ninguna carpeta que comience con '$code' en '$parentFolder'."
}
$folderServerUrl = Join-Path $parentFolder $folderName
$localRootPath = Join-Path $SettingsObject.local_root_path $code
# Create local root path if it doesn't exist
if (-not (Test-Path -LiteralPath $localRootPath)) {
    New-Item -ItemType Directory -Path $localRootPath | Out-Null
}

. .\descargar_proyecto.ps1
Initialize-Logger (Join-Path $LocalRootPath ($code + "_download_log.txt"))
function Get-LeftDownloads{
  param(
    $logFiles,
    $files
  )
  $files = $files | Where-Object { $_.ServerRelativeUrl -notin $logFiles }
  return $files
}
 
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$metadataCsvPath = Join-Path $LocalRootPath ("export_metadata_" + $code + "_" + $timestamp + ".csv")
$metadataRows = New-Object System.Collections.Generic.List[Object]
    
$files = Start-ProcessFolder -folderServerUrl $folderServerUrl
if (Test-Path -LiteralPath $logPath) {
  $logFiles = Get-Content $logPath | ForEach-Object {
      $time, $value = $_.split('Descargado: ')
      $value
  }
  $leftDownloads = Get-LeftDownloads -logFiles $logFiles -files $files
} else {
  $leftDownloads = $files
}
function New-SafePath {
    param([string]$path)
    # Crea carpeta si no existe
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

foreach ($file in $leftDownloads){
  $serverRelativeUrl = $file.ServerRelativeUrl  # para descargar siempre usamos server-relative
  $array = $serverRelativeUrl -split '/'
  # Select elements starting from index 2 to the end, then join them back with spaces
  $newFolderPath = ($array | Select-Object -Skip 5) -join '/'
  $currentFolderPath = Split-Path -Path $(Join-Path $SettingsObject.local_root_path $newFolderPath) -Parent
  New-SafePath -path $currentFolderPath
  # Descargar
  $downloaded = Invoke-FileWithRetry `
      -serverRelativeUrl $serverRelativeUrl `
      -localFolderPath $currentFolderPath `
      -fileName $file.Name
  if ($downloaded) {
      Write-Log "Descargado: $serverRelativeUrl"
      Write-Host "Descargado: $serverRelativeUrl"
      $metadataRow = Get-Metadata -file $file -localFolderPath $localRootPath
      $metadataRows.Add($metadataRow) | Out-Null
  }
  if (Test-Path $metadataCsvPath) {
      $metadataRow | Export-Csv -Path $metadataCsvPath -Append -NoTypeInformation -Encoding UTF8
  } else {
      $metadataRow | Export-Csv -Path $metadataCsvPath -NoTypeInformation -Encoding UTF8
  }
}

# ------------------------- Delete -------------------------------
Write-Host "Eliminando la carpeta del proyecto $folderName" -ForegroundColor Yellow
Remove-PnPFolder -Name $folderName -Folder $parentFolder -Recycle
Set-PnPListItem `
  -List $SettingsObject.backupLibrary `
  -Identity $currentItem.Id `
  -Values @{$SettingsObject.backupColumn = $SettingsObject.finished}
# ----------------------- Desconexión ----------------------------
Disconnect-PnPOnline

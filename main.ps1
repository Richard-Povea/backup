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
function Find-FolderByPrefix {
    param (
        [string]$parentFolderUrl,
        [string]$prefix
    )
    $subfolders = Get-PnPFolderItem `
        -FolderSiteRelativeUrl $parentFolderUrl `
        -ItemType Folder
    foreach ($sf in $subFolders) {
        if ($sf.Name -match "$prefix\s-") {
            return Split-Path -Path $sf.ServerRelativeUrl -Leaf
        }
    }
    return $null
}
$itemsLeftBackup = Get-LeftBackups -ListName $SettingsObject.backupLibrary

# Validar nombres de proyectos
$validItems = @()

foreach ($item in $itemsLeftBackup) {

    $code = $item["Title"]
    
    if ([string]::IsNullOrWhiteSpace($code)) {
        Write-Warning "Item ID $($item.Id) descartado: Title vacío"
        Set-PnPListItem `
        -List $SettingsObject.backupLibrary `
        -Identity $item.Id `
        -Values @{$SettingsObject.backupColumn = $SettingsObject.error}
        continue
    }


    try {
        $projectParentFolder = python .\utils.py $code
        $parentFolder = "$($SettingsObject.library)/$projectParentFolder"

        $folderName = Find-FolderByPrefix `
            -parentFolderUrl $parentFolder `
            -prefix $code

        if (-not $folderName) {
            Write-Warning "Proyecto $code descartado: carpeta no encontrada"
            Set-PnPListItem `
              -List $SettingsObject.backupLibrary `
              -Identity $item.Id `
              -Values @{$SettingsObject.backupColumn = $SettingsObject.error}
            continue
        }

        # ✅ item válido
        $item | Add-Member -NotePropertyName FolderName -NotePropertyValue $folderName -Force
        $validItems += $item
    }
    catch {
        Write-Warning "Proyecto $code descartado por error: $_"
    }
}


$itemsLeftBackup = $validItems

if ($itemsLeftBackup.Count -eq 0) {
    Write-Host "No hay proyectos válidos para backup" -ForegroundColor Yellow
    exit 0
}

if ($itemsLeftBackup.Count -eq 1) {
    $currentItem = $itemsLeftBackup[0]
} else {
    $currentItem = $itemsLeftBackup[0]
}

# ------------------------- Backup -------------------------------
$code = $currentItem["Title"]
Write-Host "Descarga del proyecto $code en proceso." -ForegroundColor Green
$projectParentFolder = python .\utils.py $code
$parentFolder = $SettingsObject.library + "/" + $projectParentFolder
# Busca el nombre de la carpeta a partir del código

$folderName = Find-FolderByPrefix `
  -parentFolderUrl $parentFolder `
  -prefix $code
if (-not $folderName) {
    throw "No se encontró ninguna carpeta que comience con '$code' en '$parentFolder'."
}
Set-PnPListItem `
  -List $SettingsObject.backupLibrary `
  -Identity $currentItem.Id `
  -Values @{$SettingsObject.backupColumn = $SettingsObject.inProcess}
. .\utils.ps1
$folderServerUrl = Join-Path $parentFolder $folderName
$localRootPath = Join-Path $SettingsObject.local_root_path $code
function Resolve-LocalFolderPath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    if (-not (Test-Path -LiteralPath $BasePath)) {
        return $BasePath
    }

    Write-Host ""
    Write-Host "La carpeta '$BasePath' ya existe." -ForegroundColor Yellow
    Write-Host "[R] Reemplazar carpeta existente"
    Write-Host "[N] Crear una nueva carpeta con sufijo"

    do {
        $option = (Read-Host "Seleccione una opción (R/N)").ToUpper()
    } while ($option -notin @("R", "N"))

    switch ($option) {
        "R" {
            Write-Host "Eliminando carpeta existente..." -ForegroundColor Yellow
            Remove-Item -LiteralPath $BasePath -Recurse -Force

            return $BasePath
        }

        "N" {
            $counter = 1

            do {
                $newPath = "{0}_{1}" -f $BasePath, $counter
                $counter++
            } while (Test-Path -LiteralPath $newPath)

            Write-Host "Se utilizará la carpeta '$newPath'." -ForegroundColor Cyan

            return $newPath
        }
    }
}

$localRootPath = Resolve-LocalFolderPath -BasePath $localRootPath

# Crear carpeta local
if (-not (Test-Path -LiteralPath $localRootPath)) {
    New-Item -ItemType Directory -Path $localRootPath -Force | Out-Null
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

Write-Host "Buscando Archivos ... (este proceso puede demorar unos minutos)" -ForegroundColor Yellow
$files = Start-ProcessFolder -folderServerUrl $folderServerUrl
$filtered_files = $files | Where-Object { $_ -ne $null }
Write-Host "$($filtered_files.Count) archivos encontrados" -ForegroundColor Green
if (Test-Path -LiteralPath $logPath) {
  Write-Host "Archivo Log encontrado" -ForegroundColor Green
  $logFiles = Get-Content $logPath | ForEach-Object {
      $time, $value = $_.split('Descargado: ')
      $value
  }
  $leftDownloads = Get-LeftDownloads -logFiles $logFiles -files $filtered_files
} else {
  Write-Host "Archivo Log no encontrado" -ForegroundColor Green
  $leftDownloads = $filtered_files
}
function New-SafePath {
    param([string]$path)
    # Crea carpeta si no existe
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}
Write-Host "Descargando $($leftDownloads.Count) archivos..."
foreach ($file in $leftDownloads){
  $serverRelativeUrl = $file.ServerRelativeUrl  # para descargar siempre usamos server-relative
  $array = $serverRelativeUrl -split '/'
  # Select elements starting from index 2 to the end, then join them back with spaces
  $newFolderPath = ($array | Select-Object -Skip 5) -join '/'
  $currentFolderPath = Split-Path -Path $(Join-Path $localRootPath $newFolderPath) -Parent
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
Set-PnPListItem `
  -List $SettingsObject.backupLibrary `
  -Identity $currentItem.Id `
  -Values @{$SettingsObject.backupColumn = $SettingsObject.finished}

# ------------------------- Delete -------------------------------
Write-Host "Eliminando la carpeta del proyecto $folderName" -ForegroundColor Yellow
Remove-PnPFolder -Name $folderName -Folder $parentFolder
Set-PnPListItem `
  -List $SettingsObject.backupLibrary `
  -Identity $currentItem.Id `
  -Values @{$SettingsObject.onlineColumn = $false}

Write-Host "Proceso completado!" -ForegroundColor Green

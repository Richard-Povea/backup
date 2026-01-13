
<#
.SYNOPSIS
  Exporta archivos desde una biblioteca/carpeta de SharePoint Online a disco local,
  preserva estructura y exporta metadatos a CSV.

.PARAMETER SiteUrl
  URL del sitio SharePoint (ej: https://contoso.sharepoint.com/sites/Proyectos)

.PARAMETER LibraryTitle
  Título de la biblioteca (ej: "Documentos", "Proyectos")

.PARAMETER LocalRootPath
  Carpeta local destino en el servidor. Debe existir.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ClientId,

    [Parameter(Mandatory=$true)]
    [string]$ParentFolderName,

    [Parameter(Mandatory=$true)]
    [string]$Code,

    [Parameter(Mandatory=$true)]
    [string]$SiteUrl,

    [Parameter(Mandatory=$true)]
    [string]$LibraryTitle,

    [Parameter(Mandatory=$true)]
    [string]$LocalRootPath
)

# ----------------------- Configuración -----------------------
$ErrorActionPreference = "Stop"
$maxRetries = 5
$retryDelaySeconds = 10
$logPath = Join-Path $LocalRootPath ($Code + "_download_log.txt")

# ----------------------- Conexión ----------------------------
Write-Host "Conectando a $SiteUrl..." -ForegroundColor Cyan
Connect-PnPOnline -Url $SiteUrl -ClientId $ClientId

# Obtener la lista/biblioteca
$list = Get-PnPList -Identity $LibraryTitle -ErrorAction Stop
Write-Host "Biblioteca encontrada: $($list.Title)" -ForegroundColor Green

# CSV para metadatos
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$metadataCsvPath = Join-Path $LocalRootPath ("export_metadata_" + $Code + "_" + $timestamp + ".csv")
$metadataRows = New-Object System.Collections.Generic.List[Object]

# ----------------------- Funciones auxiliares ----------------
function Write-Log {
    param (
        [string]$msg
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "$timestamp - $msg"
}
function CheckFileInLog{
    param (
        [string]$path,
        [string]$example
    )
    $files = Get-Content $path | ForEach-Object {
        $time, $value = $_.split('Descargado: ')
        if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains('#')) {
            # skip empty or comment line in ENV file
            return
        }
        $value
    }
    if ($files -contains $example) {
        return $true
    } else {
        return $false
    }
}
# Buscar las carpetas y buscar la carpeta que empiece con el prefijo dado
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
            return $sf.ServerRelativeUrl
        }
    }
    return $null
}

function New-SafePath {
    param([string]$path)
    # Crea carpeta si no existe
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

function Invoke-FileWithRetry {
    param(
        [string]$serverRelativeUrl,
        [string]$localFolderPath,
        [string]$fileName
    )

    $attempt = 0
    while ($attempt -lt $maxRetries) {
        try {
            # Descarga el archivo
            Get-PnPFile `
            -Url $serverRelativeUrl `
            -Path $localFolderPath `
            -FileName $fileName `
            -AsFile -Force
            return $true
        }
        catch {
            $attempt++
            $msg = $_.Exception.Message
            Write-Warning "Intento $attempt/$maxRetries al descargar '$serverRelativeUrl' falló: $msg"

            # Si es throttling (429) o timeout, esperar y reintentar
            Start-Sleep -Seconds $retryDelaySeconds
        }
    }
    Write-Error "No se pudo descargar '$serverRelativeUrl' tras $maxRetries intentos."
    return $false
}

function Remove-RelativeWebPrefix {
    param(
        [string]$serverRelativeUrl
    )
    # Obtiene la parte después de /sites/Proyectos/ si existe
    $parts = $serverRelativeUrl -split '/sites/Proyectos/'
    if ($parts.Length -gt 1) {
        return '/' + $parts[1]
    }else {
        <# Action when all if and elseif conditions are false #>
        return $serverRelativeUrl
    }
}

function Get-Metadata{
    param(
        [Microsoft.SharePoint.Client.File]$file,
        [string]$localFolderPath
    )
    $li = Get-PnPProperty -ClientObject $file -Property ListItemAllFields
    # Recopilar metadatos comunes (ajusta campos según tu modelo)
    $row = [PSCustomObject]@{
        ArchivoNombre        = $li["FileLeafRef"]
        ArchivoUrlServidor   = $li["FileRef"]
        RutaLocal            = (Join-Path $localFolderPath $file.Name)
        TamañoBytes          = $li["SMConvertTotalSize"]           # puede venir null si no está habilitado
        Modificado           = $li["Modified"]
        ModificadoPor        = $li["Editor"]
        Creado               = $li["Created"]
        CreadoPor            = $li["Author"]
        VersionActual        = $li["_UIVersionString"]
        TipoContenido        = $li["ContentType"]
        Titulo               = $li["Title"]
        # Ejemplos de columnas personalizadas:
        Proyecto             = $li["Proyecto"]              # si existe
        Estado               = $li["Estado"]                # si existe
        FechaCierre          = $li["FechaCierre"]           # si existe
    }
    return $row
}

function Get-FileInfo{
    param(
        [System.Object]$file
    )
    $serverRelativeUrl = $file.ServerRelativeUrl  # para descargar siempre usamos server-relative
    # Descargar
    $downloaded = Invoke-FileWithRetry `
        -serverRelativeUrl $serverRelativeUrl `
        -localFolderPath $localFolderPath `
        -fileName $file.Name
    if ($downloaded) {
        Write-Log "Descargado: $serverRelativeUrl"
        $metadataRow = Get-Metadata -file $file -localFolderPath $localFolderPath
        $metadataRows.Add($metadataRow) | Out-Null
    }
    if (Test-Path $metadataCsvPath) {
        $metadataRow | Export-Csv -Path $metadataCsvPath -Append -NoTypeInformation -Encoding UTF8
    } else {
        $metadataRow | Export-Csv -Path $metadataCsvPath -NoTypeInformation -Encoding UTF8
    }
}

function Get-FilesInfoWithLog{
    param(
        [System.Object]$files,
        [string]$logPath
    )
    foreach ($f in $files) {
        if (CheckFileInLog -path $logPath -example $f.ServerRelativeUrl) {
            Write-Host "Ya descargado (según log): $($f.ServerRelativeUrl)" -ForegroundColor Yellow
            continue
        }
        Get-FileInfo -file $f
    }
}
function Get-FilesInfo{
    param(
        [System.Object]$files
    )
    foreach ($f in $files) {
        Get-FileInfo -file $f
    }
}
# ----------------------- Proceso principal --------------------
function Start-ProcessFolder{
    param(
        [string]$folderServerUrl,  # <-- server-relative, ej: /sites/Proyectos/Documentos compartidos/...
        [string]$logPath
    )
    $parsedUrl = Remove-RelativeWebPrefix -serverRelativeUrl $folderServerUrl
    # Crear carpeta local correspondiente
    $array = $parsedUrl -split '/'
    # Select elements starting from index 2 to the end, then join them back with spaces
    $newFolderPath = ($array | Select-Object -Skip 3) -join '/'
    $localFolderPath = Join-Path $LocalRootPath $newFolderPath
    New-SafePath -path $localFolderPath
    Write-Host "Carpeta: $newFolderPath" -ForegroundColor Cyan
    #Filtrar Archivos ya descargados si hay un log
    $files = Get-PnPFolderItem -FolderSiteRelativeUrl $parsedUrl -ItemType File
    if ($logPath) {
        $logs_files = Get-Content $logPath | ForEach-Object {
            $time, $value = $_.split('Descargado: ')
            $value
        }
        $files = $files | Where-Object { $_.ServerRelativeUrl -notin $logs_files }
    }    
    Get-FilesInfo -files $files    
    # 2) Recorrer subcarpetas (también usando site-relative)
    $subFolders = Get-PnPFolderItem -FolderSiteRelativeUrl $parsedUrl -ItemType Folder
    foreach ($sf in $subFolders) {
        # Evitar carpetas del sistema como Forms
        if ($sf.Name -eq "Forms") { continue }
        Start-Process-Folder -folderServerUrl $sf.ServerRelativeUrl  # propagamos server-relative
    }
}
# ---------------Buscar carpeta correspondiente ---------------
$parentFolder = $SettingsObject.library + "/" + $ParentFolderName
$projectFolder = Find-FolderByPrefix -parentFolderUrl $parentFolder -prefix $Code
if (-not $projectFolder) {
    throw "No se encontró ninguna carpeta que comience con '$Code' en '$parentFolder'."
}
# ----------------------- Recorrido recursivo -----------------

if (-not (Test-Path $logPath)) {
    # Iniciar
    Write-Log "Inicio de descarga para proyecto '$Code' en carpeta '$projectFolder'."
    Write-Host "Descargando archivos sin log previo..." -ForegroundColor Magenta
    Start-ProcessFolder -folderServerUrl $projectFolder
} else {
    # Iniciar
    Write-Log "Inicio de descarga para proyecto '$Code' en carpeta '$projectFolder'."
    Write-Host "Descargando archivos con log previo..." -ForegroundColor Magenta
    Start-ProcessFolder -folderServerUrl $projectFolder -logPath $logPath
}
Write-Host "Proceso finalizado." -ForegroundColor Green
Write-Host "Sugerencia: respalda el CSV junto con las carpetas descargadas para trazabilidad."
Write-Log "Proceso finalizado."

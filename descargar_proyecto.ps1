# ----------------------- Configuración -----------------------
$ErrorActionPreference = "Stop"
$maxRetries = 5
$retryDelaySeconds = 10

function Initialize-Logger {
    param (
        [string]$path
    )
    Set-Variable -Name logPath -Value $path -Scope Global
}

# ----------------------- Funciones auxiliares ----------------
function Write-Log {
    param (
        [string]$msg
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logPath -Value "$timestamp - $msg"
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

# ----------------------- Proceso principal --------------------
function Start-ProcessFolder{
    param(
        [string]$folderServerUrl,  # <-- server-relative, ej: /sites/Proyectos/Documentos compartidos/...
        [string]$logPath
    )
    $parsedUrl = Remove-RelativeWebPrefix -serverRelativeUrl $folderServerUrl
    #Filtrar Archivos ya descargados si hay un log
    $files = Get-PnPFolderItem -FolderSiteRelativeUrl $parsedUrl -ItemType File
    Write-Output $files
    # 2) Recorrer subcarpetas (también usando site-relative)
    $subFolders = Get-PnPFolderItem -FolderSiteRelativeUrl $parsedUrl -ItemType Folder
    foreach ($sf in $subFolders) {
        # Evitar carpetas del sistema como Forms
        if ($sf.Name -eq "Forms") { continue }
        Start-ProcessFolder -folderServerUrl $sf.ServerRelativeUrl  # propagamos server-relative
    }
}

# Source - https://stackoverflow.com/a
# Posted by jeiea, modified by community. See post 'Timeline' for change history
# Retrieved 2026-01-12, License - CC BY-SA 4.0

Get-Content settings.env | ForEach-Object {
  $name, $value = $_.split('=')
  if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains('#')) {
    # skip empty or comment line in ENV file
    return
  }
  Set-Content env:\$name $value
}

$SettingsObject = Get-Content -Path .\config.json | ConvertFrom-Json
$SiteUrl = $SettingsObject.site
$LibraryTitle = "Proyectos en backup"
# ---------------------- Funciones ----------------------------
function Get-LeftBackups{
    param (
        [string] $listName
    )
    return Get-PnPListItem `
    -List $listName `
    -PageSize 5000 | Where-Object {
        $_["Backup"] -ne "Terminado"
    }
}

# ----------------------- Conexión ----------------------------
Write-Host "Conectando a $SiteUrl..." -ForegroundColor Cyan
Connect-PnPOnline -Url $SiteUrl -ClientId $env:CLIENT_ID

# Obtener la lista/biblioteca
$list = Get-PnPList -Identity $LibraryTitle -ErrorAction Stop
Write-Host "Biblioteca encontrada: $($list.Title)" -ForegroundColor Green

$items = Get-LeftBackups -listName $LibraryTitle
Write-Host "Items para modificar: $($items.Count)" -ForegroundColor Yellow

foreach ($item in $items) {
    Write-Host "Modificando item ID: $($item.Id)" -ForegroundColor Cyan
    Set-PnPListItem -List $LibraryTitle -Identity $item.Id -Values @{"Backup" = "En proceso"}
    .\main_descargar.ps1 -ProjectCode $item["Title"]
    Write-Host "Descarga completada para item ID: $($item.Id)" -ForegroundColor Green
    Set-PnPListItem -List $LibraryTitle -Identity $item.Id -Values @{"Backup" = "Terminado"}
}

Write-Host "Todos los items han sido procesados." -ForegroundColor Green
Disconnect-PnPOnline
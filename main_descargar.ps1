# Source - https://stackoverflow.com/a
# Posted by jeiea, modified by community. See post 'Timeline' for change history
# Retrieved 2026-01-12, License - CC BY-SA 4.0
param(
  [Parameter(Mandatory=$false)]
  [string]$ProjectCode
)

Get-Content settings.env | ForEach-Object {
  $name, $value = $_.split('=')
  if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains('#')) {
    # skip empty or comment line in ENV file
    return
  }
  Set-Content env:\$name $value
}

$SettingsObject = Get-Content -Path .\config.json | ConvertFrom-Json

$Code = if ($ProjectCode) { $ProjectCode } else { $SettingsObject.project_code }

# Call the Python script with the project code from the settings
$pythonOutput = python .\utils.py $Code
$localRootPath = Join-Path $SettingsObject.local_root_path $Code
# Create local root path if it doesn't exist
if (-not (Test-Path -LiteralPath $localRootPath)) {
    New-Item -ItemType Directory -Path $localRootPath | Out-Null
}

.\descargar_proyecto.ps1 `
    -ClientId $env:CLIENT_ID `
    -ParentFolderName $pythonOutput.Trim() `
    -Code $Code `
    -SiteUrl $SettingsObject.site `
    -LibraryTitle $SettingsObject.library `
    -LocalRootPath $localRootPath
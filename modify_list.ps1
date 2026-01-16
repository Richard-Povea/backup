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


function Get-LeftBackups {
    [CmdletBinding(DefaultParameterSetName = 'ByList')]
    param(
        # Mode 1: Accept a ListName (gets items itself)
        [Parameter(
            Mandatory, 
            ParameterSetName = 'ByList', 
            ValueFromPipelineByPropertyName
            )]
        [string]$ListName,

        # Mode 2: Accept items directly from the pipeline
        [Parameter(
            Mandatory, 
            ParameterSetName = 'ByItem', 
            ValueFromPipeline
            )]
        [Microsoft.SharePoint.Client.ListItem]$Item,

        # Optional: exclude null/empty Backup values (otherwise nulls are included by design)
        [Parameter(ParameterSetName = 'ByList')]
        [Parameter(ParameterSetName = 'ByItem')]
        [switch]$ExcludeNull
    )

    begin {
        # CAML query only used in ByList mode (server-side filtering → faster)
        $camlNotTerminado = @"
        <View>
        <Query>
            <Where>
            <Neq>
                <FieldRef Name='Backup' />
                <Value Type='Text'>
                    Terminado
                </Value>
            </Neq>
            </Where>
        </Query>
        </View>
"@

        # Variant excluding nulls if requested
        $camlNotTerminadoAndNotNull = @"
        <View>
        <Query>
            <Where>
            <And>
                <IsNotNull>
                <FieldRef Name='Backup' />
                </IsNotNull>
                <Neq>
                <FieldRef Name='Backup' />
                    <Value Type='Text'>
                        Terminado
                    </Value>
                </Neq>
            </And>
            </Where>
        </Query>
        </View>
"@
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByList') {
            # When a list name is provided, pull items server-side and filter there
            Get-PnPListItem `
                -List $ListName `
                -PageSize 5000 `
                -Fields 'Backup' `
                -Query ($ExcludeNull.IsPresent ? $camlNotTerminadoAndNotNull : $camlNotTerminado)
        }
        else {
            # When items are piped in, just pass through the ones you want
            # Note: .FieldValues retrieves the typed value; indexer works too
            $backup = $Item["Backup"]
            if ($ExcludeNull) {
                if ($null -ne $backup -and $backup -ne "Terminado") {
                    $Item
                }
            } else {
                if ($backup -ne "Terminado") {
                    $Item
                }
            }
        }
    }
}



# function Set-SharepointListItem {
#     param (
#         [Microsoft.SharePoint.Client.ListItem[]] $items
#     )
    
# }
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
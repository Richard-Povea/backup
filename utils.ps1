function Find-FolderByPrefix {
    param (
        [string]$parentFolderUrl,
        [string]$prefix
    )
    $subfolders = Get-PnPFolderItem `
        -FolderSiteRelativeUrl $parentFolderUrl `
        -ItemType Folder
    foreach ($sf in $subFolders) {
        if ($sf.Name -match "$prefix[\s-]*") {
            return $sf.Name
        }
    }
    return $null
}
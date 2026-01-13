$range = 1..100
$currentRange = 1..50

# Filter current range
$filteredRange = $range | Where-Object { $currentRange -notcontains $_ }
Write-Host $filteredRange
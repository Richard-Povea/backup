function Get-PlannerTasksInBucket {
    param (
        [string]$groupName,
        [string]$plannerName,
        [string]$bucketName
    )
    $bucket = Get-PnPPlannerBucket -Group $groupName -Plan $plannerName -Identity $bucketName
    $tasks = Get-PnPPlannerTask -Bucket $bucket.Id
    return $tasks
}

# Write-Host "Proyectos suspendidos en '$plannerName':" -ForegroundColor Cyan
# foreach ($task in $tasks) {
#     Write-Host " - $($task.Title)" -ForegroundColor Green
# }

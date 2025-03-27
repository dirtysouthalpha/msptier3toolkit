<#
.SYNOPSIS
Deletes user profiles older than 30 days.
#>

$Days = 30
$profiles = Get-CimInstance Win32_UserProfile | Where-Object {
    $_.LocalPath -notlike "*Administrator*" -and
    $_.LocalPath -notlike "*Default*" -and
    $_.LastUseTime -lt (Get-Date).AddDays(-$Days)
}

foreach ($profile in $profiles) {
    Write-Output "Removing profile: $($profile.LocalPath)"
    $profile.Delete()
}

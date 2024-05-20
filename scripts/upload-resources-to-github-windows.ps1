# upload-resources-to-github.ps1

param(
    [switch]$BinariesOnly
)

$ErrorActionPreference = "Stop"

function HandleErrorsAndCleanup {
    param (
        [int]$ExitCode
    )
    if ($ExitCode -eq 0) {
        exit 0
    }
    if ($global:AssetIdsUploaded.Count -ne 0) {
        Write-Host "`nCleaning up assets uploaded in the current execution of the script"
        foreach ($assetId in $global:AssetIdsUploaded) {
            Write-Host "Deleting asset $assetId"
            Invoke-RestMethod -Method Delete -Uri "https://api.github.com/repos/aws/aws-node-termination-handler/releases/assets/$assetId" -Headers @{Authorization = "token $env:GITHUB_TOKEN"}
        }
        exit $ExitCode
    }
}

function UploadAsset {
    param (
        [string]$AssetPath
    )
    $resp = Invoke-RestMethod -Method Post -Uri "https://uploads.github.com/repos/aws/aws-node-termination-handler/releases/$ReleaseId/assets?name=$(Split-Path -Leaf $AssetPath)" -Headers @{
        Authorization = "token $env:GITHUB_TOKEN"
        'Content-Type' = (Get-Content -Path $AssetPath -Raw | Measure-Object -Line).Count -gt 1 ? 'application/zip' : 'application/octet-stream'
    } -InFile $AssetPath -ErrorAction Stop

    if ($resp.id -ne $null) {
        $global:AssetIdsUploaded += $resp.id
        Write-Host "Created asset ID $($resp.id) successfully"
    } else {
        Write-Host "❌ Upload failed with response message: $($resp | ConvertTo-Json) ❌"
        exit 1
    }
}

$global:AssetIdsUploaded = @()
trap { HandleErrorsAndCleanup -ExitCode $global:LASTEXITCODE }

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$Version = & "$ScriptPath\..\Makefile" version -s
$BuildDir = "$ScriptPath\..\build\k8s-resources\$Version"
$BinaryDir = "$ScriptPath\..\build\bin"
$ReleaseId = (Invoke-RestMethod -Uri "https://api.github.com/repos/aws/aws-node-termination-handler/releases" -Headers @{Authorization = "token $env:GITHUB_TOKEN"} | ConvertFrom-Json | Where-Object { $_.tag_name -eq $Version }).id

$Assets = @()
if (-not $BinariesOnly) {
    $Assets += "$BuildDir\individual-resources.tar", "$BuildDir\all-resources.yaml", "$BuildDir\individual-resources-queue-processor.tar", "$BuildDir\all-resources-queue-processor.yaml"
}
if ($BinariesOnly) {
    $Assets += Get-ChildItem -Path $BinaryDir
}

Write-Host "`nUploading release assets for release id '$ReleaseId' to Github"
for ($i = 0; $i -lt $Assets.Count; $i++) {
    Write-Host "`n  $($i + 1). $($Assets[$i] | Split-Path -Leaf)"
    UploadAsset -AssetPath $Assets[$i]
}

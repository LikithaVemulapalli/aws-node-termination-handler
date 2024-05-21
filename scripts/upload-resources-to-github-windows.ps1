# upload-resources-to-github.ps1

param(
    [switch]$BinariesOnly
    [switch]$K8sAssetsOnly
)

$ErrorActionPreference = "Stop"

# Function to handle errors and cleanup any partially uploaded assets
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
            Invoke-RestMethod -Method Delete -Uri "https://api.github.com/repos/LikithaVemulapalli/aws-node-termination-handler/releases/assets/$assetId" -Headers @{Authorization = "token $env:GITHUB_TOKEN"}
        }
        exit $ExitCode
    }
}

# Function to upload an asset to GitHub
function UploadAsset {
    param (
        [string]$AssetPath
    )
    $ContentType = [System.Web.MimeMapping]::GetMimeMapping($AssetPath)
    $Headers = @{
        Authorization = "token $env:GITHUB_TOKEN"
        'Content-Type' = $ContentType
    }
    $Uri = "https://uploads.github.com/repos/LikithaVemulapalli/aws-node-termination-handler/releases/$ReleaseId/assets?name=$(Split-Path -Leaf $AssetPath)"
    
    try {
        $Response = Invoke-RestMethod -Method Post -Uri $Uri -Headers $Headers -InFile $AssetPath -ErrorAction Stop
        if ($Response.id -ne $null) {
            $global:AssetIdsUploaded += $Response.id
            Write-Host "Created asset ID $($Response.id) successfully"
        } else {
            Write-Host "❌ Upload failed with response message: $($Response | ConvertTo-Json) ❌"
            exit 1
        }
    } catch {
        Write-Host "❌ Upload failed: $_"
        exit 1
    }
}

# Initialize global variables
$global:AssetIdsUploaded = @()
trap { HandleErrorsAndCleanup -ExitCode $global:LASTEXITCODE }

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$Version = & "$ScriptPath/../Makefile" version -s
$BuildDir = "$ScriptPath/../build/k8s-resources/$Version"
$BinaryDir = "$ScriptPath/../build/bin"
$ReleaseId = (Invoke-RestMethod -Uri "https://api.github.com/repos/LikithaVemulapalli/aws-node-termination-handler/releases" -Headers @{Authorization = "token $env:GITHUB_TOKEN"} | ConvertFrom-Json | Where-Object { $_.tag_name -eq $Version }).id

if (-not $ReleaseId) {
    Write-Host "❌ Failed to find release ID for version $Version ❌"
    exit 1
}

# Gather assets to upload based on the -BinariesOnly flag
$Assets = @()
if (-not $BinariesOnly) {
    $Assets += "$BuildDir\individual-resources.tar", "$BuildDir\all-resources.yaml", "$BuildDir\individual-resources-queue-processor.tar", "$BuildDir\all-resources-queue-processor.yaml"
}
$Assets += Get-ChildItem -Path $BinaryDir | ForEach-Object { $_.FullName }

# Log gathered assets
Write-Host "Assets to upload:"
foreach ($Asset in $Assets) {
    Write-Host $Asset
}

# Upload each asset
Write-Host "`nUploading release assets for release id '$ReleaseId' to Github"
foreach ($Asset in $Assets) {
    Write-Host "`n  Uploading $($Asset | Split-Path -Leaf)"
    UploadAsset -AssetPath $Asset
}

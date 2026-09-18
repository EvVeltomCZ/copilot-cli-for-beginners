#Requires -Version 7.0
<#
.SYNOPSIS
    Syncs Azure resource tags (Owner, Team) into matching TopDesk CMDB
    Configuration Items. One-way: Azure is the source of truth.

.DESCRIPTION
    Reads samples/azure-topdesk-sync/config/mapping.json for the in-scope
    Azure resource types (VMs, Storage Accounts, Key Vaults, Function Apps)
    and the tag -> TopDesk field mapping. Authenticates to Azure via Service
    Principal and to TopDesk via basic auth, both sourced from environment
    variables (populated by the Azure DevOps pipeline's variable group).

.PARAMETER ConfigPath
    Path to mapping.json. Defaults to the config folder next to this script.

.PARAMETER DryRun
    When set, logs what would change without calling the TopDesk write API.

.EXAMPLE
    pwsh ./Sync-AzureTagsToTopdesk.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..' 'config' 'mapping.json'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'modules' 'AzureResourceReader.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules' 'TopdeskClient.psm1') -Force

function Sync-AzureTagsToTopdesk {
    [CmdletBinding()]
    param(
        [string]$ConfigPath,
        [switch]$DryRun
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }
    $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json

    $topdeskBaseUrl = $env:TOPDESK_URL
    if ([string]::IsNullOrWhiteSpace($topdeskBaseUrl)) {
        throw 'Missing required environment variable: TOPDESK_URL'
    }

    Write-Host "Authenticating to Azure..."
    Connect-AzureServicePrincipal

    Write-Host "Reading in-scope tagged resources..."
    $resources = Get-InScopeTaggedResources -Config $config
    Write-Host "Found $($resources.Count) in-scope resource(s)."

    $authHeader = Get-TopdeskAuthHeader

    $summary = [ordered]@{
        Updated  = 0
        Skipped  = 0
        NotFound = 0
        Errors   = 0
    }

    foreach ($resource in $resources) {
        try {
            $fieldsToUpdate = @{}
            foreach ($tagName in $config.tagToTopdeskField.PSObject.Properties.Name) {
                $topdeskField = $config.tagToTopdeskField.$tagName
                if ($resource.Tags -and $resource.Tags.ContainsKey($tagName)) {
                    $fieldsToUpdate[$topdeskField] = $resource.Tags[$tagName]
                }
            }

            if ($fieldsToUpdate.Count -eq 0) {
                Write-Verbose "Skipping $($resource.Name): no mapped tags present."
                $summary.Skipped++
                continue
            }

            $ci = Find-TopdeskConfigurationItem -Name $resource.Name -BaseUrl $topdeskBaseUrl -AuthHeader $authHeader
            if (-not $ci) {
                Write-Warning "No TopDesk CI found for resource '$($resource.Name)'. Skipping."
                $summary.NotFound++
                continue
            }

            if ($DryRun) {
                Write-Host "[DryRun] Would update CI '$($resource.Name)' (unid=$($ci.id)) with fields: $($fieldsToUpdate | ConvertTo-Json -Compress)"
                $summary.Updated++
                continue
            }

            Update-TopdeskConfigurationItem -Unid $ci.id -Fields $fieldsToUpdate -BaseUrl $topdeskBaseUrl -AuthHeader $authHeader
            Write-Host "Updated CI '$($resource.Name)' with fields: $($fieldsToUpdate.Keys -join ', ')"
            $summary.Updated++
        }
        catch {
            Write-Error "Error syncing resource '$($resource.Name)': $($_.Exception.Message)"
            $summary.Errors++
        }
    }

    Write-Host "`n--- Sync summary ---"
    $summary.GetEnumerator() | ForEach-Object { Write-Host "$($_.Key): $($_.Value)" }

    if ($summary.Errors -gt 0) {
        throw "$($summary.Errors) resource(s) failed to sync. See errors above."
    }
}

Sync-AzureTagsToTopdesk -ConfigPath $ConfigPath -DryRun:$DryRun

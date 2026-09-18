<#
.SYNOPSIS
    Helper functions for authenticating to Azure and reading tagged resources
    that are in scope for the TopDesk CMDB sync.
#>

function Connect-AzureServicePrincipal {
    <#
    .SYNOPSIS
        Authenticates to Azure using a Service Principal (client id/secret/tenant).
        Reads credentials from environment variables so no secrets ever live in
        the repo; the Azure DevOps pipeline populates these from a variable group.
    #>
    [CmdletBinding()]
    param()

    $clientId = $env:AZURE_CLIENT_ID
    $clientSecret = $env:AZURE_CLIENT_SECRET
    $tenantId = $env:AZURE_TENANT_ID
    $subscriptionId = $env:AZURE_SUBSCRIPTION_ID

    foreach ($pair in @(
            @{ Name = 'AZURE_CLIENT_ID'; Value = $clientId },
            @{ Name = 'AZURE_CLIENT_SECRET'; Value = $clientSecret },
            @{ Name = 'AZURE_TENANT_ID'; Value = $tenantId },
            @{ Name = 'AZURE_SUBSCRIPTION_ID'; Value = $subscriptionId }
        )) {
        if ([string]::IsNullOrWhiteSpace($pair.Value)) {
            throw "Missing required environment variable: $($pair.Name)"
        }
    }

    $securePassword = ConvertTo-SecureString $clientSecret -AsPlainText -Force
    $credential = [System.Management.Automation.PSCredential]::new($clientId, $securePassword)

    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId -Subscription $subscriptionId | Out-Null
}

function Get-InScopeTaggedResources {
    <#
    .SYNOPSIS
        Returns Azure resources matching the configured resource types (and
        optional resource group scope), along with their tags.
    .PARAMETER Config
        The parsed mapping.json configuration object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Config
    )

    $resourceGroups = $Config.scope.resourceGroups
    $resourceTypes = $Config.resourceTypes

    $allResources = @()

    if ($resourceGroups -and $resourceGroups.Count -gt 0) {
        foreach ($rg in $resourceGroups) {
            $allResources += Get-AzResource -ResourceGroupName $rg
        }
    }
    else {
        $allResources += Get-AzResource
    }

    $inScope = $allResources | Where-Object { $resourceTypes -contains $_.ResourceType }

    # Function Apps share the ARM type Microsoft.Web/sites with regular Web Apps;
    # only keep resources whose Kind indicates a Function App.
    $inScope = $inScope | Where-Object {
        if ($_.ResourceType -eq 'Microsoft.Web/sites') {
            return $_.Kind -like 'functionapp*'
        }
        return $true
    }

    return $inScope | ForEach-Object {
        [pscustomobject]@{
            Name         = $_.Name
            ResourceType = $_.ResourceType
            ResourceId   = $_.ResourceId
            Tags         = $_.Tags
        }
    }
}

Export-ModuleMember -Function Connect-AzureServicePrincipal, Get-InScopeTaggedResources

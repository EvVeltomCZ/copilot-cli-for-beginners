<#
.SYNOPSIS
    Helper functions for talking to the TopDesk CMDB REST API: finding a
    Configuration Item (CI) by name and updating its mapped fields.
#>

function Get-TopdeskAuthHeader {
    <#
    .SYNOPSIS
        Builds the Basic auth header for TopDesk from environment variables
        (populated by the Azure DevOps pipeline from a secret variable group).
    #>
    [CmdletBinding()]
    param()

    $username = $env:TOPDESK_USERNAME
    $appPassword = $env:TOPDESK_APP_PASSWORD

    if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($appPassword)) {
        throw 'Missing required environment variables: TOPDESK_USERNAME / TOPDESK_APP_PASSWORD'
    }

    $pair = "{0}:{1}" -f $username, $appPassword
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)

    return @{ Authorization = "Basic $base64" }
}

function Find-TopdeskConfigurationItem {
    <#
    .SYNOPSIS
        Looks up a TopDesk CI by name. Returns $null if no match is found.
    .PARAMETER Name
        The value to match against the TopDesk CI lookup field (default: name).
    .PARAMETER BaseUrl
        Base URL of the TopDesk instance, e.g. https://yourcompany.topdesk.net
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][hashtable]$AuthHeader
    )

    $uri = "$BaseUrl/tas/api/assetmgmt/assets?query=name=='$Name'"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $AuthHeader -Method Get
    }
    catch {
        throw "Failed to query TopDesk for CI '$Name': $($_.Exception.Message)"
    }

    if (-not $response -or $response.dataSet.Count -eq 0) {
        return $null
    }

    return $response.dataSet[0]
}

function Update-TopdeskConfigurationItem {
    <#
    .SYNOPSIS
        PATCHes the mapped fields (e.g. owner/team) on an existing TopDesk CI.
    .PARAMETER Fields
        Hashtable of TopDesk field name -> value to set.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Unid,
        [Parameter(Mandatory)][hashtable]$Fields,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][hashtable]$AuthHeader
    )

    $uri = "$BaseUrl/tas/api/assetmgmt/assets/$Unid"
    $body = $Fields | ConvertTo-Json -Compress

    if ($PSCmdlet.ShouldProcess($Unid, "PATCH TopDesk CI fields: $($Fields.Keys -join ', ')")) {
        try {
            Invoke-RestMethod -Uri $uri -Headers $AuthHeader -Method Patch -Body $body -ContentType 'application/json' | Out-Null
        }
        catch {
            throw "Failed to update TopDesk CI '$Unid': $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function Get-TopdeskAuthHeader, Find-TopdeskConfigurationItem, Update-TopdeskConfigurationItem

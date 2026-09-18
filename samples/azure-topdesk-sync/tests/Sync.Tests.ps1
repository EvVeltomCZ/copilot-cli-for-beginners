<#
.SYNOPSIS
    Pester tests for the Azure -> TopDesk CMDB sync script and modules.
    Az cmdlets and TopDesk REST calls are mocked; no real Azure/TopDesk
    calls are made.
#>

BeforeAll {
    # Stub out the Az module cmdlet used by AzureResourceReader so tests can
    # run without the real Az.Accounts/Az.Resources modules installed.
    function global:Get-AzResource { }

    $script:ModulesPath = Join-Path $PSScriptRoot '..' 'src' 'modules'
    Import-Module (Join-Path $ModulesPath 'AzureResourceReader.psm1') -Force
    Import-Module (Join-Path $ModulesPath 'TopdeskClient.psm1') -Force

    $script:ConfigPath = Join-Path $PSScriptRoot '..' 'config' 'mapping.json'
    $script:Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
}

Describe 'Get-InScopeTaggedResources' {
    BeforeAll {
        Mock -ModuleName AzureResourceReader Get-AzResource {
            return @(
                [pscustomobject]@{
                    Name = 'vm-in-scope'; ResourceType = 'Microsoft.Compute/virtualMachines'
                    ResourceId = '/subscriptions/x/vm-in-scope'; Kind = $null
                    Tags = @{ Owner = 'alice'; Team = 'platform' }
                },
                [pscustomobject]@{
                    Name = 'func-in-scope'; ResourceType = 'Microsoft.Web/sites'
                    ResourceId = '/subscriptions/x/func-in-scope'; Kind = 'functionapp,linux'
                    Tags = @{ Owner = 'bob'; Team = 'data' }
                },
                [pscustomobject]@{
                    Name = 'webapp-out-of-scope'; ResourceType = 'Microsoft.Web/sites'
                    ResourceId = '/subscriptions/x/webapp-out-of-scope'; Kind = 'app'
                    Tags = @{ Owner = 'carol' }
                },
                [pscustomobject]@{
                    Name = 'nic-out-of-scope'; ResourceType = 'Microsoft.Network/networkInterfaces'
                    ResourceId = '/subscriptions/x/nic-out-of-scope'; Kind = $null
                    Tags = @{}
                }
            )
        }
    }

    It 'includes only configured resource types' {
        $result = Get-InScopeTaggedResources -Config $Config
        $result.Name | Should -Not -Contain 'nic-out-of-scope'
    }

    It 'excludes regular Web Apps but includes Function Apps for Microsoft.Web/sites' {
        $result = Get-InScopeTaggedResources -Config $Config
        $result.Name | Should -Contain 'func-in-scope'
        $result.Name | Should -Not -Contain 'webapp-out-of-scope'
    }

    It 'preserves tags on returned resources' {
        $result = Get-InScopeTaggedResources -Config $Config
        ($result | Where-Object Name -eq 'vm-in-scope').Tags.Owner | Should -Be 'alice'
    }
}

Describe 'Find-TopdeskConfigurationItem' {
    It 'returns null when no CI matches' {
        Mock -ModuleName TopdeskClient Invoke-RestMethod { return [pscustomobject]@{ dataSet = @() } }
        $result = Find-TopdeskConfigurationItem -Name 'missing-ci' -BaseUrl 'https://example.topdesk.net' -AuthHeader @{ Authorization = 'Basic xxx' }
        $result | Should -BeNullOrEmpty
    }

    It 'returns the first matching CI' {
        Mock -ModuleName TopdeskClient Invoke-RestMethod { return [pscustomobject]@{ dataSet = @(@{ id = 'unid-1'; name = 'vm-in-scope' }) } }
        $result = Find-TopdeskConfigurationItem -Name 'vm-in-scope' -BaseUrl 'https://example.topdesk.net' -AuthHeader @{ Authorization = 'Basic xxx' }
        $result.id | Should -Be 'unid-1'
    }
}

Describe 'Update-TopdeskConfigurationItem' {
    It 'calls Invoke-RestMethod with a PATCH and the mapped fields' {
        Mock -ModuleName TopdeskClient Invoke-RestMethod { return $null }
        Update-TopdeskConfigurationItem -Unid 'unid-1' -Fields @{ owner = 'alice'; team = 'platform' } -BaseUrl 'https://example.topdesk.net' -AuthHeader @{ Authorization = 'Basic xxx' }
        Should -Invoke Invoke-RestMethod -ModuleName TopdeskClient -Times 1 -ParameterFilter { $Method -eq 'Patch' }
    }

    It 'does not call Invoke-RestMethod when -WhatIf is used' {
        Mock -ModuleName TopdeskClient Invoke-RestMethod { return $null }
        Update-TopdeskConfigurationItem -Unid 'unid-1' -Fields @{ owner = 'alice' } -BaseUrl 'https://example.topdesk.net' -AuthHeader @{ Authorization = 'Basic xxx' } -WhatIf
        Should -Invoke Invoke-RestMethod -ModuleName TopdeskClient -Times 0
    }
}

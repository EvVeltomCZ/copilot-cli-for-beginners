# Azure Tags → TopDesk CMDB Sync

A standalone PowerShell automation that pushes Azure resource tags into
matching TopDesk CMDB Configuration Items (CIs), scheduled via an Azure
DevOps pipeline. This sample is not part of the book-app course flow — it's
a real-world example of automating a CMDB integration.

## What it does

- Reads Azure resources of specific types — **Virtual Machines, Storage
  Accounts, Key Vaults, and Function Apps**.
- For each resource, reads the `Owner` and `Team` tags.
- Finds the matching TopDesk CI by resource name.
- Updates the CI's `owner` and `team` fields to match the Azure tags.
- **One-way sync**: Azure tags are the source of truth. TopDesk is never
  written back to Azure.
- If no matching CI is found, the resource is skipped and logged (CIs are
  never auto-created).

## Folder structure

```
azure-topdesk-sync/
├── azure-pipelines.yml           # Scheduled Azure DevOps pipeline
├── config/
│   └── mapping.json              # In-scope resource types + tag→field mapping
├── src/
│   ├── Sync-AzureTagsToTopdesk.ps1   # Main entry script
│   └── modules/
│       ├── AzureResourceReader.psm1  # Azure auth + resource/tag reading
│       └── TopdeskClient.psm1        # TopDesk auth + CI lookup/update
└── tests/
    └── Sync.Tests.ps1            # Pester tests (mocked Az + REST calls)
```

## Prerequisites

- [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`)
- `Az.Accounts` and `Az.Resources` PowerShell modules
- [Pester](https://pester.dev/) 5.5+ (for running tests)
- An Azure AD **Service Principal** with `Reader` access to the resources
  in scope
- A **TopDesk** account/application password with permission to read and
  update Configuration Items via the Asset Management REST API

## Configuration reference (`config/mapping.json`)

| Key | Description |
|---|---|
| `resourceTypes` | ARM resource types to include (VMs, Storage Accounts, Key Vaults, Function Apps by default) |
| `tagToTopdeskField` | Maps an Azure tag name to a TopDesk CI field name, e.g. `"Owner": "owner"`, `"Team": "team"` |
| `topdeskCiLookup.matchOn` | How to find the TopDesk CI for a resource (default: match by `name`) |
| `scope.resourceGroups` | Optional list of resource group names to restrict the scan to. Leave empty to scan the whole subscription. |

Adjust the TopDesk field names in `tagToTopdeskField` to match your
tenant's actual CI field keys (they can differ between TopDesk instances).

## Required environment variables / secrets

These are never stored in the repo. In Azure DevOps, put them in a secret
variable group (see below) and reference it from the pipeline.

| Variable | Purpose |
|---|---|
| `AZURE_CLIENT_ID` | Service Principal application (client) ID |
| `AZURE_CLIENT_SECRET` | Service Principal secret |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Subscription to scan |
| `TOPDESK_URL` | Base URL of your TopDesk instance, e.g. `https://yourcompany.topdesk.net` |
| `TOPDESK_USERNAME` | TopDesk API account username |
| `TOPDESK_APP_PASSWORD` | TopDesk application password (not the user's login password) |

## Running locally

```bash
# Install required modules once
pwsh -Command "Install-Module Az.Accounts, Az.Resources, Pester -Scope CurrentUser -Force"

# Set the required environment variables for this shell session
export AZURE_CLIENT_ID=...
export AZURE_CLIENT_SECRET=...
export AZURE_TENANT_ID=...
export AZURE_SUBSCRIPTION_ID=...
export TOPDESK_URL=https://yourcompany.topdesk.net
export TOPDESK_USERNAME=...
export TOPDESK_APP_PASSWORD=...

# Dry run: logs intended changes without calling TopDesk's write API
pwsh samples/azure-topdesk-sync/src/Sync-AzureTagsToTopdesk.ps1 -DryRun

# Real run
pwsh samples/azure-topdesk-sync/src/Sync-AzureTagsToTopdesk.ps1
```

## Running the tests

```bash
pwsh -Command "Import-Module Pester -MinimumVersion 5.5.0; Invoke-Pester -Path samples/azure-topdesk-sync/tests/Sync.Tests.ps1"
```

## Setting up the Azure DevOps pipeline

1. Create a secret **variable group** named `azure-topdesk-sync-secrets`
   (Pipelines → Library) containing the environment variables listed above
   as secret variables — ideally linked to an **Azure Key Vault** rather
   than entered manually.
2. Import `azure-pipelines.yml` as a new pipeline pointing at this repo.
3. Grant the pipeline's service connection/Service Principal `Reader`
   access to the Azure resources in scope.
4. The pipeline runs on the `schedules:` cron trigger (default: nightly at
   03:00 UTC) and has no CI trigger. Adjust the cron expression in
   `azure-pipelines.yml` to match your change window.
5. The pipeline first runs the Pester tests, then runs the sync script; a
   failed test or any resource-sync error fails the pipeline run.

## Troubleshooting

- **"No TopDesk CI found for resource '...'"** — the resource name doesn't
  match any CI's `name` field in TopDesk. Confirm your CI naming convention
  matches Azure resource names, or adjust `topdeskCiLookup` and the lookup
  logic in `TopdeskClient.psm1` to match on a different field.
- **Missing environment variable errors** — double-check the variable
  group is linked to the pipeline and all required variables are populated.
- **Function Apps not appearing** — Function Apps share the ARM type
  `Microsoft.Web/sites` with regular Web Apps; only resources with a `Kind`
  starting with `functionapp` are included.

## Out of scope (v1)

- Bidirectional sync (TopDesk → Azure).
- Auto-creating missing TopDesk CIs.
- Resource types beyond VMs, Storage Accounts, Key Vaults, and Function
  Apps (add more to `config/mapping.json` as needed).

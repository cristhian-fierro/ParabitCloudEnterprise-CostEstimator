<#
.SYNOPSIS
  Deploys the Azure Retail Prices CORS proxy (Azure Function) used by the
  Parabit Cloud Cost Estimator.

.DESCRIPTION
  Targets the "acs-enterprise-cloud" subscription, creates a dedicated resource
  group, a storage account, a Flex Consumption Function App, and publishes the
  function code from this folder. Prints the endpoint to paste into PRICE_PROXY
  in ../index.html.

  Re-running is safe: az resource creation is idempotent for the same names, and
  `func publish` simply redeploys the code.

.PREREQUISITES
  - Azure CLI (az), logged in:  az login
  - Azure Functions Core Tools v4 (func):
      npm i -g azure-functions-core-tools@4 --unsafe-perm true
  - Node.js 20+

.EXAMPLE
  ./deploy.ps1
  ./deploy.ps1 -AppName azure-price-proxy-parabit -Location eastus
#>

[CmdletBinding()]
param(
  # acs-enterprise-cloud (pinned by ID to avoid the case-only name collision with
  # the separate "ACS-Enterprise-Cloud" subscription).
  [string]$Subscription   = "cafc707e-6fe7-4360-89fc-bea96b7bd931",
  [string]$ResourceGroup  = "rg-cost-estimator",
  [string]$Location       = "westus",
  [string]$NodeVersion    = "24",   # supported Linux Functions Node versions: 24, 22, 20, 18
  # Globally-unique names. Defaults add a short random suffix; override for stable names.
  [string]$AppName        = "azure-price-proxy-$([System.Guid]::NewGuid().ToString('N').Substring(0,6))",
  [string]$StorageAccount = "stcostproxy$([System.Guid]::NewGuid().ToString('N').Substring(0,8))",
  [hashtable]$Tags        = @{ app = "cost-estimator"; owner = "cristhian.fierro@parabit.com" }
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

# ── Preflight ────────────────────────────────────────────────────────────────
Write-Step "Checking prerequisites"
if (-not (Get-Command az   -ErrorAction SilentlyContinue)) { throw "Azure CLI (az) not found. Install it and run 'az login'." }
if (-not (Get-Command func -ErrorAction SilentlyContinue)) { throw "Azure Functions Core Tools (func) not found. Run: npm i -g azure-functions-core-tools@4 --unsafe-perm true" }

# Ensure logged in
try { az account show -o none 2>$null } catch { throw "Not logged in. Run 'az login' first." }
if ($LASTEXITCODE -ne 0) { throw "Not logged in. Run 'az login' first." }

# ── Subscription ─────────────────────────────────────────────────────────────
Write-Step "Selecting subscription: $Subscription"
az account set --subscription $Subscription
if ($LASTEXITCODE -ne 0) { throw "Could not select subscription '$Subscription'. Check the name with: az account list -o table" }
$subId = az account show --query id -o tsv
Write-Host "Subscription id: $subId"

# Storage account names must be 3-24 lowercase alphanumeric.
$StorageAccount = ($StorageAccount.ToLower() -replace '[^a-z0-9]', '')
if ($StorageAccount.Length -gt 24) { $StorageAccount = $StorageAccount.Substring(0, 24) }

$tagArgs = @(); foreach ($k in $Tags.Keys) { $tagArgs += "$k=$($Tags[$k])" }

Write-Host "Resource group : $ResourceGroup"
Write-Host "Location       : $Location"
Write-Host "Function App   : $AppName"
Write-Host "Storage account: $StorageAccount"

# az is a native command: its failures do NOT trip $ErrorActionPreference, so check
# $LASTEXITCODE explicitly after each call to avoid silently continuing past an error.
function Assert-LastExit($what) { if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)." } }

# ── Resource group ───────────────────────────────────────────────────────────
Write-Step "Creating resource group"
az group create -n $ResourceGroup -l $Location --tags $tagArgs -o none
Assert-LastExit "az group create"

# ── Storage account (required by Functions) ──────────────────────────────────
Write-Step "Creating storage account"
az storage account create -n $StorageAccount -g $ResourceGroup -l $Location --sku Standard_LRS --tags $tagArgs -o none
Assert-LastExit "az storage account create"

# ── Function App (Flex Consumption / Linux / Node $NodeVersion) ──────────────
# Flex Consumption is the modern, reliable serverless plan and is always Functions
# v4. (Classic Linux Consumption has flaky first-start / sync-trigger behavior and
# is being phased out — it failed to start the host during initial bring-up.)
Write-Step "Creating Function App (Flex Consumption)"
az functionapp create `
  -n $AppName -g $ResourceGroup `
  --flexconsumption-location $Location `
  --runtime node --runtime-version $NodeVersion `
  --storage-account $StorageAccount `
  --tags $tagArgs -o none
Assert-LastExit "az functionapp create"

# ── Publish code ─────────────────────────────────────────────────────────────
Write-Step "Installing dependencies"
npm install
Assert-LastExit "npm install"

Write-Step "Publishing function code"
func azure functionapp publish $AppName
Assert-LastExit "func publish"

# ── Done ─────────────────────────────────────────────────────────────────────
$endpoint = "https://$AppName.azurewebsites.net/api/prices"
Write-Step "Deployment complete"
Write-Host "Endpoint: $endpoint" -ForegroundColor Green
Write-Host ""
Write-Host "Next: set this in ../index.html ->" -ForegroundColor Yellow
Write-Host "  const PRICE_PROXY = '$endpoint';"
Write-Host ""
Write-Host "Reminder: leave the Function App's platform CORS list EMPTY (CORS is set in code)." -ForegroundColor Yellow
Write-Host "Quick test:" -ForegroundColor Yellow
Write-Host "  `$u = [uri]::EscapeDataString(`"https://prices.azure.com/api/retail/prices?`$top=1`")"
Write-Host "  curl `"$endpoint`?url=`$u`" -i"

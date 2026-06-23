# Azure Price Proxy (CORS)

A tiny HTTP-triggered Azure Function that proxies the **Azure Retail Prices API**
(`prices.azure.com`) and adds CORS headers, so the static Cost Estimator
(`../index.html`, hosted on GitHub Pages) can call it from the browser.

`prices.azure.com` itself sends **no `Access-Control-Allow-Origin` header**, so a browser
blocks direct calls. This proxy is the fix. It is **locked to `prices.azure.com`** and so
cannot be used as an open proxy.

```
Endpoint:  https://<appName>.azurewebsites.net/api/prices
Usage:     /api/prices?url=<encodeURIComponent(azure-pricing-url)>
```

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`), logged in:
  `az login`
- [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local) (`func`):
  `npm i -g azure-functions-core-tools@4 --unsafe-perm true`
- Node.js 20+

## Run locally

```bash
cd azure-proxy
npm install
func start
```

Test (PowerShell):

```powershell
$az = [uri]::EscapeDataString("https://prices.azure.com/api/retail/prices?`$top=1")
curl "http://localhost:7071/api/prices?url=$az" -i        # → 200 + Access-Control-Allow-Origin: *
curl "http://localhost:7071/api/prices?url=https://evil.example.com" -i   # → 403
curl "http://localhost:7071/api/prices" -i                # → 400 (missing url)
```

## Deploy

A deployment script is provided: [`deploy.ps1`](deploy.ps1). It targets the
**`acs-enterprise-cloud`** subscription (pinned by id `cafc707e-…-bea96b7bd931` to avoid
the case-only collision with the separate `ACS-Enterprise-Cloud`), creates a dedicated resource group
(`rg-cost-estimator`), a storage account, and a **Flex Consumption** Function App,
then publishes the code.

```powershell
cd azure-proxy
az login                 # if not already signed in
./deploy.ps1
```

Override defaults if needed:

```powershell
./deploy.ps1 -AppName azure-price-proxy-parabit -Location eastus -ResourceGroup rg-cost-estimator
```

The script prints the invoke URL on success, e.g.
`https://azure-price-proxy-ab12cd.azurewebsites.net/api/prices`.

### Manual equivalent (if you prefer raw commands)

```powershell
az account set --subscription "cafc707e-6fe7-4360-89fc-bea96b7bd931"  # acs-enterprise-cloud
$RG="rg-cost-estimator"; $LOC="westus"
$STORAGE="stcostproxy" + (Get-Random -Maximum 99999)
$APP="azure-price-proxy-" + (Get-Random -Maximum 99999)

az group create -n $RG -l $LOC
az storage account create -n $STORAGE -g $RG -l $LOC --sku Standard_LRS
az functionapp create -n $APP -g $RG `
  --flexconsumption-location $LOC `
  --runtime node --runtime-version 24 `
  --storage-account $STORAGE

func azure functionapp publish $APP
```

> **Plan note:** use **Flex Consumption** (`--flexconsumption-location`), not classic
> Linux Consumption (`--consumption-plan-location`). The classic plan exhibited flaky
> host startup / sync-trigger failures during bring-up; Flex is the modern, reliable
> serverless plan and is what `deploy.ps1` uses.

## Wire it into the app

In `../index.html`, set the proxy constant to the deployed endpoint:

```js
const PRICE_PROXY = 'https://azure-price-proxy-12345.azurewebsites.net/api/prices';
```

Then open `index.html` and click **🔄 Refresh from Azure**.

## ⚠️ CORS note

Leave the Function App's **platform CORS list empty** (Portal → Function App → API → CORS).
This function sets CORS headers in code; if you also configure platform CORS origins, Azure
handles CORS itself and ignores the code headers, causing conflicts.

## Cost

Flex Consumption: scales to zero, billed per execution + active GB-seconds. At this volume
(a handful of calls per refresh, cached 1h) it stays comfortably within the free grant.

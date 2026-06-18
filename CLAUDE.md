# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a **single-file static HTML application** — the entire app lives in `index.html`. There is no build system, no package manager, and no server-side code. It is deployed via GitHub Pages at:

**https://cristhian-fierro.github.io/ParabitCloudEnterprise-CostEstimator/**

The only external dependency is Chart.js, loaded from a CDN:
```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.js"></script>
```

The `azure-proxy/` sibling folder is **separate backend infrastructure** — a small Azure Function CORS proxy that lets the browser call `prices.azure.com` for live price refresh. It is not part of the single-file constraint. See [`azure-proxy/README.md`](azure-proxy/README.md) for deploy instructions.

## Running Locally

Open `index.html` directly in a browser, or serve it with any static file server:

```bash
# Python
python -m http.server 8080

# Node (npx)
npx serve .
```

No build step, no install, no lint — just open the file.

## Architecture

Everything is in `index.html` in three sections:

1. **CSS** (`<style>` block, lines ~8–75) — inline styles; no external stylesheet. Key layout classes: `.section`, `.section-title`, `.metrics`, `.metric-card`, `.config-btn`, `.retention-btn`, `.failover-btn`, `.dr-btn`.

2. **HTML** (lines ~76–860) — static markup for the header (with live cost banner), controls, comparison tables, chart canvas, glossary, and action buttons. The service breakdown table (`#serviceTable`) and add-ons container (`#addonsContainer`) are populated entirely by JavaScript. Key input IDs: `controllers`, `hbInterval`, `credEvents`, `alarmEvents`, `taxRate`. Key button groups: `fo-none/fo-critical/fo-all` (failover), `dr-none/dr-standard/dr-advanced` (DR), `ret-3m/ret-6m/ret-1y/ret-3y/ret-10y` (retention).

3. **JavaScript** (`<script>` block, lines ~860+) — all logic. Key data structures and functions:

### Global State
- `selectedConfig` — 0=Minimum, 1=Standard, 2=Advanced
- `selectedRetentionMonths` — 3, 6, 12, 36, or 120 (default: 12)
- `selectedFailover` — 0=None, 1=Critical Services, 2=All Services
- `selectedDR` — 0=None, 1=Standard DR, 2=Advanced DR

### Constants
- `TIERS` — 4 controller tiers (Starter/Standard/Professional/Enterprise), each with a `max` controller count.
- `SERVICES` — Azure service line items. Each has `minCosts`, `consCosts`, `advCosts` arrays (one cost per tier index 0–3), a `skus` array (one label per config), and an `eligible` flag for reservation discounts. Services with `dynamic: 'cosmos'`, `dynamic: 'alarm'`, or `dynamic: 'egress'` are computed rather than looked up.
- `ADD_ONS` — 3 optional add-ons (SQL transaction buffer, SQL backup PITR+LTR, Cosmos continuous backup) with `baseCosts` per tier, scaled by `multipliers[selectedConfig]`.
- `CONFIGS` — the three service configurations (Minimum/Standard/Advanced).
- `multipliers` — `[0.5, 1.0, 2.0]` — module-level constant used by `getAddonCost()`, failover cost, and DR cost calculations.
- `EVENT_BYTES` — `{ credential: 1054, alarm: 342, heartbeat: 342 }` — per-event byte sizes from cloud data analysis.
- `SECURITY_OVERHEAD` — `0.50` — 50% added on top of raw event data volume for encryption/audit metadata.
- `EGRESS_GB` — estimated outbound GB/month per config and tier.
- `FAILOVER_OPTIONS` — 3 failover scopes, each with `baseCosts[tierIdx]` and a `lineItems` array of sub-components.
- `DR_OPTIONS` — 3 DR tiers, same structure as `FAILOVER_OPTIONS`.
- `DEFAULT_PRICING` — frozen object with the 9 built-in per-unit price constants: `blobHot`, `blobCool`, `blobArchive`, `laInteractive`, `laArchive`, `cosmosServerless`, `cosmosProvisioned`, `cosmosMultiRegion`, `egressPerGb`. These are the West US baseline prices baked into the app.
- `PRICING` — mutable copy of `DEFAULT_PRICING`. All cost functions reference `PRICING.*` instead of inline literals. Overwritten by `refreshPricesFromAzure()`; restored to `DEFAULT_PRICING` by `resetToDefaults()`.
- `RETAIL_API` — base URL `https://prices.azure.com/api/retail/prices` (not called directly from browser due to CORS).
- `PRICE_PROXY` — URL of the deployed Azure Function CORS proxy (`https://azure-price-proxy-e42505.azurewebsites.net/api/prices`). Set to `''` to disable live refresh.
- `PRICE_TARGETS` — array of 9 objects `{ key, label, unit, filter, pick }` — one per refreshable price. `filter` is the OData `$filter` string for the Azure Retail Prices API; `pick` selects the right item from the returned `Items` array. On no confident match the key is left at its current `PRICING` value.

### Key Functions
- `calculate()` — main recalculation; reads all inputs, recomputes every cost, updates DOM table, metric cards, header banner, and Chart.js instance.
- `calculateCosmosCost()` — dynamic Cosmos DB cost based on heartbeat interval, credential events, alarm events, controllers, and selected config. Uses `PRICING.cosmosServerless`, `PRICING.cosmosProvisioned`, `PRICING.cosmosMultiRegion`.
- `calculateMonthlyDataGb(controllers, credEvents, alarmEvents, hbInterval)` — auto-calculates data volume from event byte sizes + 50% security overhead; returns `{ credGb, alarmGb, hbGb, rawGb, totalGb }`.
- `calculateRetentionCost(ingestGb, retentionMonths)` — returns blob and Log Analytics costs broken down by Hot/Cool/Archive tiers. Uses `PRICING.blobHot/blobCool/blobArchive/laInteractive/laArchive`.
- `calculateEgressCost(tierIdx)` — returns egress cost from `EGRESS_GB[selectedConfig][tierIdx] * PRICING.egressPerGb`.
- `getAddonCost(addon, tierIdx)` — returns `addon.baseCosts[tierIdx] * multipliers[selectedConfig]`.
- `refreshPricesFromAzure()` — opens the progress modal, loops `PRICE_TARGETS` sequentially via the CORS proxy, stages matched values, assigns into `PRICING`, calls `calculate()`, shows the live-prices badge. Leaves `PRICING` untouched for any target that fails or returns no confident match.
- `resetToDefaults()` — resets all inputs to their initial values, restores `PRICING = { ...DEFAULT_PRICING }`, clears the live-prices badge, and calls `calculate()`.
- `closeRefreshModal()` — hides the progress modal.
- `selectConfig(idx)` — updates `selectedConfig`, refreshes config panel, calls `calculate()`.
- `selectRetention(months)` — updates `selectedRetentionMonths`, toggles button active state, calls `calculate()`.
- `selectFailover(idx)` — updates `selectedFailover`, toggles button active state, updates description panel, calls `calculate()`.
- `selectDR(idx)` — updates `selectedDR`, toggles button active state, updates description panel, calls `calculate()`.
- `initAddOns()` — renders add-on checkboxes from `ADD_ONS` into `#addonsContainer`.
- `initAccordions()` — wraps each `.section`'s non-title children in a `.section-content` div and wires up collapse/expand toggle.

## Pricing Data

All Azure prices are West US estimates re-verified against the Azure Retail Prices API (June 2026). Confirmed current prices:

| Service | Verified Price |
|---|---|
| App Gateway WAF_v2 | $341.64/mo base → code uses $342 |
| Blob Storage Hot LRS | $0.0208/GB/mo |
| App Service S2 | $146/mo (Windows) |
| Cosmos DB Serverless | $0.279/M RU |
| Cosmos DB Provisioned | $0.008/hr per 100 RU/s |
| Cosmos DB Multi-region write | $0.016/hr per 100 RU/s |
| AKS Uptime SLA | $0.10/hr → $73/mo |

When updating prices, update the relevant arrays in `SERVICES`, `ADD_ONS`, `FAILOVER_OPTIONS`, and `DR_OPTIONS`, and update the static comparison tables in the HTML markup to stay in sync.

The reservation discount is a flat 35% off (`cost * 0.65`) applied only to services with `eligible: true`. Failover and DR costs are not reservation-eligible.

## Important Constraints

- **No build step** — edits to `index.html` are live immediately. Test by opening the file in a browser.
- **Single file** — do not split into multiple files. All CSS, HTML, and JS stays in `index.html`.
- **Chart exclusion** — Geo-Failover and DR costs are appended to the breakdown table *after* the chart update, so they are intentionally excluded from the Cost by Category chart.
- **Accordion timing** — `initAccordions()` runs last, after all `select*()` calls in the initial render block. Do not move it earlier.
- **`annualCost` DOM element** — must exist in the HTML (currently an Annual Subtotal metric card in the Summary section). If removed, `calculate()` will throw a TypeError and the chart will not render.

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a **single-file static HTML application** — the entire app lives in `index.html`. There is no build system, no package manager, and no server-side code. It is deployed via GitHub Pages.

The only external dependency is Chart.js, loaded from a CDN:
```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.js"></script>
```

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

1. **CSS** (`<style>` block, lines ~8–65) — inline styles; no external stylesheet. Key layout classes: `.section`, `.section-title`, `.metrics`, `.metric-card`, `.config-btn`.

2. **HTML** (lines ~67–535) — static markup for the header, controls, comparison tables, chart canvas, and action buttons. The service breakdown table (`#serviceTable`) and add-ons container (`#addonsContainer`) are populated entirely by JavaScript.

3. **JavaScript** (`<script>` block, lines ~537–1208) — all logic. Key data structures and functions:
   - `TIERS` — array of 4 controller tiers (Starter/Standard/Professional/Enterprise), each with a `max` controller count.
   - `SERVICES` — array of Azure service line items. Each service has `minCosts`, `consCosts`, `advCosts` arrays (one cost per tier index), a `skus` array (one label per config), and an `eligible` flag for reservation discounts. Services with `dynamic: 'cosmos'` or `dynamic: 'alarm'` are computed rather than looked up.
   - `ADD_ONS` — optional add-on services with `baseCosts` per tier; scaled by a `[0.5, 1.0, 2.0]` multiplier for the selected config.
   - `CONFIGS` — the three service configurations (Minimum/Standard/Advanced), stored at index 0/1/2 in `selectedConfig`.
   - `calculate()` — the main recalculation function; reads all inputs, recomputes every cost, updates the DOM table and Chart.js instance.
   - `calculateCosmosCost()` — dynamic Cosmos DB cost based on heartbeat interval, credential events, alarm events, controllers, and selected config.
   - `selectTier(tierIdx, tierName)` — updates the controllers slider and tier detail panel; calls `calculate()`.
   - `selectConfig(idx)` — updates `selectedConfig`, refreshes config panel, calls `calculate()`.
   - `initAddOns()` — renders add-on checkboxes from `ADD_ONS` into `#addonsContainer`.
   - `initAccordions()` — wraps each `.section`'s non-title children in a `.section-content` div and wires up collapse/expand toggle.

## Pricing Data

All Azure prices are West US estimates verified against the Azure Pricing API (May 2025). When updating prices, update the relevant arrays in `SERVICES` and `ADD_ONS`, and update the comparison tables in the HTML static markup to stay in sync.

The reservation discount is a flat 35% off (`cost * 0.65`) applied only to services with `eligible: true`.

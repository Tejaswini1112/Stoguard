# Stoguard product roadmap

Mental model:

```
Observe → Understand → Explain → Predict → Recommend → Automate → Optimize
```

Cleaning is one step in that pipeline.

## Version map

| Version | Focus |
|--------|--------|
| **1.0** | Workstation Doctor · Explain every term · Health score + timeline · Safe cleanup |
| **2.0** | Ask Stoguard · Local AI workspace manager · Env Doctor · Build performance |
| **3.0** | Repository Doctor · Plugin marketplace packs · Automation · Predictive storage |
| **4.0** | Enterprise polish · Team insights · Shared plugins · Windows/Linux depth (core already ships) |

## Phase status

| # | Phase | Status |
|---|--------|--------|
| 1 | Doctor answers *why* (Problem→…→Learn More) | **Shipped** |
| 2 | Knowledge graph cards | **Shipped** |
| 3 | Ask Stoguard (scan-grounded) | **Shipped** |
| 4 | Health score + history | **Shipped** |
| 5 | Predictive AI (GB/day + days-to-full for Docker/Ollama/HF/DerivedData/Downloads/TM) | **Shipped** |
| 6 | Local AI workspace (RAM/GPU/quant/dupes/archive) | **Shipped** |
| 7 | Environment Doctor (Brew doctor, Node/Python/Java/Android/Flutter/Rust/asdf/mise) | **Shipped** |
| 8 | Repository Doctor (+ secrets scanner) | **Shipped** |
| 9 | Plugin SDK (detection + explanation + risk + actions + docs) | **Shipped** |
| 10 | Explain Everything (Why / undo / rebuild / common on recommendations) | **Shipped** |
| 11 | Background monitoring (growth spikes, idle models, disk) | **Shipped** (while app runs) |
| 12 | Cloud knowledge (opt-in cohorts) | **Shipped** (baselines + fleet peers + optional remote feed/contribute) |
| 13 | Enterprise fleet | **Shipped** (schema v2, compliance, AI/license inventory, LAN Team server + API key) |

## Deliberately optional

Hosted SaaS multi-tenant cloud, SSO/SAML, and App Store notarization remain optional commercial layers — the on-prem / self-hosted suite is complete.

## Ask contract

Grounded in scan / pulse / models / env / health only. Fix stages; never silent-deletes.

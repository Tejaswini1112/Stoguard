# Stoguard Enterprise & Cloud Cohorts

## Cloud cohort knowledge

Opt-in only. Default is **off** — no network calls.

When enabled (Automation → cohort toggle, or `cloudOptIn` in automation.json):

1. **Baselines** — industry-style category averages (Docker, Ollama, DerivedData, WSL, NuGet, Flatpak, …)
2. **Fleet peers** — anonymous averages from machines ingested into the local Team fleet store (≥2 samples)
3. **Remote feed** (optional) — `STOGUARD_COHORT_FEED` / UserDefaults `stoguard.cohortFeedURL` JSON:
   ```json
   { "version": "1", "averages": { "docker": 18000000000, "ollama": 14000000000 } }
   ```
4. **Contribute** (optional) — `STOGUARD_COHORT_CONTRIBUTE` / `stoguard.cohortContributeURL`  
   POSTs **only** `{ platform, metrics }` — no hostname, paths, or machine IDs.

Native: Health → Cloud cohort knowledge. Go: `/api/cohort` + Health UI.

## Multi-OS enterprise fleet

Shared **schema v2** (`EnterpriseReport` / `FleetReport`) across macOS Swift and Go (Windows/Linux).

### Fields

Machine ID · hostname · platform · arch · disk · reclaimable · top categories/items · env warnings · health score · **compliance** · **AI model inventory** · **license markers** · cohort metrics

### Compliance baseline

`Stoguard Developer Baseline v1`

- Disk &lt; 90% used  
- Env warnings = 0  
- Safe reclaimable &lt; 20 GB  
- No huge idle AI models (≥90d)  
- (Native) secrets count from last repo scan  

### Native macOS (Team console)

Sidebar **Enterprise** — export + ingest this Mac, list machines, compliance scores, push to remote Team server.

### Go Team server (all OSes)

```bash
# LAN Team console (require API key)
./stoguard -bind 0.0.0.0 -port 8787 -api-key 'your-secret' -no-open

# CLI
./stoguard -fleet list
./stoguard -fleet summary
./stoguard -fleet export
./stoguard -fleet ingest-self
```

| API | Role |
|-----|------|
| `GET /api/fleet` | List machines (Team) |
| `GET /api/fleet/summary` | Rollup |
| `POST /api/fleet/ingest` | Push report (Team) |
| `GET /api/fleet/export` | Export this host (Pro+) |
| `POST /api/fleet/delete?id=` | Remove machine |

Header: `X-Stoguard-Key: …` when `-api-key` is set.

### Client push (macOS)

Enterprise → set `http://fleet-host:8787` + API key → **Push report to remote**.

Windows/Linux agents use the same JSON against `/api/fleet/ingest`.

## Privacy

- Cohort opt-in is explicit.  
- Fleet reports stay on your Team server / local Application Support.  
- Contribute payloads never include hostnames or file paths.  
See [PRIVACY.md](PRIVACY.md).

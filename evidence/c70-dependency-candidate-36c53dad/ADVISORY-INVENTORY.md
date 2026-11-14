# DeedLight C70 — exact audit advisory inventory

Source: actual `npm audit --audit-level=high` output from run [43606668445](https://github.com/ADRN-9/deedlight/actions/runs/43606668445), job `132482681999`, executed 2026-11-14. Historical npm aggregate: **21 affected dependency entries (12 moderate, 7 high, 2 critical)**; advisory URL count differs from affected dependency count.

| Vulnerable family | Historical severity | Direct or transitive | Advisory IDs (from actual CI logs) | Candidate status |
| --- | --- | --- | --- | --- |
| `next` | critical | Direct pinned `16.3.6` | GHSA-3w37-wq28-93x7, GHSA-4jqv-mc3x-m676, GHSA-39w2-rjm5-chcv, GHSA-f87g-xv8r-7p7x, GHSA-mcj8-r9mp-w47p, GHSA-cjq9-62q9-8jv4, GHSA-2464-fhr4-w9xw, GHSA-p3m5-59mp-jv5r, GHSA-h694-7cp9-m8p3, GHSA-673q-mjm6-r5xr | Resolved `16.4.6` |
| `proxy-addr` | critical | Transitive `express` | GHSA-jqcg-44mw-7w3h | Resolved `2.0.8` |
| `body-parser` | high | Transitive `express` | GHSA-27r3-jxmh-p828 | Resolved `2.4.0` |
| `sharp` | high | Transitive `miniflare`, optional Next | GHSA-wq5f-xc86-pv6w | Resolved `0.35.5` |
| `source-map-js` | high | Transitive `postcss`, Tailwind | GHSA-68fv-2mgg-jv7q | Resolved `1.2.2` |
| `undici` | high | Transitive `miniflare`/`wrangler` | GHSA-3wwx-pv8p-q78v, GHSA-pmjh-fq2x-6v4x, GHSA-r53p-7pc4-xj5r, GHSA-rfgv-xxqx-mfg5, GHSA-3xpg-4rpp-hhhm, GHSA-2jfj-6hjv-fm6j, GHSA-2gqq-gqf2-x968, GHSA-w293-vg96-wgc3, GHSA-8436-99hf-9mmv, GHSA-rx4f-c7p8-82vq, GHSA-4qv8-2p9j-2685, GHSA-f72v-6w45-q472, GHSA-xjj6-f33q-929c, GHSA-4w7w-5xrc-9h26, GHSA-2m5v-pch6-74hx, GHSA-qrxm-fqhp-jwvm, GHSA-9fm3-97px-rjf6, GHSA-55wc-3pg8-jfw6 | Resolved `7.30.1` |
| `zod` | high | Direct, previously `latest` resolved `4.4.3` | GHSA-mrhx-c7xc-m3w5 | Resolved `4.6.7` |
| `qs` | moderate | Transitive `body-parser`/`express` | GHSA-6pq8-jhm2-2vcw | Resolved `6.17.1` |
| `glob` | moderate | Transitive `@opennextjs/cloudflare`, `@node-minify/core` | GHSA-3g3m-2fjr-6pw4 | **OPEN** `13.0.7` still vulnerable per new audit |
| `minimatch` | moderate | Transitive glob and TypeScript ESLint | GHSA-g3hv-75wg-m249 | **OPEN** `10.2.6` still vulnerable per new audit |

## New audit evidence

- [Candidate run 43618537821](https://github.com/ADRN-9/deedlight/actions/runs/43618537821) produced **9 moderate, 0 high, 0 critical**, `npm audit --audit-level=high` exit **0**.
- Underlying root OpenNext adapter updated to `@opennextjs/cloudflare@1.20.17` by npm resolution; dependency candidates passed a real Next production build and Cloudflare packaging run.
- `npm audit fix --package-lock-only` returned **1** because moderate advisories remain. No `--force` was run and no unsupported overrides were inserted. Do **not** claim complete clean audit.
- Original historical Next/`undici` multiple advisory IDs are separate advisory records; the counts above correspond to npm's **affected package** aggregation, not the number of distinct security bulletins.
- All original GHSA IDs above were recovered from actual job logs, not generated speculatively. Exact candidate audit JSON is in this directory.

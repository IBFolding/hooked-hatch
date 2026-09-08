# HOOKED / HATCH brand direction

## HOOKED

**Positioning:** experimental market lab, not generic launchpad.

**Wordmark:** heavy condensed/editorial sans, aggressively tight tracking. Hook icon should be geometric and usable alone as favicon/PFP.

**Palette:**
- carbon `#080A09`
- bone `#E9EADF`
- signal green `#B9FF2C`
- machine gray `#8F978D`

**Texture:** photocopy grain, warning labels, lab instrumentation, terminal typography. Avoid glossy gradients and generic neon cyberpunk.

**Voice:** short, declarative, slightly dangerous.

Primary line: `GET HOOKED.`
Secondary: `TOKENS WITH A MECHANISM INSIDE.`

## HATCH

**Primary line:** `FEED THE EGG.`
**Secondary:** `NOBODY KNOWS WHAT'S INSIDE.`

Visual: pale engineered egg in a dark containment chamber. Hairline fractures reveal acid-green internal light as the real Nest NVDA balance clears milestones.

Do not use NVIDIA's logo or imply NVIDIA affiliation. The mechanism can name the NVDA quote asset factually.

Stages:
0. Dormant — clean egg
1. Hairline — one tiny fracture
2. Cracked — branching fractures
3. Movement — subtle distortion/shadow
4. Eye Contact — one green eye visible
5. Containment Failing — glow/leakage
6. Hatched — shell broken; silhouette only
7. ??? — unrevealed until threshold

---

## Asset inventory

All marks are generated from `brand/generate-assets.py` (single source of truth —
edit that, then re-run it, rather than hand-editing the SVGs):

```bash
python3 brand/generate-assets.py
```

PNGs are rasterised from those SVGs at exact required dimensions.

### HOOKED

| Asset | SVG | PNG |
|---|---|---|
| Hook mark (transparent) | `web/assets/hook-mark.svg` | `png/hook-mark.png` |
| Square icon, dark | `web/assets/hooked-icon-dark.svg` | `png/hooked-icon-dark.png` 512² |
| Square icon, light | `web/assets/hooked-icon-light.svg` | `png/hooked-icon-light.png` 512² |
| Wordmark, dark bg | `web/assets/hooked-wordmark-dark.svg` | `png/…-dark.png` 1520×360 |
| Wordmark, light bg | `web/assets/hooked-wordmark-light.svg` | `png/…-light.png` 1520×360 |
| Wordmark, transparent | `web/assets/hooked-wordmark-transparent.svg` | `png/…-transparent.png` |
| Favicon | `web/assets/favicon.svg` | — |

### HATCH

| Asset | SVG | PNG |
|---|---|---|
| Mark (transparent) | `web/assets/hatch-mark.svg` | `png/hatch-mark.png` 512² |
| Square PFP | `web/assets/hatch-pfp.svg` | `png/hatch-pfp.png` 512² |
| Stages 0–7, 1:1 | `web/assets/stages/stage-N.svg` | `png/stages/stage-N.png` 1024² |

### Social

| Asset | Size | Path |
|---|---|---|
| X banner | 1500×500 | `web/assets/social/x-banner.*` |
| Share card, HOOKED | 1200×630 | `web/assets/social/og-hooked.*` |
| Share card, HATCH | 1200×630 | `web/assets/social/og-hatch.*` |

### Mark construction notes

The hook is an open eye loop, a straight shank, a deep semicircular bend, and a
**filled triangular spear point**. The point is filled rather than stroked and
tilts away from the shank on purpose: a stroked barb fills in below ~32px and the
whole mark collapses into a letter J. Placement uses the `hook_centred()` helper
because the artwork is not centred in its own viewBox.

These are house marks and stand in until final artwork lands. Replacing them means
swapping the files above — nothing else references the artwork by name except
`web/index.html`, `web/hatch.html` (favicon + og:image) and `styles.css`
(`.hook-mark`).

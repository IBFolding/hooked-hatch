#!/usr/bin/env python3
"""Generates the HOOKED / HATCH SVG asset set from the BRAND.md palette.

These are the house marks: geometric, flat, no gradients on the logo itself.
Re-run after editing to regenerate every derived size.
Output: web/assets/
"""
import os, pathlib

CARBON="#080A09"; BONE="#E9EADF"; ACID="#B9FF2C"; GRAY="#8F978D"
OUT = pathlib.Path(__file__).resolve().parent.parent / "web" / "assets"
(OUT/"stages").mkdir(parents=True, exist_ok=True)
(OUT/"social").mkdir(parents=True, exist_ok=True)

def write(name, body):
    p = OUT / name
    p.write_text(body.strip() + "\n")
    print(f"  {p.relative_to(OUT.parent.parent)}")

# ---------------------------------------------------------------- hook mark
# Geometric fishing hook: straight shank, true semicircular bend, angled barb.
def hook(color=ACID, sw=9):
    """Fishing hook: open eye loop, straight shank, deep bend, filled spear point.

    The point is a solid triangle rather than a stroked V - at favicon size a
    stroked barb fills in and the mark collapses into a letter J.
    Content bounds in this viewBox are approx x 7..78, y 1..77.
    """
    return f'''<g fill="none" stroke="{color}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="62" cy="17" r="11"/>
    <path d="M62 28 V52 A20 20 0 1 1 22 52 L17 40"/>
  </g>
  <path d="M17 16 L28 41 L6 41 Z" fill="{color}" stroke="none"/>'''

# The hook artwork is not centred in its own viewBox, so every placement uses
# this helper rather than eyeballing a translate.
HOOK_CX, HOOK_CY = 42.0, 39.0

def hook_centred(cx, cy, scale, color=ACID, sw=9):
    tx = cx - HOOK_CX * scale
    ty = cy - HOOK_CY * scale
    return f'<g transform="translate({tx:.1f} {ty:.1f}) scale({scale})">{hook(color, sw)}</g>'

write("hook-mark.svg", f'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 88 100" width="88" height="100" role="img" aria-label="HOOKED hook mark">
  {hook()}
</svg>''')

for tag, bg, fg in (("dark", CARBON, ACID), ("light", BONE, "#4B7A00")):
    write(f"hooked-icon-{tag}.svg", f'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="HOOKED">
  <rect width="512" height="512" fill="{bg}"/>
  {hook_centred(256, 256, 4.0, fg)}
</svg>''')

# favicon: no padding, maximum legibility at 16px
write("favicon.svg", f'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 88 100" width="32" height="32">
  <rect width="88" height="100" fill="{CARBON}"/>
  {hook_centred(44, 50, 1.05, ACID, 10)}
</svg>''')

# ------------------------------------------------------------------ wordmark
def wordmark(bg, textcol, hookcol, transparent=False):
    rect = "" if transparent else f'<rect width="760" height="180" fill="{bg}"/>'
    return f'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 760 180" width="760" height="180" role="img" aria-label="HOOKED">
  {rect}
  {hook_centred(96, 88, 1.05, hookcol)}
  <text x="164" y="126" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-weight="900"
        font-size="112" letter-spacing="-7" fill="{textcol}">HOOKED</text>
</svg>'''

write("hooked-wordmark-dark.svg", wordmark(CARBON, BONE, ACID))
write("hooked-wordmark-light.svg", wordmark(BONE, CARBON, "#4B7A00"))
write("hooked-wordmark-transparent.svg", wordmark(CARBON, BONE, ACID, transparent=True))

# ----------------------------------------------------------------- the egg
EGG = "M256 104 C298 104 332 156 332 216 C332 300 298 376 256 376 C214 376 180 300 180 216 C180 156 214 104 256 104 Z"

CRACKS = [
    "",
    # 1 hairline
    '<path d="M268 168 l14 26 l-9 9" />',
    # 2 branching
    '<path d="M268 168 l14 26 l-9 9 l18 22 M282 194 l24 -6" />'
    '<path d="M214 258 l-16 20 l10 14" />',
    # 3 movement: same cracks, wider
    '<path d="M268 160 l16 30 l-10 10 l20 26 M284 190 l28 -8 M274 200 l-12 30" />'
    '<path d="M212 252 l-18 22 l12 16 l-8 18" />',
    # 4 eye contact
    '<path d="M268 156 l16 32 l-10 10 l20 28 M284 188 l30 -8 M274 198 l-14 34" />'
    '<path d="M210 248 l-20 24 l12 18 l-8 20 M202 272 l-22 6" />',
    # 5 containment failing
    '<path d="M266 148 l18 36 l-12 12 l22 32 M284 184 l34 -10 M272 196 l-16 40 M300 228 l24 14" />'
    '<path d="M208 242 l-22 26 l14 20 l-10 24 M200 268 l-26 8 M214 300 l-18 22" />',
    # 6 hatched - shell broken open
    '<path d="M180 232 l30 -14 l26 20 l30 -26 l28 22 l26 -18 l12 14" stroke-width="9"/>'
    '<path d="M266 148 l18 36 l-12 12 M208 242 l-22 26 l14 20" />',
    # 7 unrevealed
    '<path d="M180 232 l30 -14 l26 20 l30 -26 l28 22 l26 -18 l12 14" stroke-width="9"/>',
]

STAGE_NAMES = ["DORMANT","HAIRLINE","CRACKED","MOVEMENT","EYE CONTACT","CONTAINMENT FAILING","HATCHED","???"]

def stage_svg(i, size=512, label=True):
    glow = ""
    eye = ""
    inner = ""
    egg_fill = "url(#shell)"
    extra_defs = ""

    if i >= 5:
        glow = f'<ellipse cx="256" cy="250" rx="120" ry="150" fill="{ACID}" opacity="{0.05 + 0.05*(i-4):.2f}" filter="url(#soft)"/>'
    if 4 <= i <= 6:
        eye = (f'<g><ellipse cx="252" cy="232" rx="34" ry="15" fill="#050605"/>'
               f'<circle cx="252" cy="231" r="7" fill="{ACID}"/>'
               f'<ellipse cx="252" cy="232" rx="34" ry="15" fill="none" stroke="{ACID}" stroke-width="2" opacity="0.5"/></g>')
    if i == 6:
        # shell broken: upper half gone, silhouette inside
        inner = (f'<path d="M196 244 C200 300 224 372 256 372 C288 372 312 300 316 244 Z" fill="#0d120e"/>'
                 f'<ellipse cx="256" cy="290" rx="42" ry="46" fill="#050605"/>'
                 f'<circle cx="244" cy="284" r="6" fill="{ACID}"/><circle cx="270" cy="284" r="6" fill="{ACID}"/>')
    if i == 7:
        egg_fill = "#0a0f0b"
        inner = (f'<text x="256" y="272" text-anchor="middle" font-family="monospace" font-weight="700"'
                 f' font-size="120" fill="{ACID}" opacity="0.85">?</text>')

    label_el = (f'<text x="256" y="452" text-anchor="middle" font-family="monospace" font-weight="700"'
                f' font-size="22" letter-spacing="4" fill="{GRAY}">{i} / {STAGE_NAMES[i]}</text>') if label else ""

    return f'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="{size}" height="{size}" role="img" aria-label="HATCH stage {i}: {STAGE_NAMES[i]}">
  <defs>
    <linearGradient id="shell" x1="0.2" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="#EDEFE3"/><stop offset="0.55" stop-color="#B7C0B0"/><stop offset="1" stop-color="#798476"/>
    </linearGradient>
    <radialGradient id="chamber" cx="0.5" cy="0.46">
      <stop offset="0" stop-color="#182016"/><stop offset="0.55" stop-color="#0c0f0d"/><stop offset="1" stop-color="{CARBON}"/>
    </radialGradient>
    <filter id="soft"><feGaussianBlur stdDeviation="26"/></filter>
  </defs>
  <rect width="512" height="512" fill="url(#chamber)"/>
  {glow}
  <g transform="{'rotate(-1.5 256 256)' if i==3 else ''}">
    <path d="{EGG}" fill="{egg_fill}"/>
    {inner}
    <g fill="none" stroke="#2b322c" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" opacity="{min(0.35 + 0.11*i, 0.95):.2f}">
      {CRACKS[i]}
    </g>
    {eye}
  </g>
  {label_el}
</svg>'''

print("\nHATCH stages:")
for i in range(8):
    write(f"stages/stage-{i}.svg", stage_svg(i))

# HATCH PFP: stage 2, no label, tight crop
write("hatch-pfp.svg", stage_svg(2, label=False))
write("hatch-mark.svg", f'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="HATCH">
  <defs><linearGradient id="s" x1="0.2" y1="0" x2="0.85" y2="1">
    <stop offset="0" stop-color="#EDEFE3"/><stop offset="0.55" stop-color="#B7C0B0"/><stop offset="1" stop-color="#798476"/>
  </linearGradient></defs>
  <path d="{EGG}" fill="url(#s)"/>
  <g fill="none" stroke="#2b322c" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" opacity="0.6">
    {CRACKS[2]}
  </g>
</svg>''')

# ------------------------------------------------------------------- social
print("\nSocial:")
write("social/x-banner.svg", f'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1500 500" width="1500" height="500" role="img" aria-label="HOOKED banner">
  <defs><radialGradient id="g" cx="0.72" cy="0.5"><stop offset="0" stop-color="#161d15"/><stop offset="1" stop-color="{CARBON}"/></radialGradient></defs>
  <rect width="1500" height="500" fill="url(#g)"/>
  {hook_centred(178, 250, 2.1, ACID)}
  <text x="290" y="250" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-weight="900" font-size="132" letter-spacing="-9" fill="{BONE}">GET HOOKED.</text>
  <text x="296" y="308" font-family="monospace" font-weight="700" font-size="26" letter-spacing="7" fill="{ACID}">TOKENS WITH A MECHANISM INSIDE.</text>
  <text x="296" y="356" font-family="monospace" font-weight="700" font-size="19" letter-spacing="4" fill="{GRAY}">ROBINHOOD CHAIN / EXPERIMENT 001: HATCH</text>
  <rect x="0" y="484" width="1500" height="16" fill="{ACID}"/>
</svg>''')

def og(title_lines, sub, kicker, egg=False):
    art = ""
    if egg:
        art = f'<g transform="translate(666 39) scale(1.15)"><path d="{EGG}" fill="url(#shell2)"/><g fill="none" stroke="#2b322c" stroke-width="5" stroke-linecap="round" opacity="0.6">{CRACKS[2]}</g></g>'
    else:
        art = f'<g opacity="0.92">{hook_centred(962, 318, 3.3, ACID)}</g>'
    return f'''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 630" width="1200" height="630" role="img" aria-label="{' '.join(title_lines)}">
  <defs>
    <radialGradient id="g2" cx="0.7" cy="0.45"><stop offset="0" stop-color="#161d15"/><stop offset="1" stop-color="{CARBON}"/></radialGradient>
    <filter id="soft2"><feGaussianBlur stdDeviation="40"/></filter>
    <linearGradient id="shell2" x1="0.2" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="#EDEFE3"/><stop offset="0.55" stop-color="#B7C0B0"/><stop offset="1" stop-color="#798476"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="630" fill="url(#g2)"/>
  <ellipse cx="962" cy="318" rx="150" ry="190" fill="{ACID}" opacity="0.05" filter="url(#soft2)"/>
  {art}
  <text x="80" y="150" font-family="monospace" font-weight="700" font-size="21" letter-spacing="6" fill="{GRAY}">{kicker}</text>
  <text x="76" y="300" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-weight="900" font-size="124" letter-spacing="-8" fill="{BONE}">{title_lines[0]}</text>
  <text x="76" y="410" font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-weight="900" font-size="124" letter-spacing="-8" fill="{ACID}">{title_lines[1]}</text>
  <text x="80" y="470" font-family="monospace" font-weight="700" font-size="24" letter-spacing="4" fill="{GRAY}">{sub}</text>
  <rect x="0" y="614" width="1200" height="16" fill="{ACID}"/>
</svg>'''

write("social/og-hooked.svg", og(["GET", "HOOKED."], "TOKENS WITH A MECHANISM INSIDE.", "HOOKED / ROBINHOOD CHAIN"))
write("social/og-hatch.svg", og(["FEED THE", "EGG."], "NOBODY KNOWS WHAT'S INSIDE.", "HOOKED 001 / HATCH / NVDA", egg=True))
print()

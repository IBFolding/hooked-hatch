#!/usr/bin/env bash
# Publish web/ to GitHub Pages.
#
#   ./scripts/deploy-web.sh
#
# Pages serves the gh-pages branch, which holds the contents of web/ at its root.
# This is the PUBLIC host: https://ibfolding.github.io/hooked-hatch/
# Vercel (hookedlabs.vercel.app) is behind the project's Vercel Authentication
# setting and stays a login wall until that is disabled in the dashboard.
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ -z "$(git status --porcelain web/)" ] || { echo "commit your web/ changes first"; exit 1; }

echo "publishing web/ to gh-pages…"
git push origin "$(git subtree split --prefix web main)":gh-pages --force
echo
echo "live in ~1 min: https://ibfolding.github.io/hooked-hatch/"

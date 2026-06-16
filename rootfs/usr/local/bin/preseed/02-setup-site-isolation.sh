#!/bin/bash
set -euo pipefail

SCRIPT=/usr/local/bin/setup-site-isolation.sh

chmod +x "$SCRIPT"

# Run immediately so pools exist before PHP-FPM accepts traffic
"$SCRIPT"

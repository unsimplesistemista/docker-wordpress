#!/bin/bash
set -euo pipefail

SCRIPT=/usr/local/bin/setup-site-isolation.sh

chmod +x "$SCRIPT"

# Fire and forget — cron picks it up within 1 minute; PHP-FPM reloads via USR2
"$SCRIPT" &

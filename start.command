#!/usr/bin/env bash
# Finder double-click wrapper. The real entry is ./start.sh.
cd "$(dirname "$0")"
./start.sh
echo
read -r -p "Press Enter to close..."

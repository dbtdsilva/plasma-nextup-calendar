#!/usr/bin/env bash
# Install or upgrade the Next Up Calendar widget for the current user.
set -euo pipefail
cd "$(dirname "$0")"

command -v kpackagetool6 >/dev/null || { echo "kpackagetool6 not found — install the 'kpackage-tools' (or 'plasma-sdk') package." >&2; exit 1; }
[ -d package ] || { echo "package/ directory not found next to this script." >&2; exit 1; }

ID="com.github.dbtdsilva.nextupcalendar"

if kpackagetool6 -t Plasma/Applet --show "$ID" >/dev/null 2>&1; then
    kpackagetool6 -t Plasma/Applet --upgrade package
else
    kpackagetool6 -t Plasma/Applet --install package
fi

echo
echo "Installed. Add it via panel right-click > Add Widgets > 'Next Up Calendar'."
echo "If an older version appears cached, restart plasmashell:"
echo "  systemctl --user restart plasma-plasmashell.service"

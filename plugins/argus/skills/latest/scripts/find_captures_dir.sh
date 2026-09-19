#!/usr/bin/env bash
# Resolves the ArgusCaptures directory for the active Unity project.
# Reads companyName + productName from ProjectSettings/ProjectSettings.asset
# and constructs the per-OS Unity persistent-data path.
#
# Prints the resolved directory on stdout. Exits non-zero with an error message on stderr if anything is missing.

set -euo pipefail

project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
settings="$project_root/ProjectSettings/ProjectSettings.asset"

if [ ! -f "$settings" ]; then
  echo "ERROR: ProjectSettings.asset not found at $settings — are we inside a Unity project?" >&2
  exit 1
fi

company=$(grep -E '^  companyName:' "$settings" | head -1 | sed -E 's/^  companyName: //; s/[[:space:]]*$//')
product=$(grep -E '^  productName:' "$settings" | head -1 | sed -E 's/^  productName: //; s/[[:space:]]*$//')

if [ -z "$company" ] || [ -z "$product" ]; then
  echo "ERROR: could not parse companyName/productName from $settings" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin)
    base="$HOME/Library/Application Support"
    ;;
  Linux)
    base="$HOME/.config/unity3d"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    # Git Bash on Windows. Unity uses %USERPROFILE%/AppData/LocalLow/<Co>/<Product>.
    base="${LOCALAPPDATA:-$HOME/AppData/Local}/../LocalLow"
    ;;
  *)
    echo "ERROR: unsupported OS $(uname -s)" >&2
    exit 1
    ;;
esac

dir="$base/$company/$product/ArgusCaptures"

if [ ! -d "$dir" ]; then
  echo "ERROR: captures directory does not exist yet: $dir" >&2
  echo "       Run a profiling session first (Tools → Argus Control → Start Profiling)." >&2
  exit 2
fi

echo "$dir"

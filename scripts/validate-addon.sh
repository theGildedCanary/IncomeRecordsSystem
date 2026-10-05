#!/usr/bin/env bash
set -euo pipefail

TOC="IncomeRecordsSystem.toc"

echo "Validating IRS repository..."

required_paths=(
  "$TOC"
  "README.md"
  "LICENSE"
  "CHANGELOG.md"
  "Core"
  "Features"
  "UI"
  "Media"
)

for path in "${required_paths[@]}"; do
  if [ ! -e "$path" ]; then
    echo "ERROR: Required path is missing: $path"
    exit 1
  fi
done

TOC_VERSION=$(awk -F: '
  /^## Version:/ {
    gsub(/^[ \t]+|[ \t]+$/, "", $2)
    print $2
    exit
  }
' "$TOC")

if [ -z "$TOC_VERSION" ]; then
  echo "ERROR: No ## Version: entry found in $TOC"
  exit 1
fi

if [[ ! "$TOC_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "ERROR: TOC version '$TOC_VERSION' is not in an expected semantic version format."
  exit 1
fi

echo "TOC version: $TOC_VERSION"

missing_reference=0

while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"

  if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
    continue
  fi

  file_path="${line//\\//}"

  if [ ! -f "$file_path" ]; then
    echo "ERROR: TOC references a missing file: $line"
    missing_reference=1
  fi
done < "$TOC"

if [ "$missing_reference" -ne 0 ]; then
  exit 1
fi

if command -v luac5.1 >/dev/null 2>&1; then
  LUAC="luac5.1"
elif command -v luac >/dev/null 2>&1; then
  LUAC="luac"
else
  echo "ERROR: Lua compiler not found."
  exit 1
fi

echo "Checking Lua syntax with $LUAC..."

while IFS= read -r -d '' file; do
  echo "  $file"
  "$LUAC" -p "$file"
done < <(find Core Features UI -type f -name '*.lua' -print0)

echo "Validation passed."

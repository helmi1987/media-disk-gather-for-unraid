#!/bin/bash
set -u

INI_FILE="consolidate.ini"

# Defaults
DEF_DIRS="/mnt/user/Filme /mnt/user/Serien"
DEF_LOG="/mnt/user/PlexMedia/consolidate.log"
DEF_ARRAY="/mnt/disk*"       # Nur Array Disks
DEF_CACHE="/mnt/cache"       # Cache oder Pools (Space getrennt)
DEF_EXCLUDE="/mnt/user/system/scripts/embycache_v2/embycache_exclude.txt"
DEF_DRYRUN="true"
DEF_MIN_FREE="256"

# Load existing
if [[ -f "$INI_FILE" ]]; then
    source "$INI_FILE"
    if [[ -n "${BASE_DIRS[*]-}" ]]; then DEF_DIRS="${BASE_DIRS[*]}"; fi
    if [[ -n "${LOGFILE-}" ]]; then DEF_LOG="$LOGFILE"; fi
    if [[ -n "${ARRAY_PATTERN-}" ]]; then DEF_ARRAY="$ARRAY_PATTERN"; fi
    if [[ -n "${CACHE_PATTERN-}" ]]; then DEF_CACHE="$CACHE_PATTERN"; fi
    if [[ -n "${EXCLUDE_FILE-}" ]]; then DEF_EXCLUDE="$EXCLUDE_FILE"; fi
    if [[ -n "${DRYRUN-}" ]]; then DEF_DRYRUN="$DRYRUN"; fi
    if [[ -n "${MIN_FREE_GB-}" ]]; then DEF_MIN_FREE="$MIN_FREE_GB"; fi
fi

echo "=========================================="
echo " 🛠  SETUP V8: Split Architecture"
echo "=========================================="

echo "1. Quellverzeichnisse (User Shares)"
read -e -i "$DEF_DIRS" -p "   Pfade: " INPUT_DIRS
echo ""

echo "2. Logdatei"
read -e -i "$DEF_LOG" -p "   Logfile: " INPUT_LOG
echo ""

echo "3. Array Disks (Muster)"
echo "   (Wo liegen die Daten dauerhaft?)"
read -e -i "$DEF_ARRAY" -p "   Array: " INPUT_ARRAY
echo ""

echo "4. Cache / Pool Disks"
echo "   (Wo liegen temporäre Daten? Trenne mehrere mit Leerzeichen)"
read -e -i "$DEF_CACHE" -p "   Cache: " INPUT_CACHE
echo ""

echo "5. Exclude-Datei"
read -e -i "$DEF_EXCLUDE" -p "   Exclude: " INPUT_EXCLUDE
echo ""

echo "6. Mindest-Freiplatz auf Ziel-Disk (GB)"
read -e -i "$DEF_MIN_FREE" -p "   Min Free: " INPUT_MIN_FREE
echo ""

echo "7. Dryrun Standardmodus"
read -e -i "$DEF_DRYRUN" -p "   Dryrun: " INPUT_DRYRUN

cat > "$INI_FILE" <<EOF
# Konfiguration V8
BASE_DIRS=($INPUT_DIRS)
LOGFILE="$INPUT_LOG"

# Pfade getrennt definiert
ARRAY_PATTERN="$INPUT_ARRAY"
CACHE_PATTERN="$INPUT_CACHE"

EXCLUDE_FILE="$INPUT_EXCLUDE"
DRYRUN=$INPUT_DRYRUN
MIN_FREE_GB=$INPUT_MIN_FREE
EOF

echo "✅ Konfiguration gespeichert."

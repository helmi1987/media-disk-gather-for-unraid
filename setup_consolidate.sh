#!/bin/bash
# =============================================================================
#  setup_consolidate.sh  —  Assistent für consolidate.ini  (V11.0)
#  Schreibt die consolidate.ini IMMER neben dieses Script (dort liest sie
#  consolidate_master.sh), unabhängig davon, aus welchem Ordner du startest.
# =============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INI_FILE="$SCRIPT_DIR/consolidate.ini"

# Defaults
DEF_DIRS="/mnt/user/Filme;/mnt/user/Serien"
DEF_LOG="/mnt/user/PlexMedia/consolidate.log"
DEF_ARRAY="/mnt/disk[0-9]*"          # nur Array-Disks (nicht /mnt/disks von Unassigned Devices)
DEF_CACHE="/mnt/cache"               # Cache oder Pools, mehrere mit Leerzeichen
DEF_EXCLUDE=""
DEF_DRYRUN="true"
DEF_MIN_FREE="256"
DEF_CACHE_ONLY="most-free"
DEF_DUP_CHECK="size"

# Bestehende Werte übernehmen
if [[ -f "$INI_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$INI_FILE"
    if [[ -n "${BASE_DIRS[*]-}" ]]; then DEF_DIRS="$(IFS=';'; echo "${BASE_DIRS[*]}")"; fi
    [[ -n "${LOGFILE-}" ]]           && DEF_LOG="$LOGFILE"
    [[ -n "${ARRAY_PATTERN-}" ]]     && DEF_ARRAY="$ARRAY_PATTERN"
    [[ -n "${CACHE_PATTERN-}" ]]     && DEF_CACHE="$CACHE_PATTERN"
    [[ -n "${EXCLUDE_FILE-}" ]]      && DEF_EXCLUDE="$EXCLUDE_FILE"
    [[ -n "${DRYRUN-}" ]]            && DEF_DRYRUN="$DRYRUN"
    [[ -n "${MIN_FREE_GB-}" ]]       && DEF_MIN_FREE="$MIN_FREE_GB"
    [[ -n "${CACHE_ONLY_TARGET-}" ]] && DEF_CACHE_ONLY="$CACHE_ONLY_TARGET"
    [[ -n "${DUP_CHECK-}" ]]         && DEF_DUP_CHECK="$DUP_CHECK"
    echo "ℹ️  Bestehende $INI_FILE wird als Vorgabe verwendet."
fi

# ask <Variable> <Vorgabe> <Prompt>  — wiederholt, bis die Prüffunktion ok sagt
ask() {
    local var="$1" def="$2" prompt="$3" check="${4:-}" val
    while true; do
        read -r -e -i "$def" -p "   $prompt: " val || { echo; echo "❌ Eingabe abgebrochen – nichts gespeichert."; exit 1; }
        if [[ -z "$check" ]] || "$check" "$val"; then
            printf -v "$var" '%s' "$val"; return 0
        fi
        def="$val"
    done
}

check_dirs() {   # mehrere Pfade mit ; getrennt, alle unter /mnt/user/
    local IFS=';' d ok=true
    [[ -n "$1" ]] || { echo "   ❌ Mindestens ein Pfad nötig."; return 1; }
    for d in $1; do
        d="${d%/}"
        if [[ "$d" != /mnt/user/?* ]]; then echo "   ❌ '$d' muss unter /mnt/user/ liegen."; ok=false
        elif [[ ! -d "$d" ]]; then echo "   ⚠️  '$d' existiert (noch) nicht."; fi
    done
    $ok
}
check_nonempty() { [[ -n "$1" ]] || { echo "   ❌ Darf nicht leer sein."; return 1; }; }
check_log() { [[ "$1" == /* ]] || { echo "   ❌ Absoluter Pfad nötig."; return 1; }; }
check_exclude() { [[ -z "$1" || -f "$1" ]] || echo "   ⚠️  '$1' existiert (noch) nicht – wird beim Lauf übersprungen."; return 0; }
check_int() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "   ❌ Ganze Zahl (GB) nötig, z.B. 256."; return 1; }; }
check_bool() {
    case "${1,,}" in
        true|false) return 0 ;;
        j|ja|y|yes|1)  echo "   ❌ Bitte genau 'true' oder 'false' eingeben."; return 1 ;;
        *)             echo "   ❌ Nur 'true' oder 'false' erlaubt."; return 1 ;;
    esac
}
check_cache_only() { case "$1" in most-free|skip) return 0;; *) echo "   ❌ 'most-free' oder 'skip'."; return 1;; esac; }
check_dup() { case "$1" in size|cmp) return 0;; *) echo "   ❌ 'size' oder 'cmp'."; return 1;; esac; }

echo "=========================================="
echo " 🛠  SETUP V11: consolidate.ini"
echo "=========================================="
echo "1. Quellverzeichnisse (User-Shares unter /mnt/user, mehrere mit ; trennen)"
ask INPUT_DIRS "$DEF_DIRS" "Pfade" check_dirs; echo ""
echo "2. Logdatei (Ordner wird beim scharfen Lauf angelegt)"
ask INPUT_LOG "$DEF_LOG" "Logfile" check_log; echo ""
echo "3. Array-Disks (Muster) – wo liegen die Daten dauerhaft?"
ask INPUT_ARRAY "$DEF_ARRAY" "Array" check_nonempty; echo ""
echo "4. Cache / Pool Disks (mehrere mit Leerzeichen trennen)"
ask INPUT_CACHE "$DEF_CACHE" "Cache" check_nonempty; echo ""
echo "5. Exclude-Datei (leer = keine; eine Datei oder ein Ordner pro Zeile)"
ask INPUT_EXCLUDE "$DEF_EXCLUDE" "Exclude" check_exclude; echo ""
echo "6. Mindest-Freiplatz auf Ziel-Disk (GB)"
ask INPUT_MIN_FREE "$DEF_MIN_FREE" "Min Free" check_int; echo ""
echo "7. Dryrun-Standardmodus (true = ohne --run wird nichts verändert)"
ask INPUT_DRYRUN "$DEF_DRYRUN" "Dryrun" check_bool; echo ""
echo "8. Ordner, die nur auf dem Cache liegen (nur mit --include-cache): most-free | skip"
ask INPUT_CACHE_ONLY "$DEF_CACHE_ONLY" "Cache-only" check_cache_only; echo ""
echo "9. Duplikat-Prüfung vor dem Löschen: size (Grösse) | cmp (Byte-Vergleich, langsam)"
ask INPUT_DUP "$DEF_DUP_CHECK" "Dup-Check" check_dup

# Array-Einträge sicher quoten (Leerzeichen, Klammern, Sonderzeichen)
q() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
dirs_quoted=""
IFS=';' read -r -a _dirs <<< "$INPUT_DIRS"
for d in "${_dirs[@]}"; do
    d="${d%/}"; [[ -z "$d" ]] && continue
    dirs_quoted+="$(q "$d") "
done

cat > "$INI_FILE" <<EOF
# consolidate.ini – erzeugt von setup_consolidate.sh (V11)
BASE_DIRS=(${dirs_quoted% })
LOGFILE=$(q "$INPUT_LOG")

# Disks
ARRAY_PATTERN=$(q "$INPUT_ARRAY")
CACHE_PATTERN=$(q "$INPUT_CACHE")

EXCLUDE_FILE=$(q "$INPUT_EXCLUDE")
DRYRUN=${INPUT_DRYRUN,,}
MIN_FREE_GB=$INPUT_MIN_FREE

# most-free | skip   (Cache-only-Ordner bei --include-cache)
CACHE_ONLY_TARGET=$(q "$INPUT_CACHE_ONLY")
# size | cmp         (wann ist eine zweite Kopie ein löschbares Duplikat)
DUP_CHECK=$(q "$INPUT_DUP")
EOF

echo ""
echo "✅ Konfiguration gespeichert: $INI_FILE"
echo "   Test:  $SCRIPT_DIR/consolidate_master.sh          (Dryrun)"
echo "   Scharf: $SCRIPT_DIR/consolidate_master.sh --run"

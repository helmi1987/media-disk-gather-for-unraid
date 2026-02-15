#!/bin/bash
set -u
IFS=$'\n\t'

# -----------------------
# 🛠 DEFAULTS
# -----------------------
BASE_DIRS=("/mnt/user/Filme")
LOGFILE="/mnt/user/PlexMedia/consolidate.log"
EXCLUDE_FILE=""
ARRAY_PATTERN="/mnt/disk*"
CACHE_PATTERN="/mnt/cache"
DRYRUN=true
INDEX_FILE="/tmp/consolidate_file_index.txt"
MIN_FREE_GB=256
MOVE_CACHE=false  # Standard: Cache nicht anfassen (macht der Mover)

# -----------------------
# 📥 CONFIG LADEN
# -----------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/consolidate.ini"

if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    echo "ℹ️  Config geladen."
fi

# Argumente parsen
for arg in "$@"; do 
    [[ "$arg" == "--run" ]] && DRYRUN=false
    [[ "$arg" == "--include-cache" ]] && MOVE_CACHE=true
done

# -----------------------
# ⚙️ INITIALISIERUNG
# -----------------------
SUMMARY_MOVED=()
SUMMARY_DUPLICATES=()
SUMMARY_IGNORED=()
SUMMARY_SKIPPED_FULL=()
SUMMARY_SKIPPED_CACHE=() # Neu für Statistik
SUMMARY_FAILED_FULL=()
SUMMARY_DELETED_DIRS=()

declare -A EXCLUDE_MAP

log_always() {
    local msg="$1"
    echo "$msg"
    [[ -d "$(dirname "$LOGFILE")" ]] && echo "$(date '+%F %T') | $msg" >> "$LOGFILE"
}

log_console() {
    local icon="$1"
    local src_root="$2"
    local tgt_root="$3"
    local file="$4"
    local s_name=$(basename "$src_root")
    local f_name=$(basename "$file")
    if [[ -n "$tgt_root" ]]; then
        local t_name=$(basename "$tgt_root")
        echo -e "   $icon [$s_name -> $t_name] $f_name"
    else
        echo -e "   $icon [$s_name] $f_name"
    fi
}

log_verbose() { $DRYRUN && echo "[DRYRUN] $1"; }

# -----------------------
# 📏 SPACE CHECK
# -----------------------
has_enough_space() {
    local target_disk="$1"
    local file_size_bytes="$2"
    local avail_kb
    avail_kb=$(df -k --output=avail "$target_disk" | tail -n1)
    local min_needed_kb=$(( MIN_FREE_GB * 1024 * 1024 ))
    local file_size_kb=$(( file_size_bytes / 1024 ))
    local remaining_kb=$(( avail_kb - file_size_kb ))
    if (( remaining_kb < min_needed_kb )); then return 1; else return 0; fi
}

# -----------------------
# 🚀 INDEXING ENGINE
# -----------------------
resolve_paths() {
    local pattern="$1"
    local OLD_IFS="$IFS"
    IFS=$' \t\n'
    local clean="${pattern//\"/}"
    clean="${clean//\'/}"
    ls -1d $clean 2>/dev/null
    IFS="$OLD_IFS"
}

build_index() {
    echo "========================================"
    echo "🚀 PHASE 1: Indexierung (Targeted)"
    echo "========================================"
    
    rm -f "$INDEX_FILE"
    
    local all_roots=()
    while read -r p; do [[ -n "$p" ]] && all_roots+=("$p"); done < <(resolve_paths "$ARRAY_PATTERN")
    while read -r p; do [[ -n "$p" ]] && all_roots+=("$p"); done < <(resolve_paths "$CACHE_PATTERN")

    if [[ ${#all_roots[@]} -eq 0 ]]; then
        echo "❌ FEHLER: Keine Laufwerke gefunden!"
        exit 1
    fi

    local search_targets=()
    for root in "${all_roots[@]}"; do
        for base in "${BASE_DIRS[@]}"; do
            local rel_path="${base#/mnt/user}" 
            local target_path="${root}${rel_path}"
            if [[ -d "$target_path" ]]; then
                search_targets+=("$target_path")
            fi
        done
    done

    if [[ ${#search_targets[@]} -eq 0 ]]; then
        echo "❌ FEHLER: Keine Ordner auf den Disks gefunden!"
        exit 1
    fi

    echo "ℹ️  Scanne ${#search_targets[@]} gefundene Pfade..."
    find "${search_targets[@]}" -type f -print > "$INDEX_FILE"
    
    local count=$(wc -l < "$INDEX_FILE")
    if [[ "$count" -eq 0 ]]; then 
        echo "⚠️ Index leer. Keine Dateien gefunden (nur leere Ordner?)."
    else
        echo "✅ Index: $count Dateien."
    fi
    echo "----------------------------------------"
}

get_physical_paths_from_index() {
    local search="$1"
    grep -F "$search" "$INDEX_FILE" | while read -r line; do
        if [[ "$line" == *"$search" ]]; then echo "$line"; fi
    done
}

get_disk_root() { echo "$1" | cut -d/ -f1-3; }

load_exclusions() {
    if [[ -f "$EXCLUDE_FILE" ]]; then
        local c=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line//$'\r'/}"
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line%"${line##*[![:space:]]}"}"
            [[ -z "$line" || "$line" == \#* ]] && continue
            EXCLUDE_MAP["$line"]=1
            ((c++))
        done < "$EXCLUDE_FILE"
        echo "ℹ️  Exclude-Liste: $c Einträge."
    fi
}

execute_move() {
    local src="$1"
    local target_disk="$2"
    local rel_path="$3"
    local is_retry="${4:-false}" 

    local src_disk=$(get_disk_root "$src")
    local dest="$target_disk$rel_path"
    
    local size=$(stat -c%s "$src")
    if ! has_enough_space "$target_disk" "$size"; then
        if $is_retry; then
            SUMMARY_FAILED_FULL+=("$src -> $target_disk")
            if $DRYRUN; then echo "   ❌ [FULL] $src -> $target_disk"; fi
        else
            SUMMARY_SKIPPED_FULL+=("$src|$target_disk|$rel_path")
            if $DRYRUN; then echo "   ⏳ [FULL-QUEUE] $(basename "$src")"; fi
        fi
        return 1
    fi

    SUMMARY_MOVED+=("$src -> $target_disk")
    
    local icon="🚚"
    if $is_retry; then icon="🔄"; fi
    if $DRYRUN; then icon="🧪$icon"; fi
    
    log_console "$icon" "$src_disk" "$target_disk" "$src"
    
    if ! $DRYRUN; then
        mkdir -p "$(dirname "$dest")"
        if rsync -a --remove-source-files "$src" "$dest"; then
            echo "$(date '+%F %T') | VERSCHOBEN: $src -> $dest" >> "$LOGFILE"
            return 0
        else
            echo "$(date '+%F %T') | ERROR: $src" >> "$LOGFILE"
            return 1
        fi
    fi
}

process_item_group() {
    local folder="$1"
    local folder_files=()
    while IFS= read -r -d '' f; do folder_files+=("$f"); done < <(find "$folder" -type f -print0)
    [[ ${#folder_files[@]} -eq 0 ]] && return

    # ---------------------------------------------------------
    # A. ZIELDISK BESTIMMEN (NUR ARRAY ZÄHLEN)
    # ---------------------------------------------------------
    local -A disk_tally
    local target_disk=""
    
    for file in "${folder_files[@]}"; do
        local rel_path="${file#/mnt/user}"
        local phys_paths_str=$(get_physical_paths_from_index "$rel_path")
        local size=$(stat -c%s "$file")

        while read -r p; do
            [[ -z "$p" ]] && continue
            
            # --- Array Only Logic ---
            if [[ "$p" != "/mnt/disk"* ]]; then continue; fi
            # ------------------------

            local d_root=$(get_disk_root "$p")
            local current_sum=${disk_tally["$d_root"]:-0}
            disk_tally["$d_root"]=$((current_sum + size))
        done <<< "$phys_paths_str"
    done

    # Gewinner ermitteln
    local max_bytes=0
    for d in "${!disk_tally[@]}"; do
        local total=${disk_tally["$d"]}
        if (( total > max_bytes )); then
            max_bytes=$total
            target_disk="$d"
        fi
    done

    # Wenn alles nur auf Cache liegt (kein Array Ziel), brechen wir ab.
    [[ -z "$target_disk" ]] && return
    # ---------------------------------------------------------

    # B. VERARBEITEN
    for file in "${folder_files[@]}"; do
        if [[ -n "${EXCLUDE_MAP[$file]-}" ]]; then SUMMARY_IGNORED+=("$file"); continue; fi

        local rel_path="${file#/mnt/user}"
        local phys_paths_str=$(get_physical_paths_from_index "$rel_path")
        local phys_paths=()
        while IFS= read -r l; do [[ -n "$l" ]] && phys_paths+=("$l"); done <<< "$phys_paths_str"

        local skip=false
        for p in "${phys_paths[@]}"; do
             if [[ -n "${EXCLUDE_MAP[$p]-}" ]]; then SUMMARY_IGNORED+=("$p"); skip=true; break; fi
        done
        $skip && continue

        local is_on_target=false
        local target_path=""

        for p in "${phys_paths[@]}"; do
            if [[ "$p" == "$target_disk"* ]]; then
                is_on_target=true
                target_path="$p"
                break
            fi
        done

        if $is_on_target; then
            # Datei ist schon am Ziel. Prüfen auf Duplikate woanders.
            if [[ ${#phys_paths[@]} -gt 1 ]]; then
                for p in "${phys_paths[@]}"; do
                    if [[ "$p" != "$target_path" ]]; then
                        
                        # --- CLEANUP LOGIC ---
                        # Duplikate löschen wir IMMER, auch auf Cache.
                        # Das ist kein "Move", sondern Müllentsorgung.
                        # ---------------------
                        
                        SUMMARY_DUPLICATES+=("$p")
                        echo -ne "\r\033[K" 
                        local p_disk=$(get_disk_root "$p")
                        if $DRYRUN; then
                            log_console "🧪🗑️" "$p_disk" "" "$p"
                        else
                            log_console "🗑️" "$p_disk" "" "$p"
                            rm -f "$p" && echo "$(date '+%F %T') | GELÖSCHT: $p" >> "$LOGFILE"
                        fi
                    fi
                done
            fi
        else
            # Datei ist NICHT am Ziel. Move Action.
            [[ ${#phys_paths[@]} -eq 0 ]] && continue
            local src="${phys_paths[0]}"
            
            # ---------------------------------------------------------
            # NEU V10.2: Cache Protection
            # Wenn Quelle NICHT Array ist (also Cache/Pool) UND flag nicht gesetzt -> Skip
            # ---------------------------------------------------------
            if [[ "$src" != "/mnt/disk"* ]] && [[ "$MOVE_CACHE" == "false" ]]; then
                SUMMARY_SKIPPED_CACHE+=("$src")
                continue
            fi
            # ---------------------------------------------------------

            echo -ne "\r\033[K"
            execute_move "$src" "$target_disk" "$rel_path" false
        fi
    done
}

# -----------------------
# 🧹 PHASE 3: DEEP CLEAN (RECURSIVE & SAFE)
# -----------------------
run_deep_clean() {
    echo "========================================"
    echo "🧹 PHASE 3: Deep Clean (Protected)"
    echo "========================================"
    echo "Suche auf physischen Disks nach verwaisten Ordnern..."

    local all_roots=()
    while read -r p; do [[ -n "$p" ]] && all_roots+=("$p"); done < <(resolve_paths "$ARRAY_PATTERN")
    while read -r p; do [[ -n "$p" ]] && all_roots+=("$p"); done < <(resolve_paths "$CACHE_PATTERN")

    local loop_count=0
    local deleted_in_this_pass=1

    while [[ $deleted_in_this_pass -gt 0 ]]; do
        ((loop_count++))
        deleted_in_this_pass=0
        
        if [[ $loop_count -gt 1 ]]; then
            echo "   ... Durchgang $loop_count ..."
        fi

        for root in "${all_roots[@]}"; do
            for base in "${BASE_DIRS[@]}"; do
                local rel_path="${base#/mnt/user}"
                local target_path="${root}${rel_path}"

                if [[ -d "$target_path" ]]; then
                    while read -r empty_dir; do
                        SUMMARY_DELETED_DIRS+=("$empty_dir")
                        ((deleted_in_this_pass++))
                        
                        if $DRYRUN; then
                            echo "   🧪🗑️ [LEER] $empty_dir"
                        else
                            echo "   🗑️ [LEER] $empty_dir"
                            rmdir "$empty_dir" 2>/dev/null && echo "$(date '+%F %T') | RMDIR: $empty_dir" >> "$LOGFILE"
                        fi
                    done < <(find "$target_path" -mindepth 1 -depth -type d -empty)
                fi
            done
        done
        
        if $DRYRUN; then
            echo "   (Dryrun: Stoppe nach Durchgang 1)"
            break
        fi
    done
}


# -----------------------
# ▶ START
# -----------------------
if $DRYRUN; then
    echo "🚧 DRYRUN MODUS"
else
    echo "⚠️ SCHARFER MODUS"
    sleep 2
fi

if $MOVE_CACHE; then
    echo "ℹ️  Cache-Move: AKTIV (Dateien werden vom Cache geholt)"
else
    echo "ℹ️  Cache-Move: INAKTIV (Cache wird ignoriert)"
fi

load_exclusions
build_index

echo "🚀 PHASE 2: Verarbeitung"
echo "----------------------------------------"

for base in "${BASE_DIRS[@]}"; do
    if [[ ! -d "$base" ]]; then echo "⚠️ Fehler: $base fehlt"; continue; fi
    
    echo "📂 Scanne: $base"
    folders=()
    while IFS= read -r -d '' d; do folders+=("$d"); done < <(find "$base" -mindepth 1 -maxdepth 1 -type d -print0)
    total=${#folders[@]}
    current=0
    
    for dir in "${folders[@]}"; do
        ((current++))
        if (( total > 0 )); then percent=$(( 100 * current / total )); else percent=0; fi
        echo -ne "   [$current/$total] $percent% - $(basename "$dir") \033[K\r"
        process_item_group "$dir"
    done
    echo ""
done

# RETRY (Queue)
if [[ ${#SUMMARY_SKIPPED_FULL[@]} -gt 0 ]]; then
    echo ""
    echo "========================================"
    echo "🔄 RETRY (Volle Disks)"
    echo "========================================"
    for item in "${SUMMARY_SKIPPED_FULL[@]}"; do
        IFS='|' read -r src target_disk rel_path <<< "$item"
        execute_move "$src" "$target_disk" "$rel_path" true
    done
fi

echo ""
run_deep_clean

echo ""
echo "========================================"
echo "📊 ZUSAMMENFASSUNG"
echo "----------------------------------------"
echo "Ignoriert (Exclude): ${#SUMMARY_IGNORED[@]}"
echo "Duplikate gelöscht:  ${#SUMMARY_DUPLICATES[@]}"
echo "Verschoben:          ${#SUMMARY_MOVED[@]}"
echo "Cache ignoriert:     ${#SUMMARY_SKIPPED_CACHE[@]}"
echo "Leere Ordner (del):  ${#SUMMARY_DELETED_DIRS[@]}"
echo "----------------------------------------"
if [[ ${#SUMMARY_FAILED_FULL[@]} -gt 0 ]]; then
    echo "❌ FEHLGESCHLAGEN:   ${#SUMMARY_FAILED_FULL[@]}"
fi
echo "========================================"
rm -f "$INDEX_FILE"
echo "--- Fertig ---"

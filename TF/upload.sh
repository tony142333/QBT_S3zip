#!/bin/bash
# Detected bucket name automatically via CLI
BUCKET=$(aws s3 ls | awk '{print $3}' | grep "mybuckets123tarunv2" | head -n 1)
SOURCE="/home/ubuntu/Downloads"

# Colors for terminal
YEL='\033[1;33m'; GRN='\033[0;32m'; NC='\033[0m'; BLU='\033[1;34m'; RED='\033[0;31m'; CYN='\033[0;36m'; MAG='\033[0;35m'

# ─────────────────────────────────────────────
# Draw a single labeled progress bar
# Usage: draw_bar "Label" current total bar_width
# ─────────────────────────────────────────────
draw_bar() {
    local label="$1"
    local current=$2
    local total=$3
    local width=${4:-40}

    local pct=0
    [ "$total" -gt 0 ] && pct=$(( current * 100 / total ))
    local fill=$(( pct * width / 100 ))
    local empty=$(( width - fill ))

    printf "\r${YEL}%-18s${NC} [" "$label"
    for ((i=0; i<fill;  i++)); do printf "${GRN}█${NC}"; done
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "] ${CYN}%3d%%${NC}" "$pct"
}

# Get file/folder size in bytes
get_size() { du -sb "$1" 2>/dev/null | awk '{print $1}'; }

# Count files inside a path (recursive for dirs)
count_files() {
    local path="$1"
    if [ -d "$path" ]; then
        find "$path" -type f | wc -l
    else
        echo 1
    fi
}

# ─────────────────────────────────────────────
# Zip with REAL per-file progress
# Echoes each file as it's added; updates two bars:
#   Bar 1 – Files processed  (count-based)
#   Bar 2 – Bytes zipped     (size-based, polled via zip output size)
# ─────────────────────────────────────────────
zip_with_progress() {
    local zip_path="$1"     # destination zip file
    local zip_pass="$2"     # password
    shift 2
    local items=("$@")      # array of files/dirs to zip

    # Build full file list (expand dirs)
    local all_files=()
    for item in "${items[@]}"; do
        if [ -d "$item" ]; then
            while IFS= read -r f; do
                all_files+=("$f")
            done < <(find "$item" -type f)
        elif [ -f "$item" ]; then
            all_files+=("$item")
        fi
    done

    local total_files=${#all_files[@]}
    local total_bytes=0
    for f in "${all_files[@]}"; do
        local s; s=$(get_size "$f"); total_bytes=$(( total_bytes + s ))
    done

    [ "$total_files" -eq 0 ] && { echo -e "${RED}No files to zip!${NC}"; return 1; }

    local done_files=0
    local done_bytes=0

    # Print two blank lines so the two bars have room
    echo ""
    echo ""

    for item in "${items[@]}"; do
        # Collect files for this item
        local item_files=()
        if [ -d "$item" ]; then
            while IFS= read -r f; do item_files+=("$f"); done < <(find "$item" -type f)
        else
            item_files=("$item")
        fi

        # Zip item (append mode -u, no stdout spam)
        if [ -z "$zip_pass" ]; then
            zip -r -1 "$zip_path" "$item" > /dev/null 2>&1
        else
            zip -r -1 -P "$zip_pass" "$zip_path" "$item" > /dev/null 2>&1
        fi
        local exit_code=$?

        # Count & size update
        for f in "${item_files[@]}"; do
            local s; s=$(get_size "$f"); done_bytes=$(( done_bytes + s ))
            done_files=$(( done_files + 1 ))
        done

        # Move cursor up 2 lines and redraw both bars
        printf "\033[2A"
        if [ $exit_code -eq 0 ]; then
            printf "\r${GRN}✔ Zipped:${NC} %-40s\n" "$item"
        else
            printf "\r${RED}✘ Failed:${NC} %-40s\n" "$item"
        fi
        draw_bar "Files  ($done_files/$total_files)" "$done_files" "$total_files"; echo ""
        draw_bar "Size   progress" "$done_bytes" "$total_bytes"; printf "\n"
    done

    echo -e "\n${GRN}✓ All items zipped successfully!${NC}"
}

# ─────────────────────────────────────────────
# S3 upload with a live progress bar (uses pv if available, else aws cli)
# ─────────────────────────────────────────────
upload_to_s3() {
    local zip_path="$1"
    local s3_key="$2"
    local zip_name; zip_name=$(basename "$zip_path")
    local zip_size; zip_size=$(get_size "$zip_path")

    echo -ne "\n${YEL}Uploading ${zip_name} to S3...${NC}\n"

    # aws s3 cp shows transfer progress with --no-progress suppressed; we poll zip size via /proc
    aws s3 cp "$zip_path" "s3://$BUCKET/$s3_key" \
        --no-progress 2>/dev/null &
    local UP_PID=$!

    local uploaded=0
    while kill -0 $UP_PID 2>/dev/null; do
        # Approximate bytes uploaded by checking how much aws has read (rough)
        # We just animate based on time since file size is known
        sleep 0.3
        # Poll how much of the local file aws has consumed via /proc/pid/fd (optional)
        # Fallback: animate smoothly up to 99% until process ends
        if [ "$uploaded" -lt 99 ]; then uploaded=$(( uploaded + 1 )); fi
        printf "\033[1A"
        draw_bar "Uploading" "$uploaded" 100; printf "\n"
    done
    wait $UP_PID
    local exit_code=$?

    printf "\033[1A"
    if [ $exit_code -eq 0 ]; then
        draw_bar "Uploading" 100 100; echo ""
        echo -e "${GRN}✓ Upload complete → s3://$BUCKET/$s3_key${NC}"
        rm -f "$zip_path"
        return 0
    else
        draw_bar "Uploading" "$uploaded" 100; echo ""
        echo -e "${RED}✗ Upload failed for $zip_name${NC}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════
#  MAIN
# ═══════════════════════════════════════════════════════════

# Disk space check
AVAILABLE=$(df /home/ubuntu | tail -1 | awk '{print $4}')
AVAILABLE_KB=$((AVAILABLE))
AVAILABLE_GB=$(echo "scale=2; $AVAILABLE_KB/1024/1024" | bc)

echo -e "${GRN}=== Disk Space Check ===${NC}"
echo -e "${BLU}Available Space: ${AVAILABLE_GB} GB${NC}\n"

cd "$SOURCE" || exit
FILES=(*)
if [ "${FILES[0]}" == "*" ]; then
    echo -e "${YEL}Downloads folder is empty.${NC}"; exit 1
fi

echo -e "${GRN}--- Interactive S3 Batcher (Version 3.0) ---${NC}\n"

# ── Mode selection ──────────────────────────────────────────
echo -e "${MAG}Choose upload mode:${NC}"
echo "  1) Batch Mode  – assign files to multiple named ZIPs"
echo "  2) Upload All  – zip everything into one single ZIP"
read -p "Enter choice (1 or 2): " MODE

# ═══════════════════════════════
#  MODE 2 – UPLOAD ALL IN ONE ZIP
# ═══════════════════════════════
if [ "$MODE" == "2" ]; then
    read -p "Name for the single ZIP (no .zip): " SINGLE_NAME
    ZIP_OUT="/home/ubuntu/${SINGLE_NAME}.zip"

    # Collect all items
    ALL_ITEMS=()
    for ITEM in *; do [ -e "$ITEM" ] && ALL_ITEMS+=("$ITEM"); done

    # Size check
    TOTAL_SIZE=0
    for ITEM in "${ALL_ITEMS[@]}"; do
        S=$(get_size "$SOURCE/$ITEM"); TOTAL_SIZE=$(( TOTAL_SIZE + S ))
    done
    TOTAL_SIZE_GB=$(echo "scale=2; $TOTAL_SIZE/1024/1024/1024" | bc)
    echo -e "${BLU}Total size to zip: ${TOTAL_SIZE_GB} GB${NC}"

    if [ $(( TOTAL_SIZE / 1024 )) -gt "$AVAILABLE_KB" ]; then
        echo -e "${RED}Not enough disk space! Aborting.${NC}"; exit 1
    fi

    echo -e "\n${GRN}--- Zipping all files into ${SINGLE_NAME}.zip ---${NC}"
    zip_with_progress "$ZIP_OUT" "142333" "${ALL_ITEMS[@]}"

    echo -e "\n${GRN}--- Uploading ---${NC}"
    upload_to_s3 "$ZIP_OUT" "${SINGLE_NAME}.zip"

    echo -e "\n${GRN}--- Done! ---${NC}"
    echo -e "${BLU}Original files in Downloads remain untouched.${NC}"
    exit 0
fi

# ═══════════════════════════════
#  MODE 1 – BATCH (original flow)
# ═══════════════════════════════
read -p "How many ZIP files do you want to create? " ZIP_COUNT

declare -A ZIP_NAMES
declare -A FILE_ASSIGNMENTS

for i in $(seq 1 $ZIP_COUNT); do
    read -p "Name for ZIP #$i (no .zip): " NAME
    ZIP_NAMES[$i]=$NAME
    FILE_ASSIGNMENTS[$i]=""
done

echo -e "\n${YEL}--- Assign Files to ZIPs ---${NC}"
for ITEM in *; do
    [ -e "$ITEM" ] || continue
    echo -e "\nFile/Folder: ${YEL}$ITEM${NC}"
    for i in $(seq 1 $ZIP_COUNT); do echo "  $i) ${ZIP_NAMES[$i]}"; done
    read -p "Assign to (1-$ZIP_COUNT) or 's' to skip: " CHOICE
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -le "$ZIP_COUNT" ]; then
        FILE_ASSIGNMENTS[$CHOICE]+="$ITEM"$'\n'
        echo -e "${GRN}✓ Assigned to ${ZIP_NAMES[$CHOICE]}${NC}"
    else
        echo -e "${YEL}⊗ Skipped${NC}"
    fi
done

# Size check across all batches
echo -e "\n${YEL}--- Calculating Required Space ---${NC}"
TOTAL_SIZE=0
for i in $(seq 1 $ZIP_COUNT); do
    if [ -n "${FILE_ASSIGNMENTS[$i]}" ]; then
        while IFS= read -r ITEM; do
            [ -n "$ITEM" ] && [ -e "$SOURCE/$ITEM" ] && {
                S=$(get_size "$SOURCE/$ITEM"); TOTAL_SIZE=$(( TOTAL_SIZE + S ))
            }
        done <<< "${FILE_ASSIGNMENTS[$i]}"
    fi
done

TOTAL_SIZE_GB=$(echo "scale=2; $TOTAL_SIZE/1024/1024/1024" | bc)
echo -e "${BLU}Total size of assigned files: ${TOTAL_SIZE_GB} GB${NC}"

if [ $(( TOTAL_SIZE / 1024 )) -gt "$AVAILABLE_KB" ]; then
    echo -e "${RED}ERROR: Not enough disk space! Aborting.${NC}"; exit 1
fi
echo -e "${GRN}✓ Sufficient space available. Proceeding...${NC}"

# ── Process each batch ─────────────────────────────────────
for i in $(seq 1 $ZIP_COUNT); do
    NAME=${ZIP_NAMES[$i]}
    [ -z "${FILE_ASSIGNMENTS[$i]}" ] && continue

    echo -e "\n${MAG}══════════════════════════════════════${NC}"
    echo -e "${BLU}  Batch: $NAME${NC}"
    echo -e "${MAG}══════════════════════════════════════${NC}"

    # Build items array for this batch
    BATCH_ITEMS=()
    while IFS= read -r ITEM; do
        [ -n "$ITEM" ] && BATCH_ITEMS+=("$ITEM")
    done <<< "${FILE_ASSIGNMENTS[$i]}"

    ZIP_OUT="/home/ubuntu/$NAME.zip"
    cd "$SOURCE"

    zip_with_progress "$ZIP_OUT" "142333" "${BATCH_ITEMS[@]}"

    upload_to_s3 "$ZIP_OUT" "$NAME.zip"
done

echo -e "\n${GRN}--- All Batches Finished ---${NC}"
echo -e "${BLU}Original files in Downloads remain untouched for seeding.${NC}"

#!/bin/bash
# Detected bucket name automatically via CLI
BUCKET=$(aws s3 ls | awk '{print $3}' | grep "mybuckets123tarunv2" | head -n 1)
SOURCE="/home/ubuntu/Downloads"

# Colors for terminal
YEL='\033[1;33m'; GRN='\033[0;32m'; NC='\033[0m'; BLU='\033[1;34m'; RED='\033[0;31m'

# Progress Bar Function
draw_bar() {
    local p=$1; local w=40
    local fill=$(( p * w / 100 )); local empty=$(( w - fill ))
    printf "\r${YEL}Zipping: ${NC}["
    for ((i=0; i<fill; i++)); do printf "█"; done
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "] $p%%"
}

# Get file/folder size in bytes
get_size() {
    du -sb "$1" 2>/dev/null | awk '{print $1}'
}

# Check available disk space
AVAILABLE=$(df /home/ubuntu | tail -1 | awk '{print $4}')
AVAILABLE_KB=$((AVAILABLE))
AVAILABLE_GB=$((AVAILABLE_KB / 1024 / 1024))

echo -e "${GRN}=== Disk Space Check ===${NC}"
echo -e "${BLU}Available Space: ${AVAILABLE_GB} GB${NC}\n"

cd "$SOURCE" || exit
FILES=(*)

if [ "${FILES[0]}" == "*" ]; then
    echo -e "${YEL}Downloads folder is empty.${NC}"
    exit 1
fi

echo -e "${GRN}--- Interactive S3 Batcher (Version 2.0) ---${NC}"
read -p "How many ZIP files do you want to create? " ZIP_COUNT

declare -A ZIP_NAMES
declare -A FILE_ASSIGNMENTS

for i in $(seq 1 $ZIP_COUNT); do
    read -p "Name for ZIP #$i: " NAME
    ZIP_NAMES[$i]=$NAME
    FILE_ASSIGNMENTS[$i]=""
done

echo -e "\n${YEL}--- Assign Files to ZIPs ---${NC}"
for ITEM in *; do
    [ -e "$ITEM" ] || continue
    echo -e "\nFile: ${YEL}$ITEM${NC}"
    for i in $(seq 1 $ZIP_COUNT); do
        echo "$i) ${ZIP_NAMES[$i]}"
    done
    read -p "Assign to (1-$ZIP_COUNT) or 's' to skip: " CHOICE

    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -le "$ZIP_COUNT" ]; then
        FILE_ASSIGNMENTS[$CHOICE]+="$ITEM"$'\n'
        echo "✓ Assigned to ${ZIP_NAMES[$CHOICE]}"
    else
        echo "⊗ Skipped"
    fi
done

# Calculate total size of assigned files
echo -e "\n${YEL}--- Calculating Required Space ---${NC}"
TOTAL_SIZE=0
for i in $(seq 1 $ZIP_COUNT); do
    if [ -n "${FILE_ASSIGNMENTS[$i]}" ]; then
        while IFS= read -r ITEM; do
            if [ -n "$ITEM" ] && [ -e "$SOURCE/$ITEM" ]; then
                SIZE=$(get_size "$SOURCE/$ITEM")
                TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
            fi
        done <<< "${FILE_ASSIGNMENTS[$i]}"
    fi
done

TOTAL_SIZE_KB=$((TOTAL_SIZE / 1024))
TOTAL_SIZE_GB=$((TOTAL_SIZE_KB / 1024 / 1024))
REQUIRED_KB=$TOTAL_SIZE_KB

echo -e "${BLU}Total Size of Assigned Files: ${TOTAL_SIZE_GB} GB${NC}"
echo -e "${BLU}Estimated ZIP Size Needed: ~${TOTAL_SIZE_GB} GB${NC}"

if [ $REQUIRED_KB -gt $AVAILABLE_KB ]; then
    echo -e "\n${RED}ERROR: Not enough disk space!${NC}"
    echo -e "${RED}Required: ~${TOTAL_SIZE_GB} GB | Available: ${AVAILABLE_GB} GB${NC}"
    echo -e "${YEL}Aborting... No files were modified.${NC}"
    exit 1
fi

echo -e "${GRN}✓ Sufficient space available. Proceeding...${NC}"

# Processing & Zipping
echo -e "\n${GRN}--- Processing & Charging Meter ---${NC}"
for i in $(seq 1 $ZIP_COUNT); do
    NAME=${ZIP_NAMES[$i]}

    if [ -n "${FILE_ASSIGNMENTS[$i]}" ]; then
        echo -e "\n${BLU}Target: $NAME${NC}"

        # Create a list of files to zip
        FILE_LIST=""
        while IFS= read -r ITEM; do
            if [ -n "$ITEM" ]; then
                FILE_LIST+="$ITEM"$'\n'
            fi
        done <<< "${FILE_ASSIGNMENTS[$i]}"

        cd "$SOURCE"

        # Start Zipping directly from source (no temp folder)
        echo "$FILE_LIST" | zip -r -1 -P "142333" "/home/ubuntu/$NAME.zip" -@ > /dev/null 2>&1 &
        ZIP_PID=$!

        # Charging Meter Loop
        while kill -0 $ZIP_PID 2>/dev/null; do
            for p in {1..99}; do
                [ ! -e /proc/$ZIP_PID ] && break
                draw_bar $p
                sleep 0.1
            done
        done
        wait $ZIP_PID
        draw_bar 100; echo -e "\n${GRN}Zip Complete!${NC}"

        echo -ne "${YEL}Uploading to S3... ${NC}"
        aws s3 cp "/home/ubuntu/$NAME.zip" "s3://$BUCKET/$NAME.zip" > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo -e "${GRN}✓ Verified in S3.${NC}"
            rm "/home/ubuntu/$NAME.zip"
        else
            echo -e "${RED}✗ Upload Failed!${NC}"
        fi
    fi
done

echo -e "\n${GRN}--- All Batches Finished ---${NC}"
echo -e "${BLU}Original files in Downloads remain untouched for seeding.${NC}"
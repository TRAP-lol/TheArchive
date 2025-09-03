#!/usr/bin/env bash

# ================================================
# ARTIFACT PROCESSOR - Final Production Version
# ================================================

# --- Configuration ---
BASE_DIR="/mnt/gossd/trap/code-trap/TheArchive"
PROCESS_IMAGES=1
PROCESS_BLOGS=1
PROCESS_SUBDIRS=1
DRY_RUN=0
REDO_CHECKSUMS=0
OVERWRITE_EXISTING=0
HIDDEN_BY_DEFAULT=0
SMALL_DIM="300x300"
LARGE_MAX=2500
QUALITY=90
WEBP_EFFORT=6
SON_SUFFIX_LEN=6
ID_CHARS="A-Z0-9"
UPLOAD_ENABLED=1
UPLOAD_INSTANCE="https://share.trap.lol"
MAX_PARALLEL=4
GENERATE_LINKS=1
REGISTRY_MAIN="$BASE_DIR/glass/data/detention.json"
WHISPERS_DIR="$BASE_DIR/whispers"
YEAR=$(date +%Y)

# --- Derived Paths ---
SCRIPT_DIR="$BASE_DIR/scripts/artifact-processor"
STATE_DIR="$SCRIPT_DIR/state"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/process-$(date +%Y%m%d).log"
UPLOAD_DB="$STATE_DIR/uploads.json"
PROCESSED_LOG="$STATE_DIR/processed.log"
LINKS_FILE="$STATE_DIR/links.txt"
mkdir -p "$STATE_DIR" "$LOG_DIR" "$(dirname "$REGISTRY_MAIN")"

# --- Initialization ---
TIMESTAMP=$(date +%s)
export LOG_FILE

# --- Logging Functions ---
log() {
    local level=$1 msg=$2
    local color=""
    case "$level" in
        ERROR) color="\033[31m" ;;
        WARN) color="\033[33m" ;;
        INFO) color="\033[32m" ;;
        DEBUG) color="\033[36m" ;;
    esac
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] $level: $msg\033[0m" | tee -a "$LOG_FILE" >&2
}

die() {
    log "ERROR" "$1"
    exit 1
}

# --- Directory Type Detection ---
get_artifact_type() {
    local dir=$1
    local dir_name=$(basename "$dir")

    # Skip output directories
    [[ "$dir_name" =~ ^(small|original)$ ]] && echo "SKIP" && return

    case "$dir_name" in
        *SON*) echo "SON" ;;
        *ECH*) echo "ECH" ;;
        *CAN*) echo "CAN" ;;
        *TIM*) echo "TIM" ;;
        *RES*) echo "RES" ;;
        *WAV*) echo "WAV" ;;
        *SYN*) echo "SYN" ;;
        *NSE*) echo "NSE" ;;
        *LYR*) echo "LYR" ;;
        *FRE*) echo "FRE" ;;
        *OCT*) echo "OCT" ;;
        *VOID*) echo "VOID" ;;
        *) echo "UNKNOWN" ;;
    esac
}

# --- Image Processing ---
get_image_command() {
    command -v magick &>/dev/null && echo "magick" || echo "convert"
}

resize_image() {
    local cmd=$(get_image_command)
    local input=$1 output=$2 dimensions=$3

    # Skip if output already exists
    [[ -f "$output" && "$OVERWRITE_EXISTING" -eq 0 ]] && return 0

    # Optimized conversion settings for WebP
    $cmd "$input" -resize "$dimensions" -quality "$QUALITY" \
        -define webp:method=$WEBP_EFFORT -define webp:lossless=false \
        -strip "$output" 2>/dev/null || {
        log "WARN" "Conversion failed: $input → $output"
        return 1
    }
    return 0
}

# --- Registry Management ---
initialize_registry() {
    [[ -f "$REGISTRY_MAIN" ]] && return

    # Create new registry with proper structure
    jq -n '{
        "meta": {
            "project": "trap.lol",
            "description": "stop consuming, start producing",
            "last_updated": '$TIMESTAMP',
            "version": "0.0.3",
            "schema": "2.0"
        },
        "id_meta": {},
        "registry": {
            "SON": {},
            "ECH": {},
            "CAN": {},
            "TIM": {},
            "RES": {},
            "WAV": {},
            "SYN": {},
            "NSE": {},
            "LYR": {},
            "FRE": {},
            "OCT": {},
            "VOID": {}
        },
        "relations": {}
    }' > "$REGISTRY_MAIN"

    # Update last_updated timestamp
    jq --argjson ts "$TIMESTAMP" '.meta.last_updated = $ts' "$REGISTRY_MAIN" > "$REGISTRY_MAIN.tmp"
    mv "$REGISTRY_MAIN.tmp" "$REGISTRY_MAIN"
}

# --- Upload Handler ---
upload_file() {
    local file=$1
    local rel_path="${file#$BASE_DIR/}"
    local url=""

    # Check if already uploaded
    if [[ -f "$UPLOAD_DB" ]] && jq -e --arg path "$rel_path" '.uploads[] | select(.path == $path)' "$UPLOAD_DB" >/dev/null; then
        url=$(jq -r --arg path "$rel_path" '.uploads[] | select(.path == $path) | .url' "$UPLOAD_DB")
        log "INFO" "Skipping (already uploaded): $rel_path → $url"
        echo "$url"
        return 0
    fi

    if [[ "$DRY_RUN" -eq 0 ]]; then
        log "INFO" "Uploading: $rel_path"
        upload_output=$(tsh upload -n "$rel_path" "$file" 2>&1)
        url=$(echo "$upload_output" | grep -m1 'https://' | awk '{print $NF}' | tr -d '\r')

        if [[ -z "$url" ]]; then
            log "ERROR" "Upload failed: $file\nOutput: $upload_output"
            echo ""
            return 1
        fi

        # Add to upload DB
        jq --arg path "$rel_path" \
           --arg url "$url" \
           --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
           '.uploads += [{"path": $path, "url": $url, "timestamp": $ts}]' \
           "$UPLOAD_DB" > "$UPLOAD_DB.tmp"
        mv "$UPLOAD_DB.tmp" "$UPLOAD_DB"

        [[ "$GENERATE_LINKS" -eq 1 ]] && echo "$url" >> "$LINKS_FILE"
    else
        # For dry run, use a consistent format
        url="dry_run:$rel_path"
    fi

    log "INFO" "Upload complete: $rel_path → $url"
    echo "$url"
}

# --- SON Processing ---
process_son_directory() {
    local dir=$1
    find "$dir" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d $'\0' subdir; do
        local son_id=$(basename "$subdir")
        [[ "$son_id" =~ ^(small|original)$ ]] && continue

        log "INFO" "Processing SON ID: $son_id in $dir"

        # Create output directories
        local son_dir="$dir/$son_id"
        mkdir -p "$son_dir/small" "$son_dir/original"

        # Initialize SON entry
        if ! jq -e ".registry.SON[\"$son_id\"]" "$REGISTRY_MAIN" >/dev/null; then
            jq --arg id "$son_id" \
               --arg year "$YEAR" \
               '.registry.SON[$id] = {
                    year: $year,
                    meta: {},
                    content: {}
               }' "$REGISTRY_MAIN" > "$REGISTRY_MAIN.tmp"
            mv "$REGISTRY_MAIN.tmp" "$REGISTRY_MAIN"
        fi

        # Process all image types including WebP
        find "$subdir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
            ! -iname "small_*" ! -iname "original_*" -print0 | while IFS= read -r -d $'\0' file; do

            # Skip if already processed
            grep -qFx "$file" "$PROCESSED_LOG" && continue

            local base_name=$(basename "$file" | sed 's/\.[^.]*$//')
            local unique_id=$(tr -dc "$ID_CHARS" </dev/urandom | head -c "$SON_SUFFIX_LEN")

            # Output filenames
            local small_filename="small_SON-${son_id}_${unique_id}.webp"
            local large_filename="original_SON-${son_id}_${unique_id}.webp"
            local small="$son_dir/small/$small_filename"
            local large="$son_dir/original/$large_filename"

            # Process images
            resize_image "$file" "$small" "$SMALL_DIM" || true
            resize_image "$file" "$large" "${LARGE_MAX}x${LARGE_MAX}>" || true

            # Record as processed
            echo "$file" >> "$PROCESSED_LOG"

            # Upload files and get URLs
            local small_url=$(upload_file "$small")
            local large_url=$(upload_file "$large")

            # Calculate hash for original file only
            local original_hash=$(sha256sum "$large" | cut -d' ' -f1)

            # Add to registry
            local content_entry=$(jq -n \
                --arg small "$small_url" \
                --arg large "$large_url" \
                --arg hash "$original_hash" \
                '{
                    small: $small,
                    original: $large,
                    hash: $hash
                }'
            )

            jq --arg id "$son_id" \
               --arg uid "$unique_id" \
               --argjson content "$content_entry" \
               '.registry.SON[$id].content[$uid] = $content' \
               "$REGISTRY_MAIN" > "$REGISTRY_MAIN.tmp"
            mv "$REGISTRY_MAIN.tmp" "$REGISTRY_MAIN"

            log "INFO" "Processed: $file → $son_id/$unique_id"
        done
    done
}

# --- Standard Artifact Processing ---
process_artifact_file() {
    local file=$1 type=$2 out_dir=$3
    local base_name=$(basename "$file" | sed 's/\.[^.]*$//')

    # Skip processed files and outputs
    [[ "$base_name" =~ ^(small|medium|original)_ ]] && return
    grep -qFx "$file" "$PROCESSED_LOG" && return

    local artifact_id="${base_name#${type}-}"

    # Create output directories
    mkdir -p "$out_dir/small" "$out_dir/original"

    # Output filenames
    local small_filename="small_${type}-${artifact_id}.webp"
    local large_filename="original_${type}-${artifact_id}.webp"
    local small="$out_dir/small/$small_filename"
    local large="$out_dir/original/$large_filename"

    # Process images
    resize_image "$file" "$small" "$SMALL_DIM" || true
    resize_image "$file" "$large" "${LARGE_MAX}x${LARGE_MAX}>" || true

    # Record as processed
    echo "$file" >> "$PROCESSED_LOG"

    # Upload files and get URLs
    local small_url=$(upload_file "$small")
    local large_url=$(upload_file "$large")

    # Calculate hash for original file only
    local original_hash=$(sha256sum "$large" | cut -d' ' -f1)

    # Preserve existing metadata
    local existing_meta=$(jq -c ".registry[\"$type\"][\"$artifact_id\"].meta // {}" "$REGISTRY_MAIN" 2>/dev/null)

    # Add to registry
    jq --arg type "$type" \
       --arg id "$artifact_id" \
       --arg year "$YEAR" \
       --argjson meta "$existing_meta" \
       --arg small "$small_url" \
       --arg large "$large_url" \
       --arg hash "$original_hash" \
       '.registry[$type][$id] = {
            year: $year,
            meta: $meta,
            files: {
                small: $small,
                original: $large,
                hash: $hash
            }
       }' "$REGISTRY_MAIN" > "$REGISTRY_MAIN.tmp"
    mv "$REGISTRY_MAIN.tmp" "$REGISTRY_MAIN"

    log "INFO" "Processed: $file → $type-$artifact_id"
}

# --- Blog Processing ---
process_blog_file() {
    local file=$1 out_dir=$2
    grep -qFx "$file" "$PROCESSED_LOG" && return

    local blog_id=$(basename "$file" | sed 's/\.[^.]*$//' | sed 's/^VOID-//')

    # Record as processed
    echo "$file" >> "$PROCESSED_LOG"

    # Upload file and get URL
    local blog_url=$(upload_file "$file")

    # Preserve existing metadata
    local existing_meta=$(jq -c ".registry.VOID[\"$blog_id\"].meta // {}" "$REGISTRY_MAIN" 2>/dev/null)

    # Add to registry
    jq --arg id "$blog_id" \
       --arg year "$YEAR" \
       --arg file "$blog_url" \
       --arg hash "$(sha256sum "$file" | cut -d' ' -f1)" \
       --argjson meta "$existing_meta" \
       '.registry.VOID[$id] = {
            year: $year,
            meta: $meta,
            file: $file,
            hash: $hash
       }' "$REGISTRY_MAIN" > "$REGISTRY_MAIN.tmp"
    mv "$REGISTRY_MAIN.tmp" "$REGISTRY_MAIN"

    log "INFO" "Processed blog: $file → $blog_id"
}

# --- Upload DB Management ---
init_upload_db() {
    [[ ! -f "$UPLOAD_DB" ]] && echo '{"uploads": []}' > "$UPLOAD_DB"
}

# --- Main Processing ---
process_directory() {
    local dir=$1
    local type=$(get_artifact_type "$dir")
    [[ "$type" == "SKIP" ]] && return

    case "$type" in
        SON) 
            process_son_directory "$dir" 
            ;;
        VOID)
            [[ "$PROCESS_BLOGS" -eq 1 ]] && {
                find "$dir" -maxdepth 1 -type f -iname "*.md" -print0 | while IFS= read -r -d $'\0' file; do
                    process_blog_file "$file" "$dir"
                done
            }
            ;;
        *)
            # Process all image types including WebP
            find "$dir" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) \
                ! -iname "small_*" ! -iname "original_*" -print0 | while IFS= read -r -d $'\0' file; do
                process_artifact_file "$file" "$type" "$dir"
            done
            ;;
    esac

    # Process subdirectories
    [[ "$PROCESS_SUBDIRS" -eq 1 ]] && {
        find "$dir" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d $'\0' subdir; do
            process_directory "$subdir"
        done
    }
}

# --- Dependency Check ---
check_dependencies() {
    local deps=("jq" "tr" "sed" "sha256sum" "tsh")
    # Check for ImageMagick
    if ! command -v magick &>/dev/null && ! command -v convert &>/dev/null; then
        die "Missing ImageMagick (install with: sudo apt install imagemagick)"
    fi
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null || die "Missing dependency: $dep"
    done
}

# --- Initialization ---
init_system() {
    initialize_registry
    init_upload_db
    touch "$PROCESSED_LOG"
    [[ "$GENERATE_LINKS" -eq 1 ]] && > "$LINKS_FILE"
}

# --- Finalization ---
finalize_registry() {
    # Update timestamp
    jq --argjson ts "$TIMESTAMP" '.meta.last_updated = $ts' "$REGISTRY_MAIN" > "$REGISTRY_MAIN.tmp"
    mv "$REGISTRY_MAIN.tmp" "$REGISTRY_MAIN"
}

# --- Cleanup ---
cleanup() {
    # Create symlink to latest log
    ln -sf "$LOG_FILE" "$LOG_DIR/latest.log" 2>/dev/null || true
}

# --- Main ---
main() {
    trap cleanup EXIT
    check_dependencies
    init_system
    log "INFO" "Starting artifact processing"

    # Process all whisper directories
    find "$WHISPERS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | while IFS= read -r -d $'\0' dir; do
        process_directory "$dir"
    done

    finalize_registry
    log "INFO" "Processing completed successfully"
    log "INFO" "Registry updated: $REGISTRY_MAIN"
    log "INFO" "Log file: $LOG_FILE"
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main
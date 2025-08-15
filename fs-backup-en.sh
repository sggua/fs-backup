#!/bin/bash

# ==============================================================================
# Universal script for filesystem backup
# Uses rsync to create full, incremental, and synchronized copies.
# Dynamically excludes the backup destination directory.
# Confirms a detailed operation plan with the user.
# Performs disk space analysis.
# Optimized and simplified version with a unified logic and pre-flight checks.
# Uses numeric IDs for ACL records.
# After synchronization, the backup is renamed to the current date.
# (c) Gemini 2.5 pro (Google), 2025
# (c) Serhii Horichenko, 2025
# ==============================================================================

# Safe mode: exit on error, exit on use of an uninitialized variable,
# and return an error if any command in a pipeline (|) fails.
set -eo pipefail

# --- CONFIGURATION AND DEFAULT VALUES ---

# Default values
MODE=""
SOURCE_PATH="/"
DEST_PATH="."
RECOVER_DATE=""
FORCE_EXECUTION=false

# Current date and time
CURRENT_DATE=$(date +%Y-%m-%d)
CURRENT_TIME=$(date +%H%M%S)

# Colors for output
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'

# List of exclusions for rsync. It's important to exclude virtual FS and the backup directory itself.
EXCLUDE_LIST=(
  "/dev/*"
  "/proc/*"
  "/sys/*"
  "/tmp/*"
  "/run/*"
  "/mnt/*"
  "/media/*"
  "/lost+found"
# "*~"
# "*.bak"
# "*/.cache"
# "*/Cache"
)

# --- FUNCTIONS ---

# Function to display help
usage() {
  echo "Usage: $0 [mode] [options]"
  echo
  echo "  MODES (choose one):"
  echo "    --full, -f         Create a new full backup."
  echo "    --sync, -s         Synchronize with the latest full backup (update it)."
  echo "    --inc, -i          Create an incremental backup relative to the latest full one."
  echo "    --recover, -r      Restore the system from a backup for the specified date (YYYY-MM-DD)."
  echo
  echo "  REQUIRED PARAMETERS:"
  echo "    For --recover:     <date in YYYY-MM-DD format>"
  echo
  echo "  ADDITIONAL OPTIONS:"
  echo "    --source <path>    Specify the backup source (default: /)."
  echo "    --dest <path>      Specify the destination directory for backups (default: current directory)."
  echo "    --force, -y        Run without asking for confirmation."
  echo "    --help, -h         Show this help message."
  echo
  exit 1
}

# Function to confirm the execution plan
plan_and_confirm() {
    local summary="$1"
    echo -e "${COLOR_YELLOW}--- OPERATION PLAN ---${COLOR_RESET}"
    echo -e "${summary}"
    echo -e "${COLOR_YELLOW}----------------------${COLOR_RESET}"

    # Check if we should skip the confirmation prompt
    if [ "$FORCE_EXECUTION" = true ]; then
        echo -e "${COLOR_CYAN}Used --force or -y flag, proceeding without confirmation.${COLOR_RESET}"
        return 0
    fi

    # Ask for confirmation
    read -p "Do you agree to execute this plan? [y/N]: " response
    case "$response" in
        [yY][eE][sS] | [yY] | [jJ] | [jJ][aA] )
            echo -e "\n${COLOR_GREEN}Plan confirmed. Starting execution...${COLOR_RESET}"
            return 0
            ;;
        *)
            echo -e "\n${COLOR_BLUE}Operation canceled by the user.${COLOR_RESET}"
            exit 1
            ;;
    esac
}

# Generate the recovery script
generate_recovery_script() {
  local backup_path="$1"
  local recovery_script_path="${backup_path}/recovery.sh"

  # Create the recovery.sh script itself
  cat > "$recovery_script_path" <<EOF
#!/bin/bash
# IMPORTANT! This script is intended for system recovery.
# Run it from a Live-CD/USB environment with sudo privileges.
# DO NOT RUN ON A LIVE (RUNNING) SYSTEM!

set -e

echo "!!! WARNING: SYSTEM RECOVERY PROCESS IS STARTING !!!"
echo "Please ensure you are running this script from a Live-CD/USB."
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Path to the root of the new system (where the partition is mounted)
RECOVERY_TARGET="/"

# Directory to restore from (where this script is located)
RECOVERY_SOURCE=\$(dirname "\$0")

echo "Source: \$RECOVERY_SOURCE"
echo "Destination: \$RECOVERY_TARGET"

# rsync command for restoration.
# --delete will remove files in the destination that are not in the backup.
# The -L (--copy-links) flag is needed for rsync to copy the files pointed to by
# symbolic links, rather than creating the links themselves in the restored system.
rsync -aAXvL --progress --delete \\
      --exclude="/recovery.sh" \\
      --exclude="/skip-files.txt" \\
      "\$RECOVERY_SOURCE/" "\$RECOVERY_TARGET"

echo "✅ Recovery complete. Manually create system directories:"
echo "mkdir -p /dev /proc /sys /tmp /run /mnt /media"
echo "After this, you need to reinstall the bootloader (GRUB)."
EOF

  chmod +x "$recovery_script_path"
}


# --- COMMAND-LINE ARGUMENT PROCESSING ---
if [ $# -eq 0 ]; then usage; fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -f | --full) MODE="full" ;;
    -s | --sync) MODE="sync" ;;
    -i | --inc) MODE="inc" ;;
    -r | --recover)
      MODE="recover"
      if [ -n "$2" ]; then
          RECOVER_DATE="$2"
          shift
      else
          echo "Error: --recover requires a date in YYYY-MM-DD format." >&2
          exit 1
      fi
      ;;
    --source)
      if [ -n "$2" ]; then
          SOURCE_PATH="$2"
          shift
      else
          echo "Error: --source requires a path." >&2
          exit 1
      fi
      ;;
    --dest)
      if [ -n "$2" ]; then
          DEST_PATH="$2"
          shift
      else
          echo "Error: --dest requires a path." >&2
          exit 1
      fi
      ;;
    -y | --force) FORCE_EXECUTION=true ;;
    -h | --help) usage ;;
    *)
      echo "Unknown parameter: $1" >&2
      usage
      ;;
  esac
  shift
done

# --- PRE-FLIGHT CHECKS ---
# Check for required programs
for cmd in rsync numfmt; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${COLOR_RED}Error: required command '$cmd' is not found. Please install it.${COLOR_RESET}"
        exit 1
    fi
done

# Check for path existence and accessibility
if [ ! -d "$SOURCE_PATH" ]; then
    echo -e "${COLOR_RED}Error: source directory '$SOURCE_PATH' not found.${COLOR_RESET}"
    exit 1
fi
if [ ! -d "$DEST_PATH" ] || [ ! -w "$DEST_PATH" ]; then
    echo -e "${COLOR_RED}Error: destination directory '$DEST_PATH' does not exist or is not writable.${COLOR_RESET}"
    exit 1
fi

# Create an array of --exclude parameters for rsync
RSYNC_EXCLUDES=()
for item in "${EXCLUDE_LIST[@]}"; do
    RSYNC_EXCLUDES+=(--exclude="$item")
done

# Add an exclusion for the backup directory itself
ABSOLUTE_DEST_PATH=$(realpath "$DEST_PATH")
RSYNC_EXCLUDES+=(--exclude="${ABSOLUTE_DEST_PATH}/*")

# Variable to store the operation plan
OPERATION_SUMMARY=""

# --- MAIN LOGIC ---

# Mode: Full backup
if [ "$MODE" = "full" ]; then
    TARGET_DIR="${ABSOLUTE_DEST_PATH}/${CURRENT_DATE}-backup-full"

    # DISK SPACE ANALYSIS
    echo "Analyzing disk space for full backup..."
    REQUIRED_KB=$(df --total --block-size=1K --output=used "$SOURCE_PATH" | tail -n 1 | tr -d '[:space:]')
    AVAILABLE_KB=$(df --block-size=1K --output=avail "$DEST_PATH" | tail -n 1 | tr -d '[:space:]')
    REQUIRED_HUMAN=$(numfmt --to=iec-i --suffix=B --format="%.2f" $((REQUIRED_KB * 1024)))
    AVAILABLE_HUMAN=$(numfmt --to=iec-i --suffix=B --format="%.2f" $((AVAILABLE_KB * 1024)))

    # Formulating the plan
    OPERATION_SUMMARY=$(printf "%s" "${COLOR_CYAN}Mode:${COLOR_RESET} Full Backup\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_CYAN}Source:${COLOR_RESET} $SOURCE_PATH\n${COLOR_CYAN}Destination:${COLOR_RESET} $TARGET_DIR\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_YELLOW}Required space (estimate):${COLOR_RESET} $REQUIRED_HUMAN\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_GREEN}Available on destination disk:${COLOR_RESET} $AVAILABLE_HUMAN")

    # Check if there is enough space
    if (( REQUIRED_KB > AVAILABLE_KB )); then
        OPERATION_SUMMARY+=$(printf "%s" "\n\n${COLOR_RED}!!! WARNING !!!\nNot enough free space on the destination disk!${COLOR_RESET}")
        echo -e "$OPERATION_SUMMARY"
        exit 1
    fi

    plan_and_confirm "$OPERATION_SUMMARY"

    echo -e "\n${COLOR_GREEN}Creating full backup in ${TARGET_DIR}...${COLOR_RESET}"
    mkdir -p "$TARGET_DIR"
    sudo rsync -aAXHv --progress --numeric-ids "${RSYNC_EXCLUDES[@]}" "${SOURCE_PATH}/" "${TARGET_DIR}"
    generate_recovery_script "$TARGET_DIR"
    echo -e "\n${COLOR_GREEN}✅ Full backup successfully created in ${TARGET_DIR} ${COLOR_RESET}"

# Mode: Sync
elif [ "$MODE" = "sync" ]; then
    LATEST_FULL=$(find "$ABSOLUTE_DEST_PATH" -maxdepth 1 -type d -name "*-backup-full" | sort -r | head -n 1)
    if [ -z "$LATEST_FULL" ]; then echo -e "${COLOR_RED}Error: no full backup found to sync with.${COLOR_RESET}" >&2; exit 1; fi

    OPERATION_SUMMARY=$(printf "%s" "${COLOR_CYAN}Mode:${COLOR_RESET} Synchronization\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_CYAN}Source:${COLOR_RESET} $SOURCE_PATH\n${COLOR_CYAN}Syncing with:${COLOR_RESET} $LATEST_FULL\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_YELLOW}Files deleted from the source will also be deleted from the backup.${COLOR_RESET}")

    if [ ! -d "${ABSOLUTE_DEST_PATH}/${CURRENT_DATE}-backup-full" ]; then
        NEW_BACKUP_NAME="${ABSOLUTE_DEST_PATH}/${CURRENT_DATE}-backup-full"
        OPERATION_SUMMARY+=$(printf "%s" "\n${COLOR_YELLOW}The backup will be renamed to:${COLOR_RESET} $NEW_BACKUP_NAME\n")
    fi

    plan_and_confirm "$OPERATION_SUMMARY"

    echo -e "\n${COLOR_GREEN}Syncing with ${LATEST_FULL}...${COLOR_RESET}"
    # Deleting old files
    sudo rsync -aAXH --delete --progress --numeric-ids --ignore-existing "${RSYNC_EXCLUDES[@]}" "${SOURCE_PATH}/" "${LATEST_FULL}" | grep '^deleting '
    # Copying new files
    sudo rsync -aAXHv --delete --progress --numeric-ids "${RSYNC_EXCLUDES[@]}" "${SOURCE_PATH}/" "${LATEST_FULL}"
    generate_recovery_script "$LATEST_FULL"

    echo -e "\n${COLOR_GREEN}✅ Synchronization with ${LATEST_FULL} is complete.${COLOR_RESET}"
    if [ ! -d "${NEW_BACKUP_NAME}" ] && [ ! -z "$NEW_BACKUP_NAME" ]; then
        sudo mv -f "${LATEST_FULL}" "${NEW_BACKUP_NAME}"
        echo -e "\n${COLOR_YELLOW}Backup has been renamed to:${COLOR_RESET} $NEW_BACKUP_NAME\n"
    fi

# Mode: Incremental backup
elif [ "$MODE" = "inc" ]; then
    LATEST_FULL=$(find "$ABSOLUTE_DEST_PATH" -maxdepth 1 -type d -name "*-backup-full" | sort -r | head -n 1)
    if [ -z "$LATEST_FULL" ]; then echo -e "${COLOR_RED}Error: no base backup found to create an increment from.${COLOR_RESET}" >&2; exit 1; fi
    TARGET_DIR="${ABSOLUTE_DEST_PATH}/${CURRENT_DATE}-backup-inc-${CURRENT_TIME}"

    OPERATION_SUMMARY=$(printf "%s" "${COLOR_CYAN}Mode:${COLOR_RESET} Incremental Backup\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_CYAN}Method:${COLOR_RESET} Hard-links (saves space, fast execution)\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_CYAN}Source:${COLOR_RESET} $SOURCE_PATH\n${COLOR_CYAN}Base backup:${COLOR_RESET} $LATEST_FULL\n")
    OPERATION_SUMMARY+=$(printf "%s" "${COLOR_CYAN}Changes will be saved to:${COLOR_RESET} $TARGET_DIR")

    plan_and_confirm "$OPERATION_SUMMARY"

    echo -e "\n${COLOR_GREEN}Creating incremental backup in ${TARGET_DIR}...${COLOR_RESET}"
    sudo rsync -aAXv --progress --numeric-ids --link-dest="${LATEST_FULL}" "${RSYNC_EXCLUDES[@]}" "${SOURCE_PATH}/" "${TARGET_DIR}"

  # Create a list of files that were deleted from the source
  echo -e "\n${COLOR_YELLOW}Generating list of deleted files ${COLOR_RESET}(skip-files.txt)..."
  sudo rsync -aAXn --progress --delete "${RSYNC_EXCLUDES[@]}" "${SOURCE_PATH}/" "${LATEST_FULL}" | \
    grep '^deleting ' | sed 's/^deleting //' > "${TARGET_DIR}/skip-files.txt"

  # Generate the recovery script for the increment (more complex logic)
  RECOVERY_SCRIPT_PATH="${TARGET_DIR}/recovery.sh"
  cat > "$RECOVERY_SCRIPT_PATH" <<EOF
#!/bin/bash
echo "!!! WARNING: RESTORING FROM AN INCREMENTAL BACKUP !!!"
echo "This process will first restore the full backup, then apply the changes."
read -p "Press Enter to continue or Ctrl+C to cancel..."

RECOVERY_TARGET="/"
INC_BACKUP_DIR=\$(dirname "\$0")
FULL_BACKUP_DIR="${LATEST_FULL}" # Path to the full backup is hardcoded

# Step 1: Restore from the full backup
echo "-> Step 1/3: Restoring from the base full backup..."
sudo rsync -aAXv --delete --progress --numeric-ids "\${FULL_BACKUP_DIR}/" "\${RECOVERY_TARGET}"

# Step 2: Restore changed files from the incremental backup
echo "-> Step 2/3: Applying changes from the incremental backup..."
sudo rsync -aAXv --progress --numeric-ids "\${INC_BACKUP_DIR}/" "\${RECOVERY_TARGET}"

# Step 3: Delete files listed in skip-files.txt
if [ -f "\${INC_BACKUP_DIR}/skip-files.txt" ]; then
  echo "-> Step 3/3: Deleting files that are no longer in the source..."
  while IFS= read -r file_to_delete; do
    # Check if the file exists before deleting
    if [ -e "\${RECOVERY_TARGET}\${file_to_delete}" ]; then
      echo "Deleting: \${RECOVERY_TARGET}\${file_to_delete}"
      sudo rm -rf "\${RECOVERY_TARGET}\${file_to_delete}"
    fi
  done < "\${INC_BACKUP_DIR}/skip-files.txt"
fi

echo "✅ Recovery complete."
EOF

  chmod +x "$RECOVERY_SCRIPT_PATH"
  echo -e "\n${COLOR_GREEN}✅ Incremental backup created in ${TARGET_DIR} ${COLOR_RESET}"

# Mode: Recover
elif [ "$MODE" = "recover" ]; then
  LATEST_FULL=$(find "$ABSOLUTE_DEST_PATH" -maxdepth 1 -type d -name "*-backup-full" -newermt "${RECOVER_DATE} 00:00:00" ! -newermt "${RECOVER_DATE} 23:59:59" -o -newermt "1970-01-01" ! -newermt "${RECOVER_DATE}" | sort -r | head -n 1)

  if [ -z "$LATEST_FULL" ]; then
    echo -e "\n${COLOR_RED}Error: no suitable full backup found for recovery on date ${COLOR_RESET} ${RECOVER_DATE}." >&2
    exit 1
  fi

  INCREMENTALS_TO_APPLY=$(find "$ABSOLUTE_DEST_PATH" -maxdepth 1 -type d -name "*-backup-inc-*" -newermt "$(stat -c %y "$LATEST_FULL")" -and ! -newermt "${RECOVER_DATE} 23:59:59" | sort)

  OPERATION_SUMMARY=$(printf "%s" "${COLOR_CYAN}Mode:${COLOR_RESET} System Recovery\n")
  OPERATION_SUMMARY+=$(printf "%s" "${COLOR_BLUE}Target date:${COLOR_RESET}  ${RECOVER_DATE}\n")
  OPERATION_SUMMARY+=$(printf "%s" "${COLOR_BLUE}Base backup:${COLOR_RESET}    ${LATEST_FULL}\n")
  if [ -n "$INCREMENTALS_TO_APPLY" ]; then
      OPERATION_SUMMARY+=$(printf "%s" "${COLOR_YELLOW}Increments to apply:${COLOR_RESET}\n${INCREMENTALS_TO_APPLY}\n")
  else
      OPERATION_SUMMARY+=$(printf "%s" "${COLOR_YELLOW}No incremental backups found; only the full backup will be restored.${COLOR_RESET}\n")
  fi
  OPERATION_SUMMARY+=$(printf "%s" "${COLOR_RED}Destination:${COLOR_RESET} $SOURCE_PATH\n")
  OPERATION_SUMMARY+=$(printf "%s" "\n${COLOR_RED}!!! WARNING: THIS OPERATION WILL OVERWRITE DATA IN:\n${SOURCE_PATH} !!!\n${COLOR_RESET}")

  plan_and_confirm "$OPERATION_SUMMARY"

  echo -e "\n${COLOR_GREEN}Restoring to ${RECOVER_DATE}...${COLOR_RESET}"

  # Step 1: Restore from the full backup
  echo -e "\n${COLOR_YELLOW}-> Step 1: Restoring from base full backup ${LATEST_FULL}...${COLOR_RESET}"
  sudo rsync -aAXv --delete --progress --numeric-ids --exclude="/recovery.sh" "${LATEST_FULL}/" "${SOURCE_PATH}"

  # Step 2: Sequentially apply increments
  if [ -n "$INCREMENTALS_TO_APPLY" ]; then
    step=2
    for inc_dir in $INCREMENTALS_TO_APPLY; do
      echo -e "\n${COLOR_YELLOW}->  Step ${step}: Applying increment ${inc_dir}... ${COLOR_RESET}"
      # Copy changed/new files
      sudo rsync -aAXv --progress --numeric-ids "${inc_dir}/" "${SOURCE_PATH}"
      # Delete files from skip-files.txt
      if [ -f "${inc_dir}/skip-files.txt" ]; then
        while IFS= read -r file_to_delete; do
          if [ -e "${SOURCE_PATH}${file_to_delete}" ]; then
            sudo rm -rf "${SOURCE_PATH}${file_to_delete}"
          fi
        done < "${inc_dir}/skip-files.txt"
      fi
      ((step++))
    done
  fi
  echo -e "\n${COLOR_GREEN}✅ Recovery to $SOURCE_PATH for date ${RECOVER_DATE} is complete. ${COLOR_RESET}"


else
  echo -e "\n${COLOR_RED}Error: no mode specified.\n ${COLOR_RESET}" >&2
  usage
fi

echo -e "\n${COLOR_GREEN}Operation completed successfully.\n${COLOR_RESET}"


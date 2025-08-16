#!/bin/bash

set -e
LOCALE_DIR="locale"
POT_FILE="$LOCALE_DIR/fs-backup.pot"

find "$LOCALE_DIR" -name "*.po" -print0 | while IFS= read -r -d '' po_file; do
    mo_file="${po_file%.po}.mo"
#    msg="$(msgmerge -U --backup=simple --no-wrap -v "$po_file" "$POT_FILE" | grep ',')"
    echo -e "$po_file:"
    msgmerge -U --backup=simple --no-wrap -v "$po_file" "$POT_FILE"
    echo -e "\n"
done

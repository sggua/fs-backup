#!/bin/bash
#msgfmt locale/uk/LC_MESSAGES/fs-backup.po -o locale/uk/LC_MESSAGES/fs-backup.mo

set -e
LOCALE_DIR="locale"

find "$LOCALE_DIR" -name "*.po" -print0 | while IFS= read -r -d '' po_file; do
    mo_file="${po_file%.po}.mo"
    msgfmt --check -o "$mo_file" "$po_file"
done


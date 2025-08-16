#!/bin/sh
# mkdir -p locale/"$1"/LC_MESSAGES
# xgettext --from-code=UTF-8 -o locale/"$1"/LC_MESSAGES/fs-backup.po --keyword=_ --keyword=gettext fs-backup.sh
#xgettext --from-code=UTF-8 -o locale/fs-backup.pot --keyword=_ --keyword=gettext fs-backup.sh
#cp locale/fs-backup.pot locale/"$1"/LC_MESSAGES/fs-backup.po
msginit -i locale/fs-backup.pot -l $1 --no-translator -o locale/"$1".po

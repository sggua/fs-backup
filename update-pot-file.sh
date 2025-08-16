#!/bin/sh
cp -b -f locale/fs-backup.pot locale/fs-backup.pot~
xgettext --from-code=UTF-8 -o locale/fs-backup.pot --keyword=_ --keyword=gettext fs-backup.sh

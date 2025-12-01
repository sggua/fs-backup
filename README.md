FS-Backup, a small tool to backup a file system into rsynced copy and it's softlinked iterated copies.
Copyright (C) 2025 Gemini 2.5 pro (Google)
Copyright (C) 2025 Serhii Horichenko

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

Universal script for filesystem backups.
Uses rsync to create full, incremental, and synchronized copies.
Dynamically excludes the backup destination directory.
Confirms a detailed operation plan with the user.
Performs disk space analysis.

Optimized and simplified version with a unified logic and pre-flight checks.
Uses numeric IDs for ACL records.
After synchronization, the backup is renamed to the current date.



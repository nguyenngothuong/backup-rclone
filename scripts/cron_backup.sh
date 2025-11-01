#!/bin/bash
# Cron Wrapper Script Template
# Mục đích: Wrapper script cho cron job để backup PostgreSQL
# License: MIT

SCRIPT_DIR="/path/to/scripts/backup"
BACKUP_SCRIPT="${SCRIPT_DIR}/backup_postgresql.sh"
LOG_DIR="/path/to/backups/logs"
CRON_LOG="${LOG_DIR}/cron_backup_$(date +%Y%m%d).log"

# Tạo log directory nếu chưa có
mkdir -p "$LOG_DIR"

# Log start time
echo "==========================================" >> "$CRON_LOG"
echo "Cron Backup Started - $(date)" >> "$CRON_LOG"
echo "==========================================" >> "$CRON_LOG"

# Chạy backup script và log output
bash "$BACKUP_SCRIPT" >> "$CRON_LOG" 2>&1
EXIT_CODE=$?

# Log end time và kết quả
echo "" >> "$CRON_LOG"
echo "==========================================" >> "$CRON_LOG"
echo "Cron Backup Finished - $(date)" >> "$CRON_LOG"
echo "Exit Code: $EXIT_CODE" >> "$CRON_LOG"
echo "==========================================" >> "$CRON_LOG"

# Exit với code tương ứng
exit $EXIT_CODE


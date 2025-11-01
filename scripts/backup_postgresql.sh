#!/bin/bash
# PostgreSQL Backup to Google Drive - Full Backup Script Template
# Mục đích: Backup tất cả databases PostgreSQL lên Google Drive với stream upload
# Tác giả: Template for community use
# License: MIT

set -e  # Exit on error

# ==================== CONFIGURATION ====================
# Cấu hình các biến sau theo môi trường của bạn

CONTAINER="postgresql_container"  # Tên container PostgreSQL của bạn
DATE=$(date +%Y%m%d_%H%M%S)
REMOTE="your-remote:backup-path"  # Tên remote Rclone của bạn (ví dụ: gdrive:backups)
BACKUP_DIR="/path/to/backups"  # Thư mục lưu logs local
LOG_FILE="${BACKUP_DIR}/logs/backup_${DATE}.log"
START_TIME=$(date +%s)  # Track total backup duration

# Kiểm tra ngày để quyết định copy vào weekly/monthly
DAY_OF_WEEK=$(date +%u)  # 1-7 (1=Monday, 7=Sunday)
DAY_OF_MONTH=$(date +%d)  # 01-31

# Optional: Webhook notification (để trống nếu không dùng)
WEBHOOK_URL=""  # URL webhook của bạn (ví dụ: https://hooks.slack.com/...)

# ==================== FUNCTIONS ====================

# Function gửi webhook notification (optional)
send_webhook_notification() {
    if [ -z "$WEBHOOK_URL" ]; then
        return 0  # Skip nếu không có webhook URL
    fi
    
    local status=$1  # success/failed
    local total_dbs=$2
    local success_count=$3
    local failed_count=$4
    local failed_dbs=$5
    local duration=$6
    local log_file=$7
    
    # Format failed_databases (remove leading spaces và newlines)
    local failed_dbs_clean=$(echo "$failed_dbs" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\n\r')
    if [ -z "$failed_dbs_clean" ]; then
        failed_dbs_clean="none"
    fi
    
    # Escape các ký tự đặc biệt trong string values
    local failed_dbs_escaped=$(echo "$failed_dbs_clean" | sed 's/"/\\"/g')
    local log_file_escaped=$(echo "$log_file" | sed 's/"/\\"/g')
    local backup_location_escaped=$(echo "${REMOTE}/daily/" | sed 's/"/\\"/g')
    local server_name=$(hostname | sed 's/"/\\"/g')
    
    # Tạo JSON payload (compact format, không có newline trong giá trị)
    local payload=$(cat <<EOF
{"timestamp":"$(date -Iseconds)","backup_type":"postgresql_full","status":"$status","total_databases":$total_dbs,"success_count":$success_count,"failed_count":$failed_count,"failed_databases":"$failed_dbs_escaped","total_duration_seconds":$duration,"log_file_path":"$log_file_escaped","backup_location":"$backup_location_escaped","server":"$server_name"}
EOF
)
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Sending webhook notification..." | tee -a "$log_file"
    
    # Gửi webhook request
    local response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$WEBHOOK_URL" 2>&1)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Webhook notification sent successfully (HTTP $http_code)" | tee -a "$log_file"
        return 0
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ Webhook notification failed (HTTP $http_code): $body" | tee -a "$log_file"
        return 1
    fi
}

# ==================== MAIN SCRIPT ====================

echo "==========================================" | tee -a $LOG_FILE
echo "PostgreSQL Full Backup - $(date)" | tee -a $LOG_FILE
echo "Remote: $REMOTE" | tee -a $LOG_FILE
echo "==========================================" | tee -a $LOG_FILE

# Tạo thư mục backup local nếu chưa có
mkdir -p "${BACKUP_DIR}/logs"

# Lấy danh sách databases
DATABASES=$(docker exec $CONTAINER psql -U postgres -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';")

TOTAL_DBS=$(echo "$DATABASES" | wc -l)
SUCCESS_COUNT=0
FAILED_COUNT=0
FAILED_DBS=""

echo "Found $TOTAL_DBS databases to backup" | tee -a $LOG_FILE
echo "" | tee -a $LOG_FILE

# Backup từng database
for db in $DATABASES; do
    echo "----------------------------------------" | tee -a $LOG_FILE
    echo "Backing up database: $db" | tee -a $LOG_FILE
    
    # Lấy kích thước database
    DB_SIZE=$(docker exec $CONTAINER psql -U postgres -t -A -c "SELECT pg_size_pretty(pg_database_size('$db'));" | tr -d ' ')
    echo "Database size: $DB_SIZE" | tee -a $LOG_FILE
    
    DB_START_TIME=$(date +%s)
    
    # Backup và upload trực tiếp (stream) - không tốn dung lượng đĩa
    docker exec $CONTAINER pg_dump -U postgres -Fc "$db" | \
      gzip | \
      rclone rcat ${REMOTE}/daily/${db}_backup_${DATE}.dump.gz \
      --progress \
      --transfers 2 \
      --buffer-size 64M \
      --stats-log-level NOTICE \
      2>&1 | tee -a $LOG_FILE
    
    # Kiểm tra kết quả
    if [ ${PIPESTATUS[2]} -eq 0 ]; then
        DB_END_TIME=$(date +%s)
        DURATION=$((DB_END_TIME - DB_START_TIME))
        
        BACKUP_SIZE_RAW=$(rclone size ${REMOTE}/daily/${db}_backup_${DATE}.dump.gz 2>/dev/null | grep Total | awk '{print $3 $4}' || echo "Unknown")
        # Trim whitespace và newline từ backup_size
        BACKUP_SIZE=$(echo "$BACKUP_SIZE_RAW" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        echo "✅ $db: Backup successful (${BACKUP_SIZE}) - ${DURATION}s" | tee -a $LOG_FILE
        
        # Copy vào weekly nếu là Chủ nhật (day 7)
        if [ "$DAY_OF_WEEK" = "7" ]; then
            echo "  📅 Copying to weekly backup (Sunday)..." | tee -a $LOG_FILE
            rclone copy ${REMOTE}/daily/${db}_backup_${DATE}.dump.gz ${REMOTE}/weekly/${db}_backup_${DATE}.dump.gz 2>/dev/null || true
        fi
        
        # Copy vào monthly nếu là ngày 1
        if [ "$DAY_OF_MONTH" = "01" ]; then
            echo "  📅 Copying to monthly backup (1st of month)..." | tee -a $LOG_FILE
            rclone copy ${REMOTE}/daily/${db}_backup_${DATE}.dump.gz ${REMOTE}/monthly/${db}_backup_${DATE}.dump.gz 2>/dev/null || true
        fi
        
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "❌ $db: Backup FAILED!" | tee -a $LOG_FILE
        FAILED_COUNT=$((FAILED_COUNT + 1))
        FAILED_DBS="${FAILED_DBS} $db"
    fi
    
    echo "" | tee -a $LOG_FILE
done

# Backup full (pg_dumpall) cho users và roles
echo "----------------------------------------" | tee -a $LOG_FILE
echo "Backing up full database (users, roles, permissions)..." | tee -a $LOG_FILE
FULL_START_TIME=$(date +%s)

docker exec $CONTAINER pg_dumpall -U postgres | \
  gzip | \
  rclone rcat ${REMOTE}/daily/full_backup_all_${DATE}.sql.gz \
  --progress \
  --transfers 2 \
  --buffer-size 64M \
  --stats-log-level NOTICE \
  2>&1 | tee -a $LOG_FILE

if [ ${PIPESTATUS[2]} -eq 0 ]; then
    FULL_END_TIME=$(date +%s)
    DURATION=$((FULL_END_TIME - FULL_START_TIME))
    
    BACKUP_SIZE_RAW=$(rclone size ${REMOTE}/daily/full_backup_all_${DATE}.sql.gz 2>/dev/null | grep Total | awk '{print $3 $4}' || echo "Unknown")
    # Trim whitespace và newline từ backup_size
    BACKUP_SIZE=$(echo "$BACKUP_SIZE_RAW" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    echo "✅ Full backup successful (${BACKUP_SIZE}) - ${DURATION}s" | tee -a $LOG_FILE
    
    # Copy vào weekly nếu là Chủ nhật (day 7)
    if [ "$DAY_OF_WEEK" = "7" ]; then
        echo "  📅 Copying full backup to weekly (Sunday)..." | tee -a $LOG_FILE
        rclone copy ${REMOTE}/daily/full_backup_all_${DATE}.sql.gz ${REMOTE}/weekly/full_backup_all_${DATE}.sql.gz 2>/dev/null || true
    fi
    
    # Copy vào monthly nếu là ngày 1
    if [ "$DAY_OF_MONTH" = "01" ]; then
        echo "  📅 Copying full backup to monthly (1st of month)..." | tee -a $LOG_FILE
        rclone copy ${REMOTE}/daily/full_backup_all_${DATE}.sql.gz ${REMOTE}/monthly/full_backup_all_${DATE}.sql.gz 2>/dev/null || true
    fi
else
    echo "❌ Full backup FAILED!" | tee -a $LOG_FILE
    FAILED_COUNT=$((FAILED_COUNT + 1))
fi

# Tóm tắt
echo "" | tee -a $LOG_FILE
echo "==========================================" | tee -a $LOG_FILE
echo "BACKUP SUMMARY" | tee -a $LOG_FILE
echo "==========================================" | tee -a $LOG_FILE
echo "Total databases: $TOTAL_DBS" | tee -a $LOG_FILE
echo "Successful: $SUCCESS_COUNT" | tee -a $LOG_FILE
echo "Failed: $FAILED_COUNT" | tee -a $LOG_FILE

if [ $FAILED_COUNT -gt 0 ]; then
    echo "Failed databases: $FAILED_DBS" | tee -a $LOG_FILE
    echo "❌ Backup completed with errors!" | tee -a $LOG_FILE
    
    # Tính tổng thời gian backup
    END_TIME=$(date +%s)
    TOTAL_DURATION=$((END_TIME - START_TIME))
    
    # Gửi webhook notification (failed)
    send_webhook_notification "failed" "$TOTAL_DBS" "$SUCCESS_COUNT" "$FAILED_COUNT" "$FAILED_DBS" "$TOTAL_DURATION" "$LOG_FILE"
    
    exit 1
else
    echo "✅ All backups completed successfully!" | tee -a $LOG_FILE
    
    # Tính tổng thời gian backup
    END_TIME=$(date +%s)
    TOTAL_DURATION=$((END_TIME - START_TIME))
    
    # Gửi webhook notification (success)
    send_webhook_notification "success" "$TOTAL_DBS" "$SUCCESS_COUNT" "$FAILED_COUNT" "$FAILED_DBS" "$TOTAL_DURATION" "$LOG_FILE"
fi

echo "" | tee -a $LOG_FILE
echo "Backup location: ${REMOTE}/daily/" | tee -a $LOG_FILE
if [ "$DAY_OF_WEEK" = "7" ]; then
    echo "Weekly backup: ✅ Copied to ${REMOTE}/weekly/" | tee -a $LOG_FILE
fi
if [ "$DAY_OF_MONTH" = "01" ]; then
    echo "Monthly backup: ✅ Copied to ${REMOTE}/monthly/" | tee -a $LOG_FILE
fi
echo "Log file: $LOG_FILE" | tee -a $LOG_FILE
echo "Total duration: ${TOTAL_DURATION} seconds" | tee -a $LOG_FILE
echo "==========================================" | tee -a $LOG_FILE

# Cleanup old backups theo retention policy
echo "" | tee -a $LOG_FILE
echo "Cleaning up old backups..." | tee -a $LOG_FILE

# Daily: Giữ 7 ngày
echo "  - Daily backups: Keeping 7 days..." | tee -a $LOG_FILE
OLD_DATE_DAILY=$(date -d '7 days ago' +%Y%m%d)
rclone delete ${REMOTE}/daily/*_backup_${OLD_DATE_DAILY}*.dump.gz 2>/dev/null || true
rclone delete ${REMOTE}/daily/full_backup_all_${OLD_DATE_DAILY}*.sql.gz 2>/dev/null || true

# Weekly: Giữ 12 tuần (84 ngày)
echo "  - Weekly backups: Keeping 12 weeks..." | tee -a $LOG_FILE
OLD_DATE_WEEKLY=$(date -d '84 days ago' +%Y%m%d)
rclone delete ${REMOTE}/weekly/*_backup_${OLD_DATE_WEEKLY}*.dump.gz 2>/dev/null || true
rclone delete ${REMOTE}/weekly/full_backup_all_${OLD_DATE_WEEKLY}*.sql.gz 2>/dev/null || true

# Monthly: Giữ 12 tháng (365 ngày)
echo "  - Monthly backups: Keeping 12 months..." | tee -a $LOG_FILE
OLD_DATE_MONTHLY=$(date -d '365 days ago' +%Y%m%d)
rclone delete ${REMOTE}/monthly/*_backup_${OLD_DATE_MONTHLY}*.dump.gz 2>/dev/null || true
rclone delete ${REMOTE}/monthly/full_backup_all_${OLD_DATE_MONTHLY}*.sql.gz 2>/dev/null || true

echo "✅ Cleanup completed" | tee -a $LOG_FILE


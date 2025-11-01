#!/bin/bash
# PostgreSQL Backup to Google Drive - Test Script Template
# Mục đích: Test backup một database PostgreSQL lên Google Drive với stream upload
# License: MIT

set -e  # Exit on error

# ==================== CONFIGURATION ====================
# Cấu hình các biến sau theo môi trường của bạn

CONTAINER="postgresql_container"  # Tên container PostgreSQL của bạn
DB_NAME="your_database"  # Database nhỏ để test
DATE=$(date +%Y%m%d_%H%M%S)
REMOTE="your-remote:backup-path/test"  # Tên remote Rclone của bạn
LOG_FILE="/tmp/postgresql_backup_test.log"
START_TIME=$(date +%s)  # Track total backup duration

# Optional: Webhook notification (để trống nếu không dùng)
WEBHOOK_URL=""  # URL webhook của bạn

# ==================== FUNCTIONS ====================

# Function gửi webhook notification (optional)
send_webhook_notification() {
    if [ -z "$WEBHOOK_URL" ]; then
        return 0  # Skip nếu không có webhook URL
    fi
    
    local status=$1  # success/failed
    local db_name=$2
    local backup_size=$3
    local duration=$4
    local log_file=$5
    local backup_file=$6
    
    # Tạo JSON payload cho single database backup
    # Escape các ký tự đặc biệt trong string values
    local db_name_escaped=$(echo "$db_name" | sed 's/"/\\"/g')
    local backup_size_escaped=$(echo "$backup_size" | sed 's/"/\\"/g' | tr -d '\n\r')
    local log_file_escaped=$(echo "$log_file" | sed 's/"/\\"/g')
    local backup_file_escaped=$(echo "$backup_file" | sed 's/"/\\"/g')
    local backup_location_escaped=$(echo "${REMOTE}/" | sed 's/"/\\"/g')
    local server_name=$(hostname | sed 's/"/\\"/g')
    
    local payload=$(cat <<EOF
{"timestamp":"$(date -Iseconds)","backup_type":"postgresql_single","status":"$status","database_name":"$db_name_escaped","backup_size":"$backup_size_escaped","duration_seconds":$duration,"log_file_path":"$log_file_escaped","backup_file":"$backup_file_escaped","backup_location":"$backup_location_escaped","server":"$server_name"}
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
echo "PostgreSQL Backup Test - $(date)" | tee -a $LOG_FILE
echo "Database: $DB_NAME" | tee -a $LOG_FILE
echo "Remote: $REMOTE" | tee -a $LOG_FILE
echo "==========================================" | tee -a $LOG_FILE

# Kiểm tra database tồn tại
DB_EXISTS=$(docker exec $CONTAINER psql -U postgres -t -A -c "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';" 2>/dev/null | tr -d ' ')

if [ "$DB_EXISTS" != "1" ]; then
    echo "❌ ERROR: Database '$DB_NAME' không tồn tại!" | tee -a $LOG_FILE
    echo "Danh sách databases:" | tee -a $LOG_FILE
    docker exec $CONTAINER psql -U postgres -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false;" | tee -a $LOG_FILE
    exit 1
fi

# Lấy kích thước database
DB_SIZE=$(docker exec $CONTAINER psql -U postgres -t -A -c "SELECT pg_size_pretty(pg_database_size('$DB_NAME'));" | tr -d ' ')
echo "Database size: $DB_SIZE" | tee -a $LOG_FILE

# Tạo thư mục trên Google Drive nếu chưa có
echo "Creating remote directory..." | tee -a $LOG_FILE
rclone mkdir $REMOTE 2>/dev/null || true

# Backup và upload trực tiếp (stream) - không tốn dung lượng đĩa
echo "Starting backup and upload..." | tee -a $LOG_FILE
BACKUP_START_TIME=$(date +%s)

docker exec $CONTAINER pg_dump -U postgres -Fc "$DB_NAME" | \
  gzip | \
  rclone rcat ${REMOTE}/${DB_NAME}_backup_${DATE}.dump.gz \
  --progress \
  --transfers 2 \
  --buffer-size 64M \
  --stats-log-level NOTICE \
  2>&1 | tee -a $LOG_FILE

BACKUP_EXIT_CODE=${PIPESTATUS[2]}

# Kiểm tra kết quả
BACKUP_FILE="${DB_NAME}_backup_${DATE}.dump.gz"

if [ "${BACKUP_EXIT_CODE:-1}" -eq 0 ]; then
    BACKUP_END_TIME=$(date +%s)
    DURATION=$((BACKUP_END_TIME - BACKUP_START_TIME))
    TOTAL_DURATION=$((BACKUP_END_TIME - START_TIME))
    
    echo "" | tee -a $LOG_FILE
    echo "==========================================" | tee -a $LOG_FILE
    echo "✅ Backup successful!" | tee -a $LOG_FILE
    echo "Duration: ${DURATION} seconds" | tee -a $LOG_FILE
    
    # Kiểm tra file trên Google Drive
    echo "Verifying backup on Google Drive..." | tee -a $LOG_FILE
    BACKUP_SIZE_RAW=$(rclone size ${REMOTE}/${BACKUP_FILE} 2>/dev/null | grep Total | awk '{print $3 $4}' || echo "Unknown")
    # Trim whitespace và newline từ backup_size
    BACKUP_SIZE=$(echo "$BACKUP_SIZE_RAW" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    echo "Backup file size: $BACKUP_SIZE" | tee -a $LOG_FILE
    
    # List files trên Google Drive
    echo "" | tee -a $LOG_FILE
    echo "Files on Google Drive:" | tee -a $LOG_FILE
    rclone lsf ${REMOTE}/ | grep "${DB_NAME}_backup" | tee -a $LOG_FILE
    
    # Gửi webhook notification (success)
    send_webhook_notification "success" "$DB_NAME" "$BACKUP_SIZE" "$TOTAL_DURATION" "$LOG_FILE" "${REMOTE}/${BACKUP_FILE}"
    
    echo "==========================================" | tee -a $LOG_FILE
    echo "Log file: $LOG_FILE" | tee -a $LOG_FILE
else
    BACKUP_END_TIME=$(date +%s)
    TOTAL_DURATION=$((BACKUP_END_TIME - START_TIME))
    
    echo "" | tee -a $LOG_FILE
    echo "❌ Backup FAILED!" | tee -a $LOG_FILE
    
    # Gửi webhook notification (failed)
    send_webhook_notification "failed" "$DB_NAME" "0" "$TOTAL_DURATION" "$LOG_FILE" "none"
    
    echo "Check log: $LOG_FILE" | tee -a $LOG_FILE
    exit 1
fi


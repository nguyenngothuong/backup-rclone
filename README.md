# PostgreSQL Backup với Rclone - Stream Upload

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Hệ thống backup PostgreSQL tự động lên Google Drive sử dụng Rclone với stream upload, không tốn dung lượng đĩa local.

## ✨ Tính năng

- 🚀 **Stream Upload**: Backup trực tiếp từ PostgreSQL → gzip → Google Drive, không tốn dung lượng đĩa
- 📦 **Compression**: Tự động nén với gzip (giảm ~95% dung lượng)
- 📅 **Retention Policy**: Daily (7 ngày), Weekly (12 tuần), Monthly (12 tháng)
- 🔔 **Webhook Notification**: Optional webhook để nhận thông báo backup
- 📝 **Logging**: Logging đầy đủ với timestamp và kết quả chi tiết
- ⚙️ **Automated**: Cron job tự động chạy hàng ngày

## 📊 Flow Logic Backup

### Backup Process Flow

```mermaid
graph TD
    A[Cron Job Trigger] --> B[Start Backup Script]
    B --> C{Get Database List}
    C --> D[For Each Database]
    D --> E[pg_dump -Fc]
    E --> F[gzip Compression]
    F --> G[rclone rcat Stream Upload]
    G --> H{Upload Success?}
    H -->|Yes| I[Save to daily/]
    H -->|No| J[Log Error]
    I --> K{Is Sunday?}
    K -->|Yes| L[Copy to weekly/]
    K -->|No| M{Is 1st of Month?}
    L --> M
    M -->|Yes| N[Copy to monthly/]
    M -->|No| O[Continue Next DB]
    N --> O
    O --> P{More Databases?}
    P -->|Yes| D
    P -->|No| Q[Backup pg_dumpall]
    Q --> R[gzip + Upload]
    R --> S[Cleanup Old Backups]
    S --> T[Send Webhook Notification]
    T --> U[End]
    J --> U
```

### Retention Policy Flow

```mermaid
graph LR
    A[Daily Backup] --> B{daily/ folder}
    B --> C{After 7 days}
    C -->|Delete| D[Cleanup]
    
    E[Weekly Backup<br/>Every Sunday] --> F{weekly/ folder}
    F --> G{After 84 days}
    G -->|Delete| D
    
    H[Monthly Backup<br/>1st of Month] --> I{monthly/ folder}
    I --> J{After 365 days}
    J -->|Delete| D
    
    D --> K[Storage Optimized]
```

### Backup Architecture

```mermaid
graph TB
    subgraph "PostgreSQL Container"
        A[PostgreSQL Database]
    end
    
    subgraph "Backup Process"
        B[pg_dump -Fc]
        C[gzip Compression]
        D[rclone Stream]
    end
    
    subgraph "Google Drive Storage"
        E[daily/]
        F[weekly/]
        G[monthly/]
    end
    
    subgraph "Monitoring"
        H[Log Files]
        I[Webhook Notification]
    end
    
    A -->|pg_dump| B
    B -->|Stream| C
    C -->|Stream| D
    D -->|Upload| E
    E -->|Copy Sunday| F
    E -->|Copy 1st| G
    D -->|Log| H
    D -->|Notify| I
```

### Restore Process Flow

```mermaid
graph TD
    A[Start Restore] --> B[Select Backup File]
    B --> C{rclone cat from Google Drive}
    C --> D[gunzip Decompress]
    D --> E{Backup Type?}
    E -->|Single DB| F[pg_restore]
    E -->|Full Backup| G[psql]
    F --> H[Restore to Database]
    G --> I[Restore Users/Roles]
    H --> J[Verify Restore]
    I --> J
    J --> K{Success?}
    K -->|Yes| L[✅ Restore Complete]
    K -->|No| M[❌ Check Logs]
```

## 📋 Yêu cầu

- Docker với PostgreSQL container
- Rclone đã cài đặt
- Google Drive account với API access
- Bash shell

## 🚀 Quick Start

### 1. Clone repository

```bash
git clone https://github.com/nguyenngothuong/backup-rclone.git
cd backup-rclone
```

### 2. Cài đặt Rclone

```bash
curl https://rclone.org/install.sh | sudo bash
```

### 3. Cấu hình Rclone

```bash
bash scripts/setup_rclone.sh
# Hoặc
rclone config
```

### 4. Cấu hình script backup

Sửa các biến trong `scripts/backup_postgresql.sh`:

```bash
CONTAINER="your_postgresql_container"
REMOTE="your-remote:backup-path"
BACKUP_DIR="/path/to/backups"
```

### 5. Test backup

```bash
bash scripts/test_backup.sh
```

### 6. Setup cron job

```bash
crontab -e
# Thêm dòng sau (chạy hàng ngày lúc 2:36 AM)
36 2 * * * /bin/bash /path/to/scripts/cron_backup.sh >/dev/null 2>&1
```

## 📁 Cấu trúc Project

```
backup-rclone/
├── scripts/
│   ├── backup_postgresql.sh    # Script backup chính
│   ├── test_backup.sh          # Script test backup
│   ├── setup_rclone.sh         # Script setup Rclone
│   └── cron_backup.sh          # Cron wrapper script
└── documentation/
    └── SETUP_GUIDE.md          # Hướng dẫn chi tiết
```

## 🔧 Cấu hình

### Retention Policy

Mặc định:
- **Daily**: 7 ngày
- **Weekly**: 12 tuần (84 ngày)
- **Monthly**: 12 tháng (365 ngày)

Có thể thay đổi trong script `backup_postgresql.sh`.

### Webhook Notification

Để enable webhook, thêm `WEBHOOK_URL` vào script:

```bash
WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

Format payload: JSON với thông tin backup (success/failed, số databases, duration, etc.)

## 📊 Backup Structure trên Google Drive

```
your-remote:backup-path/
├── daily/
│   ├── database1_backup_20251101_114649.dump.gz
│   ├── database2_backup_20251101_114649.dump.gz
│   └── full_backup_all_20251101_114649.sql.gz
├── weekly/
│   └── ... (copied từ daily mỗi Chủ nhật)
└── monthly/
    └── ... (copied từ daily mỗi ngày 1)
```

## 🔄 Restore

### Restore một database

```bash
rclone cat your-remote:backup-path/daily/database_backup_20251101.dump.gz | \
  gunzip | \
  docker exec -i postgresql_container pg_restore -U postgres -d database_name --clean --if-exists
```

### Restore full backup

```bash
rclone cat your-remote:backup-path/daily/full_backup_all_20251101.sql.gz | \
  gunzip | \
  docker exec -i postgresql_container psql -U postgres
```

## 📖 Documentation

Xem [SETUP_GUIDE.md](documentation/SETUP_GUIDE.md) để biết hướng dẫn chi tiết.

## ⚠️ Troubleshooting

### Rclone token hết hạn

```bash
rclone config reconnect your-remote:
```

### Backup fail

1. Kiểm tra kết nối: `rclone lsd your-remote:`
2. Kiểm tra container: `docker ps | grep postgres`
3. Xem logs: `cat /path/to/backups/logs/backup_*.log`

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 License

MIT License - Xem file LICENSE để biết chi tiết.

## 🙏 Acknowledgments

- [Rclone](https://rclone.org/) - Tool để sync files với cloud storage
- PostgreSQL - Database system

## 📞 Support

Nếu gặp vấn đề, vui lòng tạo issue trên GitHub repository.


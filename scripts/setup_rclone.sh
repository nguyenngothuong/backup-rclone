#!/bin/bash
# Setup Rclone với Google Drive
# Mục đích: Hướng dẫn cấu hình Rclone để backup lên Google Drive
# License: MIT

echo "=========================================="
echo "Cấu hình Rclone với Google Drive"
echo "=========================================="
echo ""

# Kiểm tra Rclone đã cài chưa
if ! command -v rclone &> /dev/null; then
    echo "❌ Rclone chưa được cài đặt!"
    echo ""
    echo "Cài đặt Rclone:"
    echo "  curl https://rclone.org/install.sh | sudo bash"
    echo ""
    exit 1
fi

echo "✅ Rclone đã được cài đặt: $(rclone version | head -n1)"
echo ""

# Backup config cũ nếu có
if [ -f ~/.config/rclone/rclone.conf ]; then
    BACKUP_FILE=~/.config/rclone/rclone.conf.backup.$(date +%Y%m%d_%H%M%S)
    cp ~/.config/rclone/rclone.conf "$BACKUP_FILE"
    echo "✅ Đã backup config cũ: $BACKUP_FILE"
    echo ""
fi

echo "=========================================="
echo "Cấu hình Rclone"
echo "=========================================="
echo ""
echo "Chạy lệnh sau để cấu hình Rclone:"
echo ""
echo "  rclone config"
echo ""
echo "Chọn các options sau:"
echo "  n          -> New remote"
echo "  <name>     -> Tên remote (ví dụ: gdrive)"
echo "  drive      -> Storage type (chọn Google Drive)"
echo "  [Enter]    -> Client ID (dùng mặc định hoặc nhập từ Google Cloud Console)"
echo "  [Enter]    -> Client Secret (dùng mặc định hoặc nhập từ Google Cloud Console)"
echo "  n          -> Advanced config? No"
echo "  y          -> Use auto config? Yes (cần browser)"
echo "  [Enter]    -> Service Account File (để trống nếu không dùng)"
echo "  drive.file -> Scope (hoặc drive cho full access)"
echo "  n          -> Root folder ID (để trống)"
echo "  n          -> Share With Me (No)"
echo "  y          -> Use Shared Drive (No)"
echo "  y          -> Server Side Across Configs (Yes)"
echo "  q          -> Quit"
echo ""
echo "=========================================="
echo "Sau khi cấu hình xong, kiểm tra kết nối:"
echo "=========================================="
echo ""
echo "  rclone lsd <remote-name>:"
echo "  rclone about <remote-name>:"
echo ""
echo "Ví dụ:"
echo "  rclone lsd gdrive:"
echo "  rclone about gdrive:"
echo ""


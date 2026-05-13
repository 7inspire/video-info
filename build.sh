#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PKG_ROOT="$BUILD_DIR/pkg_root"
PKG_OUTPUT="$BUILD_DIR/VideoInfoTool.pkg"

echo "=== 构建视频信息工具 ==="

# 清理
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$PKG_ROOT/usr/local/bin"
mkdir -p "$PKG_ROOT/Library/Services"

# 1. 编译 Swift 脚本为可执行文件
echo ">>> 编译 video_info..."
swiftc "$SCRIPT_DIR/scripts/video_info.swift" \
    -o "$BUILD_DIR/video_info" \
    -O \
    -framework AVFoundation \
    -framework CoreMedia \
    -framework Foundation

# 复制到 pkg 根目录
cp "$BUILD_DIR/video_info" "$PKG_ROOT/usr/local/bin/video_info"
chmod 755 "$PKG_ROOT/usr/local/bin/video_info"

# 2. 复制 workflow
echo ">>> 复制 workflow..."
cp -R "$SCRIPT_DIR/workflow/查看视频信息.workflow" "$PKG_ROOT/Library/Services/"

# 3. 创建 postinstall 脚本（刷新服务菜单）
mkdir -p "$BUILD_DIR/scripts"
cat > "$BUILD_DIR/scripts/postinstall" << 'EOF'
#!/bin/bash
# 刷新 Services 菜单，使新安装的 Quick Action 立即可用
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
# 通知 Finder 刷新
killall Finder 2>/dev/null || true
exit 0
EOF
chmod 755 "$BUILD_DIR/scripts/postinstall"

# 4. 构建 pkg
echo ">>> 构建 pkg 安装包..."
pkgbuild \
    --root "$PKG_ROOT" \
    --scripts "$BUILD_DIR/scripts" \
    --identifier "com.videoinfo.tool" \
    --version "1.0.0" \
    --install-location "/" \
    "$PKG_OUTPUT"

echo ""
echo "=== 构建完成 ==="
echo "安装包位置: $PKG_OUTPUT"
echo ""
echo "安装后："
echo "  - video_info 命令: /usr/local/bin/video_info"
echo "  - Quick Action: /Library/Services/查看视频信息.workflow"
echo ""
echo "使用方法："
echo "  1. 双击 VideoInfoTool.pkg 安装"
echo "  2. 在 Finder 中右键任意视频文件"
echo "  3. 选择 快速操作 → 查看视频信息"

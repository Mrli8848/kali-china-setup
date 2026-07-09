#!/bin/bash
# ============================================================================
#  加密构建器 — 将原始脚本加密为自解密脚本
#  Author: Mr.li8848
#  用法: bash build-encrypted.sh
#  说明: 使用文件管道方式构建，避免 shell 变量截断
# ============================================================================
set -e

ORIGINAL="./kali-china-setup.sh"
OUTPUT="./kali-china-setup-encrypted.sh"
PASSWORD="l9l7o3i3ecf7"
HEADER_FILE="/tmp/kali-header.sh"
PAYLOAD_FILE="/tmp/kali-payload.b64"

# ── 检查依赖 ──
if [ ! -f "$ORIGINAL" ]; then
    echo "错误: 找不到 $ORIGINAL"
    exit 1
fi

if ! command -v openssl &>/dev/null; then
    echo "错误: 需要 openssl"
    exit 1
fi

echo "[*] 原始脚本: $ORIGINAL ($(wc -l < "$ORIGINAL") 行)"

# ── Step 1: 生成自解密头部 ──
cat > "$HEADER_FILE" << 'HEADER_EOF'
#!/bin/bash
# ============================================================================
#
#   ██╗  ██╗ █████╗ ██╗     ██╗
#   ██║ ██╔╝██╔══██╗██║     ██║
#   █████╔╝ ███████║██║     ██║
#   ██╔═██╗ ██╔══██║██║     ██║
#   ██║  ██╗██║  ██║███████╗██║
#   ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝
#
#   Kali 全方位配置脚本 — 加密版 v3.0
#   Author : Mr.li8848
#   ⚠  运行时需要输入解密密码
#
# ============================================================================

set -e

# ── 颜色 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

echo ""
echo -e "  ${BOLD}${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}${CYAN}║   Kali 全方位配置脚本 v3.0 — 加密版        ║${NC}"
echo -e "  ${BOLD}${CYAN}║   Author: Mr.li8848                         ║${NC}"
echo -e "  ${BOLD}${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# 检查 root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "  ${RED}⛔ 请使用 sudo 运行此脚本！${NC}"
    exit 1
fi

# 检查 openssl
if ! command -v openssl &>/dev/null; then
    echo -e "  ${RED}⛔ 此脚本需要 openssl 才能解密运行${NC}"
    echo -e "  ${YELLOW}请先安装: sudo apt install openssl${NC}"
    exit 1
fi

MAX_TRIES=3
TRIES=0

while [ $TRIES -lt $MAX_TRIES ]; do
    echo ""
    echo -ne "  ${YELLOW}🔑 请输入解密密码: ${NC}"
    read -s PASSWORD
    echo ""

    if [ -z "$PASSWORD" ]; then
        echo -e "  ${RED}密码不能为空！${NC}"
        TRIES=$((TRIES + 1))
        continue
    fi

    echo -ne "  ${DIM}正在解密...${NC}"

    # 从脚本自身提取加密载荷（文件管道方式，避免 shell echo 转义）
    PAYLOAD_B64=$(sed -n '/^__PAYLOAD_START__$/,/^__PAYLOAD_END__$/p' "$0" | sed '1d;$d')

    # 创建临时文件存放解密结果
    TMPFILE=$(mktemp /tmp/kali-setup-XXXXXX.sh)
    chmod 700 "$TMPFILE"

    # openssl 直接输出到文件，不经过 shell 变量
    printf '%s' "$PAYLOAD_B64" | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -d -base64 \
        -pass pass:"$PASSWORD" -out "$TMPFILE" 2>/dev/null && DECRYPT_OK=1 || DECRYPT_OK=0

    # 验证文件合法性
    if [ "$DECRYPT_OK" = "1" ] && [ -s "$TMPFILE" ] && head -1 "$TMPFILE" | grep -q '^#!/bin/bash'; then
        echo -e " ${GREEN}✓ 解密成功${NC}"
        echo ""

        cleanup() {
            if [ -f "$TMPFILE" ]; then
                shred -u "$TMPFILE" 2>/dev/null || rm -f "$TMPFILE"
            fi
        }
        trap cleanup EXIT

        bash "$TMPFILE"
        exit $?
    else
        rm -f "$TMPFILE"
        echo -e " ${RED}✗ 密码错误${NC}"
        TRIES=$((TRIES + 1))
        if [ $TRIES -lt $MAX_TRIES ]; then
            echo -e "  ${DIM}剩余尝试次数: $((MAX_TRIES - TRIES))${NC}"
        fi
    fi
done

echo ""
echo -e "  ${RED}⛔ 密码错误次数过多，脚本退出。${NC}"
echo -e "  ${DIM}如需重置，请联系脚本提供者。${NC}"
echo ""
exit 1

# ═══════════════════════════════════════════════════════════════
#  以下是加密载荷 (AES-256-CBC + PBKDF2)
#  请勿修改以下标记行之间的内容
# ═══════════════════════════════════════════════════════════════
__PAYLOAD_START__
HEADER_EOF

echo "[*] 头部生成完毕 ($(wc -l < "$HEADER_FILE") 行)"

# ── Step 2: 加密原始脚本 → 直接写入文件 ──
openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -pass pass:"$PASSWORD" -base64 \
    < "$ORIGINAL" > "$PAYLOAD_FILE"
echo "[*] 加密载荷: $(wc -l < "$PAYLOAD_FILE") 行 ($(wc -c < "$PAYLOAD_FILE") bytes)"

# ── Step 3: 拼接最终脚本 (文件级拼接，不经过 shell 变量) ──
cat "$HEADER_FILE" > "$OUTPUT"
cat "$PAYLOAD_FILE" >> "$OUTPUT"
echo "__PAYLOAD_END__" >> "$OUTPUT"
chmod +x "$OUTPUT"
echo "[*] 加密脚本: $OUTPUT ($(wc -l < "$OUTPUT") 行)"

# ── Step 4: 完整验证 ──
echo ""
echo "═══════════════════════════════════════════"

# 4.1 提取并解密，验证与原始一致
sed -n '/^__PAYLOAD_START__$/,/^__PAYLOAD_END__$/p' "$OUTPUT" | sed '1d;$d' > /tmp/verify-payload.b64
openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -d -base64 -pass pass:"$PASSWORD" \
    -in /tmp/verify-payload.b64 -out /tmp/verify-decrypted.sh 2>/dev/null

if diff "$ORIGINAL" /tmp/verify-decrypted.sh > /dev/null 2>&1; then
    echo "  内容验证:  与原始一致 ✓"
else
    echo "  内容验证:  不一致 ✗ (构建失败)"
    rm -f "$HEADER_FILE" "$PAYLOAD_FILE" /tmp/verify-payload.b64 /tmp/verify-decrypted.sh
    exit 1
fi

# 4.2 语法检查
SYNTAX_OUT=$(bash -n /tmp/verify-decrypted.sh 2>&1) && SYNTAX_OK=1 || SYNTAX_OK=0
if [ "$SYNTAX_OK" = "1" ] && [ -z "$SYNTAX_OUT" ]; then
    echo "  语法检查:  完全通过 ✓ (零警告)"
else
    echo "  语法检查:  有警告 ⚠"
    echo "$SYNTAX_OUT"
fi

# 4.3 错误密码测试
printf '%s' "$(sed -n '/^__PAYLOAD_START__$/,/^__PAYLOAD_END__$/p' "$OUTPUT" | sed '1d;$d')" | \
    openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -d -base64 -pass pass:"wrong" -out /tmp/verify-wrong.sh 2>/dev/null
if [ -s /tmp/verify-wrong.sh ] && head -1 /tmp/verify-wrong.sh 2>/dev/null | grep -q '^#!/bin/bash'; then
    echo "  密码防护:  失败 ✗ (错误密码不应解密成功)"
else
    echo "  密码防护:  正常 ✓"
fi

# 清理
rm -f "$HEADER_FILE" "$PAYLOAD_FILE" /tmp/verify-payload.b64 /tmp/verify-decrypted.sh /tmp/verify-wrong.sh

echo "═══════════════════════════════════════════"
echo ""
echo "  ✓ 构建成功: $OUTPUT"
echo "  密码: $PASSWORD"
echo ""

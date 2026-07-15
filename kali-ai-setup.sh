#!/bin/bash
# ============================================================================
#   Kali AI + 中文可视化 一站式部署 v3.0
#   Author : Mr.li8848
#   Usage  : sudo bash kali-ai-setup.sh
#
#   ① Docker Engine
#   ② LobeChat (开机自启 + API 留空 + 模型可选)
#   ③ Chrome 浏览器 (Web Speech API)
#   ④ 声卡检测 + 网页语音
#   ⑤ 中文可视化 (语言包/字体/输入法/Xfce 主题)
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

LOG_FILE="/tmp/kali-ai-setup-$(date +%Y%m%d-%H%M%S).log"
LOBE_PORT=3210
CONTAINER_NAME="lobe-chat"

log_msg()   { echo -e "$1" | tee -a "$LOG_FILE"; }
step_ok()   { log_msg "   ${GREEN}✓${NC}  $1"; }
step_warn() { log_msg "   ${YELLOW}⚠${NC}  $1"; }
step_err()  { log_msg "   ${RED}✗${NC}  $1"; }
step_info() { log_msg "   ${CYAN}→${NC}  $1"; }

banner() {
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    printf "  ║  %-54s ║\n" "$1"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

confirm_yes() {
    local answer
    read -p "$(echo -e "   ${YELLOW}${1} [Y/n]: ${NC}")" answer
    [[ ! "$answer" =~ ^[Nn] ]]
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}⛔ 请使用 sudo 运行！${NC}"
        echo "   sudo bash $0"
        exit 1
    fi
}

# ============================================================================
#  ① Docker
# ============================================================================
step_docker() {
    banner "① 安装 Docker Engine"

    if command -v docker &>/dev/null; then
        step_ok "$(docker --version) — 已安装"
        return
    fi

    apt update -y

    # 优先 Kali 自带 docker.io，走国内镜像，不受 GFW 干扰
    step_info "安装 docker.io (Kali 官方源)..."
    if apt install -y docker.io docker-compose 2>/dev/null; then
        step_ok "docker.io 安装成功"
    else
        # 备用: Docker 官方源
        step_warn "docker.io 失败，尝试 Docker 官方源..."

        local DEBIAN_CODENAME="" DEBIAN_VER KALI_YEAR
        DEBIAN_VER=$(cat /etc/debian_version 2>/dev/null | cut -d. -f1)
        case "$DEBIAN_VER" in
            13) DEBIAN_CODENAME="trixie" ;;
            12) DEBIAN_CODENAME="bookworm" ;;
            11) DEBIAN_CODENAME="bullseye" ;;
            kali-rolling|*)
                KALI_YEAR=$(grep -oP 'VERSION_ID="\K\d{4}' /etc/os-release 2>/dev/null || echo "0")
                case "$KALI_YEAR" in
                    2026|2025) DEBIAN_CODENAME="trixie" ;;
                    *)         DEBIAN_CODENAME="bookworm" ;;
                esac
                ;;
        esac
        step_info "Debian 基版: ${DEBIAN_CODENAME}"

        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${DEBIAN_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

        apt update -y
        apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || {
            step_err "Docker 安装失败，请检查网络"
            rm -f /etc/apt/sources.list.d/docker.list
            return 1
        }
    fi

    systemctl enable docker --now 2>/dev/null || true
    [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG docker "$SUDO_USER" 2>/dev/null || true
    step_ok "Docker 安装完成 — $(docker --version)"
}

# ============================================================================
#  ② LobeChat
# ============================================================================
step_lobechat() {
    banner "② 部署 LobeChat（开机自启 + 自动配置 API）"

    echo -e "   ${DIM}开源聊天 UI | 支持 30+ LLM | 自带 Web Speech 语音输入${NC}"
    echo -e "   ${DIM}https://github.com/lobehub/lobe-chat${NC}"
    echo ""

    if ! command -v docker &>/dev/null; then
        step_err "Docker 未安装，请先执行步骤 ①"
        return 1
    fi

    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    # API Key — 可在部署时填入，也可跳过后续在 Web 界面配
    local API_KEY=""
    echo -e "   ${BOLD}${WHITE}API Key 配置:${NC}"
    echo -e "   ${DIM}粘贴后脚本自动注入容器，回车跳过则在 Web 界面手动配${NC}"
    echo ""
    read -p "$(echo -e "   ${YELLOW}阿里云百炼 API Key [sk-xxx，回车跳过]: ${NC}")" API_KEY

    if [ -n "$API_KEY" ]; then
        if [[ "$API_KEY" =~ ^sk-[a-zA-Z0-9]+$ ]]; then
            step_ok "API Key 格式检查通过"
        else
            step_warn "API Key 格式异常，但仍会注入（稍后可在 Web 界面修正）"
        fi
    else
        step_info "未提供 API Key — 部署后需在 LobeChat Web 界面手动填入"
    fi

    # 访问密码
    local ACCESS_PASSWORD
    read -p "$(echo -e "   ${YELLOW}设置 LobeChat 访问密码（回车跳过）: ${NC}")" ACCESS_PASSWORD

    # 端口
    read -p "$(echo -e "   ${YELLOW}Web 端口 [默认 ${LOBE_PORT}]: ${NC}")" CUSTOM_PORT
    LOBE_PORT="${CUSTOM_PORT:-$LOBE_PORT}"

    step_info "拉取镜像（约 500MB）..."

    local DOCKER_ARGS=(-d --name "$CONTAINER_NAME" --restart unless-stopped -p "${LOBE_PORT}:3210")

    [ -n "$ACCESS_PASSWORD" ] && DOCKER_ARGS+=(-e "ACCESS_CODE=${ACCESS_PASSWORD}")

    # 百炼兼容端点
    DOCKER_ARGS+=(-e "OPENAI_PROXY_URL=https://dashscope.aliyuncs.com/compatible-mode/v1")

    # 如果用户填了 API Key，直接注入
    if [ -n "$API_KEY" ]; then
        DOCKER_ARGS+=(-e "OPENAI_API_KEY=${API_KEY}")
    fi

    # 预设可用模型列表（百炼兼容端点不支持 Get Model List，需要手动指定）
    DOCKER_ARGS+=(-e "OPENAI_MODEL_LIST=-all,qwen-turbo,qwen-plus,qwen-max,qwen-max-longcontext")

    docker run "${DOCKER_ARGS[@]}" lobehub/lobe-chat || {
        step_err "容器启动失败，检查网络。"
        return 1
    }

    sleep 3
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && \
        step_ok "LobeChat 运行中 — 已设置开机自启 (--restart unless-stopped)" || {
        step_err "容器异常"
        docker logs "$CONTAINER_NAME" 2>/dev/null | tail -20
        return 1
    }

    echo ""
    if [ -n "$API_KEY" ]; then
        echo -e "   ${GREEN}${BOLD}✓ API Key 已自动注入，打开浏览器即可使用！${NC}"
        echo ""
    fi
    echo -e "   ${BOLD}访问地址:${NC} ${CYAN}http://localhost:${LOBE_PORT}${NC}"
    echo -e "   ${BOLD}可用模型:${NC} qwen-turbo / qwen-plus / qwen-max / qwen-max-longcontext"
}

# ============================================================================
#  ③ Chrome 浏览器
# ============================================================================
step_browser() {
    banner "③ 安装 Chrome 浏览器"

    if command -v google-chrome-stable &>/dev/null; then
        step_ok "Google Chrome 已安装 — $(google-chrome-stable --version)"
        return
    fi

    # 方法一: 直接下载 .deb
    step_info "尝试下载 Chrome .deb..."
    if curl -fsSL -o /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb 2>/dev/null; then
        apt install -y /tmp/chrome.deb 2>/dev/null && rm -f /tmp/chrome.deb
    fi
    rm -f /tmp/chrome.deb

    if command -v google-chrome-stable &>/dev/null; then
        step_ok "Google Chrome 安装完成 — $(google-chrome-stable --version)"
        return
    fi

    # 方法二: Google APT 源 (更可靠)
    step_warn ".deb 下载失败，切换 APT 源安装"
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg 2>/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
    apt update -y 2>/dev/null || true
    apt install -y google-chrome-stable 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/google-chrome.list

    if command -v google-chrome-stable &>/dev/null; then
        step_ok "Google Chrome 安装完成 — $(google-chrome-stable --version)"
    else
        step_warn "Chrome 安装失败，改用 Chromium"
        apt install -y chromium 2>/dev/null || true
    fi
}

# ============================================================================
#  ④ 声卡 + 网页语音
# ============================================================================
step_voice() {
    banner "④ VMware 声卡检测 + LobeChat 网页语音"

    echo ""
    echo -e "   ${BOLD}${WHITE}声卡检测:${NC}"
    echo ""

    local SOUND_OK=1

    if cat /proc/asound/cards 2>/dev/null | grep -q '\[.*\]'; then
        echo -e "   ${GREEN}声卡已识别:${NC}"
        cat /proc/asound/cards | grep '\[' | while read line; do
            echo -e "     ${CYAN}${line}${NC}"
        done
    else
        echo -e "   ${RED}未检测到声卡${NC}"
        SOUND_OK=0
    fi

    echo ""
    if amixer sget Capture 2>/dev/null | grep -q 'Capture' || arecord -l 2>/dev/null | grep -q 'card'; then
        echo -e "   ${GREEN}录音设备已识别${NC}"
    else
        echo -e "   ${YELLOW}未检测到麦克风${NC}"
        SOUND_OK=0
    fi

    apt install -y pulseaudio pavucontrol alsa-utils 2>/dev/null || true

    if [ $SOUND_OK -eq 0 ]; then
        echo ""
        echo -e "   ${YELLOW}${BOLD}VMware 声卡映射检查:${NC}"
        echo -e "   ${CYAN}1.${NC} 关闭 Kali → VMware 设置 → 硬件 → 声卡"
        echo -e "   ${CYAN}2.${NC} 勾选: ${BOLD}已连接${NC} + ${BOLD}启动时连接${NC}"
        echo -e "   ${CYAN}3.${NC} 声卡类型: ${BOLD}Intel HD Audio${NC} → 重启"
        echo ""
    fi

    echo ""
    echo -e "   ${BOLD}${WHITE}LobeChat 网页语音使用方式:${NC}"
    echo -e "   ${CYAN}1.${NC} Chrome 打开 ${GREEN}http://localhost:${LOBE_PORT}${NC}"
    echo -e "   ${CYAN}2.${NC} 点击输入框右侧 ${BOLD}🎤 麦克风图标${NC}"
    echo -e "   ${CYAN}3.${NC} 浏览器弹窗请求麦克风权限 → ${BOLD}允许${NC}"
    echo -e "   ${CYAN}4.${NC} 说话 → 实时转文字 → Enter 发送"
    echo -e "   ${YELLOW}首次使用自动下载语音模型（约 50MB），需联网${NC}"
    echo ""

    step_ok "声卡检查完毕"
}

# ============================================================================
#  ⑤ 中文可视化
# ============================================================================
step_chinese() {
    banner "⑤ 中文可视化 — 语言 · 字体 · 输入法 · 主题"

    # ── 5.1 语言包 ──
    echo ""
    echo -e "   ${BOLD}5.1${NC} 中文语言包 + 系统语言切换"
    echo ""
    if confirm_yes "安装中文语言包并设为默认？"; then
        if [ -f /etc/locale.gen ]; then
            sed -i 's/^#\s*zh_CN.UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
            grep -q "^zh_CN.UTF-8" /etc/locale.gen || echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
            locale-gen 2>/dev/null || true
        fi

        cat > /etc/default/locale << 'LOCALEOF'
LANG=zh_CN.UTF-8
LC_ALL=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LOCALEOF
        update-locale LANG=zh_CN.UTF-8 2>/dev/null || true

        cat > /etc/profile.d/kali-zh-locale.sh << 'ENVEOF'
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
export LANGUAGE=zh_CN:zh
ENVEOF
        chmod +x /etc/profile.d/kali-zh-locale.sh
        grep -q "LANG=zh_CN.UTF-8" /etc/environment 2>/dev/null || echo "LANG=zh_CN.UTF-8" >> /etc/environment
        step_ok "系统语言已切换为简体中文"
    fi

    # ── 5.2 中文字体 ──
    echo ""
    echo -e "   ${BOLD}5.2${NC} 中文字体（防乱码）"
    echo ""
    if confirm_yes "安装中文字体？"; then
        apt install -y fonts-wqy-zenhei fonts-wqy-microhei fonts-noto-cjk 2>/dev/null || \
        apt install -y fonts-wqy-zenhei fonts-wqy-microhei 2>/dev/null || true
        step_ok "中文字体安装完成"
    fi

    # ── 5.3 中文输入法 ──
    echo ""
    echo -e "   ${BOLD}5.3${NC} 中文输入法"
    echo ""
    if confirm_yes "安装 fcitx5 拼音输入法？"; then
        apt install -y fcitx5 fcitx5-chinese-addons \
            fcitx5-frontend-gtk3 fcitx5-frontend-gtk2 \
            fcitx5-frontend-qt5 fcitx5-frontend-qt6 2>/dev/null || \
        apt install -y fcitx fcitx-googlepinyin 2>/dev/null || true

        cat > /etc/profile.d/kali-fcitx.sh << 'FCITXEOF'
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
FCITXEOF
        chmod +x /etc/profile.d/kali-fcitx.sh
        step_ok "fcitx5 拼音已安装"
        step_info "重启后执行 fcitx5-configtool 添加拼音输入法"
    fi

    # ── 5.4 Xfce 主题 ──
    echo ""
    echo -e "   ${BOLD}5.4${NC} Xfce 桌面主题美化"
    echo ""
    if confirm_yes "安装并应用美观的 Xfce 主题？"; then
        apt install -y gtk2-engines-pixbuf 2>/dev/null || true
        apt install -y papirus-icon-theme greybird-gtk-theme arc-theme 2>/dev/null || \
        apt install -y papirus-icon-theme greybird-gtk-theme 2>/dev/null || true
        apt install -y breeze-cursor-theme fonts-firacode 2>/dev/null || true

        # 自动应用主题 — 需要 D-Bus 会话总线才能操作 xfconf
        if command -v xfconf-query &>/dev/null && [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
            local USER_ID
            USER_ID=$(id -u "$SUDO_USER" 2>/dev/null)
            local DBUS="unix:path=/run/user/${USER_ID}/bus"

            sudo -u "$SUDO_USER" env DBUS_SESSION_BUS_ADDRESS="$DBUS" DISPLAY=:0 \
                xfconf-query -c xfwm4 -p /general/theme -s Greybird 2>/dev/null || true
            sudo -u "$SUDO_USER" env DBUS_SESSION_BUS_ADDRESS="$DBUS" DISPLAY=:0 \
                xfconf-query -c xsettings -p /Net/ThemeName -s Greybird 2>/dev/null || true
            sudo -u "$SUDO_USER" env DBUS_SESSION_BUS_ADDRESS="$DBUS" DISPLAY=:0 \
                xfconf-query -c xsettings -p /Net/IconThemeName -s Papirus 2>/dev/null || true
            sudo -u "$SUDO_USER" env DBUS_SESSION_BUS_ADDRESS="$DBUS" DISPLAY=:0 \
                xfconf-query -c xfwm4 -p /general/title_font -s "Noto Sans CJK SC 10" 2>/dev/null || true
            sudo -u "$SUDO_USER" env DBUS_SESSION_BUS_ADDRESS="$DBUS" DISPLAY=:0 \
                xfconf-query -c xsettings -p /Gtk/CursorThemeName -s Breeze 2>/dev/null || true
            step_ok "已自动应用: Greybird 窗口 + Papirus 图标 + Breeze 光标"
        else
            step_ok "主题已安装: Greybird + Papirus + Breeze"
            step_info "Kali 菜单 → 设置 → 外观 → 手动选择主题和图标"
        fi
    fi

    echo ""
    echo -e "   ${GREEN}${BOLD}中文可视化配置完成${NC}"
    echo -e "   ${YELLOW}重启后全部生效: sudo reboot${NC}"
}

# ============================================================================
#  显示汇总
# ============================================================================
show_summary() {
    local KALI_IP
    KALI_IP=$(ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
    [ -z "$KALI_IP" ] && KALI_IP="localhost"

    echo ""
    echo -e "  ${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║         ✓  部署完成                                     ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "  ${NC}"
    echo ""
    echo -e "  ${BOLD}LobeChat:${NC}  ${CYAN}http://localhost:${LOBE_PORT}${NC}"
    [ "$KALI_IP" != "localhost" ] && echo -e "  外网访问:  ${CYAN}http://${KALI_IP}:${LOBE_PORT}${NC}"
    echo ""
    echo -e "  ${BOLD}API 配置:${NC}  右上角 ⚙ → 语言模型 → OpenAI → 填入 Key"
    echo -e "  代理地址:  ${CYAN}https://dashscope.aliyuncs.com/compatible-mode/v1${NC}"
    echo ""
    echo -e "  ${BOLD}语音输入:${NC}  Chrome 打开 → 输入框旁 🎤 → 允许麦克风 → 说话"
    echo -e "  ${BOLD}中文界面:${NC}  重启后生效"
    echo ""
    echo -e "  ${DIM}日志: ${LOG_FILE}${NC}"
    echo ""
}

# ============================================================================
#  主菜单
# ============================================================================
main_menu() {
    while true; do
        clear
        echo ""
        echo -e "  ${BOLD}${CYAN}"
        echo "  ╔══════════════════════════════════════════════════════════╗"
        echo "  ║       Kali AI + 中文可视化 一站式部署 v3.0             ║"
        echo "  ║       Author: Mr.li8848                                 ║"
        echo "  ╚══════════════════════════════════════════════════════════╝"
        echo -e "  ${NC}"

        echo ""
        echo -e "  ${BOLD}${WHITE}选择要执行的步骤（可单独运行）:${NC}"
        echo ""
        echo -e "  ${GREEN}${BOLD}  [1]${NC}  安装 Docker Engine"
        echo -e "  ${CYAN}${BOLD}  [2]${NC}  部署 LobeChat (开机自启 + API 留空 + 选择模型)"
        echo -e "  ${MAGENTA}${BOLD}  [3]${NC}  安装 Chrome 浏览器"
        echo -e "  ${YELLOW}${BOLD}  [4]${NC}  声卡检测 + LobeChat 网页语音配置"
        echo -e "  ${RED}${BOLD}  [5]${NC}  中文可视化 (语言包/字体/输入法/Xfce 主题)"
        echo ""
        echo -e "  ${WHITE}${BOLD}  [A]${NC}  一键全部部署"
        echo -e "  ${DIM}  [S]${NC}  ${DIM}显示汇总信息${NC}"
        echo -e "  ${DIM}  [Q]${NC}  ${DIM}退出${NC}"
        echo ""
        echo -e "  ${DIM}──────────────────────────────────────────────────────────${NC}"
        echo -e "  ${DIM}日志: ${LOG_FILE}${NC}"
        echo ""

        local CHOICE
        read -p "$(echo -e "  ${YELLOW}请选择 [1-5/A/S/Q]: ${NC}")" CHOICE

        case "$CHOICE" in
            1) step_docker ;;
            2) step_lobechat ;;
            3) step_browser ;;
            4) step_voice ;;
            5) step_chinese ;;
            A|a)
                step_docker
                step_lobechat
                step_browser
                step_voice
                step_chinese
                show_summary
                ;;
            S|s) show_summary ;;
            Q|q)
                echo -e "  ${GREEN}退出 — 日志: ${LOG_FILE}${NC}"
                echo ""
                exit 0
                ;;
            *) echo -e "  ${RED}无效选项${NC}"; sleep 0.5 ;;
        esac

        if [[ "$CHOICE" =~ ^[1-5]$ ]] || [[ "$CHOICE" =~ ^[Aa]$ ]]; then
            echo ""
            read -p "$(echo -e "   ${DIM}按 Enter 返回菜单...${NC}")" _
        fi
        if [[ "$CHOICE" =~ ^[Ss]$ ]]; then
            read -p "$(echo -e "   ${DIM}按 Enter 返回菜单...${NC}")" _
        fi
    done
}

# ============================================================================
#  入口
# ============================================================================
check_root

cat > "$LOG_FILE" << SETUPLOG
═══════════════════════════════════════════
  Kali AI + 中文可视化 部署日志
  时间: $(date '+%Y-%m-%d %H:%M:%S')
  v3.0 — Mr.li8848
═══════════════════════════════════════════

SETUPLOG

main_menu

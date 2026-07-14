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

    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    apt update -y
    apt install -y ca-certificates curl

    local DEBIAN_CODENAME
    if [ -f /etc/debian_version ]; then
        case "$(cat /etc/debian_version | cut -d. -f1)" in
            13) DEBIAN_CODENAME="trixie" ;;
            12) DEBIAN_CODENAME="bookworm" ;;
            11) DEBIAN_CODENAME="bullseye" ;;
            *)  DEBIAN_CODENAME="bookworm" ;;
        esac
    else
        DEBIAN_CODENAME="bookworm"
    fi
    step_info "Debian 基版: ${DEBIAN_CODENAME}"

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${DEBIAN_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

    apt update -y
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker --now 2>/dev/null || true

    [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG docker "$SUDO_USER" 2>/dev/null || true
    step_ok "Docker 安装完成 — $(docker --version)"
}

# ============================================================================
#  ② LobeChat
# ============================================================================
step_lobechat() {
    banner "② 部署 LobeChat（开机自启 + API 留空 + 模型可选）"

    echo -e "   ${DIM}开源聊天 UI | 支持 30+ LLM | 自带 Web Speech 语音输入${NC}"
    echo -e "   ${DIM}https://github.com/lobehub/lobe-chat${NC}"
    echo ""

    # 检查 Docker
    if ! command -v docker &>/dev/null; then
        step_err "Docker 未安装，请先执行步骤 ①"
        return 1
    fi

    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    # 访问密码
    local ACCESS_PASSWORD
    read -p "$(echo -e "   ${YELLOW}设置 LobeChat 访问密码（回车跳过）: ${NC}")" ACCESS_PASSWORD

    # 端口
    read -p "$(echo -e "   ${YELLOW}Web 端口 [默认 ${LOBE_PORT}]: ${NC}")" CUSTOM_PORT
    LOBE_PORT="${CUSTOM_PORT:-$LOBE_PORT}"

    # 模型选择
    echo ""
    echo -e "   ${BOLD}${WHITE}选择默认模型:${NC}"
    echo -e "   ${CYAN}1${NC}) qwen-turbo            最快最省"
    echo -e "   ${CYAN}2${NC}) qwen-plus             均衡推荐（默认）"
    echo -e "   ${CYAN}3${NC}) qwen-max              最强推理"
    echo -e "   ${CYAN}4${NC}) qwen-max-longcontext   超长上下文"
    echo -e "   ${CYAN}5${NC}) 不预设，Web 界面里自己配"
    echo ""

    local DEFAULT_MODEL="qwen-plus"
    read -p "$(echo -e "   ${YELLOW}选择 [1-5，默认 2]: ${NC}")" MODEL_CHOICE
    case "${MODEL_CHOICE:-2}" in
        1) DEFAULT_MODEL="qwen-turbo" ;;
        2) DEFAULT_MODEL="qwen-plus" ;;
        3) DEFAULT_MODEL="qwen-max" ;;
        4) DEFAULT_MODEL="qwen-max-longcontext" ;;
        5) DEFAULT_MODEL="" ;;
    esac

    step_info "拉取镜像（约 500MB）..."

    local DOCKER_ARGS=(-d --name "$CONTAINER_NAME" --restart unless-stopped -p "${LOBE_PORT}:3210")

    [ -n "$ACCESS_PASSWORD" ] && DOCKER_ARGS+=(-e "ACCESS_CODE=${ACCESS_PASSWORD}")
    DOCKER_ARGS+=(-e "OPENAI_PROXY_URL=https://dashscope.aliyuncs.com/compatible-mode/v1")
    [ -n "$DEFAULT_MODEL" ] && DOCKER_ARGS+=(-e "OPENAI_MODEL_LIST=-all,+${DEFAULT_MODEL}")

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
    echo -e "   ${BOLD}API Key 配置位置:${NC}"
    echo -e "   LobeChat → 右上角 ⚙ → 语言模型 → OpenAI"
    echo -e "   API 代理: ${CYAN}https://dashscope.aliyuncs.com/compatible-mode/v1${NC}"
    echo -e "   API Key:  ${YELLOW}← 你自行填入百炼 Key${NC}"
    echo -e "   模型:     ${CYAN}${DEFAULT_MODEL:-在界面里选}${NC}"
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

    if command -v chromium &>/dev/null; then
        step_ok "Chromium 已安装"
        return
    fi

    step_info "下载 Google Chrome..."
    curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/chrome.deb
    apt install -y /tmp/chrome.deb 2>/dev/null || apt install -f -y 2>/dev/null || true
    rm -f /tmp/chrome.deb

    command -v google-chrome-stable &>/dev/null && step_ok "Chrome 安装完成" || {
        step_warn "Chrome 失败，改用 Chromium"
        apt install -y chromium 2>/dev/null || true
    }
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
        apt install -y gtk2-engines-murrine gtk2-engines-pixbuf 2>/dev/null || true
        apt install -y papirus-icon-theme greybird-gtk-theme arc-theme 2>/dev/null || \
        apt install -y papirus-icon-theme greybird-gtk-theme 2>/dev/null || true
        apt install -y breeze-cursor-theme fonts-firacode 2>/dev/null || true

        # 自动应用主题 — 需要 D-Bus 会话总线才能操作 xfconf
        if command -v xfconf-query &>/dev/null && [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
            local UID
            UID=$(id -u "$SUDO_USER" 2>/dev/null)
            local DBUS="unix:path=/run/user/${UID}/bus"

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

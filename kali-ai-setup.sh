#!/bin/bash
# ============================================================================
#   Kali AI 交互环境一键部署 v2.0
#   Author : Mr.li8848
#   Usage  : sudo bash kali-ai-setup.sh
#
#   ① Docker Engine
#   ② LobeChat (开机自启 + API 框架留空 + 模型可选)
#   ③ Chrome 浏览器 (Web Speech API)
#   ④ VMware 声卡检查 + LobeChat 网页端语音
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

section_title() {
    echo ""
    echo -e "  ${BOLD}${MAGENTA}▶ ${1}${NC}"
    echo -e "  ${MAGENTA}──────────────────────────────────────────────────────────${NC}"
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
install_docker() {
    banner "① 安装 Docker Engine"

    if command -v docker &>/dev/null; then
        step_ok "$(docker --version) — 已安装"
        return
    fi

    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    apt update -y
    apt install -y ca-certificates curl

    # Kali 的 VERSION_CODENAME 是 "kali-rolling"，Docker 官方源没有这个
    # 取 Kali 底层 Debian 版本: 从 /etc/debian_version 读取
    local DEBIAN_CODENAME=""
    if [ -f /etc/debian_version ]; then
        local DEBIAN_VER
        DEBIAN_VER=$(cat /etc/debian_version | cut -d. -f1)
        case "$DEBIAN_VER" in
            13) DEBIAN_CODENAME="trixie" ;;
            12) DEBIAN_CODENAME="bookworm" ;;
            11) DEBIAN_CODENAME="bullseye" ;;
            *)  DEBIAN_CODENAME="bookworm" ;;  # fallback
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
#  ② LobeChat — 开机自启 + API 留空 + 模型可选
# ============================================================================
deploy_lobe_chat() {
    banner "② 部署 LobeChat（开机自启 + API 框架）"

    echo -e "   ${DIM}开源聊天 UI | 支持 30+ LLM | 自带语音输入 (Web Speech API)${NC}"
    echo -e "   ${DIM}https://github.com/lobehub/lobe-chat${NC}"
    echo ""

    # 干掉旧容器
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    # 访问密码
    local ACCESS_PASSWORD=""
    read -p "$(echo -e "   ${YELLOW}设置 LobeChat 访问密码（回车跳过）: ${NC}")" ACCESS_PASSWORD

    # 端口
    read -p "$(echo -e "   ${YELLOW}Web 端口 [默认 ${LOBE_PORT}]: ${NC}")" CUSTOM_PORT
    LOBE_PORT="${CUSTOM_PORT:-$LOBE_PORT}"

    # ── 模型选择 ──
    echo ""
    echo -e "   ${BOLD}${WHITE}选择默认模型:${NC}"
    echo -e "   ${CYAN}1${NC}) qwen-turbo      — 最快最省"
    echo -e "   ${CYAN}2${NC}) qwen-plus       — 均衡推荐 (默认)"
    echo -e "   ${CYAN}3${NC}) qwen-max        — 最强推理"
    echo -e "   ${CYAN}4${NC}) qwen-max-longcontext — 超长上下文"
    echo -e "   ${CYAN}5${NC}) 不预设，我自己在 Web 界面里配"
    echo ""

    local MODEL_CHOICE
    local DEFAULT_MODEL="qwen-plus"
    read -p "$(echo -e "   ${YELLOW}选择 [1-5，默认 2]: ${NC}")" MODEL_CHOICE
    case "${MODEL_CHOICE:-2}" in
        1) DEFAULT_MODEL="qwen-turbo" ;;
        2) DEFAULT_MODEL="qwen-plus" ;;
        3) DEFAULT_MODEL="qwen-max" ;;
        4) DEFAULT_MODEL="qwen-max-longcontext" ;;
        5) DEFAULT_MODEL="" ;;
    esac

    # ── 启动容器 ──
    # API Key 留空，用户自行在 Web 界面设置里填入
    # OPENAI_PROXY_URL 预设为百炼兼容端点
    step_info "拉取镜像（约 500MB）..."

    local DOCKER_ARGS=(
        -d
        --name "$CONTAINER_NAME"
        --restart unless-stopped
        -p "${LOBE_PORT}:3210"
    )

    [ -n "$ACCESS_PASSWORD" ] && DOCKER_ARGS+=(-e "ACCESS_CODE=${ACCESS_PASSWORD}")
    DOCKER_ARGS+=(-e "OPENAI_PROXY_URL=https://dashscope.aliyuncs.com/compatible-mode/v1")
    [ -n "$DEFAULT_MODEL" ] && DOCKER_ARGS+=(-e "OPENAI_MODEL_LIST=-all,+${DEFAULT_MODEL}")

    docker run "${DOCKER_ARGS[@]}" lobehub/lobe-chat || {
        step_err "容器启动失败！检查网络。"
        return 1
    }

    sleep 3
    docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$" && step_ok "LobeChat 运行中 — 已设置开机自启" || {
        step_err "容器异常"
        docker logs "$CONTAINER_NAME" 2>/dev/null | tail -20
        return 1
    }
}

# ============================================================================
#  ③ 浏览器安装
# ============================================================================
install_browser() {
    banner "③ 安装 Chrome 浏览器"

    if command -v google-chrome-stable &>/dev/null; then
        step_ok "Google Chrome 已安装"
        return
    fi

    [ -f /usr/bin/chromium ] && step_ok "Chromium 已安装" && return

    step_info "安装 Google Chrome (最佳 Web Speech API 支持)..."

    curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/chrome.deb
    apt install -y /tmp/chrome.deb 2>/dev/null || apt install -f -y 2>/dev/null || true
    rm -f /tmp/chrome.deb

    command -v google-chrome-stable &>/dev/null && step_ok "Chrome 安装完成" || {
        step_warn "Chrome 安装失败，改用 Chromium"
        apt install -y chromium 2>/dev/null || true
    }
}

# ============================================================================
#  ④ 声卡 + 语音
# ============================================================================
setup_voice() {
    banner "④ VMware 声卡检查 + LobeChat 网页语音"

    # ── 声卡检测 ──
    echo ""
    echo -e "   ${BOLD}${WHITE}检测音频设备:${NC}"
    echo ""

    local SOUND_OK=1

    # 检查声卡
    if cat /proc/asound/cards 2>/dev/null | grep -q '\[.*\]'; then
        echo -e "   ${GREEN}声卡已识别:${NC}"
        cat /proc/asound/cards | grep '\[' | while read line; do
            echo -e "     ${CYAN}${line}${NC}"
        done
    else
        echo -e "   ${RED}未检测到声卡！${NC}"
        SOUND_OK=0
    fi

    # 检查麦克风
    echo ""
    if amixer sget Capture 2>/dev/null | grep -q 'Capture'; then
        echo -e "   ${GREEN}麦克风控件已识别${NC}"
    elif arecord -l 2>/dev/null | grep -q 'card'; then
        echo -e "   ${GREEN}录音设备已识别:${NC}"
        arecord -l | grep 'card'
    else
        echo -e "   ${YELLOW}未检测到麦克风设备${NC}"
        SOUND_OK=0
    fi

    # PulseAudio 状态
    echo ""
    if command -v pactl &>/dev/null; then
        pactl info 2>/dev/null | grep "Server Name" && echo -e "   ${GREEN}PulseAudio 运行中${NC}" || echo -e "   ${YELLOW}PulseAudio 未运行${NC}"
    fi

    # ── VMware 声卡配置提示 ──
    echo ""
    if [ $SOUND_OK -eq 0 ]; then
        echo -e "   ${YELLOW}${BOLD}⚠ VMware 声卡映射检查:${NC}"
        echo ""
        echo -e "   ${CYAN}1.${NC} 关闭 Kali 虚拟机"
        echo -e "   ${CYAN}2.${NC} VMware → 虚拟机设置 → 硬件 → 声卡"
        echo -e "   ${CYAN}3.${NC} 确保: ${BOLD}已连接${NC} + ${BOLD}启动时连接${NC} 都已勾选"
        echo -e "   ${CYAN}4.${NC} 声卡类型选 ${BOLD}Intel HD Audio${NC}"
        echo -e "   ${CYAN}5.${NC} 重启 Kali"
        echo ""
    fi

    # 安装 PulseAudio 音量控制
    apt install -y pulseaudio pavucontrol alsa-utils 2>/dev/null || true

    # ── LobeChat 网页端语音说明 ──
    echo ""
    echo -e "   ${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "   ${BOLD}${WHITE}  🎤 LobeChat 网页端语音输入${NC}"
    echo -e "   ${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "   ${GREEN}不需要任何额外配置。${NC}"
    echo ""
    echo -e "   ${CYAN}1.${NC} Chrome 打开 ${GREEN}http://localhost:${LOBE_PORT}${NC}"
    echo -e "   ${CYAN}2.${NC} 点击输入框 ${BOLD}右侧的麦克风图标 🎤${NC}"
    echo -e "   ${CYAN}3.${NC} 浏览器弹出麦克风权限请求 → ${BOLD}允许${NC}"
    echo -e "   ${CYAN}4.${NC} 对着麦克风说话 → 实时转文字 → Enter 发送"
    echo ""
    echo -e "   ${YELLOW}首次使用自动下载语音模型（约 50MB），需联网。${NC}"
    echo ""

    step_ok "声卡检查完毕"
}

# ============================================================================
#  完成
# ============================================================================
show_summary() {
    local KALI_IP
    KALI_IP=$(ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
    [ -z "$KALI_IP" ] && KALI_IP="localhost"

    echo ""
    echo -e "  ${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║         ✓  AI 交互环境部署完成                         ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "  ${NC}"
    echo ""

    echo -e "  ${BOLD}访问地址:${NC}"
    echo -e "    本机:  ${CYAN}http://localhost:${LOBE_PORT}${NC}"
    [ "$KALI_IP" != "localhost" ] && echo -e "    外网:  ${CYAN}http://${KALI_IP}:${LOBE_PORT}${NC}"
    echo ""
    echo -e "  ${BOLD}API Key 配置:${NC}"
    echo -e "    LobeChat → 右上角 ⚙ → 语言模型 → OpenAI"
    echo -e "    API 代理: ${CYAN}https://dashscope.aliyuncs.com/compatible-mode/v1${NC}"
    echo -e "    API Key:  ${YELLOW}← 在此填入你的百炼 Key${NC}"
    echo -e "    模型:     ${CYAN}qwen-plus${NC} (或 qwen-turbo / qwen-max)"
    echo ""

    echo -e "  ${BOLD}常用管理:${NC}"
    echo -e "    ${DIM}docker restart lobe-chat${NC}  重启"
    echo -e "    ${DIM}docker logs lobe-chat${NC}     查看日志"
    echo -e "    ${DIM}docker stop lobe-chat${NC}     停止"
    echo ""

    echo -e "  ${BOLD}语音输入:${NC}"
    echo -e "    Chrome 打开页面 → 输入框旁 🎤 → 允许麦克风 → 说话"
    echo ""

    echo -e "  ${DIM}日志: ${LOG_FILE}${NC}"
    echo ""
}

# ============================================================================
#  主流程
# ============================================================================
main() {
    clear
    banner "Kali AI 交互环境一键部署 v2.0"

    echo -e "  ${GREEN}❶${NC}  Docker Engine"
    echo -e "  ${CYAN}❷${NC}  LobeChat (开机自启 + API 留空 + 模型可选)"
    echo -e "  ${MAGENTA}❸${NC}  Chrome 浏览器"
    echo -e "  ${YELLOW}❹${NC}  声卡检查 + 网页语音"
    echo ""
    echo -e "  ${RED}⚠ API Key 由你自行在 LobeChat Web 界面填入，脚本不触碰${NC}"
    echo ""

    confirm_yes "开始部署？" || { log_msg "已取消"; exit 0; }

    install_docker
    deploy_lobe_chat
    install_browser
    setup_voice
    show_summary
}

check_root
cat > "$LOG_FILE" << SETUPLOG
═══════════════════════════════════════════
  Kali AI 环境部署日志
  时间: $(date '+%Y-%m-%d %H:%M:%S')
  v2.0 — Mr.li8848
═══════════════════════════════════════════

SETUPLOG
main

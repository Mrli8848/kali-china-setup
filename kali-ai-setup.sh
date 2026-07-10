#!/bin/bash
# ============================================================================
#
#   ██╗  ██╗ █████╗ ██╗     ██╗    ██████╗ ██╗
#   ██║ ██╔╝██╔══██╗██║     ██║    ██╔══██╗██║
#   █████╔╝ ███████║██║     ██║    ██████╔╝██║
#   ██╔═██╗ ██╔══██║██║     ██║    ██╔══██╗██║
#   ██║  ██╗██║  ██║███████╗██║    ██║  ██║██║
#   ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝    ╚═╝  ╚═╝╚═╝
#
#   Kali AI 交互环境一键部署脚本 v1.0
#   Author : Mr.li8848
#   Usage  : sudo bash kali-ai-setup.sh
#
#   ─────────────────────────────────────────────────────────────
#   功能: Docker → Lobe Chat → 阿里云百炼 → 语音输入
#   ─────────────────────────────────────────────────────────────
#   第一步: 安装 Docker 环境
#   第二步: 部署 Lobe Chat (Web UI)
#   第三步: 配置阿里云百炼 API Key
#   第四步: 语音输入配置说明 (Win + H)
#   ─────────────────────────────────────────────────────────────
#
# ============================================================================

set -e

# ////////////////////////////////////////////////////////////////////////////
#  配色 & 变量
# ////////////////////////////////////////////////////////////////////////////
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
LOBE_PORT=3210                          # 默认访问端口
CONTAINER_NAME="lobe-chat"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ////////////////////////////////////////////////////////////////////////////
#  工具函数
# ////////////////////////////////////////////////////////////////////////////
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
    local prompt="$1"
    local answer
    read -p "$(echo -e "   ${YELLOW}${prompt} [Y/n]: ${NC}")" answer
    [[ ! "$answer" =~ ^[Nn] ]]
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_msg "${RED}⛔ 请使用 sudo 运行此脚本！${NC}"
        log_msg "   sudo bash $0"
        exit 1
    fi
}

# ////////////////////////////////////////////////////////////////////////////
#  第一步：安装 Docker
# ////////////////////////////////////////////////////////////////////////////
install_docker() {
    banner "第一步：安装 Docker 环境"

    if command -v docker &>/dev/null; then
        echo -e "   $(docker --version)"
        step_ok "Docker 已安装，跳过"
    else
        section_title "安装 Docker Engine"
        step_info "正在导入 Docker GPG 密钥..."

        # 移除旧版本
        apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

        # 安装依赖
        apt update -y
        apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

        # 添加 Docker 官方 GPG 密钥
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/debian/gpg | \
            gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null

        # 添加 apt 源
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
            https://download.docker.com/linux/debian \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt update -y
        apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

        # 启动 Docker
        systemctl enable docker --now 2>/dev/null || true

        step_ok "Docker 安装完成 — $(docker --version)"

        # 把当前用户加入 docker 组（避免每次 sudo）
        if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
            usermod -aG docker "$SUDO_USER" 2>/dev/null || true
            step_info "已将 $SUDO_USER 加入 docker 组（下次登录生效）"
        fi
    fi

    # 验证
    echo ""
    step_info "验证 Docker 是否正常..."
    if docker run --rm hello-world 2>/dev/null | grep -q "Hello from Docker"; then
        step_ok "Docker 运行正常"
    else
        step_warn "Docker 测试失败，请检查"
    fi
}

# ////////////////////////////////////////////////////////////////////////////
#  第二步：部署 Lobe Chat
# ////////////////////////////////////////////////////////////////////////////
deploy_lobe_chat() {
    banner "第二步：部署 Lobe Chat 聊天界面"

    echo ""
    echo -e "   ${BOLD}${WHITE}Lobe Chat${NC}"
    echo -e "   ${DIM}开源、现代化、支持 30+ LLM 的聊天 UI${NC}"
    echo -e "   ${DIM}官网: https://github.com/lobehub/lobe-chat${NC}"
    echo ""

    # 检查是否已有容器
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        step_info "检测到已有 Lobe Chat 容器，将先移除..."
        docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    fi

    # 读取或设置访问密码
    local ACCESS_PASSWORD=""
    read -p "$(echo -e "   ${YELLOW}设置 Lobe Chat 访问密码（直接回车则无密码）: ${NC}")" ACCESS_PASSWORD

    # 读取端
    read -p "$(echo -e "   ${YELLOW}设置 Web 访问端口 [默认: ${LOBE_PORT}]: ${NC}")" CUSTOM_PORT
    LOBE_PORT="${CUSTOM_PORT:-$LOBE_PORT}"

    # 构建 docker run 命令
    local DOCKER_ENVS=(
        "-e OPENAI_API_KEY=sk-dummy-placeholder"
        "-e OPENAI_PROXY_URL=https://dashscope.aliyuncs.com/compatible-mode/v1"
        "-e ACCESS_CODE=${ACCESS_PASSWORD}"
    )

    echo ""
    step_info "正在拉取 Lobe Chat 镜像（约 500MB，请耐心等待）..."

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "${LOBE_PORT}:3210" \
        -e ACCESS_CODE="${ACCESS_PASSWORD}" \
        lobehub/lobe-chat 2>/dev/null || {
        step_err "镜像拉取或容器启动失败！请检查网络连接。"
        return 1
    }

    # 等待服务启动
    step_info "等待服务启动..."
    sleep 3

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        step_ok "Lobe Chat 容器运行中"
    else
        step_err "容器未正常运行，请查看日志:"
        docker logs "$CONTAINER_NAME" 2>/dev/null | tail -20
        return 1
    fi
}

# ////////////////////////////////////////////////////////////////////////////
#  第三步：配置 API Key
# ////////////////////////////////////////////////////////////////////////////
configure_api() {
    banner "第三步：配置阿里云百炼 API 密钥"

    echo ""
    echo -e "   ${BOLD}${WHITE}📝 获取 API Key 的步骤（在 Windows 浏览器操作）:${NC}"
    echo ""
    echo -e "   ${CYAN}1.${NC} 打开浏览器访问: ${WHITE}https://bailian.console.aliyun.com/${NC}"
    echo -e "   ${CYAN}2.${NC} 注册/登录阿里云账号"
    echo -e "   ${CYAN}3.${NC} 左侧菜单 → ${BOLD}模型广场${NC} → 选择 ${BOLD}通义千问${NC}"
    echo -e "   ${CYAN}4.${NC} 左侧菜单 → ${BOLD}API-KEY 管理${NC} → 创建新的 API Key"
    echo -e "   ${CYAN}5.${NC} 复制生成的 API Key（格式: sk-xxxxxxxxxxxxxxxx）"
    echo ""

    # 读取用户输入的 API Key
    local API_KEY=""
    while [ -z "$API_KEY" ]; do
        read -p "$(echo -e "   ${YELLOW}请粘贴你的阿里云百炼 API Key: ${NC}")" API_KEY

        if [ -z "$API_KEY" ]; then
            echo -e "   ${RED}API Key 不能为空！${NC}"
            echo ""
        fi
    done

    # 验证 API Key 格式
    if [[ "$API_KEY" =~ ^sk-[a-zA-Z0-9]+$ ]]; then
        step_ok "API Key 格式检查通过"
    else
        step_warn "API Key 格式异常（标准格式为 sk- 开头），但继续尝试配置..."
    fi

    # 更新 Lobe Chat 容器的环境变量
    step_info "正在注入 API Key 到 Lobe Chat 容器..."

    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "${LOBE_PORT}:3210" \
        -e OPENAI_API_KEY="${API_KEY}" \
        -e OPENAI_PROXY_URL="https://dashscope.aliyuncs.com/compatible-mode/v1" \
        -e ACCESS_CODE="${ACCESS_PASSWORD}" \
        lobehub/lobe-chat 2>/dev/null

    sleep 2

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        step_ok "API Key 已配置，容器重启完成"
    else
        step_err "容器重启失败！"
        step_info "手动检查: docker logs $CONTAINER_NAME"
        return 1
    fi
}

# ////////////////////////////////////////////////////////////////////////////
#  第四步：语音输入指南
# ////////////////////////////////////////////////////////////////////////////
show_voice_guide() {
    banner "第四步：配置语音下命令（Win + H）"

    echo ""
    echo -e "   ${BOLD}${WHITE}🎤 核心原理（一句话讲清楚）:${NC}"
    echo ""
    echo -e "   ${GREEN}Win + H${NC} 是 ${BOLD}Windows 自带${NC}的语音听写功能，不需要在 Kali 里装任何东西。"
    echo -e "   你在 Kali 里点一下输入框 → 按 ${BOLD}Win + H${NC} → 说话 → 文字自动打进去。"
    echo ""

    echo -e "   ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "   ${BOLD}${WHITE}  📋 操作步骤${NC}"
    echo -e "   ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "   ${CYAN}①${NC}  ${BOLD}在 Windows 上开启在线语音识别:${NC}"
    echo -e "      Windows 设置 → 隐私和安全性 → 语音"
    echo -e "      → 打开 ${GREEN}"在线语音识别"${NC}"
    echo ""
    echo -e "   ${CYAN}②${NC}  ${BOLD}选择输入法:${NC}"
    echo -e "      按 ${BOLD}Win + 空格${NC} 切换到 ${YELLOW}微软拼音${NC}"
    echo -e "      ${DIM}(Win + H 依赖微软拼音才能正常工作)${NC}"
    echo ""
    echo -e "   ${CYAN}③${NC}  ${BOLD}在 Kali 里点击输入框:${NC}"
    echo -e "      点击终端 / 浏览器地址栏 / Lobe Chat 对话框"
    echo -e "      ${DIM}(关键是让光标在文本输入框里闪烁)${NC}"
    echo ""
    echo -e "   ${CYAN}④${NC}  ${BOLD}按下 Win + H:${NC}"
    echo -e "      屏幕顶部出现语音悬浮窗"
    echo -e "      ${DIM}如果出现的是麦克风图标 → 点一下开始听写${NC}"
    echo ""
    echo -e "   ${CYAN}⑤${NC}  ${BOLD}对着麦克风说话:${NC}"
    echo -e "      说的话会实时转成文字打到 Kali 输入框里"
    echo -e "      说完按 ${BOLD}Enter${NC} 发送"
    echo ""

    echo -e "   ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "   ${BOLD}${WHITE}  🔧 常见问题${NC}"
    echo -e "   ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "   ${YELLOW}Q: Win + H 没反应？${NC}"
    echo -e "   ${CYAN}A:${NC} 1) 确认输入法是微软拼音"
    echo -e "         2) 确认联网（语音识别需要网络）"
    echo -e "         3) Windows 设置 → 蓝牙和设备 → 麦克风 → 确保已连接"
    echo ""
    echo -e "   ${YELLOW}Q: 识别的是英文不是中文？${NC}"
    echo -e "   ${CYAN}A:${NC} 在语音悬浮窗上点齿轮 ⚙ → 选择 ${BOLD}中文(简体)${NC}"
    echo ""
    echo -e "   ${YELLOW}Q: 识别不准？${NC}"
    echo -e "   ${CYAN}A:${NC} 说话慢一点、清晰一点；靠近麦克风；降低环境噪音"
    echo ""

    echo -e "   ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "   ${BOLD}${WHITE}  🎯 典型场景演示${NC}"
    echo -e "   ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "   ${BOLD}场景一: 在 Lobe Chat 里用语音提问${NC}"
    echo -e "   ${CYAN}1.${NC} 浏览器打开 http://localhost:${LOBE_PORT}"
    echo -e "   ${CYAN}2.${NC} 点击底部的输入框"
    echo -e "   ${CYAN}3.${NC} 按 Win + H → 说 ${YELLOW}"请帮我写一个 Nmap 扫描脚本"${NC}"
    echo -e "   ${CYAN}4.${NC} 文字出现在输入框 → 按 Enter → AI 回复"
    echo ""
    echo -e "   ${BOLD}场景二: 在终端里用语音输入命令${NC}"
    echo -e "   ${CYAN}1.${NC} 打开 Kali 终端"
    echo -e "   ${CYAN}2.${NC} 点击命令行输入区"
    echo -e "   ${CYAN}3.${NC} 按 Win + H → 说 ${YELLOW}"nmap -sV 192.168.1.1"${NC}"
    echo -e "   ${CYAN}4.${NC} 文字出现在终端 → 按 Enter 执行"
}

# ////////////////////////////////////////////////////////////////////////////
#  完成汇总
# ////////////////////////////////////////////////////////////////////////////
show_summary() {
    # 获取虚拟机 IP
    local KALI_IP=""
    KALI_IP=$(ip addr show 2>/dev/null | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | head -1)
    [ -z "$KALI_IP" ] && KALI_IP="localhost"

    echo ""
    echo -e "  ${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║                                                          ║"
    echo "  ║         🎉  AI 交互环境部署完成！                       ║"
    echo "  ║                                                          ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "  ${NC}"
    echo ""

    echo -e "  ${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}${WHITE}  📋 部署信息汇总${NC}"
    echo -e "  ${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  🌐 ${BOLD}Lobe Chat 地址:${NC}"
    echo -e "     Kali 本机:  ${CYAN}http://localhost:${LOBE_PORT}${NC}"
    [ "$KALI_IP" != "localhost" ] && \
        echo -e "     Windows 访问: ${CYAN}http://${KALI_IP}:${LOBE_PORT}${NC}"
    echo ""
    echo -e "  🔑 ${BOLD}访问密码:${NC} ${GREEN}${ACCESS_PASSWORD:-无密码}${NC}"
    echo -e "  🤖 ${BOLD}对接模型:${NC} 阿里云百炼 — 通义千问"
    echo -e "  🎤 ${BOLD}语音输入:${NC} Windows 系统级 Win + H"
    echo ""
    echo -e "  ${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}${WHITE}  🔧 常用管理命令${NC}"
    echo -e "  ${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${DIM}# 查看容器状态${NC}"
    echo -e "  ${CYAN}docker ps | grep lobe${NC}"
    echo ""
    echo -e "  ${DIM}# 查看日志${NC}"
    echo -e "  ${CYAN}docker logs lobe-chat${NC}"
    echo ""
    echo -e "  ${DIM}# 重启容器${NC}"
    echo -e "  ${CYAN}docker restart lobe-chat${NC}"
    echo ""
    echo -e "  ${DIM}# 停止容器${NC}"
    echo -e "  ${CYAN}docker stop lobe-chat${NC}"
    echo ""

    echo -e "  ${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}${WHITE}  🚀 开始使用${NC}"
    echo -e "  ${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}1.${NC} 浏览器打开 ${GREEN}http://localhost:${LOBE_PORT}${NC}"
    echo -e "  ${CYAN}2.${NC} 左侧选择模型 → ${BOLD}通义千问${NC}"
    echo -e "  ${CYAN}3.${NC} 点击输入框 → ${BOLD}Win + H${NC} → 说话 → Enter"
    echo ""

    echo -e "  ${DIM}日志文件: ${LOG_FILE}${NC}"
    echo ""
}

# ////////////////////////////////////////////////////////////////////////////
#  主流程
# ////////////////////////////////////////////////////////////////////////////
main() {
    clear
    banner "Kali AI 交互环境一键部署 v1.0"

    echo ""
    echo -e "  ${BOLD}${WHITE}本脚本将完成以下操作:${NC}"
    echo ""
    echo -e "  ${GREEN}❶${NC}  安装 Docker 容器引擎"
    echo -e "  ${CYAN}❷${NC}  部署 Lobe Chat 聊天界面 (Web UI)"
    echo -e "  ${MAGENTA}❸${NC}  配置阿里云百炼 API Key (通义千问)"
    echo -e "  ${YELLOW}❹${NC}  语音输入操作指南 (Win + H)"
    echo ""
    echo -e "  ${DIM}预估时间: 5-10 分钟（主要看网络速度）${NC}"
    echo ""

    if ! confirm_yes "现在开始部署？"; then
        log_msg "已取消"
        exit 0
    fi

    # ── 第一步 ──
    install_docker

    # ── 第二步 ──
    deploy_lobe_chat

    # ── 第三步 ──
    configure_api

    # ── 第四步 ──
    show_voice_guide

    # ── 完成 ──
    show_summary
}

# ////////////////////////////////////////////////////////////////////////////
#  入口
# ////////////////////////////////////////////////////////////////////////////
check_root

# 初始化日志
cat > "$LOG_FILE" << SETUPLOG
═══════════════════════════════════════════
  Kali AI 交互环境部署日志
  时间: $(date '+%Y-%m-%d %H:%M:%S')
  脚本: v1.0 — Mr.li8848
═══════════════════════════════════════════

SETUPLOG

main

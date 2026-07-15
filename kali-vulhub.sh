#!/bin/bash
# ============================================================================
#   Kali Docker + Vulhub 一键部署 v1.0
#   Author : Mr.li8848
#   Usage  : sudo bash kali-vulhub.sh
#
#   ① 安装 Docker + 镜像加速
#   ② 部署 Vulhub (200+ 漏洞靶场)
#   ③ 常用管理命令速查
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

LOG_FILE="/tmp/kali-vulhub-$(date +%Y%m%d-%H%M%S).log"
VULHUB_DIR="/opt/vulhub"

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
#  Docker
# ============================================================================
install_docker() {
    banner "安装 Docker Engine + 镜像加速"

    if command -v docker &>/dev/null; then
        step_ok "$(docker --version) — 已安装"
    else
        apt update -y

        # 优先用 Kali 自带的 docker.io，走国内镜像源，不受 GFW 干扰
        step_info "尝试从 Kali 源安装 docker.io..."
        if apt install -y docker.io docker-compose 2>/dev/null; then
            step_ok "docker.io 安装成功"
        else
            # 备用：Docker 官方源（可能被墙）
            step_warn "docker.io 安装失败，尝试 Docker 官方源..."

            local DEBIAN_CODENAME DEBIAN_VER KALI_YEAR
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
    fi

    # 镜像加速
    echo ""
    if [ ! -f /etc/docker/daemon.json ] || ! grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null; then
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ]
}
EOF
        systemctl restart docker
        step_ok "Docker 镜像加速已配置"
    else
        step_ok "镜像加速已存在"
    fi

    # 验证
    echo ""
    step_info "验证 Docker..."
    docker run --rm hello-world 2>/dev/null | grep -q "Hello from Docker" && step_ok "Docker 运行正常" || step_warn "Docker 测试失败"
}

# ============================================================================
#  Vulhub
# ============================================================================
install_vulhub() {
    banner "部署 Vulhub 漏洞靶场"

    echo -e "   ${DIM}Vulhub — 基于 Docker-Compose 的漏洞复现合集 (200+ 环境)${NC}"
    echo -e "   ${DIM}官网: https://github.com/vulhub/vulhub${NC}"
    echo ""

    if ! command -v docker &>/dev/null; then
        step_err "Docker 未安装，请先执行 Docker 安装步骤"
        return 1
    fi

    if [ -d "$VULHUB_DIR" ]; then
        step_ok "Vulhub 已存在 → ${VULHUB_DIR}"

        # 更新
        echo ""
        if confirm_yes "是否更新 Vulhub 到最新版？"; then
            step_info "正在更新..."
            cd "$VULHUB_DIR"
            git pull 2>/dev/null && step_ok "Vulhub 已更新" || step_warn "更新失败，请检查网络"
            cd - > /dev/null
        fi

        # 列出已安装的靶场
        echo ""
        echo -e "   ${BOLD}已安装的漏洞环境:${NC}"
        echo ""
        local COUNT=0
        find "$VULHUB_DIR" -maxdepth 2 -name "docker-compose.yml" | while read f; do
            local DIR
            DIR=$(dirname "$f" | sed "s|${VULHUB_DIR}/||")
            printf "     ${CYAN}%-60s${NC}\n" "$DIR"
        done
        echo ""
    else
        step_info "正在克隆 Vulhub..."
        git clone --depth 1 https://github.com/vulhub/vulhub.git "$VULHUB_DIR" 2>/dev/null || {
            step_err "克隆失败！尝试镜像..."
            git clone --depth 1 https://gitee.com/nuoya99/vulhub.git "$VULHUB_DIR" 2>/dev/null || {
                step_err "Vulhub 下载完全失败，请手动安装"
                return 1
            }
        }
        step_ok "Vulhub → ${VULHUB_DIR}"
    fi

    # 使用指南
    echo ""
    echo -e "   ${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "   ${BOLD}${WHITE}  📖 使用方法${NC}"
    echo -e "   ${BOLD}${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "   ${BOLD}1. 选择漏洞:${NC}"
    echo -e "      ls ${VULHUB_DIR}/"
    echo ""
    echo -e "   ${BOLD}2. 进入目标目录并启动:${NC}"
    echo -e "      cd ${VULHUB_DIR}/${CYAN}<漏洞路径>${NC}"
    echo -e "      docker compose up -d"
    echo ""
    echo -e "   ${BOLD}3. 停止并清理:${NC}"
    echo -e "      docker compose down -v"
    echo ""
    echo -e "   ${BOLD}4. 热门靶场速览:${NC}"
    echo -e "      ${CYAN}${VULHUB_DIR}/weblogic/CVE-2020-14882/${NC}  — WebLogic 未授权"
    echo -e "      ${CYAN}${VULHUB_DIR}/struts2/s2-061/${NC}          — Struts2 RCE"
    echo -e "      ${CYAN}${VULHUB_DIR}/spring/CVE-2022-22965/${NC}    — Spring4Shell"
    echo -e "      ${CYAN}${VULHUB_DIR}/shiro/CVE-2016-4437/${NC}      — Shiro 反序列化"
    echo -e "      ${CYAN}${VULHUB_DIR}/log4j/CVE-2021-44228/${NC}     — Log4Shell"
    echo -e "      ${CYAN}${VULHUB_DIR}/tomcat/CVE-2017-12615/${NC}    — Tomcat 文件上传"
    echo ""
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
    echo "  ║         ✓  Docker + Vulhub 部署完成                    ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "  ${NC}"
    echo ""
    echo -e "  ${BOLD}Docker:${NC}  $(docker --version 2>/dev/null)"
    echo -e "  ${BOLD}Compose:${NC} $(docker compose version 2>/dev/null)"
    echo -e "  ${BOLD}Vulhub:${NC}  ${VULHUB_DIR}"
    echo ""

    echo -e "  ${BOLD}常用命令:${NC}"
    echo -e "  ${DIM}docker compose up -d${NC}      启动靶场"
    echo -e "  ${DIM}docker compose down -v${NC}    停止并清理"
    echo -e "  ${DIM}docker compose logs${NC}       查看日志"
    echo -e "  ${DIM}docker compose ps${NC}         查看状态"
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
        echo "  ║     Kali Docker + Vulhub 一键部署 v1.0                  ║"
        echo "  ║     Author: Mr.li8848                                   ║"
        echo "  ╚══════════════════════════════════════════════════════════╝"
        echo -e "  ${NC}"
        echo ""

        echo -e "  ${GREEN}${BOLD}  [1]${NC}  安装 Docker Engine (含镜像加速)"
        echo -e "  ${CYAN}${BOLD}  [2]${NC}  部署 Vulhub (200+ 漏洞靶场)"
        echo -e "  ${YELLOW}${BOLD}  [A]${NC}  一键全部安装"
        echo ""
        echo -e "  ${DIM}  [S]${NC}  ${DIM}显示汇总${NC}"
        echo -e "  ${DIM}  [Q]${NC}  ${DIM}退出${NC}"
        echo ""

        local CHOICE
        read -p "$(echo -e "  ${YELLOW}请选择 [1/2/A/S/Q]: ${NC}")" CHOICE

        case "$CHOICE" in
            1) install_docker ;;
            2) install_vulhub ;;
            A|a)
                install_docker
                install_vulhub
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

        if [[ "$CHOICE" =~ ^[12Aa]$ ]]; then
            echo ""
            read -p "$(echo -e "   ${DIM}按 Enter 返回菜单...${NC}")" _
        fi
        if [[ "$CHOICE" =~ ^[Ss]$ ]]; then
            read -p "$(echo -e "   ${DIM}按 Enter 返回菜单...${NC}")" _
        fi
    done
}

check_root
cat > "$LOG_FILE" << SETUPLOG
═══════════════════════════════════════════
  Kali Docker + Vulhub 部署日志
  时间: $(date '+%Y-%m-%d %H:%M:%S')
  v1.0 — Mr.li8848
═══════════════════════════════════════════

SETUPLOG
main_menu

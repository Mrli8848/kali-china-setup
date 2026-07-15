#!/bin/bash
# ============================================================================
#   Kali Docker + Vulhub 一键部署 v2.0
#   Author : Mr.li8848
#   Usage  : sudo bash kali-vulhub.sh
#
#   ① Docker: 优先 Kali 自带的 docker.io（走国内镜像），Docker Hub 被墙时自动配加速
#   ② Vulhub: 多级回退克隆（github.dpik.top / ghproxy / kgithub / GitHub 直连）
#   ③ 镜像代理: Vulhub 小众镜像加速站无缓存时，用代理前缀拉取 + 改名
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

LOG_FILE="/tmp/kali-vulhub-$(date +%Y%m%d-%H%M%S).log"
VULHUB_DIR="/opt/vulhub"

# 国内实测可用的 Docker 代理前缀（按速度排序）
DOCKER_PROXIES=(
    "docker.1ms.run"
    "dockerproxy.com"
    "docker.m.daocloud.io"
)

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
    banner "① 安装 Docker Engine + 镜像加速"

    if command -v docker &>/dev/null; then
        step_ok "$(docker --version) — 已安装，跳过"
    else
        apt update -y
        step_info "优先 Kali 自带 docker.io（走国内镜像，免翻墙）..."

        if apt install -y docker.io docker-compose 2>/dev/null; then
            step_ok "docker.io 安装成功"
        else
            step_warn "docker.io 失败 → 尝试 Docker 官方源（可能被墙）..."

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
                step_err "Docker 官方源也失败 — 请检查网络或手动安装 docker.io"
                rm -f /etc/apt/sources.list.d/docker.list
                return 1
            }
        fi

        systemctl enable docker --now 2>/dev/null || true
        [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ] && usermod -aG docker "$SUDO_USER" 2>/dev/null || true
        step_ok "Docker 安装完成 — $(docker --version)"
        step_info "提示: 普通用户需重新登录 docker 组才生效，或使用 sudo 运行 docker"
    fi

    # ── 镜像加速 ──
    echo ""
    mkdir -p /etc/docker
    if [ ! -f /etc/docker/daemon.json ] || ! grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null; then
        cat > /etc/docker/daemon.json << 'EOF'
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me",
    "https://hub.rat.dev",
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com",
    "https://docker.nju.edu.cn"
  ]
}
EOF
        systemctl restart docker
        step_ok "Docker 镜像加速已配置（国内 6 个源）"
    else
        step_ok "镜像加速已存在"
    fi
}

# ============================================================================
#  镜像代理辅助 — Vulhub 小众镜像加速站无缓存时的解决方案
# ============================================================================
pull_proxy() {
    local IMAGE="$1"  # 格式: vulhub/tomcat:8.5.19 或 library/tomcat:8.5.19
    local TARGET_NAME="$2"  # 改名目标，如 vulhub/tomcat:8.5.19

    if [ -z "$TARGET_NAME" ]; then
        TARGET_NAME="$IMAGE"
    fi

    # 检查是否已存在
    if docker image inspect "$TARGET_NAME" &>/dev/null; then
        step_ok "${TARGET_NAME} — 已存在，跳过"
        return 0
    fi

    # 逐个代理前缀尝试
    for PROXY in "${DOCKER_PROXIES[@]}"; do
        local PROXY_IMAGE="${PROXY}/${IMAGE}"
        echo ""
        step_info "尝试代理: ${PROXY_IMAGE}"

        if docker pull "$PROXY_IMAGE" 2>/dev/null; then
            docker tag "$PROXY_IMAGE" "$TARGET_NAME" 2>/dev/null
            docker rmi "$PROXY_IMAGE" 2>/dev/null || true
            step_ok "拉取成功 → ${TARGET_NAME}"
            return 0
        fi
    done

    step_err "所有代理均失败: ${IMAGE}"
    step_info "手动尝试: docker pull docker.1ms.run/${IMAGE}"
    return 1
}

# ============================================================================
#  Vulhub
# ============================================================================
install_vulhub() {
    banner "② 部署 Vulhub 漏洞靶场"

    echo -e "   ${DIM}Vulhub — 基于 Docker-Compose 的漏洞复现合集 (200+ 环境)${NC}"
    echo ""

    if ! command -v docker &>/dev/null; then
        step_err "Docker 未安装 — 请先执行步骤 ①"
        return 1
    fi

    if [ -d "$VULHUB_DIR" ]; then
        step_ok "Vulhub 已存在 → ${VULHUB_DIR}"
        echo ""
        echo -e "   ${BOLD}已安装的漏洞环境:${NC}"
        find "$VULHUB_DIR" -maxdepth 2 -name "docker-compose.yml" | while read f; do
            printf "     ${CYAN}%-60s${NC}\n" "$(dirname "$f" | sed "s|${VULHUB_DIR}/||")"
        done
        echo ""
        return
    fi

    # 多级回退克隆 — 只用实测可用的镜像
    local CLONED=0
    local MIRRORS=(
        "https://github.dpik.top/https://github.com/vulhub/vulhub"   # 实测可用
        "https://ghproxy.net/https://github.com/vulhub/vulhub"
        "https://gitclone.com/github.com/vulhub/vulhub"
        "https://github.com/vulhub/vulhub"                             # 最后试直连
    )

    for URL in "${MIRRORS[@]}"; do
        local LABEL
        LABEL=$(echo "$URL" | awk -F/ '{print $3}')
        step_info "尝试: ${LABEL}..."

        if git clone --depth 1 "$URL" "$VULHUB_DIR" 2>/dev/null; then
            CLONED=1
            break
        fi

        # 如果目录残留但 clone 失败，清理
        [ -d "$VULHUB_DIR" ] && rm -rf "$VULHUB_DIR"
    done

    if [ $CLONED -eq 0 ]; then
        step_err "所有克隆方式均失败"
        echo ""
        echo -e "   ${YELLOW}手动方案:${NC}"
        echo -e "   1. Windows 浏览器打开 ${CYAN}https://github.com/vulhub/vulhub${NC}"
        echo -e "   2. Code → Download ZIP → 拖进 Kali"
        echo -e "   3. unzip vulhub-main.zip -d /opt/ && mv /opt/vulhub-main /opt/vulhub"
        return 1
    fi

    step_ok "Vulhub → ${VULHUB_DIR} ($(ls "$VULHUB_DIR" | wc -l) 个漏洞分类)"
}

# ============================================================================
#  3. 快速部署靶场
# ============================================================================
quick_deploy() {
    banner "③ 快速部署指定靶场"

    if [ ! -d "$VULHUB_DIR" ]; then
        step_err "Vulhub 未安装 — 请先执行步骤 ②"
        return 1
    fi

    if ! command -v docker &>/dev/null; then
        step_err "Docker 未安装 — 请先执行步骤 ①"
        return 1
    fi

    echo ""
    echo -e "   ${BOLD}${WHITE}热门靶场快速选择:${NC}"
    echo ""
    echo -e "   ${CYAN}1${NC})  Log4Shell          log4j/CVE-2021-44228"
    echo -e "   ${CYAN}2${NC})  Spring4Shell        spring/CVE-2022-22965"
    echo -e "   ${CYAN}3${NC})  Shiro 反序列化       shiro/CVE-2016-4437"
    echo -e "   ${CYAN}4${NC})  WebLogic 未授权      weblogic/CVE-2020-14882"
    echo -e "   ${CYAN}5${NC})  Struts2 RCE         struts2/s2-061"
    echo -e "   ${CYAN}6${NC})  Tomcat 文件上传      tomcat/CVE-2017-12615"
    echo -e "   ${CYAN}7${NC})  Redis 未授权         redis/4-unacc"
    echo -e "   ${CYAN}8${NC})  SambaCry            samba/CVE-2017-7494"
    echo -e "   ${CYAN}0${NC})  自定义路径"
    echo ""

    local TARGET_DIR
    read -p "$(echo -e "   ${YELLOW}选择 [0-8]: ${NC}")" TARGET_CHOICE
    case "$TARGET_CHOICE" in
        1) TARGET_DIR="$VULHUB_DIR/log4j/CVE-2021-44228" ;;
        2) TARGET_DIR="$VULHUB_DIR/spring/CVE-2022-22965" ;;
        3) TARGET_DIR="$VULHUB_DIR/shiro/CVE-2016-4437" ;;
        4) TARGET_DIR="$VULHUB_DIR/weblogic/CVE-2020-14882" ;;
        5) TARGET_DIR="$VULHUB_DIR/struts2/s2-061" ;;
        6) TARGET_DIR="$VULHUB_DIR/tomcat/CVE-2017-12615" ;;
        7) TARGET_DIR="$VULHUB_DIR/redis/4-unacc" ;;
        8) TARGET_DIR="$VULHUB_DIR/samba/CVE-2017-7494" ;;
        0|"")
            read -p "$(echo -e "   ${YELLOW}输入完整路径 (如 tomcat/CVE-2017-12615): ${NC}")" CUSTOM
            TARGET_DIR="$VULHUB_DIR/$CUSTOM"
            ;;
        *) step_warn "无效选择" && return ;;
    esac

    if [ ! -f "$TARGET_DIR/docker-compose.yml" ]; then
        step_err "路径不存在: ${TARGET_DIR}"
        return 1
    fi

    echo ""
    step_info "目标: ${TARGET_DIR}"

    # 提取 docker-compose.yml 中的镜像名，预拉
    local IMAGES
    IMAGES=$(grep 'image:' "$TARGET_DIR/docker-compose.yml" 2>/dev/null | awk '{print $2}' | sort -u || true)

    if [ -n "$IMAGES" ]; then
        echo ""
        echo -e "   ${BOLD}需要的镜像:${NC}"
        echo "$IMAGES" | while read img; do echo -e "     ${CYAN}${img}${NC}"; done

        echo ""
        if confirm_yes "是否用国内代理预拉镜像（加速站无缓存时走代理前缀）？"; then
            echo "$IMAGES" | while read img; do
                [ -z "$img" ] && continue
                pull_proxy "$img" "$img"
            done
            echo ""
            step_info "镜像准备完毕，启动靶场..."
        fi
    fi

    cd "$TARGET_DIR"
    docker compose up -d
    echo ""

    # 解析暴露端口
    local PORTS
    PORTS=$(docker compose ps 2>/dev/null | grep -oP '0.0.0.0:\K\d+' | head -3 || true)

    echo -e "   ${GREEN}${BOLD}靶场已启动！${NC}"
    if [ -n "$PORTS" ]; then
        echo "$PORTS" | while read port; do
            echo -e "   访问: ${CYAN}http://localhost:${port}${NC}"
        done
    fi
    echo ""
    echo -e "   ${DIM}停止: cd ${TARGET_DIR} && docker compose down -v${NC}"
    echo ""
    echo -e "   ${DIM}按 Enter 返回菜单...${NC}"
    read -r _
}

# ============================================================================
#  4. 代理拉取工具
# ============================================================================
step_proxy_pull() {
    banner "④ 代理拉取 Vulhub 镜像"

    echo -e "   ${DIM}当 docker compose up -d 卡住不动时，用这个工具${NC}"
    echo -e "   ${DIM}代理前缀拉取 → 重命名为 vulhub 镜像名 → 再去启动${NC}"
    echo ""

    if ! command -v docker &>/dev/null; then
        step_err "Docker 未安装"
        return 1
    fi

    read -p "$(echo -e "   ${YELLOW}输入镜像名（如 vulhub/tomcat:8.5.19）: ${NC}")" IMG
    [ -z "$IMG" ] && step_warn "未输入" && return

    pull_proxy "$IMG" "$IMG"
}

# ============================================================================
#  完成
# ============================================================================
show_summary() {
    echo ""
    echo -e "  ${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║         ✓  Docker + Vulhub 部署完成                    ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "  ${NC}"
    echo ""

    [ -x "$(command -v docker)" ] && echo -e "  ${BOLD}Docker:${NC}  $(docker --version 2>/dev/null)"
    [ -d "$VULHUB_DIR" ] && echo -e "  ${BOLD}Vulhub:${NC}  ${VULHUB_DIR} ($(ls "$VULHUB_DIR" 2>/dev/null | wc -l) 个分类)"

    echo ""
    echo -e "  ${BOLD}常用命令:${NC}"
    echo -e "  ${DIM}docker compose up -d${NC}       启动靶场"
    echo -e "  ${DIM}docker compose down -v${NC}     停止并清理"
    echo -e "  ${DIM}docker compose ps${NC}          查看状态"
    echo ""

    echo -e "  ${BOLD}镜像代理拉取（Docker Hub 被墙时用）:${NC}"
    echo -e "  ${CYAN}docker pull docker.1ms.run/vulhub/tomcat:8.5.19${NC}"
    echo -e "  ${CYAN}docker tag docker.1ms.run/vulhub/tomcat:8.5.19 vulhub/tomcat:8.5.19${NC}"
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
        echo "  ║     Kali Docker + Vulhub 一键部署 v2.0                  ║"
        echo "  ║     Author: Mr.li8848                                   ║"
        echo "  ╚══════════════════════════════════════════════════════════╝"
        echo -e "  ${NC}"
        echo ""

        echo -e "  ${GREEN}${BOLD}  [1]${NC}  安装 Docker Engine (优先 docker.io + 国内镜像加速)"
        echo -e "  ${CYAN}${BOLD}  [2]${NC}  部署 Vulhub (多级镜像回退克隆)"
        echo -e "  ${MAGENTA}${BOLD}  [3]${NC}  快速部署指定靶场 (含镜像代理预拉)"
        echo -e "  ${YELLOW}${BOLD}  [4]${NC}  代理拉取单个镜像 (docker pull 卡住时手动用)"
        echo ""
        echo -e "  ${WHITE}${BOLD}  [A]${NC}  ${WHITE}一键全部安装${NC}"
        echo -e "  ${DIM}  [S]${NC}  ${DIM}显示汇总${NC}"
        echo -e "  ${DIM}  [Q]${NC}  ${DIM}退出${NC}"
        echo ""

        local CHOICE
        read -p "$(echo -e "  ${YELLOW}请选择 [1-4/A/S/Q]: ${NC}")" CHOICE

        case "$CHOICE" in
            1) install_docker ;;
            2) install_vulhub ;;
            3) quick_deploy ;;
            4) step_proxy_pull ;;
            A|a) install_docker; install_vulhub; show_summary ;;
            S|s) show_summary ;;
            Q|q)
                echo -e "  ${GREEN}退出 — 日志: ${LOG_FILE}${NC}"
                echo ""
                exit 0
                ;;
            *) echo -e "  ${RED}无效选项${NC}"; sleep 0.5 ;;
        esac

        if [[ "$CHOICE" =~ ^[1-4Aa]$ ]]; then
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
  v2.0 — Mr.li8848
═══════════════════════════════════════════

SETUPLOG
main_menu

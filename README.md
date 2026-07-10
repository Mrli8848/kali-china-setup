# 🔐 Kali Linux 全方位配置工具集

> **Author:** Mr.li8848  
> **License:** MIT（仅供合法授权使用）

## ⚠️ 免责声明

本仓库所有脚本仅供合法的网络安全测试、教学研究、授权渗透测试使用。严禁用于未授权入侵或违反《网络安全法》的行为。使用者自行承担全部法律责任。

---

## 📦 脚本列表

| 脚本 | 用途 | 运行方式 |
|------|------|----------|
| `kali-china-setup.sh` | 🔐 Kali 换源/汉化/红蓝队工具链 | `sudo bash kali-china-setup.sh` |
| `kali-ai-setup.sh` | 🤖 Docker + Lobe Chat + 阿里云百炼 AI | `sudo bash kali-ai-setup.sh` |

---

## 🚀 kali-china-setup — 系统配置

```bash
wget https://raw.githubusercontent.com/Mrli8848/kali-china-setup/main/kali-china-setup.sh
sudo bash kali-china-setup.sh
# 输入解密密码进入主菜单
```

### 功能模块

| 模块 | 内容 |
|------|------|
| **一、系统基础初始化** | 镜像测速换源 · 账号加固 · 常用工具 · SSH · 字典库 |
| **二、渗透测试 / 红队** | Burp Suite · 信息收集 · 靶场 · 内网渗透 · 持久化 |
| **三、安全运维 / 蓝队** | 漏洞扫描器 · 基线核查 · 流量分析 · 应急响应 |
| **四、CTF 竞赛** | 密码学 · 二进制逆向 · Web 攻防 · 隐写取证 |
| **五、无线安全** | 网卡驱动 · aircrack-ng · AP 钓鱼 |

### 加密说明

分发版采用 **AES-256-CBC + PBKDF2** 加密，运行时输入密码解密到 `/tmp`，执行完自动安全擦除。

---

## 🤖 kali-ai-setup — AI 交互环境

```bash
wget https://raw.githubusercontent.com/Mrli8848/kali-china-setup/main/kali-ai-setup.sh
sudo bash kali-ai-setup.sh
```

### 一键部署

| 步骤 | 内容 |
|------|------|
| **① Docker** | 安装 Docker Engine，含镜像加速 |
| **② Lobe Chat** | Docker 一键部署开源聊天界面 |
| **③ API 配置** | 用户在阿里云百炼生成 Key → 脚本自动注入 |
| **④ 语音输入** | Win + H 语音听写 → Kali 输入框打字 |

### 语音输入原理

> Win + H 是 Windows 自带的语音听写功能，不需要在 Kali 里装任何东西。
> 你在 Kali 里点输入框 → 按 Win + H → 说话 → 文字自动打进去。

---

## 📝 更新日志

- **2026-07** — 新增 kali-ai-setup.sh；kali-china-setup v3.0 发布

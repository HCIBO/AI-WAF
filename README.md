# 🛡️ AI-WAF: AI-Powered Web Application Firewall

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.9+](https://img.shields.io/badge/python-3.9+-blue.svg)](https://www.python.org/downloads/)
[![Nginx](https://img.shields.io/badge/nginx-1.24+-green.svg)](https://nginx.org/)
[![ModSecurity](https://img.shields.io/badge/modsecurity-3.0+-red.svg)](https://modsecurity.org/)
[![Groq](https://img.shields.io/badge/groq-ai-orange.svg)](https://groq.com/)

> **AI-Powered Web Application Firewall that combines ModSecurity + OWASP CRS (200+ rules) with Groq AI for intelligent attack detection and instant Telegram alerts.**

---

## 🧠 What is AI-WAF?

**AI-WAF** is an intelligent, AI-powered Web Application Firewall that combines the power of **ModSecurity + OWASP CRS (200+ rules)** with **Groq AI** to provide real-time attack detection and instant Telegram alerts.

Traditional WAFs rely solely on rule-based detection. AI-WAF adds an **AI decision layer** that analyzes ModSecurity alerts and distinguishes between **real attacks** and **false positives**, dramatically reducing noise and improving accuracy.

## 🚀 Features

| Feature | Description |
|---------|-------------|
| **ModSecurity WAF** | Industry-standard Web Application Firewall |
| **OWASP CRS** | 200+ security rules (SQL Injection, XSS, LFI, RCE, etc.) |
| **Groq AI Decision Layer** | AI distinguishes real attacks from false positives |
| **Instant Telegram Alerts** | Real-time attack notifications |
| **One-Command Installation** | Fully automated bash script |
| **Blog Site Included** | Test environment out-of-the-box |
| **False Positive Reduction** | AI filters out false alarms |
| **Zero-Day Protection** | AI can detect novel attack patterns |
| **DetectionOnly Mode** | ModSecurity logs without blocking (AI decides) |
| **Full Audit Trail** | All attacks logged in `/var/log/modsec_audit.log` |

## 📋 System Components

| Component | Role | Port |
|-----------|------|------|
| **Nginx** | Web server / Reverse proxy | 80 |
| **ModSecurity** | WAF engine | Integrated with Nginx |
| **OWASP CRS** | 200+ security rules | Loaded by ModSecurity |
| **Flask** | AI-WAF service (Python) | 5000 |
| **Groq AI** | AI decision engine | API (external) |
| **Telegram Bot** | Alert notification system | API (external) |

---

## 🔧 Installation

### Prerequisites

| Requirement | Details |
|-------------|---------|
| **OS** | Ubuntu 22.04 or 24.04 LTS |
| **CPU** | 1 vCPU minimum (2+ recommended) |
| **RAM** | 1 GB minimum (2+ GB for AI) |
| **Disk** | 10 GB free space |
| **Root Access** | Required for installation |
| **Internet** | Required for API access |

### API Keys Required

1. **Groq API Key** - Get from [console.groq.com](https://console.groq.com/)
   - Free tier: 7,500 requests/day
   - Model: `openai/gpt-oss-120b`

2. **Telegram Bot Token** - Create via [@BotFather](https://t.me/botfather)
   - Free and unlimited

3. **Telegram Chat ID** - Get from [@getmyid_bot](https://t.me/getmyid_bot)

### One-Command Installation

```bash
curl -sSL https://raw.githubusercontent.com/HCIBO/AI-WAF/main/install.sh | sudo bash

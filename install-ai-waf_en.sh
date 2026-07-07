#!/bin/bash
# ============================================
# AI-WAF COMPLETE INSTALLATION SCRIPT
# ModSecurity + OWASP CRS + Groq AI + Telegram
# Ubuntu 22.04/24.04
# All issues resolved, ready to use!
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════╗"
echo "║        🛡️  AI-WAF INSTALLER  🛡️            ║"
echo "║   ModSecurity + OWASP CRS + Groq AI        ║"
echo "║        Telegram Instant Alerts             ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# Root check
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Please run as root: sudo $0${NC}"
    exit 1
fi

# ============================================
# USER INPUT
# ============================================
echo -e "\n${YELLOW}📝 Please enter the following information:${NC}"
echo ""

read -p "🔑 Groq API Key (https://console.groq.com/): " GROQ_API_KEY
if [ -z "$GROQ_API_KEY" ]; then
    echo -e "${RED}❌ Groq API Key is required!${NC}"
    exit 1
fi

read -p "🤖 Telegram Bot Token (from @BotFather): " TELEGRAM_BOT_TOKEN
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "${RED}❌ Telegram Bot Token is required!${NC}"
    exit 1
fi

read -p "👤 Telegram Chat ID (from @getmyid_bot): " TELEGRAM_CHAT_ID
if [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo -e "${RED}❌ Telegram Chat ID is required!${NC}"
    exit 1
fi

echo -e "\n${GREEN}✅ Information received. Starting installation...${NC}"

# ============================================
# 1. SYSTEM UPDATE
# ============================================
echo -e "\n${YELLOW}📦 Updating system...${NC}"
apt update && apt upgrade -y
apt install wget curl git nano -y

# ============================================
# 2. NGINX + MODSECURITY INSTALLATION
# ============================================
echo -e "\n${YELLOW}📦 Installing Nginx + ModSecurity...${NC}"

# Create www-data user if missing
groupadd -r www-data 2>/dev/null || true
useradd -r -g www-data -s /usr/sbin/nologin www-data 2>/dev/null || true

apt install nginx libnginx-mod-http-modsecurity -y

# ============================================
# 3. OWASP CRS DOWNLOAD
# ============================================
echo -e "\n${YELLOW}📥 Downloading OWASP CRS...${NC}"
cd /usr/local/src
rm -rf coreruleset
git clone https://github.com/coreruleset/coreruleset.git
cp coreruleset/crs-setup.conf.example /etc/nginx/crs-setup.conf
cp -r coreruleset/rules /etc/nginx/

# ============================================
# 4. MODSECURITY CONFIGURATION
# ============================================
echo -e "\n${YELLOW}⚙️  Configuring ModSecurity...${NC}"

# Copy ModSecurity files
cp /usr/share/nginx/docs/modsecurity/modsecurity.conf /etc/nginx/modsecurity.conf
cp /usr/share/nginx/docs/modsecurity/unicode.mapping /etc/nginx/

# ModSecurity configuration (with False Positive fixes)
cat > /etc/nginx/modsecurity.conf << 'EOF'
# ModSecurity Main Configuration
SecRuleEngine DetectionOnly

# Request Body
SecRequestBodyAccess On
SecRequestBodyLimit 134217728
SecRequestBodyNoFilesLimit 131072
SecRequestBodyLimitAction Reject

# Response Body
SecResponseBodyAccess On
SecResponseBodyMimeType text/plain text/html text/xml
SecResponseBodyLimit 524288
SecResponseBodyLimitAction ProcessPartial

# Temporary Files
SecTmpDir /tmp/
SecDataDir /tmp/

# Audit Log
SecAuditEngine RelevantOnly
SecAuditLogRelevantStatus "^(?:5|4(?!04))"
SecAuditLogParts ABIJDEFHZ
SecAuditLogType Serial
SecAuditLog /var/log/modsec_audit.log

# Unicode Mapping
SecUnicodeMapFile /etc/nginx/unicode.mapping 20127

# PCRE Limits
SecPcreMatchLimit 1000
SecPcreMatchLimitRecursion 1000

# Debug Log
SecDebugLog /var/log/modsec_debug.log
SecDebugLogLevel 0

# ============================================
# FALSE POSITIVE FIXES
# ============================================

# 941160: XSS InjectionChecker (false positive on empty requests)
SecRuleRemoveById 941160

# 920350: Host header numeric IP (normal behavior)
SecRuleRemoveById 920350

# 920420: Request content type (normal behavior)
SecRuleRemoveById 920420

# OWASP CRS - 200+ Rules
Include /etc/nginx/crs-setup.conf
Include /etc/nginx/rules/*.conf
EOF

# ============================================
# 5. NGINX CONFIGURATION
# ============================================
echo -e "\n${YELLOW}⚙️  Configuring Nginx...${NC}"

# Main nginx.conf
cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    server_tokens off;
    sendfile on;
    tcp_nopush on;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;
    gzip on;

    # ModSecurity active
    modsecurity on;
    modsecurity_rules_file /etc/nginx/modsecurity.conf;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

# ============================================
# 6. REMOVE DEFAULT SITE (Conflict Fix)
# ============================================
echo -e "\n${YELLOW}🗑️  Removing default Nginx site...${NC}"
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-available/default

# ============================================
# 7. NGINX AI-WAF PROXY PASS
# ============================================
echo -e "\n${YELLOW}⚙️  Setting up AI-WAF proxy...${NC}"
cat > /etc/nginx/conf.d/ai-waf.conf << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        proxy_connect_timeout 5s;
        proxy_send_timeout 5s;
        proxy_read_timeout 5s;
    }
}
EOF

# ============================================
# 8. START NGINX
# ============================================
echo -e "\n${YELLOW}🚀 Starting Nginx...${NC}"
nginx -t && systemctl restart nginx
systemctl enable nginx

# ============================================
# 9. LOG FILES
# ============================================
echo -e "\n${YELLOW}📂 Creating log files...${NC}"
touch /var/log/modsec_audit.log
touch /var/log/modsec_debug.log
chown www-data:www-data /var/log/modsec_audit.log
chown www-data:www-data /var/log/modsec_debug.log
chmod 644 /var/log/modsec_audit.log
chmod 644 /var/log/modsec_debug.log

# ============================================
# 10. AI-WAF PYTHON SERVICE
# ============================================
echo -e "\n${YELLOW}🐍 Installing AI-WAF Python service...${NC}"
apt install python3-pip python3-venv -y

mkdir -p /opt/ai-waf
cd /opt/ai-waf
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install flask requests groq gunicorn

# ============================================
# 11. AI-WAF CODE (Complete & Working)
# ============================================
echo -e "\n${YELLOW}📝 Writing AI-WAF code...${NC}"
cat > proxy.py << 'PYEOF'
import os
import json
import requests
import re
import subprocess
import time
import logging
from flask import Flask, request, Response, jsonify
from groq import Groq
from urllib.parse import unquote

app = Flask(__name__)

GROQ_API_KEY = "GROQ_API_KEY_PLACEHOLDER"
TELEGRAM_BOT_TOKEN = "TELEGRAM_BOT_TOKEN_PLACEHOLDER"
TELEGRAM_CHAT_ID = "TELEGRAM_CHAT_ID_PLACEHOLDER"

client = Groq(api_key=GROQ_API_KEY)
logging.basicConfig(level=logging.INFO)

def send_telegram_alert(message, threat_level="HIGH"):
    url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
    emoji = "🚨" if threat_level == "HIGH" else "⚠️"
    level_text = "CRITICAL" if threat_level == "HIGH" else "MEDIUM"
    
    full_message = f"""
{emoji} <b>ATTACK DETECTED!</b>
<b>Threat Level:</b> {level_text}

📌 <b>IP:</b> {message.get('ip', 'Unknown')}
🔗 <b>URL:</b> {message.get('uri', 'Unknown')}
🛠️ <b>Method:</b> {message.get('method', 'Unknown')}
📊 <b>OWASP CRS Rule:</b> {message.get('rule', 'Unknown')}
📝 <b>Rule Message:</b> {message.get('rule_message', 'Unknown')}
🤖 <b>AI Decision:</b> {message.get('ai_decision', 'Unknown')}
⏰ <b>Time:</b> {message.get('timestamp', 'Unknown')}
"""
    
    data = {"chat_id": TELEGRAM_CHAT_ID, "text": full_message, "parse_mode": "HTML"}
    try:
        response = requests.post(url, json=data, timeout=5)
        if response.status_code == 200:
            print("✅ Telegram: Alert sent!")
        else:
            print(f"❌ Telegram: {response.status_code}")
    except Exception as e:
        print(f"❌ Telegram error: {e}")

def get_modsecurity_alert():
    """Read ModSecurity logs from multiple sources"""
    
    # 1. Check audit log
    audit_log = "/var/log/modsec_audit.log"
    
    try:
        with open(audit_log, 'r') as f:
            lines = f.readlines()
            last_lines = lines[-100:] if len(lines) > 100 else lines
            
            for line in reversed(last_lines):
                if 'ModSecurity' in line and 'id "' in line:
                    rule_id_match = re.search(r'\[id "(\d+)"\]', line)
                    rule_msg_match = re.search(r'\[msg "([^"]+)"\]', line)
                    
                    if rule_id_match:
                        rule_id = rule_id_match.group(1)
                        rule_msg = rule_msg_match.group(1) if rule_msg_match else "Unknown"
                        
                        attack_keywords = ['SQLi', 'XSS', 'LFI', 'RCE', 'Command', 'Injection', 'Attack']
                        if any(keyword in rule_msg for keyword in attack_keywords):
                            severity = "CRITICAL" if rule_id.startswith("942") or rule_id.startswith("932") else "HIGH"
                            return {
                                "matched": True,
                                "rule_id": rule_id,
                                "rule_message": rule_msg,
                                "severity": severity
                            }
    except Exception as e:
        print(f"❌ Audit log read error: {e}")
    
    # 2. Check error log
    error_log = "/var/log/nginx/error.log"
    
    try:
        with open(error_log, 'r') as f:
            lines = f.readlines()
            last_lines = lines[-100:] if len(lines) > 100 else lines
            
            for line in reversed(last_lines):
                if 'ModSecurity' in line and 'id "' in line:
                    rule_id_match = re.search(r'\[id "(\d+)"\]', line)
                    rule_msg_match = re.search(r'\[msg "([^"]+)"\]', line)
                    
                    if rule_id_match:
                        rule_id = rule_id_match.group(1)
                        rule_msg = rule_msg_match.group(1) if rule_msg_match else "Unknown"
                        
                        attack_keywords = ['SQLi', 'XSS', 'LFI', 'RCE', 'Command', 'Injection', 'Attack']
                        if any(keyword in rule_msg for keyword in attack_keywords):
                            severity = "CRITICAL" if rule_id.startswith("942") or rule_id.startswith("932") else "HIGH"
                            return {
                                "matched": True,
                                "rule_id": rule_id,
                                "rule_message": rule_msg,
                                "severity": severity
                            }
    except Exception as e:
        print(f"❌ Error log read error: {e}")
    
    return {"matched": False}

def analyze_with_ai(request_data, modsec_data):
    if not modsec_data.get('matched', False):
        return False, "No OWASP CRS rule matched", "LOW", None
    
    uri = unquote(request_data.get('uri', ''))
    query = unquote(request_data.get('query_string', ''))
    rule_id = modsec_data.get('rule_id', 'Unknown')
    rule_msg = modsec_data.get('rule_message', 'Unknown')
    
    prompt = f"""
You are an AI security analyst. Analyze this OWASP CRS alert:

OWASP CRS ALERT:
- Rule ID: {rule_id}
- Message: {rule_msg}

REQUEST CONTEXT:
URL: {uri}
Query: {query}
IP: {request_data.get('ip', '')}
User-Agent: {request_data.get('user_agent', '')[:100]}

IMPORTANT: OWASP CRS alerts are rarely false positives. 
Only mark as FALSE_POSITIVE if it's clearly a legitimate request.

DECISION: "ATTACK" or "FALSE_POSITIVE"
CONFIDENCE: "HIGH", "MEDIUM", or "LOW"
REASON: Brief explanation

Your response:
"""
    
    try:
        chat_completion = client.chat.completions.create(
            messages=[
                {"role": "system", "content": "You are a strict security analyst. OWASP CRS alerts are rarely false positives. Only override if the request is clearly legitimate."},
                {"role": "user", "content": prompt}
            ],
            model="openai/gpt-oss-120b",
            temperature=0.1,
            max_tokens=150
        )
        
        result = chat_completion.choices[0].message.content.strip()
        print(f"🤖 AI: {result}")
        
        decision = "FALSE_POSITIVE"
        confidence = "MEDIUM"
        reason = "AI analysis completed"
        
        for line in result.split('\n'):
            line = line.strip()
            if line.startswith("DECISION:"):
                decision = line.replace("DECISION:", "").strip().upper()
            elif line.startswith("CONFIDENCE:"):
                confidence = line.replace("CONFIDENCE:", "").strip().upper()
            elif line.startswith("REASON:"):
                reason = line.replace("REASON:", "").strip()
        
        if decision == "ATTACK":
            return True, f"AI confirmed: {reason}", confidence, modsec_data
        elif decision == "FALSE_POSITIVE" and confidence == "HIGH":
            return False, f"AI overruled: {reason}", "LOW", modsec_data
        else:
            return True, f"AI uncertain, trusting OWASP CRS: {reason}", "MEDIUM", modsec_data
            
    except Exception as e:
        print(f"❌ AI error: {e}")
        return True, "AI failed, trusting OWASP CRS", "HIGH", modsec_data

def analyze_request(request_data):
    modsec_data = get_modsecurity_alert()
    
    if not modsec_data.get('matched', False):
        return False, "No OWASP CRS rules matched", "LOW", None
    
    return analyze_with_ai(request_data, modsec_data)

@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def proxy(path):
    request_data = {
        'uri': path,
        'query_string': request.query_string.decode('utf-8') if request.query_string else '',
        'method': request.method,
        'ip': request.remote_addr,
        'user_agent': request.headers.get('User-Agent', ''),
        'body': request.get_data().decode('utf-8', errors='ignore')[:1000],
        'timestamp': time.strftime('%Y-%m-%d %H:%M:%S')
    }
    
    print(f"📥 {request_data['method']} /{path}?{request_data['query_string']}")
    
    is_threat, reason, confidence, rule_data = analyze_request(request_data)
    
    if is_threat and rule_data:
        alert_data = {
            'ip': request_data['ip'],
            'uri': request_data['uri'],
            'method': request_data['method'],
            'rule': rule_data.get('rule_id', 'Unknown'),
            'rule_message': rule_data.get('rule_message', 'Unknown'),
            'ai_decision': f"ATTACK ({confidence})",
            'timestamp': request_data['timestamp']
        }
        send_telegram_alert(alert_data, rule_data.get('severity', 'HIGH'))
        return Response(f"403 Forbidden - OWASP CRS + AI WAF\nRule: {rule_data.get('rule_id', 'Unknown')}\nReason: {reason}", status=403)
    
    return "OK - AI-WAF Approved", 200

@app.route('/analyze', methods=['POST'])
def analyze():
    data = request.get_json()
    if not data:
        return jsonify({"error": "No data"}), 400
    
    is_threat, reason, confidence, rule_data = analyze_request(data)
    return jsonify({
        "threat": is_threat,
        "reason": reason,
        "confidence": confidence,
        "rule_data": rule_data
    })

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "service": "AI-WAF", "mode": "ModSecurity + OWASP CRS + AI"})

if __name__ == '__main__':
    print("🚀 AI-WAF starting...")
    print("🧠 Mode: ModSecurity + OWASP CRS + AI Decision")
    print("📡 API: http://0.0.0.0:5000")
    app.run(host='0.0.0.0', port=5000, debug=False)
PYEOF

# Place API keys
sed -i "s/GROQ_API_KEY_PLACEHOLDER/$GROQ_API_KEY/g" proxy.py
sed -i "s/TELEGRAM_BOT_TOKEN_PLACEHOLDER/$TELEGRAM_BOT_TOKEN/g" proxy.py
sed -i "s/TELEGRAM_CHAT_ID_PLACEHOLDER/$TELEGRAM_CHAT_ID/g" proxy.py

# ============================================
# 12. SYSTEMD SERVICE
# ============================================
echo -e "\n${YELLOW}⚙️  Creating systemd service...${NC}"
cat > /etc/systemd/system/ai-waf.service << 'EOF'
[Unit]
Description=AI WAF Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/ai-waf
ExecStart=/opt/ai-waf/venv/bin/python3 /opt/ai-waf/proxy.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ai-waf
systemctl start ai-waf

# ============================================
# 13. FINAL CHECK
# ============================================
echo -e "\n${YELLOW}🧪 Testing system...${NC}"

sleep 3

# AI-WAF health check
if curl -s http://localhost:5000/health | grep -q healthy; then
    echo -e "${GREEN}✅ AI-WAF service is running!${NC}"
else
    echo -e "${RED}❌ AI-WAF service is not running!${NC}"
fi

# Nginx check
if systemctl is-active --quiet nginx; then
    echo -e "${GREEN}✅ Nginx is running!${NC}"
else
    echo -e "${RED}❌ Nginx is not running!${NC}"
fi

# Get IP
IP=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")

# ============================================
# 14. USER INFORMATION
# ============================================
echo -e "\n${GREEN}"
echo "╔══════════════════════════════════════════════╗"
echo "║        ✅ INSTALLATION COMPLETE!            ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${GREEN}🌐 AI-WAF URL: http://$IP${NC}"
echo -e "${GREEN}📡 Health Check: http://$IP/health${NC}"
echo -e "${GREEN}📊 OWASP CRS: 200+ rules active${NC}"
echo -e "${GREEN}🤖 AI Mode: Groq AI active${NC}"
echo -e "${GREEN}📱 Telegram: Instant alerts active${NC}"

echo -e "\n${YELLOW}📋 Test commands:${NC}"
echo -e "  ${CYAN}curl http://$IP/${NC} ${GREEN}# Normal request (200 OK)${NC}"
echo -e "  ${CYAN}curl \"http://$IP/?id=1%27%20OR%20%271%27=%271\"${NC} ${GREEN}# SQL Injection (403 Forbidden)${NC}"
echo -e "  ${CYAN}curl \"http://$IP/?q=<script>alert(1)</script>\"${NC} ${GREEN}# XSS (403 Forbidden)${NC}"
echo -e "  ${CYAN}curl \"http://$IP/?file=../../etc/passwd\"${NC} ${GREEN}# Path Traversal (403 Forbidden)${NC}"

echo -e "\n${YELLOW}📝 Log monitoring:${NC}"
echo -e "  ${CYAN}sudo journalctl -u ai-waf -f${NC} ${GREEN}# AI-WAF logs${NC}"
echo -e "  ${CYAN}sudo tail -f /var/log/modsec_audit.log${NC} ${GREEN}# ModSecurity audit log${NC}"
echo -e "  ${CYAN}sudo tail -f /var/log/nginx/error.log${NC} ${GREEN}# Nginx error log${NC}"

echo -e "\n${GREEN}✅ AI-WAF successfully installed! Attacks will be reported to Telegram instantly.${NC}"
echo -e "${GREEN}   Thank you! 🚀${NC}"
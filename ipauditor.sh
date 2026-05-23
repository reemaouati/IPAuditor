#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_FILE="${SCRIPT_DIR}/ips.json"
PHP_FILE="${SCRIPT_DIR}/server.php"
PORT=8080
PHP_PID=""
TUNNEL_PID=""

display_banner() {
    clear
    cat << "EOF"
IPAuditor - Public IP Address Tracking CLI Tool
EOF
}

check_requirements() {
    local missing=()
    
    command -v php &> /dev/null || missing+=("php")
    command -v cloudflared &> /dev/null || missing+=("cloudflared")
    command -v jq &> /dev/null || missing+=("jq")
    command -v column &> /dev/null || missing+=("column")
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Error: Missing required tools:"
        for tool in "${missing[@]}"; do
            echo "  - $tool"
        done
        exit 1
    fi
    
    if [ ! -f "$PHP_FILE" ]; then
        echo "Error: server.php not found"
        exit 1
    fi
}

initialize_json() {
    if [ ! -f "$JSON_FILE" ]; then
        echo "[]" > "$JSON_FILE"
    fi
}

display_help() {
    cat << "EOF"
Usage: ./ipauditor.sh [OPTIONS]

Options:
  -h, --help    Display this help message
  -u, --url     Generate public URL and start listening
  -i, --ip      Display stored IP data
  -c, --clear   Clear all stored data

Examples:
  ./ipauditor.sh --help
  ./ipauditor.sh -u
  ./ipauditor.sh --ip

EOF
}

start_php_server() {
    php -S localhost:${PORT} -t "${SCRIPT_DIR}" > /dev/null 2>&1 &
    PHP_PID=$!
    sleep 2
    
    if ! kill -0 $PHP_PID 2>/dev/null; then
        echo "Error: Failed to start PHP server"
        exit 1
    fi
}

generate_url() {
    display_banner
    check_requirements
    initialize_json
    
    start_php_server
    
    cloudflared tunnel --url localhost:${PORT} > /tmp/cloudflare_tunnel.log 2>&1 &
    TUNNEL_PID=$!
    
    sleep 3
    TUNNEL_URL=$(grep -oP 'https://[^ ]+' /tmp/cloudflare_tunnel.log | head -1 || echo "")
    
    if [ -z "$TUNNEL_URL" ]; then
        echo "Error: Failed to establish Cloudflare Tunnel"
        kill $PHP_PID 2>/dev/null || true
        kill $TUNNEL_PID 2>/dev/null || true
        exit 1
    fi
    
    echo ""
    echo "Public URL:"
    echo "$TUNNEL_URL"
    echo ""
    echo "Listening for connections..."
    echo "Press Ctrl+C to stop"
    echo ""
    
    listen_for_connections
    
    cleanup
}

listen_for_connections() {
    local connection_count=0
    
    while true; do
        if [ -f "$JSON_FILE" ]; then
            local current_count=$(jq 'length' "$JSON_FILE" 2>/dev/null || echo 0)
            
            if [ "$current_count" -gt "$connection_count" ]; then
                connection_count=$current_count
                echo "[+] New connection detected"
                
                local latest=$(jq '.[-1]' "$JSON_FILE" 2>/dev/null)
                if [ ! -z "$latest" ] && [ "$latest" != "null" ]; then
                    local ip=$(echo "$latest" | jq -r '.ip // "N/A"')
                    local timestamp=$(echo "$latest" | jq -r '.timestamp // "N/A"')
                    echo "IP: $ip"
                    echo "Time: $timestamp"
                    echo ""
                fi
            fi
        fi
        
        sleep 2
    done
}

display_ip_data() {
    display_banner
    echo ""
    
    if [ ! -f "$JSON_FILE" ]; then
        echo "No data stored yet"
        exit 0
    fi
    
    local count=$(jq 'length' "$JSON_FILE" 2>/dev/null || echo 0)
    
    if [ "$count" -eq 0 ]; then
        echo "No visitors recorded"
        exit 0
    fi
    
    echo "Captured IP Addresses ($count records)"
    echo ""
    
    jq -r '.[] | [.timestamp, .ip, .user_agent // "N/A"] | @csv' "$JSON_FILE" | \
    column -t -s',' \
           -N "TIMESTAMP,IP,USER_AGENT" \
           --table-columns TIMESTAMP,IP,USER_AGENT
    
    echo ""
}

clear_ip_data() {
    if [ ! -f "$JSON_FILE" ]; then
        echo "No data to clear"
        exit 0
    fi
    
    echo "Clear all stored IP data? (yes/no)"
    read -r response
    
    if [ "$response" = "yes" ]; then
        echo "[]" > "$JSON_FILE"
        echo "Data cleared"
    else
        echo "Cancelled"
    fi
}

cleanup() {
    if [ ! -z "$PHP_PID" ] && kill -0 $PHP_PID 2>/dev/null; then
        kill $PHP_PID 2>/dev/null || true
    fi
    
    if [ ! -z "$TUNNEL_PID" ] && kill -0 $TUNNEL_PID 2>/dev/null; then
        kill $TUNNEL_PID 2>/dev/null || true
    fi
}

trap 'cleanup' EXIT INT TERM

main() {
    if [ $# -eq 0 ]; then
        display_banner
        echo ""
        exit 0
    fi
    
    case "$1" in
        -h|--help)
            display_help
            ;;
        -u|--url)
            generate_url
            ;;
        -i|--ip)
            display_ip_data
            ;;
        -c|--clear)
            clear_ip_data
            ;;
        *)
            echo "Error: Unknown option: $1"
            exit 1
            ;;
    esac
}

main "$@"

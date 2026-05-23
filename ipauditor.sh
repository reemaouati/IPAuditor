#!/bin/bash

################################################################################
# IPAuditor - Public IP Address Tracking CLI Tool
# A Bash scripting tool that generates a public URL to capture visitor's IP
# Uses PHP and Cloudflare tunneling for real-time IP address tracking
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSON_FILE="${SCRIPT_DIR}/ips.json"
PHP_FILE="${SCRIPT_DIR}/server.php"
PORT=8080
TUNNEL_URL=""

################################################################################
# Function: Display ASCII Art Banner
################################################################################
display_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║                    🔍 I P A U D I T O R 🔍                   ║
    ║                                                              ║
    ║            Public IP Address Tracking CLI Tool              ║
    ║                                                              ║
    ║          Powered by PHP & Cloudflare Tunnel                ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

################################################################################
# Function: Check Runtime Requirements
################################################################################
check_requirements() {
    local missing_tools=()

    # Check for required commands
    command -v php &> /dev/null || missing_tools+=("php")
    command -v cloudflared &> /dev/null || missing_tools+=("cloudflared")
    command -v jq &> /dev/null || missing_tools+=("jq")
    command -v column &> /dev/null || missing_tools+=("column")
    command -v curl &> /dev/null || missing_tools+=("curl")

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}❌ Error: Missing required tools:${NC}"
        for tool in "${missing_tools[@]}"; do
            echo -e "  ${RED}• ${tool}${NC}"
        done
        echo -e "\n${YELLOW}Install missing dependencies and try again.${NC}"
        exit 1
    fi

    # Check if server.php exists
    if [ ! -f "$PHP_FILE" ]; then
        echo -e "${RED}❌ Error: server.php not found at ${PHP_FILE}${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ All requirements met!${NC}\n"
}

################################################################################
# Function: Initialize JSON file
################################################################################
initialize_json() {
    if [ ! -f "$JSON_FILE" ]; then
        echo "[]" > "$JSON_FILE"
        echo -e "${GREEN}✅ Created ips.json${NC}"
    fi
}

################################################################################
# Function: Display Help
################################################################################
display_help() {
    cat << EOF
${CYAN}IPAuditor - Public IP Address Tracking CLI Tool${NC}

${BLUE}USAGE:${NC}
    ./ipauditor.sh [OPTIONS]

${BLUE}OPTIONS:${NC}
    -h, --help              Display this help message and all available options
    -u, --url               Generate a public URL and start listening for connections
    -i, --ip                Display stored IP address data from ips.json
    -v, --version           Display version information
    -c, --clear             Clear all stored IP data from ips.json

${BLUE}EXAMPLES:${NC}
    ./ipauditor.sh --help                    # Show this help message
    ./ipauditor.sh -u                        # Generate public URL and listen
    ./ipauditor.sh --ip                      # Display captured IP data
    ./ipauditor.sh --clear                   # Clear all stored data

${BLUE}REQUIREMENTS:${NC}
    • php (PHP CLI)
    • cloudflared (Cloudflare Tunnel client)
    • jq (JSON processor)
    • column (Text formatter)
    • curl (HTTP client)

${BLUE}FEATURES:${NC}
    ✓ Generate public URLs via Cloudflare Tunnel
    ✓ Real-time IP address capture
    ✓ Automatic data storage in JSON format
    ✓ View captured data with formatted output
    ✓ Cross-platform compatibility

${CYAN}For more information, visit the project repository${NC}

EOF
}

################################################################################
# Function: Display Version
################################################################################
display_version() {
    echo -e "${CYAN}IPAuditor${NC} version ${BLUE}1.0.0${NC}"
    echo "Public IP Address Tracking CLI Tool"
    echo "Powered by PHP & Cloudflare Tunnel"
}

################################################################################
# Function: Start PHP Server
################################################################################
start_php_server() {
    echo -e "${BLUE}Starting PHP server on port ${PORT}...${NC}"
    php -S localhost:${PORT} -t "${SCRIPT_DIR}" > /dev/null 2>&1 &
    PHP_PID=$!
    
    # Give server time to start
    sleep 2
    
    # Verify server started
    if ! kill -0 $PHP_PID 2>/dev/null; then
        echo -e "${RED}❌ Failed to start PHP server${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ PHP server running (PID: ${PHP_PID})${NC}"
}

################################################################################
# Function: Start Cloudflare Tunnel
################################################################################
start_cloudflare_tunnel() {
    echo -e "${BLUE}Starting Cloudflare Tunnel...${NC}"
    
    # Start tunnel and capture output
    local tunnel_output=$(cloudflared tunnel --url localhost:${PORT} 2>&1 | head -20)
    
    # Extract URL from output
    TUNNEL_URL=$(echo "$tunnel_output" | grep -oP 'https://[^ ]+' | head -1 || echo "")
    
    if [ -z "$TUNNEL_URL" ]; then
        echo -e "${RED}❌ Failed to establish Cloudflare Tunnel${NC}"
        kill $PHP_PID 2>/dev/null || true
        exit 1
    fi
    
    echo -e "${GREEN}✅ Cloudflare Tunnel established${NC}"
}

################################################################################
# Function: Generate Public URL
################################################################################
generate_url() {
    display_banner
    check_requirements
    initialize_json
    
    start_php_server
    
    # Start tunnel in background
    cloudflared tunnel --url localhost:${PORT} > /tmp/cloudflare_tunnel.log 2>&1 &
    TUNNEL_PID=$!
    
    # Wait for tunnel to establish and extract URL
    sleep 3
    TUNNEL_URL=$(grep -oP 'https://[^ ]+' /tmp/cloudflare_tunnel.log | head -1 || echo "")
    
    if [ -z "$TUNNEL_URL" ]; then
        echo -e "${RED}❌ Failed to establish Cloudflare Tunnel${NC}"
        kill $PHP_PID 2>/dev/null || true
        kill $TUNNEL_PID 2>/dev/null || true
        exit 1
    fi
    
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✅ Public URL Generated Successfully!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    echo -e "${YELLOW}Share this link with your target:${NC}"
    echo -e "${BLUE}${TUNNEL_URL}${NC}\n"
    
    echo -e "${CYAN}Waiting for connections...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop listening${NC}\n"
    
    # Listen for connections
    listen_for_connections
    
    # Cleanup
    cleanup $PHP_PID $TUNNEL_PID
}

################################################################################
# Function: Listen for Connections
################################################################################
listen_for_connections() {
    local connection_count=0
    
    while true; do
        # Check if new IPs have been recorded
        if [ -f "$JSON_FILE" ]; then
            local current_count=$(jq 'length' "$JSON_FILE" 2>/dev/null || echo 0)
            
            if [ "$current_count" -gt "$connection_count" ]; then
                connection_count=$current_count
                echo -e "${GREEN}[+] New connection detected!${NC}"
                
                # Display latest entry
                local latest=$(jq '.[-1]' "$JSON_FILE" 2>/dev/null)
                if [ ! -z "$latest" ] && [ "$latest" != "null" ]; then
                    local ip=$(echo "$latest" | jq -r '.ip // "N/A"')
                    local timestamp=$(echo "$latest" | jq -r '.timestamp // "N/A"')
                    echo -e "    IP: ${BLUE}${ip}${NC}"
                    echo -e "    Time: ${YELLOW}${timestamp}${NC}\n"
                fi
            fi
        fi
        
        sleep 2
    done
}

################################################################################
# Function: Display Stored IP Data
################################################################################
display_ip_data() {
    display_banner
    
    if [ ! -f "$JSON_FILE" ]; then
        echo -e "${YELLOW}⚠ No data stored yet. Generate a URL first.${NC}"
        exit 0
    fi
    
    local count=$(jq 'length' "$JSON_FILE" 2>/dev/null || echo 0)
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}⚠ No visitors recorded yet.${NC}"
        exit 0
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📊 Captured IP Address Data (${count} records)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    
    # Format and display data
    jq -r '.[] | [.timestamp, .ip, .user_agent // "N/A"] | @csv' "$JSON_FILE" | \
    column -t -s',' \
           -N "TIMESTAMP,IP ADDRESS,USER AGENT" \
           --table-columns TIMESTAMP,IP,AGENT
    
    echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Total visitors: ${GREEN}${count}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

################################################################################
# Function: Clear IP Data
################################################################################
clear_ip_data() {
    if [ ! -f "$JSON_FILE" ]; then
        echo -e "${YELLOW}⚠ No data file to clear.${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}⚠ Are you sure you want to clear all stored IP data? (yes/no)${NC}"
    read -r response
    
    if [ "$response" = "yes" ]; then
        echo "[]" > "$JSON_FILE"
        echo -e "${GREEN}✅ All data cleared successfully.${NC}"
    else
        echo -e "${BLUE}Cancelled.${NC}"
    fi
}

################################################################################
# Function: Cleanup on Exit
################################################################################
cleanup() {
    local php_pid=${1:-}
    local tunnel_pid=${2:-}
    
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    
    if [ ! -z "$php_pid" ] && kill -0 $php_pid 2>/dev/null; then
        kill $php_pid 2>/dev/null || true
        echo -e "${GREEN}✅ PHP server stopped${NC}"
    fi
    
    if [ ! -z "$tunnel_pid" ] && kill -0 $tunnel_pid 2>/dev/null; then
        kill $tunnel_pid 2>/dev/null || true
        echo -e "${GREEN}✅ Cloudflare Tunnel stopped${NC}"
    fi
    
    echo -e "${GREEN}✅ Cleanup complete${NC}"
}

# Trap signals for cleanup
trap 'cleanup $PHP_PID $TUNNEL_PID' EXIT INT TERM

################################################################################
# Main Script Logic
################################################################################
main() {
    # Initialize variables
    PHP_PID=""
    TUNNEL_PID=""
    
    # Parse command line arguments
    if [ $# -eq 0 ]; then
        display_banner
        echo -e "${YELLOW}No options provided. Use${NC} ${BLUE}-h${NC} ${YELLOW}or${NC} ${BLUE}--help${NC} ${YELLOW}for help.${NC}\n"
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
        -v|--version)
            display_version
            ;;
        -c|--clear)
            clear_ip_data
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            echo -e "Use ${BLUE}-h${NC} or ${BLUE}--help${NC} for usage information.\n"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"

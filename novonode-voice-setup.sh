#!/bin/bash

set -e  # Exit on error
set -o pipefail
set -u

# ANSI color codes
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

clear

# Display Novonode ASCII Art in red
echo -e "${RED}"
cat <<'EOF'
                                       _         _               _   _             
                                      | |       | |             | | (_)            
 _ __   _____   _____  _ __   ___   __| | ___   | |__   ___  ___| |_ _ _ __   __ _ 
| '_ \ / _ \ \ / / _ \| '_ \ / _ \ / _` |/ _ \  | '_ \ / _ \/ __| __| | '_ \ / _` |
| | | | (_) \ V / (_) | | | | (_) | (_| |  __/  | | | | (_) \__ \ |_| | | | | (_| |
|_| |_|\___/ \_/ \___/|_| |_|\___/ \__,_|\___|  |_| |_|\___/|___/\__|_|_| |_|\__, |
                                                                              __/ |
                                                                             |___/ 
EOF
echo -e "${RESET}"

spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    echo -ne "   "
    while ps -p $pid > /dev/null 2>&1; do
        for i in $(seq 0 3); do
            echo -ne "\b${spinstr:i:1}"
            sleep $delay
        done
    done
    echo -ne "\b✔\n"
}

step() {
    echo -e "${CYAN}${BOLD}➜ $1...${RESET}"
}

success() {
    echo -e "${GREEN}✔ $1${RESET}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${RESET}"
}

error() {
    echo -e "${RED}✖ $1${RESET}"
}

# Display current server timezone
echo -e "${BLUE}${BOLD}Current Server Timezone Information:${RESET}"
timedatectl | grep "Time zone"
echo ""

# Prompt for FiveM server restart time(s)
echo -e "${YELLOW}${BOLD}FiveM Server Restart Configuration${RESET}"
echo -e "${CYAN}Please enter the time(s) your FiveM server restarts (in server's local timezone)${RESET}"
echo -e "${CYAN}Format: HH:MM (24-hour format, e.g., 04:00 for 4 AM or 16:30 for 4:30 PM)${RESET}"
echo -e "${CYAN}For multiple restart times, separate with commas (e.g., 04:00,12:00,20:00)${RESET}"
read -p "Restart time(s): " RESTART_TIMES

# Split restart times by comma and validate each one
IFS=',' read -ra TIME_ARRAY <<< "$RESTART_TIMES"
VALID_TIMES=()

for TIME in "${TIME_ARRAY[@]}"; do
    # Trim whitespace
    TIME=$(echo "$TIME" | xargs)
    
    # Validate time format
    if ! [[ $TIME =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
        error "Invalid time format: $TIME. Please use HH:MM format (e.g., 04:00)"
        exit 1
    fi
    
    VALID_TIMES+=("$TIME")
done

if [ ${#VALID_TIMES[@]} -eq 0 ]; then
    error "No valid restart times provided"
    exit 1
fi

success "Restart time(s) configured: ${VALID_TIMES[*]}"

# Update system packages
step "Updating system packages"
sudo apt update &>/dev/null && sudo apt upgrade -y &>/dev/null &
spinner
success "System updated successfully"

# Install dependencies
step "Installing dependencies"
sudo apt install -y llvm clang make pkg-config libssl-dev git curl ufw &>/dev/null &
spinner
success "Dependencies installed"

# Check if Rust is installed
step "Checking for Rust installation"
if ! command -v rustc &>/dev/null; then
    warning "Rust not found, installing now"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y &>/dev/null
    source "$HOME/.cargo/env"
    success "Rust installed successfully"
else
    success "Rust is already installed"
fi

# Clone Rust-Mumble
step "Cloning Rust-Mumble repository"
if [ ! -d "/root/rust-mumble" ]; then
    git clone https://github.com/AvarianKnight/rust-mumble.git /root/rust-mumble &>/dev/null &
    spinner
    success "Rust-Mumble repository cloned"
else
    success "Rust-Mumble already exists, skipping"
fi

# Build Rust-Mumble
cd /root/rust-mumble
step "Building Rust-Mumble"
cargo clean &>/dev/null && cargo build --release &>/dev/null &
spinner
success "Rust-Mumble built successfully"

# Check for certificates
step "Checking if certificates exist"
if [ ! -f "/root/rust-mumble/cert.pem" ] || [ ! -f "/root/rust-mumble/key.pem" ]; then
    warning "Certificates not found, generating self-signed certificates"
    openssl req -newkey rsa:2048 -days 365 -nodes -x509 \
        -keyout /root/rust-mumble/key.pem -out /root/rust-mumble/cert.pem \
        -subj "/CN=Rust-Mumble" &>/dev/null &
    spinner
    success "Certificates generated"
else
    success "Certificates already exist, skipping"
fi

# Create systemd service
step "Creating systemd service"
cat <<EOF | sudo tee /etc/systemd/system/rust-mumble.service &>/dev/null
[Unit]
Description=Rust-Mumble Voice Server
After=network.target

[Service]
User=root
WorkingDirectory=/root/rust-mumble
ExecStart=/root/rust-mumble/target/release/rust-mumble --cert /root/rust-mumble/cert.pem --key /root/rust-mumble/key.pem --listen 0.0.0.0:55500 --http-listen 0.0.0.0:8080 --restrict-to-version CitizenFX --http-password dummy
Restart=always
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
success "Systemd service created"

# Reload systemd
step "Reloading systemd and enabling Rust-Mumble service"
sudo systemctl daemon-reload &>/dev/null
sudo systemctl enable rust-mumble &>/dev/null
sudo systemctl start rust-mumble &
spinner
success "Rust-Mumble service started"

# Configure file descriptor limits
step "Configuring file descriptor limits"
cat <<EOF | sudo tee -a /etc/security/limits.conf &>/dev/null
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576
EOF
success "File descriptor limits set"

step "Ensuring PAM applies limits"
echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/common-session &>/dev/null
echo "session required pam_limits.so" | sudo tee -a /etc/pam.d/common-session-noninteractive &>/dev/null
success "PAM limits applied"

step "Setting system-wide limits"
sudo sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE=1048576/' /etc/systemd/system.conf &>/dev/null
sudo sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE=1048576/' /etc/systemd/user.conf &>/dev/null
success "System-wide limits configured"

# Configure firewall
step "Configuring firewall rules"
sudo ufw allow 55500/tcp &>/dev/null
sudo ufw allow 55500/udp &>/dev/null
sudo ufw allow 8080/tcp &>/dev/null
sudo systemctl enable ufw &>/dev/null
sudo ufw enable &>/dev/null &
spinner
success "Firewall rules applied"

# Configure crontab for automatic restart
step "Configuring automatic restart via crontab"

# Remove any existing rust-mumble crontab entries
crontab -l 2>/dev/null | grep -v "rust-mumble.service" | crontab - 2>/dev/null || true

# Create crontab entries for each restart time
CRON_ENTRIES=()
for TIME in "${VALID_TIMES[@]}"; do
    # Extract hour and minute
    RESTART_HOUR=$(echo $TIME | cut -d: -f1)
    RESTART_MINUTE=$(echo $TIME | cut -d: -f2)
    
    # Remove leading zeros for cron (cron doesn't like leading zeros)
    RESTART_HOUR=$((10#$RESTART_HOUR))
    RESTART_MINUTE=$((10#$RESTART_MINUTE))
    
    CRON_ENTRY="$RESTART_MINUTE $RESTART_HOUR * * * /usr/bin/systemctl restart rust-mumble.service"
    CRON_ENTRIES+=("$CRON_ENTRY")
done

# Add all crontab entries
(
    crontab -l 2>/dev/null | grep -v "rust-mumble.service" || true
    printf '%s\n' "${CRON_ENTRIES[@]}"
) | crontab -

if [ ${#VALID_TIMES[@]} -eq 1 ]; then
    success "Crontab configured to restart rust-mumble.service daily at ${VALID_TIMES[0]}"
else
    success "Crontab configured to restart rust-mumble.service daily at: ${VALID_TIMES[*]}"
fi

echo -e "\n${GREEN}${BOLD}All tasks completed successfully! Rust-Mumble is now running.${RESET}"
if [ ${#VALID_TIMES[@]} -eq 1 ]; then
    echo -e "${CYAN}Automatic restart scheduled for: ${VALID_TIMES[0]} daily${RESET}\n"
else
    echo -e "${CYAN}Automatic restarts scheduled for: ${VALID_TIMES[*]} daily${RESET}\n"
fi

# Display Rust-Mumble Service Status
step "Checking Rust-Mumble service status"
sudo systemctl status rust-mumble --no-pager

echo -e "\n${BLUE}${BOLD}Crontab Entries:${RESET}"
for ENTRY in "${CRON_ENTRIES[@]}"; do
    echo -e "${CYAN}$ENTRY${RESET}"
done

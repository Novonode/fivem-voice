#!/usr/bin/env bash
set -euo pipefail

CRON_FILE="/etc/cron.d/rust-mumble-restart"
SERVICE_NAME="rust-mumble"
CMD="/bin/systemctl restart ${SERVICE_NAME}"

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Please run as root: sudo $0"
    exit 1
  fi
}

need_whiptail() {
  if ! command -v whiptail >/dev/null 2>&1; then
    echo "whiptail is required. Installing..."
    if command -v apt-get >/dev/null 2>&1; then
      apt-get update -y && apt-get install -y whiptail
    elif command -v dnf >/dev/null 2>&1; then
      dnf install -y newt
    elif command -v yum >/dev/null 2>&1; then
      yum install -y newt
    elif command -v pacman >/dev/null 2>&1; then
      pacman -Sy --noconfirm libnewt
    else
      echo "Could not auto-install whiptail. Install it manually and re-run."
      exit 1
    fi
  fi
}

server_tz() {
  timedatectl show -p Timezone --value 2>/dev/null || echo "UTC"
}

write_cron() {
  local cron_line="$1"
  cat > "$CRON_FILE" <<EOF
# Managed by novonode voiceserver restart menu
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$cron_line
EOF
  chmod 0644 "$CRON_FILE"
}

remove_cron() {
  rm -f "$CRON_FILE"
}

current_status() {
  if [[ -f "$CRON_FILE" ]]; then
    echo "Enabled ✅"
    echo
    echo "Cron file: $CRON_FILE"
    echo
    echo "Active schedule line:"
    grep -vE '^(#|SHELL=|PATH=|$)' "$CRON_FILE" || true
  else
    echo "Disabled ❌"
    echo
    echo "No cron file found at: $CRON_FILE"
  fi
}

validate_int_range() {
  local val="$1" min="$2" max="$3"
  [[ "$val" =~ ^[0-9]+$ ]] || return 1
  (( val >= min && val <= max )) || return 1
  return 0
}

# Convert “client timezone + HH:MM” -> server HH:MM for today
convert_time_to_server() {
  local client_tz="$1" hh="$2" mm="$3"
  local s_tz
  s_tz="$(server_tz)"

  # pick today's date in server timezone, then interpret that same date in client tz
  # we build a datetime "today HH:MM" in client tz and convert to server tz.
  local today
  today="$(TZ="$s_tz" date +%F)"

  # Convert using GNU date. If parsing fails, return blank.
  local out
  out="$(TZ="$s_tz" date -d "$(TZ="$client_tz" date -d "${today} ${hh}:${mm}" +'%F %T %z')" +'%H:%M' 2>/dev/null || true)"
  echo "$out"
}

timezone_conversion_ui() {
  local s_tz
  s_tz="$(server_tz)"

  # A “nice and easy” shortlist (can add more)
  local tz
  tz=$(whiptail --title "Timezone Conversion" --menu "Server timezone: ${s_tz}\n\nPick your timezone:" 20 80 10 \
    "America/New_York" "US Eastern (ET)" \
    "America/Chicago"  "US Central (CT)" \
    "America/Denver"   "US Mountain (MT)" \
    "America/Los_Angeles" "US Pacific (PT)" \
    "Europe/London"    "UK (GMT/BST)" \
    "Europe/Berlin"    "Central Europe" \
    "Australia/Sydney" "Australia (Sydney)" \
    "UTC"              "UTC" \
    "CUSTOM"           "Type a timezone name" 3>&1 1>&2 2>&3) || return

  if [[ "$tz" == "CUSTOM" ]]; then
    tz=$(whiptail --title "Custom Timezone" --inputbox "Enter timezone (example: Europe/Paris)\n\nTip: list all with:\n  timedatectl list-timezones" 12 80 "" 3>&1 1>&2 2>&3) || return
  fi

  local hour minute
  hour=$(whiptail --title "Timezone Conversion" --inputbox "Enter the time you WANT in ${tz}\n\nHour (0-23):" 12 70 "4" 3>&1 1>&2 2>&3) || return
  validate_int_range "$hour" 0 23 || { whiptail --msgbox "Invalid hour. Must be 0-23." 10 45; return; }

  minute=$(whiptail --title "Timezone Conversion" --inputbox "Minute (0-59):" 10 60 "0" 3>&1 1>&2 2>&3) || return
  validate_int_range "$minute" 0 59 || { whiptail --msgbox "Invalid minute. Must be 0-59." 10 45; return; }

  local server_hhmm
  server_hhmm="$(convert_time_to_server "$tz" "$hour" "$minute")"
  if [[ -z "$server_hhmm" ]]; then
    whiptail --msgbox "Could not convert time.\n\nThis server might not have GNU date features or the timezone string may be invalid.\n\nTry:\n  timedatectl list-timezones" 14 70
    return
  fi

  local now_client now_server
  now_client="$(TZ="$tz" date '+%Y-%m-%d %H:%M (%Z)')"
  now_server="$(TZ="$s_tz" date '+%Y-%m-%d %H:%M (%Z)')"

  whiptail --title "Conversion Result" --msgbox \
"Current time:
- In ${tz}: ${now_client}
- On server (${s_tz}): ${now_server}

If you want the restart at ${hour}:$(printf '%02d' "$minute") in ${tz},
set the cron time to: ${server_hhmm} (server local time)

Cron reminder (daily):
MIN HOUR * * *  (server time)

Would you like to APPLY this as a DAILY restart time?" 22 80

  if whiptail --title "Apply Daily Schedule" --yesno "Apply daily restart using server time ${server_hhmm}?\n\nThis will schedule:\n${server_hhmm} server local time, daily." 14 75; then
    local sh sm
    sh="${server_hhmm%:*}"
    sm="${server_hhmm#*:}"
    write_cron "${sm} ${sh} * * * root ${CMD}"
    whiptail --msgbox "Saved ✅\n\nDaily restart at ${server_hhmm} (server timezone: ${s_tz})\n\nCron: ${sm} ${sh} * * * root ${CMD}" 12 80
  fi
}

set_server_timezone_ui() {
  local s_tz
  s_tz="$(server_tz)"
  if ! command -v timedatectl >/dev/null 2>&1; then
    whiptail --msgbox "timedatectl not found on this system.\n\nYou can usually set timezone by updating /etc/localtime, but this menu uses timedatectl." 12 70
    return
  fi

  if ! whiptail --yesno "Server timezone is currently:\n\n${s_tz}\n\nDo you want to change the SERVER timezone?" 14 70; then
    return
  fi

  local tz
  tz=$(whiptail --title "Set Server Timezone" --inputbox \
"Enter server timezone (example: America/New_York)\n\nTip: list all with:\n  timedatectl list-timezones" 14 80 "" 3>&1 1>&2 2>&3) || return

  if timedatectl set-timezone "$tz" 2>/dev/null; then
    whiptail --msgbox "Server timezone updated ✅\n\nNew timezone: $(server_tz)" 10 60
  else
    whiptail --msgbox "Failed to set timezone ❌\n\nCheck the timezone name with:\n  timedatectl list-timezones" 12 70
  fi
}

pick_daily_server_time() {
  local hour minute
  hour=$(whiptail --title "Daily Restart (Server Time)" --inputbox "Enter hour (0-23) in SERVER time:" 10 60 "4" 3>&1 1>&2 2>&3) || return
  validate_int_range "$hour" 0 23 || { whiptail --msgbox "Invalid hour. Must be 0-23." 10 45; return; }

  minute=$(whiptail --title "Daily Restart (Server Time)" --inputbox "Enter minute (0-59) in SERVER time:" 10 60 "0" 3>&1 1>&2 2>&3) || return
  validate_int_range "$minute" 0 59 || { whiptail --msgbox "Invalid minute. Must be 0-59." 10 45; return; }

  write_cron "${minute} ${hour} * * * root ${CMD}"
  whiptail --msgbox "Saved ✅\n\nDaily restart at ${hour}:$(printf '%02d' "$minute") (server local time)\n\nCron: ${minute} ${hour} * * * root ${CMD}" 12 80
}

test_run() {
  if whiptail --title "Test Restart" --yesno "This will run:\n\n${CMD}\n\nRun it now?" 14 70; then
    if systemctl restart "rust-mumble"; then
      whiptail --msgbox "Restart command ran successfully ✅" 10 45
    else
      whiptail --msgbox "Restart command failed ❌\n\nCheck:\n- systemctl status ${SERVICE_NAME}\n- journalctl -u ${SERVICE_NAME}\n" 14 60
    fi
  fi
}

disable_schedule() {
  if [[ -f "$CRON_FILE" ]]; then
    if whiptail --title "Disable Schedule" --yesno "Disable scheduled restarts?\n\nThis will remove:\n${CRON_FILE}" 12 70; then
      remove_cron
      whiptail --msgbox "Disabled ✅\n\nRemoved ${CRON_FILE}" 10 55
    fi
  else
    whiptail --msgbox "No schedule is currently enabled." 10 45
  fi
}

pick_multiple_daily() {
  local minute
  minute=$(whiptail --title "Multiple Daily Restarts" \
    --inputbox "Restart at what minute each selected hour?\n\nEnter minute (0-59):" 12 70 "0" \
    3>&1 1>&2 2>&3) || return

  validate_int_range "$minute" 0 59 || { whiptail --msgbox "Invalid minute. Must be 0-59." 10 45; return; }

  local selections
  selections=$(whiptail --title "Multiple Daily Restarts" \
    --notags --separate-output \
    --checklist \
"How to use this menu:

• ↑ ↓  Arrow keys  →  Move up and down
• SPACE            →  Select / deselect an hour
• TAB              →  Switch between list and buttons
• ENTER            →  Confirm selection
• ESC / Cancel     →  Exit without saving

Select the HOURS (server time) to restart each day:" \
    24 75 14 \
    "00" "00:00  (midnight)           " OFF \
    "01" "01:00                      " OFF \
    "02" "02:00                      " OFF \
    "03" "03:00                      " OFF \
    "04" "04:00                      " OFF \
    "05" "05:00                      " OFF \
    "06" "06:00                      " OFF \
    "07" "07:00                      " OFF \
    "08" "08:00                      " OFF \
    "09" "09:00                      " OFF \
    "10" "10:00                      " OFF \
    "11" "11:00                      " OFF \
    "12" "12:00  (noon)              " OFF \
    "13" "13:00                      " OFF \
    "14" "14:00                      " OFF \
    "15" "15:00                      " OFF \
    "16" "16:00                      " OFF \
    "17" "17:00                      " OFF \
    "18" "18:00                      " OFF \
    "19" "19:00                      " OFF \
    "20" "20:00                      " OFF \
    "21" "21:00                      " OFF \
    "22" "22:00                      " OFF \
    "23" "23:00                      " OFF \
    3>&1 1>&2 2>&3) || return

  if [[ -z "$selections" ]]; then
    whiptail --msgbox "No hours selected. Nothing changed." 10 45
    return
  fi

  local cron_lines=""
  local h
  while IFS= read -r h; do
    cron_lines+="${minute} ${h} * * * root ${CMD}"$'\n'
  done <<< "$selections"

  cat > "$CRON_FILE" <<EOF
# Managed by novonode voiceserver restart menu
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

${cron_lines}
EOF
  chmod 0644 "$CRON_FILE"

  local s_tz
  s_tz="$(server_tz)"

  whiptail --msgbox "Saved ✅

Daily restarts configured at:
Minute: $(printf '%02d' "$minute")
Hours:
$(echo "$selections" | tr '\n' ' ')

Server timezone: ${s_tz}

Cron file:
${CRON_FILE}" 18 80
}



main_menu() {
  while true; do
    local s_tz
    s_tz="$(server_tz)"

    local choice
    choice=$(whiptail --title "Novonode Voice Server Restart Scheduler" \
      --menu "Need help? If you’re unsure how to use this menu, reach out on Discord:
https://discord.gg/novonode

Controls: ↑↓ to move • ENTER to select • TAB to switch buttons • ESC to cancel

Service: ${SERVICE_NAME}
Server timezone: ${s_tz}

Pick an option:" 24 95 10 \
      "1" "Set DAILY restart time (SERVER time)" \
      "2" "Set MULTIPLE DAILY restart times (pick hours + minute)" \
      "3" "Timezone conversion tool (pick YOUR tz + time, convert & apply)" \
      "4" "Show current status / schedule" \
      "5" "Test run restart now" \
      "6" "Disable scheduled restarts" \
      "7" "Set SERVER timezone (optional)" \
      "8" "Exit" 3>&1 1>&2 2>&3) || exit 0

    case "$choice" in
      1) pick_daily_server_time ;;
      2) pick_multiple_daily ;;
      3) timezone_conversion_ui ;;
      4) whiptail --title "Current Status" --msgbox "$(current_status)" 18 90 ;;
      5) test_run ;;
      6) disable_schedule ;;
      7) set_server_timezone_ui ;;
      8) exit 0 ;;
    esac
  done
}



require_root
need_whiptail
main_menu

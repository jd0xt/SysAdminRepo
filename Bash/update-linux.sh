#!/usr/bin/env bash

# can be modify to support another distro AllowReboot= "TRUE" Action="Install" if reboot required flag is set it will autoreboot 
declare ALLOWREBOOT="True"
declare DEFAULT_REBOOT="False"; ALLOWREBOOT="${ALLOWREBOOT:-$DEFAULT_REBOOT}"
declare ACTION="Install"
declare DEFAULT_ACTION="Scan"; ACTION="${ACTION:-$DEFAULT_ACTION}"
declare -r LOG_DIR="/var/lib/amazon/ssm/"
declare INSTALLED_UPDATES=false

function log_file_creation() {
  local log_dir=$1
  local os=$2

  if [ ! -d "$log_dir" ]
  then
   LOG_FILE="/tmp/linux-updates-output.log"
   find "$LOG_FILE" -type f -mtime +4  -exec rm -f {} \; &> /dev/null
   if [ ! -f "$LOG_FILE" ]
   then
    touch "$LOG_FILE"
    chmod 777 "$LOG_FILE"
   fi
  else
   LOG_FILE="${log_dir}${os}-updates-ouput.log"
   find "$LOG_FILE" -type f -mtime +4  -exec rm -f {} \; &> /dev/null
  if [ ! -f "$LOG_FILE" ]
   then
    touch "$LOG_FILE"
    chmod 777 "$LOG_FILE"
   fi
  fi
}

function exit_message() {
 local error_message="$1" 
 local return_value=${2:-1}
 if [ "$2" -ne 0 ]
  then
    echo "[!] [$(date +"%m-%d-%y:%H:%M:%S")] ${error_message}" | tee -a "$LOG_FILE"
    exit "$return_value"
  fi
}

function log_message() {
  local message="$1"
  echo "[*] [$(date +"%m-%d-%y:%H:%M:%S")] ${message}" | tee -a "$LOG_FILE"
}

function check_kernel() {
  current_version=$(uname -r)
  if cat "$LOG_FILE" | head -1 | grep "Kernel" > /dev/null
  then
    old_version="$(cat "$LOG_FILE" | head -1 | grep "Kernel" | awk -F: '{print $2}')" 
    if [ "$old_version" != "$current_version" ]
    then
      log_message "New Kernel version found appending to top of the file."
      log_message "New version:${current_version}, Version before:${old_version}"
      sed -i 1d "$LOG_FILE" 
      sed -i "1i \Kernel Version:${current_version}" "$LOG_FILE"
    fi
  else
    sed -i "1i \Kernel Version:${current_version}" "$LOG_FILE"
  fi
}

function handle_reboot() {
  local os=$1
  case "$os" in
    ubuntu)
      restart_needed=/var/run/reboot-required
      if [ -f "$restart_needed" ]
      then
        INSTALLED_UPDATES=true
        if $INSTALLED_UPDATES
          then
          log_message "Packages and Updates were successfully installed. Rebooting."
          sleep 15
          #ssm reboot(exit194) or you can add sudo reboot 
          exit 194
        fi
      fi
      ;;
    *)
      exit_message "ERROR: Unsupported linux distribution." 1
  esac
}

function update_system() {
  local os=$1
  case "$os" in
    ubuntu)
      export DEBIAN_FRONTEND=noninteractive
      log_message "Removing dependencies no longer needed and marked for deletion."
      sudo apt autoremove -y >> "$LOG_FILE" 2>&1
      log_message "Updating packages, database and metadata..."
      sudo -E apt-get update >> "$LOG_FILE" 2>&1
      exit_message "ERROR: Failed updating metadata and packages, log files location: ${LOG_FILE}" $?
      log_message "Performing a full upgrade and packages..."
      sudo -E apt-get -y dist-upgrade >> "$LOG_FILE" 2>&1
      exit_message "ERROR: Performing a full distro upgrade and packages, log file location: ${LOG_FILE}" $?
      ;;
    *)
      exit_message "ERROR: Unsupported linux distribution." 1
  esac
}

function stage_packages() {
    local os=$1
    case "$os" in
      ubuntu)
        export DEBIAN_FRONTEND=noninteractive
        log_message "Removing dependencies no longer needed and marked for deletion."
        sudo apt autoremove -y >> "$LOG_FILE" 2>&1
        log_message "Cleaning cache..."
        sudo apt-get autoclean >> "$LOG_FILE" 2>&1
        log_message "Updating packages database and metadata..."
        sudo -E apt-get update >> "$LOG_FILE" 2>&1
        exit_message "ERROR: Failed updating metadata and packages, log file location: ${LOG_FILE}" $?
        ;;
      *)
        exit_message "ERROR: Unsupported linux distribution." 1
        ;;
    esac
}

main() {
  if [ -f /etc/os-release ] 
  then
    DISTRO="$(cat /etc/os-release | grep -E '\bID\b' | awk -F= '{print $2}')"
  elif [ -f /etc/centos-release ]
  then
    DISTRO="$(cat /etc/centos-release | grep -E '\bID\b' | awk -F= '{print $2}')"
  else
    exit_message "ERROR: Unsupported linux distribution." 1
  fi

  log_file_creation $LOG_DIR "$DISTRO"
  log_message "Starting script execution..."

  if [ "$ACTION" = "Scan" ]
  then
    stage_packages "$DISTRO"
    log_message "Packages and database is up to date."
    exit 0
  elif [ "$ACTION" =  "Install" ]
  then
    update_system "$DISTRO"
    if [ "$ALLOWREBOOT" = "True" ]
    then
      check_kernel
      handle_reboot "$DISTRO"
    fi
    log_message "Updates were successfully installed."
  else
    exit_message "INVALID: Invalid option select from allowed set (Scan, Install)" 1
  fi
}

main "$@"


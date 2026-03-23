#!/bin/bash

# Project N.O.M.A.D. macOS Installation Script

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. macOS Installation Script
# Version               | 1.0.0
# Author                | Crosstalk Solutions, LLC
# Website               | https://crosstalksolutions.com
# Notes                 | macOS-specific installer. Called automatically by install_nomad.sh on Darwin systems.

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Color Codes                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

RESET='\033[0m'
YELLOW='\033[1;33m'
WHITE_R='\033[39m' # Same as GRAY_R for terminals with white background.
GRAY_R='\033[39m'
RED='\033[1;31m' # Light Red.
GREEN='\033[1;32m' # Light Green.

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Constants & Variables                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

NOMAD_DIR="${NOMAD_DIR:-$HOME/.project-nomad}"
MANAGEMENT_COMPOSE_FILE_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/management_compose_macos.yaml"
START_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/start_nomad.sh"
STOP_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/stop_nomad.sh"
UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/update_nomad.sh"
UNINSTALL_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/uninstall_nomad.sh"
script_option_debug='true'
accepted_terms='false'
local_ip_address=''

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

header() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${GREEN}#########################################################################${RESET}\\n"
}

header_red() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${RED}#########################################################################${RESET}\\n"
}

check_is_bash() {
  if [[ -z "$BASH_VERSION" ]]; then
    header_red
    echo -e "${RED}#${RESET} This script requires bash to run. Please run the script using bash.\\n"
    echo -e "${RED}#${RESET} For example: bash $(basename "$0")"
    exit 1
  fi
    echo -e "${GREEN}#${RESET} This script is running in bash.\\n"
}

ensure_dependencies_installed() {
  if ! command -v brew &>/dev/null; then
    echo -e "${RED}#${RESET} Homebrew is required but not installed."
    echo -e "${YELLOW}#${RESET} Install it from https://brew.sh and re-run this script."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Homebrew is installed.\\n"

  if ! command -v curl &>/dev/null; then
    echo -e "${YELLOW}#${RESET} Installing curl via Homebrew...\\n"
    brew install curl
    if ! command -v curl &>/dev/null; then
      echo -e "${RED}#${RESET} Failed to install curl. Please install it manually and try again."
      exit 1
    fi
  fi
  echo -e "${GREEN}#${RESET} All required dependencies are installed.\\n"
}

ensure_docker_installed() {
  if ! command -v docker &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Desktop is not installed."
    echo -e "${YELLOW}#${RESET} Download it from https://www.docker.com/products/docker-desktop/"
    echo -e "${YELLOW}#${RESET} After installing, open Docker Desktop and ensure it is running, then re-run this script."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Docker is installed.\\n"

  # Check Docker daemon is running
  if ! docker info &>/dev/null; then
    echo -e "${RED}#${RESET} Docker is installed but not running."
    echo -e "${YELLOW}#${RESET} Please open Docker Desktop and wait for it to start, then re-run this script."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Docker Desktop is running.\\n"
}

check_docker_compose() {
  # Check if 'docker compose' (v2 plugin) is available
  if ! docker compose version &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Compose v2 is not installed or not available as a Docker plugin."
    echo -e "${YELLOW}#${RESET} This script requires 'docker compose' (v2), not 'docker-compose' (v1)."
    echo -e "${YELLOW}#${RESET} Docker Desktop for Mac should include Docker Compose v2 by default."
    echo -e "${YELLOW}#${RESET} Please update Docker Desktop and try again."
    exit 1
  fi
}

generateRandomPass() {
  local length="${1:-32}"  # Default to 32
  local password

  # Generate random password using /dev/urandom
  password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length")

  echo "$password"
}

setup_gpu() {
  local arch
  arch=$(uname -m)
  if [[ "$arch" == "arm64" ]]; then
    echo -e "${YELLOW}#${RESET} Apple Silicon detected."
    echo -e "${YELLOW}#${RESET} Docker cannot access the Metal GPU. For full AI performance, install Ollama natively:"
    echo -e "${WHITE_R}   brew install ollama && ollama serve${RESET}"
    echo -e "${YELLOW}#${RESET} Then set OLLAMA_HOST=http://host.docker.internal:11434 in ${NOMAD_DIR}/.env to use it from N.O.M.A.D.\\n"
  else
    echo -e "${YELLOW}#${RESET} Intel Mac detected. AI will run CPU-only inside Docker.\\n"
  fi
}

get_local_ip() {
  # Try common macOS network interfaces in order
  for iface in en0 en1 en2; do
    local ip
    ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
    if [[ -n "$ip" ]]; then
      local_ip_address="$ip"
      return
    fi
  done
  # Fallback
  local_ip_address="localhost"
  echo -e "${YELLOW}#${RESET} Could not determine LAN IP — defaulting to localhost.\\n"
}

get_install_confirmation(){
  echo -e "${YELLOW}#${RESET} This script will install Project N.O.M.A.D. and its dependencies on your Mac."
  echo -e "${YELLOW}#${RESET} Installation directory: ${NOMAD_DIR}"
  echo -e "${YELLOW}#${RESET} If you already have Project N.O.M.A.D. installed with customized config or data, please be aware that running this installation script may overwrite existing files and configurations. It is highly recommended to back up any important data/configs before proceeding."
  read -p "Are you sure you want to continue? (y/N): " choice
  case "$choice" in
    y|Y )
      echo -e "${GREEN}#${RESET} User chose to continue with the installation."
      ;;
    * )
      echo "User chose not to continue with the installation."
      exit 0
      ;;
  esac
}

accept_terms() {
  printf "\n\n"
  echo "License Agreement & Terms of Use"
  echo "__________________________"
  printf "\n\n"
  echo "Project N.O.M.A.D. is licensed under the Apache License 2.0. The full license can be found at https://www.apache.org/licenses/LICENSE-2.0 or in the LICENSE file of this repository."
  printf "\n"
  echo "By accepting this agreement, you acknowledge that you have read and understood the terms and conditions of the Apache License 2.0 and agree to be bound by them while using Project N.O.M.A.D."
  echo -e "\n\n"
  read -p "I have read and accept License Agreement & Terms of Use (y/N)? " choice
  case "$choice" in
    y|Y )
      accepted_terms='true'
      ;;
    * )
      echo "License Agreement & Terms of Use not accepted. Installation cannot continue."
      exit 1
      ;;
  esac
}

create_nomad_directory(){
  # Ensure the main installation directory exists (user-writable, no sudo needed on macOS)
  if [[ ! -d "$NOMAD_DIR" ]]; then
    echo -e "${YELLOW}#${RESET} Creating directory for Project N.O.M.A.D at $NOMAD_DIR...\\n"
    mkdir -p "$NOMAD_DIR"
    echo -e "${GREEN}#${RESET} Directory created successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} Directory $NOMAD_DIR already exists.\\n"
  fi

  # Ensure storage/logs subdirectory exists
  mkdir -p "${NOMAD_DIR}/storage/logs"

  # Create an admin.log file in the logs directory
  touch "${NOMAD_DIR}/storage/logs/admin.log"
}

download_management_compose_file() {
  local compose_file_path="${NOMAD_DIR}/compose.yml"

  echo -e "${YELLOW}#${RESET} Downloading docker-compose file for management...\\n"
  if ! curl -fsSL "$MANAGEMENT_COMPOSE_FILE_URL" -o "$compose_file_path"; then
    echo -e "${RED}#${RESET} Failed to download the docker compose file. Please check the URL and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Docker compose file downloaded successfully to $compose_file_path.\\n"

  local app_key=$(generateRandomPass)
  local db_root_password=$(generateRandomPass)
  local db_user_password=$(generateRandomPass)

  # Inject dynamic env values into the compose file (BSD sed: -i '' with empty string)
  echo -e "${YELLOW}#${RESET} Configuring docker-compose file env variables...\\n"
  sed -i '' "s|URL=replaceme|URL=http://${local_ip_address}:8080|g" "$compose_file_path"
  sed -i '' "s|APP_KEY=replaceme|APP_KEY=${app_key}|g" "$compose_file_path"

  sed -i '' "s|DB_PASSWORD=replaceme|DB_PASSWORD=${db_user_password}|g" "$compose_file_path"
  sed -i '' "s|MYSQL_ROOT_PASSWORD=replaceme|MYSQL_ROOT_PASSWORD=${db_root_password}|g" "$compose_file_path"
  sed -i '' "s|MYSQL_PASSWORD=replaceme|MYSQL_PASSWORD=${db_user_password}|g" "$compose_file_path"

  echo -e "${GREEN}#${RESET} Docker compose file configured successfully.\\n"

  # Generate .env file for Docker Compose variable substitution
  echo -e "${YELLOW}#${RESET} Generating .env file...\\n"
  cat > "${NOMAD_DIR}/.env" <<EOF
# Project N.O.M.A.D. environment configuration
# Generated by install_nomad_macos.sh

NOMAD_DIR=${NOMAD_DIR}

# Uncomment the line below to use a natively installed Ollama for full Metal GPU acceleration on Apple Silicon:
# OLLAMA_HOST=http://host.docker.internal:11434
EOF
  echo -e "${GREEN}#${RESET} .env file created at ${NOMAD_DIR}/.env\\n"
}

download_helper_scripts() {
  local start_script_path="${NOMAD_DIR}/start_nomad.sh"
  local stop_script_path="${NOMAD_DIR}/stop_nomad.sh"
  local update_script_path="${NOMAD_DIR}/update_nomad.sh"
  local uninstall_script_path="${NOMAD_DIR}/uninstall_nomad.sh"

  echo -e "${YELLOW}#${RESET} Downloading helper scripts...\\n"
  if ! curl -fsSL "$START_SCRIPT_URL" -o "$start_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the start script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$start_script_path"

  if ! curl -fsSL "$STOP_SCRIPT_URL" -o "$stop_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the stop script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$stop_script_path"

  if ! curl -fsSL "$UPDATE_SCRIPT_URL" -o "$update_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the update script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$update_script_path"

  if ! curl -fsSL "$UNINSTALL_SCRIPT_URL" -o "$uninstall_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the uninstall script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$uninstall_script_path"

  echo -e "${GREEN}#${RESET} Helper scripts downloaded successfully.\\n"
}

start_management_containers() {
  echo -e "${YELLOW}#${RESET} Starting management containers using docker compose...\\n"
  if ! docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" up -d; then
    echo -e "${RED}#${RESET} Failed to start management containers. Please check the logs and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Management containers started successfully.\\n"
}

check_is_debug_mode(){
  if [[ "${script_option_debug}" == 'true' ]]; then
    echo -e "${YELLOW}#${RESET} Debug mode is enabled, the script will not clear the screen...\\n"
  else
    clear; clear
  fi
}

success_message() {
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D installation completed successfully!\\n"
  echo -e "${GREEN}#${RESET} Installation files are located at ${NOMAD_DIR}\\n\\n"
  echo -e "${GREEN}#${RESET} To start N.O.M.A.D, run: ${WHITE_R}${NOMAD_DIR}/start_nomad.sh${RESET}\\n"
  echo -e "${GREEN}#${RESET} To stop N.O.M.A.D, run: ${WHITE_R}${NOMAD_DIR}/stop_nomad.sh${RESET}\\n"
  echo -e "${GREEN}#${RESET} You can now access the management interface at http://localhost:8080 or http://${local_ip_address}:8080\\n"
  echo -e "${GREEN}#${RESET} Thank you for supporting Project N.O.M.A.D!\\n"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Main Script                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

# Pre-flight checks
check_is_bash
ensure_dependencies_installed
check_is_debug_mode

# Main install
get_install_confirmation
accept_terms
ensure_docker_installed
check_docker_compose
setup_gpu
get_local_ip
create_nomad_directory
download_helper_scripts
download_management_compose_file
start_management_containers
success_message

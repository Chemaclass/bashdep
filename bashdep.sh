#!/bin/bash

URL_DIR_DIVISOR=":"
DEFAULT_DEST_DIR="lib"

# Process the dependencies and download them
function process_dependencies() {
  local dependencies=("$@")
  local cleaned_dep url destination_dir

  for dep in "${dependencies[@]}"; do
    # Remove the scheme (https:// or http://)
    cleaned_dep="${dep#*://}"

    if [[ $cleaned_dep == *"$URL_DIR_DIVISOR"* ]]; then
      url="${dep%"$URL_DIR_DIVISOR"*}"
      destination_dir="${dep##*"$URL_DIR_DIVISOR"}"
    else
      url="$dep"
      destination_dir="$DEFAULT_DEST_DIR"
    fi

    setup_directory "$destination_dir"
    download_url "$url" "$destination_dir"
  done
}

# Ensure destination directory exists, and create it if missing
function setup_directory() {
  local destination_dir=$1

  if [[ ! -d "$destination_dir" ]]; then
    mkdir -p "$destination_dir" || {
      echo "Error: Could not create directory '$destination_dir'. Exiting."
      exit 1
    }
  fi
}

# Download URL to the destination directory
# shellcheck disable=SC2155
function download_url() {
  local url=$1
  local destination_dir=${2:-$DEFAULT_DEST_DIR}
  local file_name=$(basename "$url")
  local destination_file="$destination_dir/$file_name"

  echo "Downloading '$file_name' to '$destination_dir'..."

  if curl -s -L "$url" -o "$destination_file"; then
    echo "> $file_name installed successfully in '$destination_dir'"
    chmod +x "$destination_file"
  else
    echo "Error: Failed to install $file_name from $url"
    return 1
  fi
}


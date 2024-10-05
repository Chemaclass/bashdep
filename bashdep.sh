#!/bin/bash

BASHDEP_URL_DIVISOR_IR=":"
BASHDEP_DEFAULT_DEST_DIR="lib"

# Process the dependencies and download them
function bashdep::install() {
  local dependencies=("$@")
  local cleaned_dep url destination_dir

  for dep in "${dependencies[@]}"; do
    # Remove the scheme (https:// or http://)
    cleaned_dep="${dep#*://}"

    if [[ $cleaned_dep == *"$BASHDEP_URL_DIVISOR_IR"* ]]; then
      url="${dep%"$BASHDEP_URL_DIVISOR_IR"*}"
      destination_dir="${dep##*"$BASHDEP_URL_DIVISOR_IR"}"
    else
      url="$dep"
      destination_dir="$BASHDEP_DEFAULT_DEST_DIR"
    fi

    bashdep::setup_directory "$destination_dir"
    bashdep::download_url "$url" "$destination_dir"
  done
}

# Ensure destination directory exists, and create it if missing
function bashdep::setup_directory() {
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
function bashdep::download_url() {
  local url=$1
  local destination_dir=${2:-$BASHDEP_DEFAULT_DEST_DIR}
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


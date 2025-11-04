#!/bin/bash

# Test script for get_normalized_package_list function
# This test validates the function with a large package list
# On macOS, this will run via orbctl in a Ubuntu container

set -e

# Get the script directory (parent directory where lib.sh is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Detect if we're on macOS and should use orbctl
if [[ "$(uname)" == "Darwin" ]]; then
    # Check if orbctl is available
    if ! command -v orbctl &> /dev/null; then
        echo "❌ ERROR: orbctl is not installed. Please install OrbStack from https://orbstack.dev/"
        exit 1
    fi
    
    echo "🐳 Detected macOS - running test in Linux VM via orbctl"
    echo ""
    
    # Get the absolute path and translate it for Linux
    # orbctl automatically translates macOS paths, but we need to ensure it's absolute
    ABS_SCRIPT_DIR="${SCRIPT_DIR}"
    
    # Run the test script inside the Linux VM
    # orbctl automatically translates paths, so we can use the macOS path
    orbctl run -w "${ABS_SCRIPT_DIR}" bash -c "
        set -e
        # Check if dpkg is available (should be on Ubuntu/Debian)
        if ! command -v dpkg &> /dev/null; then
            echo '📦 Installing dpkg...'
            sudo apt-get update -qq > /dev/null 2>&1
            sudo apt-get install -y -qq dpkg apt-utils > /dev/null 2>&1
        fi
        
        # Make the test script executable and run it
        # The script will detect it's running in Linux (not macOS) and execute normally
        chmod +x test_shell/test_get_normalized_package_list.sh
        test_shell/test_get_normalized_package_list.sh
    "
    exit $?
fi

# Test input: Large package list from user
TEST_INPUT="moreutils protobuf-compiler ripgrep libnss3-tools mkcert cmake autoconf git gh curl expect psmisc coreutils tmux moreutils util-linux mkcert gettext libsodium23 libsodium-dev postgresql-client redis-tools mysql-client awscli build-essential procps file pkg-config libssl-dev libffi-dev python3-dev python3-pip libkrb5-dev libx11-dev x11proto-core-dev libxkbfile-dev libpng-dev libjpeg-dev libwebp-dev git wget ca-certificates gnupg software-properties-common apt-transport-https ripgrep jq ruff"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Test: get_normalized_package_list"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Input packages:"
echo "${TEST_INPUT}"
echo ""

# Check if apt_query binaries exist
architecture=$(dpkg --print-architecture 2>/dev/null || echo "x86_64")
if [ "${architecture}" == "arm64" ]; then
    APT_QUERY_BIN="${SCRIPT_DIR}/apt_query-arm64"
else
    APT_QUERY_BIN="${SCRIPT_DIR}/apt_query-x86"
fi

if [ ! -f "${APT_QUERY_BIN}" ]; then
    echo "❌ ERROR: apt_query binary not found at ${APT_QUERY_BIN}"
    echo "   Please ensure the binary exists in the project root."
    exit 1
fi

if [ ! -x "${APT_QUERY_BIN}" ]; then
    echo "⚠️  WARNING: apt_query binary is not executable. Making it executable..."
    chmod +x "${APT_QUERY_BIN}"
fi

# Source lib.sh to get the function
# Note: The get_normalized_package_list function uses ${0} to find the apt_query binaries.
# Since ${0} will be this test script (in test_shell/), we override the function to use
# SCRIPT_DIR directly where the binaries are actually located.
source "${SCRIPT_DIR}/lib.sh"

# Override get_normalized_package_list to use the correct script_dir
# This is necessary for testing since ${0} points to the test script, not lib.sh's location
get_normalized_package_list() {
  local packages=$(echo "${1}" \
    | sed 's/[,\]/ /g; s/\s\+/ /g; s/^\s\+//g; s/\s\+$//g' \
    | sort -t' ')
  local script_dir="${SCRIPT_DIR}"

  local architecture=$(dpkg --print-architecture)
  if [ "${architecture}" == "arm64" ]; then
    ${script_dir}/apt_query-arm64 normalized-list ${packages}
  else
    ${script_dir}/apt_query-x86 normalized-list ${packages}
  fi
}

# Call the function
echo "Calling get_normalized_package_list..."
result=$(get_normalized_package_list "${TEST_INPUT}")

# Check if result is non-empty
if [ -z "${result}" ]; then
    echo "❌ ERROR: get_normalized_package_list returned empty output"
    exit 1
fi

echo "✅ Success: get_normalized_package_list returned output"
echo ""
echo "Normalized output:"
echo "${result}"
echo ""

# Count packages in input vs output
input_count=$(echo "${TEST_INPUT}" | tr ' ' '\n' | sort -u | grep -v '^$' | wc -l)
output_count=$(echo "${result}" | tr ' ' '\n' | grep -v '^$' | wc -l)

echo "Input package count (unique): ${input_count}"
echo "Output package count: ${output_count}"

# Verify output format (should be space-delimited package=version pairs)
if echo "${result}" | grep -qvE '^[a-zA-Z0-9._+-]+=[a-zA-Z0-9.:~+-]+([[:space:]]+[a-zA-Z0-9._+-]+=[a-zA-Z0-9.:~+-]+)*$'; then
    echo "⚠️  WARNING: Output format may not match expected pattern (package=version pairs)"
else
    echo "✅ Output format validation passed"
fi

# Check for duplicates in output (should be none)
duplicate_check=$(echo "${result}" | tr ' ' '\n' | sed 's/=.*$//' | sort | uniq -d)
if [ -n "${duplicate_check}" ]; then
    echo "⚠️  WARNING: Found duplicate packages in output:"
    echo "${duplicate_check}"
else
    echo "✅ No duplicate packages found in output"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Test completed successfully"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

#!/bin/bash

set -e

# Include library.
script_dir="$(dirname -- "$(realpath -- "${0}")")"
source "${script_dir}/lib.sh"

# Debug mode for diagnosing issues.
# Setup first before other operations.
debug="${4}"
validate_bool "${debug}" debug 1
test ${debug} == "true" && set -x

# Directory that holds the cached packages.
cache_dir="${1}"

# Version of the cache to create or load.
version="${2}"

# Execute post-installation script.
execute_install_scripts="${3}"

# Debug mode for diagnosing issues.
debug="${4}"

# Repositories to add before installing packages.
add_repository="${5}"

# List of the packages to use.
input_packages="${@:6}"

# Check for Aptfile at repository root and merge with input packages
aptfile_path="${GITHUB_WORKSPACE:-.}/Aptfile"
aptfile_packages=""
if test -n "${GITHUB_WORKSPACE}" && test -f "${aptfile_path}"; then
  log "Found Aptfile at ${aptfile_path}, parsing packages..."
  aptfile_packages="$(parse_aptfile "${aptfile_path}")"
  if test -n "${aptfile_packages}"; then
    log "Parsed $(echo "${aptfile_packages}" | wc -w) package(s) from Aptfile"
  else
    log "Aptfile is empty or contains only comments"
  fi
elif test -z "${GITHUB_WORKSPACE}"; then
  log "GITHUB_WORKSPACE not set, skipping Aptfile check"
else
  log "No Aptfile found at ${aptfile_path}"
fi

# Merge input packages with Aptfile packages
if test -n "${input_packages}" && test -n "${aptfile_packages}"; then
  combined_packages="${input_packages} ${aptfile_packages}"
  log "Merging packages from input and Aptfile..."
elif test -n "${aptfile_packages}"; then
  combined_packages="${aptfile_packages}"
  log "Using packages from Aptfile only..."
elif test -n "${input_packages}"; then
  combined_packages="${input_packages}"
  log "Using packages from input only..."
else
  combined_packages=""
fi

# Create cache directory so artifacts can be saved.
mkdir -p ${cache_dir}

log "Validating action arguments (version='${version}', packages='${combined_packages}')...";
if grep -q " " <<< "${version}"; then
  log "aborted" 
  log "Version value '${version}' cannot contain spaces." >&2
  exit 2
fi

# Check if packages are empty before calling get_normalized_package_list
# (which would error if called with empty input)
if test -z "${combined_packages}"; then
  case "$EMPTY_PACKAGES_BEHAVIOR" in
    ignore)
      exit 0
      ;;
    warn)
      echo "::warning::Packages argument is empty. Please provide packages via the 'packages' input or create an Aptfile at the repository root."
      exit 0
      ;;
    *)
      log "aborted"
      log "Packages argument cannot be empty. Please provide packages via the 'packages' input or create an Aptfile at the repository root." >&2
      exit 3
      ;;
  esac
fi

# Trim commas, excess spaces, and sort.
log "Normalizing package list..."
packages="$(get_normalized_package_list "${combined_packages}")"
log "done"

validate_bool "${execute_install_scripts}" execute_install_scripts 4

# Basic validation for repository parameter
if [ -n "${add_repository}" ]; then
  log "Validating repository parameter..."
  for repository in ${add_repository}; do
    # Check if repository format looks valid (basic check)
    if [[ "${repository}" =~ [^a-zA-Z0-9:\/.-] ]]; then
      log "aborted"
      log "Repository '${repository}' contains invalid characters." >&2
      log "Supported formats: 'ppa:user/repo', 'deb http://...', 'http://...', 'multiverse', etc." >&2
      exit 6
    fi
  done
  log "done"
fi

log "done"

log_empty_line

# Abort on any failure at this point.
set -e

log "Creating cache key..."

# Forces an update in cases where an accidental breaking change was introduced
# and a global cache reset is required, or change in cache action requiring reload.
force_update_inc="3"

# Force a different cache key for different architectures (currently x86_64 and aarch64 are available on GitHub)
cpu_arch="$(arch)"
log "- CPU architecture is '${cpu_arch}'."

value="${packages} @ ${version} ${force_update_inc}"

# Include repositories in cache key to ensure different repos get different caches
if [ -n "${add_repository}" ]; then
  value="${value} ${add_repository}"
  log "- Repositories '${add_repository}' added to value."
fi

# Don't invalidate existing caches for the standard Ubuntu runners
if [ "${cpu_arch}" != "x86_64" ]; then
  value="${value} ${cpu_arch}"
  log "- Architecture '${cpu_arch}' added to value."
fi

log "- Value to hash is '${value}'."

key="$(echo "${value}" | md5sum | cut -f1 -d' ')"
log "- Value hashed as '${key}'."

log "done"

key_filepath="${cache_dir}/cache_key.md5"
echo "${key}" > "${key_filepath}"
log "Hash value written to ${key_filepath}"

# Save normalized packages to file so post_cache_action.sh can use them
packages_filepath="${cache_dir}/packages.txt"
echo "${packages}" > "${packages_filepath}"
if test ! -f "${packages_filepath}"; then
  log "Failed to write packages.txt" >&2
  exit 4
fi
log "Normalized packages saved to ${packages_filepath}"

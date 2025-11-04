#!/usr/bin/env bash

set -euo pipefail

echo "Scenario: ${SCENARIO_NAME}"
echo "Cache hit: ${CACHE_HIT}"
echo "Package version list: ${PACKAGE_VERSION_LIST}"
echo "All package version list: ${ALL_PACKAGE_VERSION_LIST}"

if [ -z "${PACKAGE_VERSION_LIST}" ]; then
  echo "❌ ERROR: package-version-list output is empty (${SCENARIO_NAME})"
  exit 1
fi

case "${EXPECT_CACHE_HIT}" in
  true)
    if [ "${CACHE_HIT}" != "true" ]; then
      echo "❌ ERROR: cache-hit was expected to be true but was '${CACHE_HIT}' (${SCENARIO_NAME})"
      exit 1
    fi
    ;;
  false)
    if [ "${CACHE_HIT}" != "false" ]; then
      echo "❌ ERROR: cache-hit was expected to be false but was '${CACHE_HIT}' (${SCENARIO_NAME})"
      exit 1
    fi
    ;;
  any)
    ;; # no-op
  *)
    echo "❌ ERROR: unexpected EXPECT_CACHE_HIT value '${EXPECT_CACHE_HIT}' (${SCENARIO_NAME})"
    exit 1
    ;;
esac

for pkg in ${EXPECTED_PACKAGES}; do
  if ! echo "${PACKAGE_VERSION_LIST}" | grep -qE "(^|,)${pkg}="; then
    echo "❌ ERROR: ${pkg} not found in package-version-list (${SCENARIO_NAME})"
    echo "Package list: ${PACKAGE_VERSION_LIST}"
    exit 1
  fi
done

echo "✅ Scenario '${SCENARIO_NAME}' passed"

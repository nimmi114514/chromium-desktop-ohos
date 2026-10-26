#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHROMIUM_ROOT="${1:-$(cd "${HAP_DIR}/../chromium_src" && pwd)}"
if [[ -d "${CHROMIUM_ROOT}/src" ]]; then
  CHROMIUM_SRC="${CHROMIUM_ROOT}/src"
else
  CHROMIUM_SRC="${CHROMIUM_ROOT}"
fi
# A second argument allows newer ports to use their own GN output directory.
OUT_DIR="${2:-${CHROMIUM_SRC}/out/musl_64}"
SDK_LIB_DIR="${CHROMIUM_SRC}/ohos_sdk/openharmony/native/llvm/lib/aarch64-linux-ohos"
LIB_DIR="${HAP_DIR}/chromium/libs/arm64-v8a"
RESOURCE_DIR="${HAP_DIR}/web_engine/src/main/resources/resfile"

required_files=(
  "${OUT_DIR}/libadapter.so"
  "${OUT_DIR}/libchrome_main_web.so"
  "${OUT_DIR}/resources.pak"
  "${OUT_DIR}/chrome_100_percent.pak"
  "${OUT_DIR}/chrome_200_percent.pak"
  "${OUT_DIR}/icudtl.dat"
  "${OUT_DIR}/locales"
)

# Select the snapshots that Chromium actually built. Modern desktop builds use
# the context snapshot alone; the two-snapshot mode is an Android build option.
SNAPSHOT_FLAGS="${OUT_DIR}/gen/tools/v8_context_snapshot/buildflags.h"
if [[ ! -f "${SNAPSHOT_FLAGS}" ]]; then
  echo "Missing generated V8 snapshot configuration: ${SNAPSHOT_FLAGS}" >&2
  exit 1
fi
snapshot_flags="$(<"${SNAPSHOT_FLAGS}")"
snapshot_files=()
if [[ "${snapshot_flags}" == *'BUILDFLAG_INTERNAL_USE_V8_CONTEXT_SNAPSHOT() (1)'* ]]; then
  snapshot_files+=("v8_context_snapshot.bin")
fi
if [[ ${#snapshot_files[@]} -eq 0 || "${snapshot_flags}" == *'BUILDFLAG_INTERNAL_INCLUDE_BOTH_V8_SNAPSHOTS() (1)'* ]]; then
  snapshot_files+=("snapshot_blob.bin")
fi
for snapshot in "${snapshot_files[@]}"; do
  required_files+=("${OUT_DIR}/${snapshot}")
done

for path in "${required_files[@]}"; do
  if [[ ! -e "${path}" ]]; then
    echo "Missing Chromium runtime artifact: ${path}" >&2
    echo "Build chrome_main_web first, then run this script again." >&2
    exit 1
  fi
done

# GRIT's .pak.info files map resource IDs back to their build inputs. Chromium
# loads the locale .pak files at runtime; the build maps are not app resources.
shopt -s nullglob
locale_paks=("${OUT_DIR}"/locales/*.pak)
shopt -u nullglob
if [[ ${#locale_paks[@]} -eq 0 ]]; then
  echo "Missing Chromium locale PAK files: ${OUT_DIR}/locales" >&2
  exit 1
fi

# Chromium can link its pinned libc++ statically. Only package the SDK's
# shared runtime when the built native libraries actually depend on it.
RUNTIME_READELF="${CHROMIUM_SRC}/third_party/llvm-build/Release+Asserts/bin/llvm-readelf"
if [[ ! -x "${RUNTIME_READELF}" ]]; then
  RUNTIME_READELF="$(command -v readelf)"
fi
NEEDS_SHARED_LIBCXX=false
for library in "${OUT_DIR}/libadapter.so" "${OUT_DIR}/libchrome_main_web.so"; do
  dynamic_section="$("${RUNTIME_READELF}" -d "${library}")"
  if [[ "${dynamic_section}" == *"[libc++_shared.so]"* ]]; then
    NEEDS_SHARED_LIBCXX=true
  fi
done
if ${NEEDS_SHARED_LIBCXX} && [[ ! -f "${SDK_LIB_DIR}/libc++_shared.so" ]]; then
  echo "Missing required C++ shared runtime: ${SDK_LIB_DIR}/libc++_shared.so" >&2
  exit 1
fi

mkdir -p "${LIB_DIR}" "${RESOURCE_DIR}"
cp "${OUT_DIR}/libadapter.so" "${LIB_DIR}/"
cp "${OUT_DIR}/libchrome_main_web.so" "${LIB_DIR}/"
if ${NEEDS_SHARED_LIBCXX}; then
  cp "${SDK_LIB_DIR}/libc++_shared.so" "${LIB_DIR}/"
else
  rm -f "${LIB_DIR}/libc++_shared.so"
fi
cp "${OUT_DIR}/resources.pak" "${RESOURCE_DIR}/"
cp "${OUT_DIR}/chrome_100_percent.pak" "${RESOURCE_DIR}/"
cp "${OUT_DIR}/chrome_200_percent.pak" "${RESOURCE_DIR}/"
cp "${OUT_DIR}/icudtl.dat" "${RESOURCE_DIR}/"
# Remove prior staged snapshots before copying the selected current snapshots.
rm -f "${RESOURCE_DIR}/snapshot_blob.bin" "${RESOURCE_DIR}/v8_context_snapshot.bin"
for snapshot in "${snapshot_files[@]}"; do
  cp "${OUT_DIR}/${snapshot}" "${RESOURCE_DIR}/"
done
rm -rf "${RESOURCE_DIR}/locales"
mkdir -p "${RESOURCE_DIR}/locales"
cp "${locale_paks[@]}" "${RESOURCE_DIR}/locales/"

echo "Chromium runtime artifacts prepared for the HAP."

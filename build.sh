#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:-deb}"
VERSION="${QA_TOUCH_VERSION:-0.1.0}"

run_host_tests() {
  local out_bin="${ROOT_DIR}/obj/qa_touch_model_tests"
  mkdir -p "${ROOT_DIR}/obj"
  clang -fobjc-arc -Wall -Wextra -Werror \
    -framework Foundation \
    -I "${ROOT_DIR}/src" \
    "${ROOT_DIR}/src/QATouchScriptModel.m" \
    "${ROOT_DIR}/Tests/QATouchScriptModelTests.m" \
    -o "${out_bin}"
  "${out_bin}"
  python3 "${ROOT_DIR}/package-deb.py" --self-test
}

build_ios_dylib() {
  local sdk_path
  sdk_path="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
  if [[ -z "${sdk_path}" ]]; then
    echo "ERROR: iPhoneOS SDK not found via xcrun. Install full Xcode or run the GitHub Actions workflow (.github/workflows/ios-build-dylib-deb.yml)." >&2
    exit 1
  fi

  local out_dir="${ROOT_DIR}/obj"
  local out_dylib="${out_dir}/QATouchRecorder.dylib"
  mkdir -p "${out_dir}"

  xcrun --sdk iphoneos clang \
    -arch arm64 \
    -isysroot "${sdk_path}" \
    -miphoneos-version-min=16.0 \
    -dynamiclib \
    -fobjc-arc \
    -fvisibility=hidden \
    -Wall -Wextra \
    -install_name "@rpath/QATouchRecorder.dylib" \
    -framework UIKit \
    -framework Foundation \
    -framework CoreGraphics \
    -framework QuartzCore \
    -I "${ROOT_DIR}/src" \
    "${ROOT_DIR}/src/QATouchScriptModel.m" \
    "${ROOT_DIR}/src/QATouchRecorderEngine.m" \
    "${ROOT_DIR}/src/QATouchOverlayUI.m" \
    "${ROOT_DIR}/src/QATouchEntry.m" \
    -o "${out_dylib}"

  if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none "${out_dylib}"
  fi

  echo "Built: ${out_dylib}"
  file "${out_dylib}"
  otool -L "${out_dylib}"
  otool -l "${out_dylib}" | grep -A 5 LC_BUILD_VERSION || true
}

package_deb() {
  local dylib_path="${ROOT_DIR}/obj/QATouchRecorder.dylib"
  local pkg_dir="${ROOT_DIR}/packages"
  local deb_path="${pkg_dir}/com.local.qa-touch-recorder_${VERSION}_iphoneos-arm.deb"

  python3 "${ROOT_DIR}/package-deb.py" \
    --dylib "${dylib_path}" \
    --out "${deb_path}" \
    --version "${VERSION}"

  ar -t "${deb_path}"
}

case "${MODE}" in
  test)
    run_host_tests
    ;;
  ios)
    build_ios_dylib
    ;;
  deb)
    build_ios_dylib
    package_deb
    ;;
  all)
    run_host_tests
    build_ios_dylib
    package_deb
    ;;
  *)
    echo "Usage: $0 [test|ios|deb|all]" >&2
    exit 2
    ;;
esac

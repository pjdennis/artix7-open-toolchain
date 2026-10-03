#!/usr/bin/env bash
# Installs the open-source Xilinx 7-series toolchain into $FPGA_PREFIX (no root needed):
#   - OSS CAD Suite: yosys, iverilog, verilator, openFPGALoader
#   - openXC7:       nextpnr-xilinx, prebuilt chipdbs, prjxray-db, fasm2frames, xc7frames2bit
# Re-running is safe; set OSS_CAD_SUITE_TAG / OPENXC7_TAG to pin a release (default: latest).
set -euo pipefail

FPGA_PREFIX="${FPGA_PREFIX:-$HOME/opt/fpga}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$FPGA_PREFIX/downloads"

# release_asset <owner/repo> <tag|latest> <asset-name-regex>  ->  "<tag> <url>"
release_asset() {
  local api="https://api.github.com/repos/$1/releases/latest"
  [[ "$2" == latest ]] || api="https://api.github.com/repos/$1/releases/tags/$2"
  curl -fsSL "$api" | python3 -c '
import json, re, sys
d = json.load(sys.stdin)
urls = [a["browser_download_url"] for a in d["assets"] if re.search(sys.argv[1], a["name"])]
if not urls: sys.exit("no asset matching " + sys.argv[1])
print(d["tag_name"], urls[0])' "$3"
}

# install_tarball <name> <owner/repo> <tag> <asset-regex>
install_tarball() {
  local name=$1 tag url file
  read -r tag url < <(release_asset "$2" "$3" "$4")
  file="$FPGA_PREFIX/downloads/$(basename "$url")"
  if [[ -f "$FPGA_PREFIX/$name/.installed-$tag" ]]; then
    echo "$name $tag already installed"
  else
    echo "Downloading $name $tag ..."
    curl -fsSL --retry 3 -C - -o "$file" "$url"
    rm -rf "$FPGA_PREFIX/$name.tmp" && mkdir -p "$FPGA_PREFIX/$name.tmp"
    tar -xzf "$file" -C "$FPGA_PREFIX/$name.tmp"
    # Flatten a single top-level directory if the tarball has one.
    local top=("$FPGA_PREFIX/$name.tmp"/*)
    if [[ ${#top[@]} -eq 1 && -d ${top[0]} ]]; then mv "${top[0]}" "$FPGA_PREFIX/$name.new"; rmdir "$FPGA_PREFIX/$name.tmp"
    else mv "$FPGA_PREFIX/$name.tmp" "$FPGA_PREFIX/$name.new"; fi
    rm -rf "$FPGA_PREFIX/$name" && mv "$FPGA_PREFIX/$name.new" "$FPGA_PREFIX/$name"
    touch "$FPGA_PREFIX/$name/.installed-$tag"
    rm -f "$file"
  fi
  echo "$name $tag $url" >> "$FPGA_PREFIX/VERSIONS.new"
}

rm -f "$FPGA_PREFIX/VERSIONS.new"
install_tarball oss-cad-suite YosysHQ/oss-cad-suite-build "${OSS_CAD_SUITE_TAG:-latest}" '^oss-cad-suite-linux-x64-.*\.tgz$'
install_tarball openxc7 cavearr/toolchain-openxc7-releases "${OPENXC7_TAG:-latest}" '^openxc7-toolchain-linux-x86-64-.*\.tgz$'
mv "$FPGA_PREFIX/VERSIONS.new" "$FPGA_PREFIX/VERSIONS"
cp "$FPGA_PREFIX/VERSIONS" "$REPO_ROOT/TOOLCHAIN_VERSIONS"

echo
cat "$FPGA_PREFIX/VERSIONS"
echo "Done. Run: source $REPO_ROOT/env.sh"

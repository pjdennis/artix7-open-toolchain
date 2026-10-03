# Source this file to put the FPGA toolchain on PATH: `source env.sh`
# Tool dirs are appended (not prepended) so OSS CAD Suite's bundled python3 etc.
# don't shadow the system versions.
FPGA_PREFIX="${FPGA_PREFIX:-$HOME/opt/fpga}"
# Designs in other repositories include $FPGA_KIT/mk/*.mk (see README, "Using the kit from another repository").
export FPGA_KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OPENXC7_ROOT="$FPGA_PREFIX/openxc7"
export PRJXRAY_DB="$OPENXC7_ROOT/share/nextpnr/external/prjxray-db"
for _d in "$OPENXC7_ROOT/bin" "$FPGA_PREFIX/oss-cad-suite/bin"; do
  case ":$PATH:" in *":$_d:"*) ;; *) PATH="$PATH:$_d" ;; esac
done
unset _d
export PATH

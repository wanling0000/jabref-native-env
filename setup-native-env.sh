#!/usr/bin/env bash
# setup-native-env.sh — provision an Ubuntu/Debian x86_64 box to build & test
# JabRef native images. Toolchain: mise + BellSoft Liberica NIK Full (JavaFX + native-image).
#
#   jabkit / jabls  : no GPU/display needed.
#   jabsrv / jabgui : CAYW popup needs a real display+GPU for interactive verification.
#
# Overrides:  NIK="java@..." MIN_DISK_GB=8 ./setup-native-env.sh
# Safe to re-run.
set -euo pipefail

NIK="${NIK:-java@liberica-nik-javafx-openjdk25-25.0.4+1}"
MIN_DISK_GB="${MIN_DISK_GB:-10}"

log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[abort]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 1. Preflight (hard blockers) ----------
log "Preflight..."
command -v apt-get >/dev/null 2>&1 || die "Not Debian/Ubuntu (no apt-get); this script is apt-only."
arch="$(uname -m)"; [ "$arch" = "x86_64" ] || die "Arch '$arch': Liberica Full NIK is x86_64-only (no aarch64)."
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || die "Need root or sudo for apt."
  SUDO="sudo"
else
  SUDO=""
fi

# soft: disk
avail_gb="$(df -BG --output=avail . 2>/dev/null | tail -1 | tr -dc '0-9' || true)"
if [ "${avail_gb:-0}" -lt "$MIN_DISK_GB" ]; then
  warn "Only ${avail_gb:-?}G free (< ${MIN_DISK_GB}G recommended). Rough footprint:"
  warn "  OS ~2-3G | NIK ~0.7G | gradle cache ~2-4G | repo+submodules ~1G | build temp/out ~1-2G"
  warn "  Tight disk: git clone --depth 1 ; build one module at a time ; clear ~/.gradle/caches between builds."
else
  log "Disk: ${avail_gb}G free (ok)."
fi

# ---------- 2. System dev libraries ----------
log "Installing apt packages..."
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y --no-install-recommends \
  build-essential zlib1g-dev curl git ca-certificates \
  libgtk-3-dev libglib2.0-dev libgdk-pixbuf-2.0-dev \
  libcairo2-dev libpango1.0-dev libatk1.0-dev \
  libxtst-dev libx11-dev libxext-dev \
  libfontconfig-dev libfreetype-dev libharfbuzz-dev libgl1-mesa-dev \
  xvfb mesa-utils libgl1-mesa-dri imagemagick
#  GTK/X11/GL            : link JavaFX native (jabsrv/jabgui); harmless for jabkit/jabls.
#  xvfb/mesa/imagemagick : headless CAYW render + screenshot fallback.

# ---------- 3. JDK toolchain (mise + Liberica NIK Full) ----------
if ! command -v mise >/dev/null 2>&1; then
  log "Installing mise..."
  curl -fsSL https://mise.run | sh
  export PATH="$HOME/.local/bin:$PATH"
fi
command -v mise >/dev/null 2>&1 || die "mise not on PATH; see https://mise.run"
log "Installing $NIK ..."
mise install "$NIK"
JH="$(mise where "$NIK")"
"$JH/bin/java" --list-modules 2>/dev/null | grep -q javafx || die "No JavaFX modules — not the Full NIK."
"$JH/bin/native-image" --version >/dev/null 2>&1 || die "native-image missing in toolchain."
log "Toolchain OK: $JH"
log "  $("$JH/bin/native-image" --version | head -1)"

# ---------- 4. GPU / display capability (informational) ----------
log "Detecting GPU / GL (for CAYW popup verification)..."
gpu_line="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 || true)"
have_dri="no"; [ -e /dev/dri/renderD128 ] && have_dri="yes"
gl_renderer="$(xvfb-run -a glxinfo -B 2>/dev/null | grep -i 'OpenGL renderer' | head -1 || true)"
echo "----------------------------------------------------------------"
echo " GPU device : ${gpu_line:-none found}"
echo " /dev/dri   : $have_dri"
echo " GL renderer: ${gl_renderer:-unknown}"
echo " Verification capability:"
echo "   JabKit / JabLS            : OK  (CLI/data-plane, no GPU/display needed)"
if echo "$gl_renderer" | grep -qi llvmpipe || [ "$have_dri" = "no" ]; then
  echo "   JabSrv / JabGui CAYW popup : LIMITED (no hardware GPU)"
  echo "     JavaFX es2 rejects software GL; the picker renders only with"
  echo "     -Dprism.forceGPU=true under xvfb-run (non-interactive)."
  echo "     For the real user scenario (interactive popup) use a GPU + desktop host."
else
  echo "   JabSrv / JabGui CAYW popup : OK  (hardware GL present, full interactive verification)"
fi
echo "----------------------------------------------------------------"

# ---------- 5. Usage ----------
cat <<EOF

Toolchain ready. Run gradle commands inside your JabRef checkout.
(If 'mise' is not on PATH in new shells, add: eval "\$(mise activate bash)")

  # jabkit / jabls (no display needed):
  mise exec $NIK -- ./gradlew :jabkit:nativeCompile

  # jabsrv (JavaFX):
  mise exec $NIK -- ./gradlew :jabsrv-cli:nativeCompile -PuseLibericaJdkFull \\
    -Dorg.gradle.java.installations.paths="\$(mise where $NIK)"

  # CAYW real interactive popup (GPU + desktop host): run the binary directly:
  ./jabsrv-cli/build/native/nativeCompile/jabsrv
  #   then: curl "http://localhost:23119/better-bibtex/cayw?librarypath=demo&format=biblatex"
  #
  # GPU-less box: smoke-render only (non-interactive):
  #   xvfb-run -a ./jabsrv-cli/build/native/nativeCompile/jabsrv -Dprism.forceGPU=true
EOF
log "Done."

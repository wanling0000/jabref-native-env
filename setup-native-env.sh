#!/usr/bin/env bash
# setup-native-env.sh <module>...  (jabkit | jabls | jabsrv | jabgui | all)
#
# Installs ONLY the toolchain(s) + system deps the requested module(s) need:
#   jabls          -> plain GraalVM CE. no AWT/JavaFX, no GTK, no GPU.
#   jabkit         -> Liberica NIK Full (PDFBox reaches AWT). headless: fonts only, no GTK/GPU.
#   jabsrv/jabgui  -> Liberica NIK Full (JavaFX). GTK/X11/GL; needs a display for CAYW.
#
# Overrides: GRAALVM="java@..." LIBERICA="java@..." MIN_DISK_GB=8 ./setup-native-env.sh ...
# Safe to re-run.
set -euo pipefail

GRAALVM="${GRAALVM:-java@graalvm-community-25.0.2}"                   # plain modules (jabls)
LIBERICA="${LIBERICA:-java@liberica-nik-javafx-openjdk25-25.0.4+1}"   # AWT/JavaFX modules (jabkit/jabsrv/jabgui)
MIN_DISK_GB="${MIN_DISK_GB:-10}"

log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[abort]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- 0. What do you want to build? ----------
[ $# -ge 1 ] || die "Usage: $0 <module>...  (jabkit | jabls | jabsrv | jabgui | all)"
mods=("$@"); [ "${mods[*]}" = "all" ] && mods=(jabkit jabls jabsrv jabgui)

need_graalvm=no; need_liberica=no; need_gui=no; need_awt_fonts=no
for m in "${mods[@]}"; do
  case "$m" in
    jabls)          need_graalvm=yes ;;
    jabkit)         need_liberica=yes; need_awt_fonts=yes ;;     # Liberica for PDFBox AWT; headless
    jabsrv|jabgui)  need_liberica=yes; need_gui=yes ;;
    *) die "Unknown module '$m' (want: jabkit | jabls | jabsrv | jabgui | all)" ;;
  esac
done
log "Requested: ${mods[*]}  ->  GraalVM CE: $need_graalvm | Liberica Full: $need_liberica | GUI deps: $need_gui"

# ---------- 1. Preflight (hard blockers) ----------
command -v apt-get >/dev/null 2>&1 || die "Not Debian/Ubuntu (no apt-get); this script is apt-only."
arch="$(uname -m)"; [ "$arch" = "x86_64" ] || die "Arch '$arch': Liberica Full NIK is x86_64-only (no aarch64)."
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo >/dev/null 2>&1 || die "Need root or sudo for apt."
  SUDO="sudo"
else
  SUDO=""
fi

avail_gb="$(df -BG --output=avail . 2>/dev/null | tail -1 | tr -dc '0-9' || true)"
if [ "${avail_gb:-0}" -lt "$MIN_DISK_GB" ]; then
  warn "Only ${avail_gb:-?}G free (< ${MIN_DISK_GB}G recommended). Rough footprint:"
  warn "  OS ~2-3G | JDK ~0.5-0.7G each | gradle cache ~2-4G | repo+submodules ~1G | build temp/out ~1-2G"
  warn "  Tight disk: git clone --depth 1 ; build one module at a time ; clear ~/.gradle/caches between builds."
else
  log "Disk: ${avail_gb}G free (ok)."
fi

# ---------- 2. System dev libraries (only what the modules need) ----------
export DEBIAN_FRONTEND=noninteractive
pkgs=(build-essential zlib1g-dev curl git ca-certificates)          # base: native-image link + tooling
if [ "$need_gui" = yes ]; then
  pkgs+=(libgtk-3-dev libglib2.0-dev libgdk-pixbuf-2.0-dev \
         libcairo2-dev libpango1.0-dev libatk1.0-dev \
         libxtst-dev libx11-dev libxext-dev \
         libfontconfig-dev libfreetype-dev libharfbuzz-dev libgl1-mesa-dev \
         xvfb mesa-utils libgl1-mesa-dri imagemagick)               # link JavaFX + headless CAYW render
elif [ "$need_awt_fonts" = yes ]; then
  pkgs+=(libfontconfig-dev libfreetype-dev)                         # headless AWT (PDFBox) font rendering
fi
log "Installing apt packages (${#pkgs[@]})..."
$SUDO apt-get update -qq
$SUDO apt-get install -y --no-install-recommends "${pkgs[@]}"

# ---------- 3. Toolchains (mise) ----------
if ! command -v mise >/dev/null 2>&1; then
  log "Installing mise..."; curl -fsSL https://mise.run | sh; export PATH="$HOME/.local/bin:$PATH"
fi
command -v mise >/dev/null 2>&1 || die "mise not on PATH; see https://mise.run"

install_jdk() { # <mise-id> <needs-javafx yes|no>
  local id="$1" fx="$2" jh
  log "Installing $id ..."
  mise install "$id" || die "mise could not install '$id'. Check: mise ls-remote java | grep -E 'graalvm-community|nik'"
  jh="$(mise where "$id")"
  "$jh/bin/native-image" --version >/dev/null 2>&1 || die "native-image missing in $id."
  if [ "$fx" = yes ]; then
    "$jh/bin/java" --list-modules 2>/dev/null | grep -q javafx || die "$id has no JavaFX modules — not the Full NIK."
  fi
  log "  ok: $("$jh/bin/native-image" --version | head -1)"
}
[ "$need_graalvm"  = yes ] && install_jdk "$GRAALVM"  no
[ "$need_liberica" = yes ] && install_jdk "$LIBERICA" yes

# ---------- 4. GPU / display capability (only if a JavaFX module was requested) ----------
if [ "$need_gui" = yes ]; then
  log "Detecting GPU / GL (for CAYW popup verification)..."
  gpu_line="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 || true)"
  have_dri="no"; [ -e /dev/dri/renderD128 ] && have_dri="yes"
  gl_renderer="$(xvfb-run -a glxinfo -B 2>/dev/null | grep -i 'OpenGL renderer' | head -1 || true)"
  echo "----------------------------------------------------------------"
  echo " GPU device : ${gpu_line:-none found}"
  echo " /dev/dri   : $have_dri"
  echo " GL renderer: ${gl_renderer:-unknown}"
  if echo "$gl_renderer" | grep -qi llvmpipe || [ "$have_dri" = "no" ]; then
    echo " CAYW popup : LIMITED (no hardware GPU) — es2 rejects software GL."
    echo "   Renders only with -Dprism.forceGPU=true under xvfb-run (non-interactive, screenshot)."
    echo "   For the real user scenario (interactive popup) use a GPU + desktop host."
  else
    echo " CAYW popup : OK (hardware GL present, full interactive verification)."
  fi
  echo "----------------------------------------------------------------"
fi

# ---------- 5. Usage (per requested module) ----------
echo ""
log "Toolchain ready. Run gradle inside your JabRef checkout."
echo '(If mise is not on PATH in new shells: eval "$(mise activate bash)")'
echo ""
for m in "${mods[@]}"; do
  case "$m" in
    jabls)  echo "  mise exec $GRAALVM -- ./gradlew :jabls-cli:nativeCompile \\";
            echo "    -Dorg.gradle.java.installations.paths=\"\$(mise where $GRAALVM)\"" ;;
    jabkit) echo "  mise exec $LIBERICA -- ./gradlew :jabkit:nativeCompile \\";
            echo "    -Dorg.gradle.java.installations.paths=\"\$(mise where $LIBERICA)\"" ;;
    jabsrv) echo "  mise exec $LIBERICA -- ./gradlew :jabsrv-cli:nativeCompile -PuseLibericaJdkFull \\";
            echo "    -Dorg.gradle.java.installations.paths=\"\$(mise where $LIBERICA)\"" ;;
    jabgui) echo "  # jabgui native build is not wired in JabRef yet; deps are ready for when it is." ;;
  esac
done
if [ "$need_gui" = yes ]; then
  cat <<'EOF'

  # CAYW real interactive popup (GPU + desktop host): run the binary directly:
  ./jabsrv-cli/build/native/nativeCompile/jabsrv
  #   then: curl "http://localhost:23119/better-bibtex/cayw?librarypath=demo&format=biblatex"
  # GPU-less box: smoke-render only:  xvfb-run -a ... -Dprism.forceGPU=true
EOF
fi
log "Done."

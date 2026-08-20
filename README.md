# jabref-native-env

One-shot provisioning to build & test **JabRef native images** (GraalVM Native Image).

The **baseline** toolchain is plain **GraalVM** (Community Edition) — that's what JabLS
targets. **BellSoft Liberica NIK Full** is only pulled in for the modules that reach
**AWT / JavaFX**: JabKit (PDFBox → AWT) and JabSrv / JabGui (the CAYW JavaFX GUI). It
bundles JavaFX + the AWT native backend. In other words, Liberica is a forced exception,
not the goal. (JabKit is transitioning off Liberica as the PDFBox AWT need is resolved
upstream; on branches where it still hits AWT it stays on Liberica.)

You tell the script **which module(s)** you want to build; it installs **only** the
toolchain(s) and system libraries those need — GraalVM CE for JabLS; Liberica NIK Full for
JabKit (AWT) and JabSrv/JabGui (JavaFX, plus the GTK/X11/GL stack). Nothing extra on a
small box.

Keeps the environment setup out of the JabRef repo so it can be reused across
JabKit / JabLS / JabSrv / JabGui.

## What `setup-native-env.sh` does

Given the requested module(s), it installs only what they need:

1. **Preflight** — aborts unless: Debian/Ubuntu (`apt`), `x86_64`, and root/`sudo`.
   Soft-warns on low disk (< 10 GB).
2. **System dev libraries** — base build tools always; GTK / X11 / GL + `xvfb` / `mesa` /
   `imagemagick` **only** for JavaFX modules (jabsrv/jabgui); just `fontconfig`/`freetype`
   for JabKit's headless AWT.
3. **Toolchain(s)** via `mise` — GraalVM CE for jabls, Liberica NIK Full for
   jabkit/jabsrv/jabgui; each verified to ship `native-image` (and JavaFX for Liberica).
4. **GPU / display capability** — printed only when a JavaFX module was requested
   (whether CAYW can be verified interactively here).

## Requirements

- Ubuntu/Debian, **x86_64** — Liberica Full NIK has **no aarch64** build.
- root or `sudo` for `apt`.
- **~8 GB+ RAM** for native-image compilation (it is memory-heavy), ~10 GB free disk.

## Quick start (blank Ubuntu/Debian x86_64 box)

```bash
git clone https://github.com/wanling0000/jabref-native-env.git
cd jabref-native-env
./setup-native-env.sh jabsrv          # pick: jabkit | jabls | jabsrv | jabgui | all
```

The script installs the toolchain and **prints the exact build command** for what you
picked. Then get JabRef and run that command inside it:

```bash
# mise was just installed; make it available in this shell:
export PATH="$HOME/.local/bin:$PATH"

cd ~
git clone --depth 1 --recurse-submodules https://github.com/JabRef/jabref.git
cd jabref
# ...paste the `mise exec ... ./gradlew ...` line the script printed...
```

(Use your own fork + `git checkout <branch>` instead of upstream when building WIP work.)

## Options

```bash
./setup-native-env.sh jabls               # GraalVM CE only, no GTK/GPU
./setup-native-env.sh jabkit jabsrv       # both toolchains
GRAALVM="java@..." LIBERICA="java@..." MIN_DISK_GB=8 ./setup-native-env.sh jabsrv
```

## GPU / display

| Module | Needs GPU/display? |
| --- | --- |
| JabKit / JabLS | No — CLI / data-plane. |
| JabSrv / JabGui (CAYW popup) | Yes for **interactive** verification. |

On a GPU-less box, JavaFX `es2` rejects the software (llvmpipe) renderer, so the CAYW
picker renders only with `-Dprism.forceGPU=true` under `xvfb` (non-interactive, screenshot
only). For the **real user scenario** (an interactive popup you can click), use a GPU +
desktop host — e.g. an AWS `g4dn` instance with a NICE DCV desktop.

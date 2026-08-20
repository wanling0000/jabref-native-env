# jabref-native-env

One-shot provisioning to build & test **JabRef native images** (GraalVM Native Image via
BellSoft **Liberica NIK Full**, which bundles JavaFX + `native-image`).

Keeps the environment setup out of the JabRef repo so it can be reused across
JabKit / JabLS / JabSrv / JabGui.

## What `setup-native-env.sh` does

1. **Preflight** — aborts unless: Debian/Ubuntu (`apt`), `x86_64`, and root/`sudo`.
   Soft-warns on low disk (< 10 GB).
2. **System dev libraries** — GTK / X11 / GL headers needed to *link* JavaFX native
   (jabsrv/jabgui), plus `xvfb` / `mesa` / `imagemagick` for headless rendering.
3. **Toolchain** — installs `mise` and the Liberica NIK Full JDK, then verifies it
   really ships JavaFX modules + `native-image`.
4. **GPU / display capability** — prints, per module, whether CAYW can be verified here.

## Requirements

- Ubuntu/Debian, **x86_64** — Liberica Full NIK has **no aarch64** build.
- root or `sudo` for `apt`.
- **~8 GB+ RAM** for native-image compilation (it is memory-heavy), ~10 GB free disk.

## Usage

```bash
./setup-native-env.sh
# override the JDK:      NIK="java@..." ./setup-native-env.sh
# override disk warning: MIN_DISK_GB=8 ./setup-native-env.sh
```

Then build **inside your JabRef checkout**, e.g.:

```bash
mise exec java@liberica-nik-javafx-openjdk25-25.0.4+1 -- ./gradlew :jabkit:nativeCompile
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

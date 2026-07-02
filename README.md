# EQRouter — Linux Edition

A Linux port of the macOS **EQRouter** per-app audio equalizer. The digital
signal processing is the *same code* as the Mac app; only the parts that are
inherently platform-specific — audio capture/playback and the UI — are
reimplemented for Linux.

| Layer | macOS app | Linux edition |
|-------|-----------|---------------|
| DSP core | `EQRouterCore` (Swift) | **identical** `EQRouterCore` (portable subset, no CoreAudio) |
| Audio I/O | CoreAudio process taps | `parec`/`pacat` pipe to PulseAudio / PipeWire |
| UI | SwiftUI window | self-hosted **web control panel** (no SwiftUI on Linux) |
| Persistence | app storage | `~/.config/eqrouter/config.json` |

The DSP chain is unchanged: route gain → 10-band custom EQ (genre-aware Q) →
headphone-correction EQ → user parametric (AutoEq import) → output trim →
optional safety ceiling → soft-limiter, with input/output metering.

---

## Install (Linux, x86-64)

One line — downloads the latest static binary from Releases (no dependencies,
works on any distro):

```bash
curl -fsSL https://raw.githubusercontent.com/adv4sd-cyber/eqrouter-linux/main/Scripts/install.sh | sh
```

Or manually: grab `eqrouter-linux-x86_64.tar.gz` from the
[latest release](https://github.com/adv4sd-cyber/eqrouter-linux/releases/latest),
extract, and put `eqrouter` anywhere on your `PATH`.

Then:

```bash
eqrouter serve      # web control panel at http://127.0.0.1:8080/
```

For other architectures, build from source (see below).

---

## What is verified vs. what is not

This port was built and tested on macOS with the Swift **static-Linux SDK**
for cross-compilation. Be clear-eyed about what that proves:

- ✅ **Verified (executed):**
  - DSP correctness — the ported core's full test suite passes (65 tests,
    including the dependency-install command builder).
  - Offline WAV EQ — measured: +6 dB on the 1 kHz band raises a 1 kHz tone by
    exactly 6 dB; a boost on another band leaves it untouched; flat passes
    through unchanged.
  - Web control panel + JSON API + config persistence; `doctor` / deps status.
- ✅ **Compile-verified for Linux (not run):** the whole package
  cross-compiles to a **statically-linked x86-64 Linux ELF** with the
  `x86_64-swift-linux-musl` SDK (debug *and* release).
- ⚠️ **Compile-verified but never executed on Linux:** the live
  `parec | DSP | pacat` routing pump, the PulseAudio null-sink setup, and the
  actual package-manager install (`sudo apt-get install …` etc. — the command
  *construction* is unit-tested, but no real install was run). These require a
  running Linux system and were not executed.
- ⚠️ **Not compiled here:** the native-glibc build path. The static-musl
  binary is the recommended artifact (it runs on any distro); a native
  `swift build` on a glibc distro takes the `#elseif canImport(Glibc)`
  socket branch, which is written to the documented idiom but unverified.

---

## Build from source

### Recommended: static binary (runs on any Linux distro)

This is the path that was verified. On a machine with the Swift toolchain and
the static-Linux SDK installed:

```bash
# one-time: install the static SDK matching your Swift version
swift sdk install \
  https://download.swift.org/swift-6.3.1-release/static-sdk/swift-6.3.1-RELEASE/swift-6.3.1-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz \
  --checksum fac05271c1f7d060bd203240ce5251d5ca902d30ac899f553765dbb3a88b97ad

# build
swift build -c release --swift-sdk x86_64-swift-linux-musl --product eqrouter
```

The binary is at `.build/x86_64-swift-linux-musl/release/eqrouter`. The ~4000
headphone-correction profiles are **compiled into the binary**, so it works
standalone — you can move or copy just the executable and the full catalog
still loads. (To override with your own set, point
`EQROUTER_PROFILES=/path/to/BundledProfiles.json`; the `Scripts/build-linux.sh`
helper also stages the JSON resource alongside the binary for that path.)

### Native build on a Linux box (untested)

```bash
swift build -c release --product eqrouter
```

Requires a Swift toolchain on the target machine. See the caveat above.

### Runtime dependency for live routing (installed automatically)

The offline (file) mode and the web UI need nothing extra. **Live routing**
shells out to the PulseAudio client tools `parec`/`pacat`/`pactl`.

**You don't have to install these by hand.** When you start routing and the
tools are missing, EQRouter detects your distro's package manager and installs
them for you:

- `eqrouter run` prompts to install them before starting (or `--yes` to skip
  the prompt, `--no-install` to opt out).
- `eqrouter install-deps` installs them on demand; `eqrouter doctor` reports
  what's present and what's missing.
- The web panel shows a one-click **Install** button when they're missing.

Supported package managers: apt, dnf, yum, zypper, pacman, apk, xbps, emerge.
The package is `pulseaudio-utils` on most distros (`libpulse` on Arch,
`media-sound/pulseaudio` on Gentoo), and works against both PulseAudio and
PipeWire (via its pulse compatibility layer). Installation needs root — the
app uses `sudo` (terminal) or `pkexec` (graphical prompt) automatically, or
runs directly if you're already root.

---

## Usage

```
eqrouter serve   [--host 127.0.0.1] [--port 8080]   # web control panel (the GUI)
eqrouter run     [--source NAME] [--sink NAME] [--setup-sink]   # headless routing
eqrouter file    --in a.wav --out b.wav [options]   # offline WAV EQ (no server)
eqrouter devices                                    # list sinks/sources
eqrouter doctor                                     # check runtime dependencies
eqrouter install-deps [--yes]                       # install parec/pacat/pactl
eqrouter setup-sink | teardown-sink                 # manage the EQRouter sink
```

### The GUI

```bash
eqrouter serve
# → EQRouter control panel → http://127.0.0.1:8080/
```

Open that URL in a browser. The panel has the 10-band EQ with a live response
curve, genre presets, headphone-correction selection, output/gain controls,
AutoEq/EqualizerAPO import, and a live-engine section with device pickers and
VU meters. It binds to localhost only by default.

### Route system audio through the EQ (Linux)

The cleanest per-app-style routing uses a virtual sink:

```bash
eqrouter setup-sink            # creates an "EQRouter" null sink
# set "EQRouter" as your system output (in the panel's device list, your
# desktop sound settings, or: pactl set-default-sink EQRouter)
```

Then in the panel's **Live engine** section pick capture source
`EQRouter.monitor` and your real device as the output sink, and press
**Start routing**. Everything playing into the EQRouter sink is now EQ'd on the
way to your headphones.

To EQ *everything you currently hear* without a virtual sink, just capture your
existing sink's `.monitor` as the source and play to your real device.

Headless equivalent:

```bash
eqrouter run --setup-sink      # create sink, set default, capture its monitor
```

### Offline file processing (no audio server needed)

```bash
eqrouter file --in song.wav --out song_eq.wav \
  --genre rock --correction oratory1990_sennheiser_hd650 \
  --band 5=6 --band 8=3 --trim -2
# --band i=dB may repeat; i is 0..9 for 31 Hz .. 16 kHz
# --import preset.txt loads an AutoEq/EqualizerAPO parametric file
```

Supports PCM 16/24/32-bit and 32-bit float WAV, mono or multichannel.

---

## Architecture

```
Sources/
  EQRouterCore/       # portable DSP — shared verbatim with the macOS app
    DSP/  Models/  IO/  Profiles/  Resources/
  EQRouterLinux/      # the Linux-specific layer
    EQConfig.swift          # serializable config (one system-wide route)
    EQState.swift           # thread-safe live state + DSP chain
    WavFile.swift           # RIFF/WAVE read + write
    FileProcessor.swift     # offline WAV EQ
    PulseAudioBackend.swift # pactl device discovery + parec/pacat pump
    EngineController.swift   # engine lifecycle + null-sink management
    HTTPServer.swift        # tiny BSD-socket HTTP/1.1 server
    ControlServer.swift     # /api routes -> EQState
    WebUI.swift             # embedded single-page control panel
  eqrouter/           # CLI entry (serve / run / file / devices)
```

**Concurrency:** one lock guards the config and the DSP chain. The audio pump
takes it once per *buffer* (not per sample); control mutations take it briefly.
Because the pipe engine has OS buffering between the three processes it is not
hard-real-time, so per-buffer locking is safe and makes structural changes
(loading a correction profile) race-free.

## Relationship to the macOS project

`EQRouterCore` here is a copied, portable subset of the macOS app's core (the
CoreAudio `Audio/` folder is omitted; everything else is byte-for-byte the
same). Changes to the shared DSP should be kept in sync between the two.

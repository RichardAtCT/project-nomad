# macOS / Apple Silicon Implementation Plan

> **Author:** Richard Atkinson ([@RichardAtCT](https://github.com/RichardAtCT))  
> **Branch strategy:** All work on `feature/macos-support`, PR back to upstream when stable  
> **Upstream issue:** [#477](https://github.com/Crosstalk-Solutions/project-nomad/issues/477)  
> **Goal:** Full N.O.M.A.D functionality on macOS (Intel + Apple Silicon), with Metal-accelerated AI on Apple Silicon via host-installed Ollama

---

## Overview

Project N.O.M.A.D. currently requires a Debian-based Linux OS. This plan adds macOS support with minimal disruption to the existing Linux path. The approach is:

1. OS detection in the existing install script → redirect to a macOS-specific installer
2. A new `install_nomad_macos.sh` covering macOS-specific setup
3. Docker Compose adjustments for macOS compatibility
4. Optional host-Ollama support for full Metal GPU acceleration on Apple Silicon
5. README and docs updates

---

## Phase 1 — Install Script: OS Detection

**File:** `install/install_nomad.sh`

**Change:** Replace the hard-exit in `check_is_debian_based()` with OS routing logic at the top of the main script section.

```bash
# Detect OS and route accordingly
OS="$(uname -s)"
case "$OS" in
  Linux*)
    # Existing Debian check
    check_is_debian_based
    ;;
  Darwin*)
    echo -e "${YELLOW}#${RESET} macOS detected. Switching to macOS installer...\n"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    bash "${SCRIPT_DIR}/install_nomad_macos.sh"
    exit $?
    ;;
  *)
    echo -e "${RED}#${RESET} Unsupported OS: $OS"
    exit 1
    ;;
esac
```

This keeps the Linux path entirely unchanged.

---

## Phase 2 — macOS Install Script

**File:** `install/install_nomad_macos.sh` _(new)_

Full equivalent of `install_nomad.sh` for macOS. Key differences from the Linux script:

### 2.1 — No sudo requirement
macOS users should not need sudo. Default install dir: `~/.project-nomad` (user-writable).  
`NOMAD_DIR` defaults to `~/.project-nomad` but is overridable via env var:
```bash
NOMAD_DIR="${NOMAD_DIR:-$HOME/.project-nomad}"
```

### 2.2 — Dependency checks (Homebrew-based)
Replace `apt-get` with Homebrew:
```bash
ensure_dependencies_installed() {
  if ! command -v brew &>/dev/null; then
    echo -e "${RED}#${RESET} Homebrew is required but not installed."
    echo -e "${YELLOW}#${RESET} Install it from https://brew.sh and re-run this script."
    exit 1
  fi
  if ! command -v curl &>/dev/null; then
    brew install curl
  fi
}
```

### 2.3 — Docker Desktop check
Replace the `apt-get`-based Docker install with a check + guidance:
```bash
ensure_docker_installed() {
  if ! command -v docker &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Desktop is not installed."
    echo -e "${YELLOW}#${RESET} Download it from https://www.docker.com/products/docker-desktop/"
    echo -e "${YELLOW}#${RESET} After installing, open Docker Desktop and ensure it is running, then re-run this script."
    exit 1
  fi
  # Check Docker daemon is running
  if ! docker info &>/dev/null; then
    echo -e "${RED}#${RESET} Docker is installed but not running."
    echo -e "${YELLOW}#${RESET} Please open Docker Desktop and wait for it to start, then re-run this script."
    exit 1
  fi
}
```

### 2.4 — Local IP detection
Replace `hostname -I` with macOS equivalent:
```bash
get_local_ip() {
  # Try common interfaces in order
  for iface in en0 en1 en2; do
    local ip
    ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
    if [[ -n "$ip" ]]; then
      local_ip_address="$ip"
      return
    fi
  done
  # Fallback
  local_ip_address="localhost"
  echo -e "${YELLOW}#${RESET} Could not determine LAN IP — defaulting to localhost.\n"
}
```

### 2.5 — Skip NVIDIA toolkit
`setup_nvidia_container_toolkit()` is a no-op on macOS. Replace with Apple Silicon AI guidance:
```bash
setup_gpu() {
  local arch
  arch=$(uname -m)
  if [[ "$arch" == "arm64" ]]; then
    echo -e "${YELLOW}#${RESET} Apple Silicon detected."
    echo -e "${YELLOW}#${RESET} Docker cannot access Metal/GPU. For full AI performance, install Ollama natively:"
    echo -e "${WHITE_R}   brew install ollama && ollama serve${RESET}"
    echo -e "${YELLOW}#${RESET} Then set OLLAMA_HOST=http://host.docker.internal:11434 to use it from N.O.M.A.D.\n"
  else
    echo -e "${YELLOW}#${RESET} Intel Mac detected. AI will run CPU-only inside Docker.\n"
  fi
}
```

### 2.6 — macOS compose file variant
Use a macOS-specific compose file (`management_compose_macos.yaml`) that:
- Replaces `/opt/project-nomad` paths with `$NOMAD_DIR`
- Removes `rslave` from disk-collector
- Removes the `host.docker.internal:host-gateway` extra_hosts (not needed on macOS)

### 2.7 — No systemctl
Replace any `systemctl` references. On macOS, Docker starts/stops via Docker Desktop GUI — no daemon management needed in the script.

---

## Phase 3 — Docker Compose: macOS Variant

**File:** `install/management_compose_macos.yaml` _(new)_

Key differences from `management_compose.yaml`:

### 3.1 — Storage path
Replace hardcoded `/opt/project-nomad/` with `${NOMAD_DIR}`:
```yaml
volumes:
  - ${NOMAD_DIR}/storage:/app/storage
  - ${NOMAD_DIR}/mysql:/var/lib/mysql
  - ${NOMAD_DIR}/redis:/data
  - ${NOMAD_DIR}:/nomad-data
```
A `.env` file in `NOMAD_DIR` will be generated by the install script with `NOMAD_DIR` set.

### 3.2 — Remove extra_hosts Linux workaround
```yaml
# Remove this block (not needed on macOS):
# extra_hosts:
#   - "host.docker.internal:host-gateway"
```

### 3.3 — Fix disk-collector rslave
The `rslave` propagation option causes failures on macOS Docker Desktop:
```yaml
disk-collector:
  volumes:
    - /:/host:ro          # remove rslave — not needed on macOS
    - ${NOMAD_DIR}/storage:/storage
```

### 3.4 — Optional host Ollama support
Add `OLLAMA_HOST` env var to the admin service, defaulting to the containerised Ollama but overridable:
```yaml
admin:
  environment:
    - OLLAMA_HOST=${OLLAMA_HOST:-http://ollama:11434}
```
When a user has Ollama installed natively, they set `OLLAMA_HOST=http://host.docker.internal:11434` in their `.env` and the `ollama` container service becomes optional/skippable.

### 3.5 — ARM64 platform declarations
Until multi-arch images are confirmed published, add explicit platform hints to avoid silent Rosetta emulation:
```yaml
admin:
  platform: linux/amd64   # or linux/arm64 once ARM images are published
```
_(To be updated based on upstream response to issue #477 re: multi-arch images)_

---

## Phase 4 — Existing Compose: Linux path hardening

**File:** `install/management_compose.yaml` _(minor edit)_

Make `NOMAD_DIR` configurable on Linux too (no behaviour change, just allows override):
```yaml
volumes:
  - ${NOMAD_DIR:-/opt/project-nomad}/storage:/app/storage
```
This is a non-breaking change for all existing Linux installs.

---

## Phase 5 — Helper Scripts

**Files:** `install/start_nomad.sh`, `install/stop_nomad.sh`, `install/update_nomad.sh`

Each script currently hardcodes `/opt/project-nomad`. Update to:
```bash
NOMAD_DIR="${NOMAD_DIR:-/opt/project-nomad}"
```
...and use `$NOMAD_DIR` throughout. macOS installs set `NOMAD_DIR` in their environment (or a sourced `.env`).

---

## Phase 6 — Uninstall Script

**File:** `install/uninstall_nomad.sh`

Same `NOMAD_DIR` parameterisation. On macOS, skip any `systemctl` calls.

---

## Phase 7 — README / Docs

**File:** `README.md`

Add a macOS section after the existing install instructions:

```markdown
### macOS (Intel + Apple Silicon)

> macOS support is community-contributed. Requires Docker Desktop and Homebrew.

curl -fsSL https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/main/install/install_nomad.sh \
  -o install_nomad.sh && bash install_nomad.sh

The script will detect macOS and use the appropriate installer automatically.

**Apple Silicon (M1/M2/M3) — AI performance note:**  
Docker cannot access the Metal GPU. For full-speed local AI, install Ollama natively:
brew install ollama && ollama serve
Then in your N.O.M.A.D settings, set `OLLAMA_HOST=http://host.docker.internal:11434`.
All other features (Kiwix, Kolibri, maps, CyberChef, FlatNotes) run natively at full speed.
```

---

## Implementation Order

| # | Task | Effort | File(s) | Status |
|---|------|--------|---------| ------ |
| 1 | OS detection in existing install script | Small | `install_nomad.sh` | Done |
| 2 | `install_nomad_macos.sh` — core structure | Medium | new file | Done |
| 3 | macOS compose file | Medium | new file | Done |
| 4 | `NOMAD_DIR` parameterisation in helper scripts | Small | `update/uninstall_nomad.sh` | Done |
| 5 | Linux compose: `NOMAD_DIR` env var (non-breaking) | Tiny | `management_compose.yaml` | Done |
| 6 | README macOS section | Small | `README.md` | Done |
| 7 | Test on Mac mini M1 (Docker Desktop) | — | — | Pending |
| 8 | Test on Intel Mac (if available) | — | — | Pending |

---

## Open Questions (pending upstream response)

- ~~Are `ghcr.io/crosstalk-solutions/project-nomad:*` images published for `linux/arm64`?~~
  → **Answered:** No. CI builds on `ubuntu-latest` only (no buildx/multi-arch). macOS compose uses `platform: linux/amd64` on project images.
- Does the admin app's `OLLAMA_HOST` config already exist, or does it need app-level changes?  
  → May require a small change inside the Node.js admin app to read the env var

---

## Out of Scope (for now)

- Full native macOS app / `.pkg` installer
- macOS launchd service (auto-start on boot) — nice to have, post-MVP
- ROCm / AMD GPU support
- Windows support

# local-persist — Improvement Roadmap & Maintenance Plan

A working document for the maintained fork at **https://github.com/mataebi/local-persist**.
Intended to be picked up in a future session without needing the original conversation.

---

## 1. Background

`local-persist` is a Docker volume plugin that creates **named volumes backed by a host directory of your choosing** (`docker volume create -d local-persist -o mountpoint=/path --name=foo`).

It differs from Docker's built-in bind options in two decisive ways:

- **Auto-create** — on volume creation it runs `os.MkdirAll(mountpoint, 0755)`, so the target directory is created if missing.
- **Auto-populate** — because it registers as a *named volume*, Docker copies the image's content into the empty volume on first use (copy-up). A `driver_opts: type=none, o=bind, device=...` volume is treated as a bind mount and gets neither behavior.

The upstream project (`MatchbookLab/local-persist`) was **archived on 2025-09-15**. This fork keeps it alive and is used in a **multi-host Docker Swarm** environment with **shared CephFS storage** mounted at `/docker/volumes/`, where services must be able to move between hosts without losing state.

---

## 2. Current status

- Fork: `mataebi/local-persist`
- Target engine: **Docker 29.9.2**
- `scripts/install.sh` has been fixed for:
  - piped execution (`curl | bash`) — guarded `$BASH_SOURCE`
  - default repo pointing at the fork
  - SSH and HTTPS remote detection
  - malformed `GITHUB_RAW_BASE` URL
  - dynamic "latest release" lookup with fallback
- A `v1.3.0` release exists with asset `local-persist-linux-amd64`
- Plugin installed and running as a systemd service on host `HeRo`
- **Not yet verified:** volume create/mount against Docker 29.x, and task rescheduling on a second node.

---

## 3. Goals

1. Stay compatible with current and near-future Docker Engine and Go toolchains.
2. Reliable, repeatable installation across **all** Swarm nodes.
3. Preserve **auto-create + auto-populate** semantics.
4. Support shared/network filesystems (CephFS, NFS) for host mobility.

---

## 4. Improvement items

### 4.1 Modernize the Docker client dependency — **HIGH**

**Problem:** `driver.go` imports `github.com/docker/engine-api/client` and `github.com/docker/engine-api/types`. Both are long-deprecated and are the most likely cause of build/runtime breakage on modern Docker and Go.

**Tasks:**
- Replace `engine-api` with the modern `github.com/docker/docker/client` and `github.com/docker/docker/api/types`.
- Rewrite `findExistingVolumesFromDockerDaemon()` to use the modern client.
- Bump `github.com/docker/go-plugins-helpers` to the latest release.
- Update `go.mod` / `go.sum`; raise the Go directive.
- Add a README note stating the verified Docker/Go versions.

**Sketch — old vs new:**

```go
// OLD
import (
    "github.com/docker/engine-api/client"
    "github.com/docker/engine-api/types"
)
cli, err := client.NewClient("unix:///var/run/docker.sock", "v1.21", nil, defaultHeaders)
containers, err := cli.ContainerList(context.Background(), options)
info, err := cli.ContainerInspect(context.Background(), container.ID)

// NEW
import (
    "github.com/docker/docker/client"
    "github.com/docker/docker/api/types"
)
cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
containers, err := cli.ContainerList(ctx, types.ContainerListOptions{All: true})
info, err := cli.ContainerInspect(ctx, container.ID)
```

**Acceptance:** `go build` succeeds with Go 1.22+; plugin starts; `docker volume create` and mount work on Docker 29.x.

---

### 4.2 Release automation — **HIGH**

**Problem:** The install script downloads assets named `local-persist-<os>-<arch>`. Today these are built and uploaded by hand.

**Tasks:**
- Add `.github/workflows/release.yml`, triggered on `v*` tags.
- Build `linux/amd64` and `linux/arm64` (optionally darwin/windows).
- Name assets exactly `local-persist-linux-amd64`, `local-persist-linux-arm64`, etc.
- Attach them to the GitHub release.
- Optionally emit `SHA256SUMS` and attach it.

**Sketch:**

```yaml
name: release
on:
  push:
    tags: ['v*']
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        include:
          - { goos: linux, goarch: amd64 }
          - { goos: linux, goarch: arm64 }
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.22'
      - name: Build
        run: GOOS=${{ matrix.goos }} GOARCH=${{ matrix.goarch }} \
             go build -o local-persist-${{ matrix.goos }}-${{ matrix.goarch }} .
      - uses: softprops/action-gh-release@v2
        with:
          files: local-persist-${{ matrix.goos }}-${{ matrix.goarch }}
```

**Acceptance:** pushing a tag produces a release whose asset names match what `install.sh` builds.

---

### 4.3 Install script hardening — **MEDIUM**

**Tasks:**
- Add `set -euo pipefail`.
- Fallback when `realpath` is unavailable (use `cd "$(dirname ...)" && pwd`).
- Verify the downloaded binary against a published checksum.
- Add `--prefix <dir>` / custom install directory.
- Add an `uninstall` mode (stop/disable service, remove unit + binary).
- Ensure the arm64 path is exercised.
- Keep the existing fixes (piped execution, remote detection, dynamic version).

---

### 4.4 Multi-node installation / Swarm global service — **MEDIUM**

**Problem:** The plugin must exist on **every** node that could run the tasks; a missing node causes task failures.

**Tasks:**
- **Option A (docs + automation):** document/systematize installing the plugin on each node (Ansible role, cloud-init, image bake).
- **Option B (preferred):** run the plugin as a **Swarm global service** — one task per node — using a container image that mounts `/run/docker/plugins/` and the required data paths. This makes per-node presence automatic.
- Document both, recommend one.

---

### 4.5 Container image — **MEDIUM**

**Tasks:**
- Build and publish an image (GHCR or Docker Hub) from `Dockerfile`.
- Tag images to match releases (`:v1.3.0`, `:latest`).
- Update README to reference **this fork's** image instead of `cwspear/docker-local-persist-volume-plugin`.

---

### 4.6 Documentation — **MEDIUM**

**Tasks:**
- Migration guide: `driver_opts` bind → `local-persist` (include the "directory must pre-exist / no copy-up" rationale).
- Swarm multi-node setup guide.
- Shared-filesystem guide (CephFS/NFS) and host-mobility notes.
- Troubleshooting: release 404, "Unit … not loaded", plugin not registered, version mismatch, stuck `_data` mounts.

---

### 4.7 Testing & CI — **MEDIUM**

**Tasks:**
- Run `go test ./...` in CI on every push/PR.
- Add an integration test that asserts **auto-create** (missing dir is created) and **auto-populate** (image content copied into an empty volume).
- Add a Docker 29.x compatibility job (DinD or a matrix against engine versions).

---

### 4.8 Security — **LOW / MEDIUM**

**Tasks:**
- Publish `SHA256SUMS` with each release.
- Verify the checksum in `install.sh` before installing.
- Optionally sign release assets (cosign / sigstore).
- Never run the install script as `curl | sudo bash` in docs without the checksum step.

---

### 4.9 Code quality — **LOW**

**Tasks:**
- Add `context` timeouts to Docker API calls.
- Improve logging and error messages (the plugin currently prints to stdout).
- In `Mount`, re-create the mountpoint if it disappeared.
- Harden the state-file read/write (`/var/lib/docker/plugin-data/local-persist.json`).
- Add a minimal `CONTRIBUTING.md` and issue template.

---

## 5. Suggested milestones

| Milestone | Scope | Exit criteria |
|---|---|---|
| **M1 — Compatibility** | 4.1 + 4.7 | Builds on Go 1.22, works on Docker 29.9.2 |
| **M2 — Distribution** | 4.2 + 4.3 + 4.5 | Tag push publishes working, checksum-verified assets + image |
| **M3 — Operations** | 4.4 + 4.6 | Repeatable multi-node install; documented Swarm + CephFS |
| **M4 — Hardening** | 4.8 + 4.9 | Checksums enforced, code/robustness cleanup |

---

## 6. Known constraints / decisions

- The `local` driver is intentionally not used directly because it cannot provide auto-create + auto-populate on an arbitrary shared path.
- Data is expected on shared storage (CephFS at `/docker/volumes/`) so tasks remain host-mobile.
- The plugin is node-local (`Scope: local`); Swarm invokes `Create` on each node, which is what re-creates the directory on CephFS.
- Upstream is archived, so all changes live in this fork; no upstream PRs are possible.

---

## 7. References

- Fork: https://github.com/mataebi/local-persist
- Upstream (archived): https://github.com/MatchbookLab/local-persist
- Docker volume plugin API: https://docs.docker.com/engine/extend/plugin_api/
- Modern Docker Go client: https://github.com/docker/docker/tree/master/client

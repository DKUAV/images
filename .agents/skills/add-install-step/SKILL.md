---
name: add-install-step
description: "Add a new shared installation step to the repository. Use when: adding a new shared install script, adding a new tool to dev images, adding a build step to Dockerfiles, creating a new _scripts entry, extracting repeated inline RUN commands into a reusable script."
argument-hint: "Describe the installation step to add, e.g. install tool X for dev images"
---

# Add a New Installation Step

## When to Use

- Installing a new tool or configuring a new environment in one or more Docker images
- Extracting repeated inline `RUN` commands into a reusable script
- Introducing new build-time assets (config files, templates, etc.)

## Repository Layout Reference

```
src/
  _scripts/   # Shared install scripts (numbered sequentially)
  _assets/    # Build-time static assets (config files, etc.)
  <image>/
    Dockerfile
```

## Step 1 — Choose a Script Number and Scope

Check existing script numbers in `src/_scripts/` (currently 01–10) and pick the next available number.

| Number range | Conventional purpose |
|---|---|
| 01–03 | Core system deps (apt, Python, pip) |
| 04–05 | Common tools (ROS 2, CMake) |
| 06–09 | Dev-only tools (clang, dotnet, devshell) |
| 10+   | New additions |

Determine the target scope:
- **All images** → add to `system.sh` or a new script; update every Dockerfile
- **All base images** → update `luciole-base`, `luciole-cuda-base`, `luciole-l4t-base`
- **All dev images** → update `luciole-humble-dev`, `luciole-humble-cuda-dev`, `luciole-humble-l4t-dev`
- **Specific image only** → update only that image's Dockerfile

## Step 2 — Write the Script

Create `src/_scripts/<NN>-<name>.sh` following these conventions:

```bash
#!/bin/bash
# One-line description: what this script does and which images use it.
# If the script must run as the target non-root user, state that here.
# List all environment variables read and their defaults.
set -euo pipefail

# Accept parameters via environment variables with defaults
MY_VAR="${MY_VAR:-default_value}"
```

Rules:
- `set -euo pipefail` is mandatory
- After `apt-get install`, always clean up: `rm -rf /var/lib/apt/lists/*`
- Pass build-time values via environment variables (`ARG` → `ENV`), never hardcode
- Verify checksums for any downloaded external binaries

## Step 3 — Handle Static Assets (if any)

If the script depends on config files or templates:

1. Place the files under `src/_assets/`
2. In the Dockerfile, copy the **entire** assets directory, not individual files:
   ```dockerfile
   COPY src/_assets/ /tmp/assets/
   ```
3. Reference the path in the script via an environment variable with a default:
   ```bash
   MY_CONFIG="${MY_CONFIG:-/tmp/assets/my-config.yaml}"
   ```

## Step 4 — Update the Dockerfile(s)

### Where to call the script

- **Root-level scripts**: insert `RUN /tmp/scripts/<NN>-<name>.sh` before `USER ${USERNAME}`
- **Scripts that must run as the target user** (e.g. devshell, pre-commit): call after `USER ${USERNAME}`

### Standard Dockerfile structure

```dockerfile
COPY src/_scripts/ /tmp/scripts/
COPY src/_assets/ /tmp/assets/        # only when assets are needed
RUN chmod +x /tmp/scripts/*.sh

# --- root-level scripts ---

ARG USERNAME=luciole
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# --- user-level scripts (if any) ---
RUN /tmp/scripts/devshell.sh
RUN /tmp/scripts/precommit.sh

USER root
RUN rm -rf /tmp/scripts /tmp/assets   # clean up both in one RUN

USER ${USERNAME}
WORKDIR /home/${USERNAME}
```

> **Common mistake**: `/tmp/scripts/` and `/tmp/assets/` are both removed in the single `RUN rm -rf` line after switching back to root. Do not split this across multiple `RUN` instructions and do not forget `/tmp/assets/`.

## Step 5 — Update Documentation

Per the documentation sync rules in `AGENTS.md`:

| Changed file | Documentation to update |
|---|---|
| New `src/_scripts/*.sh` | Update the script table in `AGENTS.md`; update `README.md` / `README_zh.md` for affected images |
| `Dockerfile` | Update the corresponding image's `README.md` and `README_zh.md` |
| New file under `src/_assets/` | Update image docs that reference the asset's feature |

## Step 6 — Checklist

- [ ] Script has `#!/bin/bash` and `set -euo pipefail`
- [ ] Script number does not conflict with existing scripts
- [ ] All target Dockerfiles updated (base / dev / runtime as appropriate)
- [ ] `COPY src/_assets/` used instead of copying a single file (when assets exist)
- [ ] Cleanup line `rm -rf /tmp/scripts /tmp/assets` covers all temp directories
- [ ] Documentation synced (`README.md`, `README_zh.md`, `AGENTS.md`)
- [ ] `image-deps.json` unchanged (only needed when adding a new image directory)

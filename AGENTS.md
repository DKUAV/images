# LucioleImages Agent Guide

## Scope

- This repository stores Docker-based development environment definitions for the Luciole project.
- Today the only concrete environment is [src/jammy-dev/Dockerfile](src/jammy-dev/Dockerfile) with its runtime wiring in [src/jammy-dev/docker-compose.yml](src/jammy-dev/docker-compose.yml).
- Treat this as an infrastructure/configuration repo, not an application repo.

## Primary Entry Points

- [README.md](README.md) currently only gives the repository title.
- [src/jammy-dev/Dockerfile](src/jammy-dev/Dockerfile) defines the Ubuntu 22.04 image, ROS 2 Humble setup, Python tooling, GUI support, and shell/editor bootstrap.
- [src/jammy-dev/docker-compose.yml](src/jammy-dev/docker-compose.yml) defines how that image is launched locally.

## Working Rules

- Run Docker Compose commands from the [src/jammy-dev](src/jammy-dev) directory, not from the repository root.
- There is no application source tree, CI pipeline, test suite, or lint configuration in this repository right now.
- When changing the Docker image, keep existing mirror, locale, ROS, and developer-tooling choices intact unless the task explicitly asks to change them.
- Prefer small, reviewable diffs. Most tasks here should touch only the Dockerfile, the compose file, or documentation.

## Validation

- Use `cd src/jammy-dev && docker compose config` for a cheap structural check after compose edits.
- Use `cd src/jammy-dev && docker compose build` to validate Dockerfile or dependency changes.
- If a change affects GUI or ROS runtime behavior, mention that full validation may require a host with WSLg-compatible display plumbing.

## Environment Notes

- The compose file mounts `/tmp/.X11-unix` and `/mnt/wslg` and forwards display-related environment variables. That is WSLg-oriented setup, so do not rewrite it as a generic Linux or macOS solution unless the user asks.
- The image creates a non-root `luciole` user, switches the default shell to zsh, and appends shell customizations during build. Be careful with changes in the user-setup section because they can break login shell startup.
- The Dockerfile uses Aliyun mirrors for apt and pip. Keep mirror changes deliberate.

## When Extending Instructions

- Link to the defining file instead of copying long package or environment variable lists into instructions.
- If this repository grows beyond [src/jammy-dev](src/jammy-dev), add focused files under `.github/instructions/` for per-area guidance instead of expanding this file into a long checklist.
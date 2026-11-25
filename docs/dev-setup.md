# Developer setup

Supported: **Linux x86_64**, and **Windows 10/11 through WSL2** (Ubuntu 24.04), which behaves like Linux. macOS is not supported by the scripts. Nothing below needs root except installing Docker and the one-time `make host-sysctl`.

Needs about **10–12 GB RAM** for the full stack with monitoring, and ~25 GB disk.

## Linux

```bash
git clone git@github.com:hokusai0603/CCSA-final-project.git && cd CCSA-final-project
make tools                    # k3d, kubectl, helm, k6, uv, shellcheck, actionlint -> ~/.local/bin (pinned, checksummed)
nvm install                   # Node 24 from .nvmrc (install nvm first: https://github.com/nvm-sh/nvm)
uv python install 3.12
make preflight                # fix every FAIL; if inotify fails: make host-sysctl (sudo, once)
```

Docker Engine must be usable without sudo (`docker ps` works; user in the `docker` group, then log out and in).

## Windows (WSL2)

Do everything **inside the WSL Ubuntu shell**, not PowerShell or Git Bash.

1. Install WSL with Ubuntu (PowerShell as admin): `wsl --install -d Ubuntu-24.04`.
2. Give the WSL VM enough memory. Create `%UserProfile%\.wslconfig`:
   ```ini
   [wsl2]
   memory=12GB
   ```
3. Enable systemd so sysctl settings and Docker start with WSL. In Ubuntu, `sudo nano /etc/wsl.conf`:
   ```ini
   [boot]
   systemd=true
   ```
   Then in PowerShell: `wsl --shutdown`, and reopen Ubuntu.
4. Install **Docker Engine inside Ubuntu** (https://docs.docker.com/engine/install/ubuntu/), then `sudo usermod -aG docker $USER` and restart the shell. This keeps Docker, k3d and the sysctl limits in one Linux system, so `make preflight` checks the machine that actually runs the containers. Docker Desktop with WSL integration also works, but its containers run in a separate VM that `preflight` cannot inspect. Use one or the other, not both.
5. Clone **into the WSL filesystem** (`~/CCSA-final-project`), never under `/mnt/c/...`: that path is slow and breaks file modes (`preflight` fails on it). Edit with VS Code's *WSL* extension (`code .` from the Ubuntu shell).
6. Continue with the Linux steps above (`make tools`, `nvm install`, …).

A Windows browser reaches the cluster at `http://localhost:8080` (WSL forwards localhost). Phones on the LAN cannot reach a WSL2 cluster without extra Windows networking setup, so the live demo runs on the Linux machine.

> These WSL2 steps follow the official WSL/Docker documentation but have not been run on this project yet. On first setup, run `make preflight` and report anything it flags.

## Line endings

`.gitattributes` forces LF on every OS. If a script fails with `/usr/bin/env: 'bash\r'`, the checkout predates it: `git rm -r --cached . && git reset --hard`. `make preflight` checks this.

## One machine for official numbers

Develop anywhere, but record every number in `docs/goals.md` on **one** machine (the Linux lab host) and run the demo there. Different CPUs and background load change p99 latencies and HPA timing (`docs/host-environment.md` R4).

# orca-server

Container build for a headless [Orca](https://github.com/stablyai/orca) runtime,
intended for deployment through Dokploy.

Orca ships a Linux AppImage and a `serve` command, but no official server image.
This repo packages that AppImage into a non-root container that starts as a
runtime server, serves the bundled browser client on one port, and keeps agent
credentials on a persistent volume.

## What runs

- `orca serve` on port `6768`, launched through `resources/bin/orca-ide` (the
  bundled CLI launcher; `AppRun` does not print the readiness/pairing payload).
- The runtime serves the web client over HTTP on the same port: `/` and
  `/web-index.html` both return the SPA, with assets under `/assets/`.
- Orca starts its own `Xvfb :99` when `DISPLAY` is unset.
- Everything runs as the unprivileged `orca` user. Claude Code refuses
  `--dangerously-skip-permissions` under uid 0, and Orca passes that flag.

## Agents installed

- opencode (`opencode-ai`)
- Claude Code (`@anthropic-ai/claude-code`)
- Codex (`@openai/codex`)
- Antigravity (`agy`)

## Volumes

- `/home/orca` — Orca state, pairing/device keys, agent credentials. Sequentially
  the same volume across redeploys, so logins survive.
- `/workspace` — cloned repositories and git worktrees.

## Environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `ORCA_VERSION` | `v1.4.212` | Release tag baked into the image |
| `ORCA_SERVE_PORT` | `6768` | Runtime listener port |
| `ORCA_PAIRING_ADDRESS` | `wss://localhost:6768` | Advertised endpoint clients dial |
| `ORCA_PROJECT_ROOT` | _(unset)_ | Optional default project root |
| `ORCA_JSON` | `0` | Emit the machine-readable ready JSON |
| `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GH_TOKEN` | _(unset)_ | Agent/repo credentials |

The pairing URL is printed in the container logs at startup (`Pairing URL:` and
`Web client URL:`). Treat it as a credential: it grants a full shell on the
runtime. Keep the runtime on a private network path (Tailscale/SSH tunnel) or
behind authenticated TLS, never raw on the public internet.

## Deploy

```bash
docker compose up -d --build
docker compose logs -f orca
```

Pin the release tag deliberately; `orca serve` never self-updates.

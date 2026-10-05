# RPFM 5.1.1 in Docker

This container runs **RPFM Server**, the current headless RPFM backend, with
WebSocket and Streamable HTTP MCP access. It does not display the desktop GUI
and does not implement the removed `rpfm_cli` command syntax.

The root Dockerfile and existing GitHub Action remain the legacy CLI setup.
This separate directory lets you try the new backend without replacing them.

## Build and start

Install Docker Desktop on Windows, using Linux containers. From this directory:

```sh
docker compose up -d --build
```

The first build compiles Rust dependencies and can take a while. Subsequent
builds reuse BuildKit's Cargo caches. No image is downloaded from or published
to the old GHCR package by these commands.

Verify the running server:

```sh
curl http://127.0.0.1:45127/version
docker compose ps
docker compose logs
```

In Windows PowerShell, use `curl.exe` instead of `curl` if `curl` is an alias.

Put your `.pack` files inside `work/`. A host file `work/example.pack` is
`/work/example.pack` inside RPFM. MCP clients must use the container path.
The image runs as UID/GID 1000; on Linux, ensure that user can write to `work/`.
Configuration, schemas and caches persist in the `rpfm-config` named volume.

For example, from PowerShell:

```powershell
Copy-Item 'C:\Mods\example.pack' '.\work\example.pack'
```

## Connect

- MCP (Streamable HTTP): `http://127.0.0.1:45127/mcp`
- WebSocket: `ws://127.0.0.1:45127/ws`
- Server version: `http://127.0.0.1:45127/version`

An MCP client can call `set_game_selected` with
`{"game_name":"warhammer_3","rebuild_dependencies":false}`, then
`open_packfiles` with `{"paths":["/work/example.pack"]}`. Inspect the tool's
input schema in your client for additional optional parameters.

The port is published on the host's **localhost only**. Upstream has no
authentication here. Keep this binding when using the container locally.
This does not automatically connect the container to ChatGPT.

For dependency diagnostics against vanilla files, mount your game's data
directory read-only, e.g. add a Compose volume
`"C:/Games/Total War WARHAMMER III/data:/game/data:ro"`. Then configure the
game paths via the server's settings tools using `/game/...` paths; some
operations also require the game executable or Assembly Kit files. Those
files are not included in the image. Ordinary pack inspection and editing
do not require a full game installation.

## GitHub Actions

Use the composite action in this directory on a Linux runner. It builds the
pinned backend unless given a prebuilt image, waits for readiness, and mounts
the job's repository at `/work`. It runs as the runner's UID/GID so saved packs
can be read and uploaded by subsequent steps. Configuration is temporary for
each invocation, avoiding interference between jobs.

```yaml
jobs:
  mod-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7.0.1
      - uses: Warhammer-Mods/rpfm_cli-docker/server@d8e9d8c2cea27c04657431b70f3cf890aeffd8d9
        id: rpfm
      - name: Run your pack script
        env:
          RPFM_MCP_URL: ${{ steps.rpfm.outputs.mcp-url }}
        run: python3 scripts/build_mod.py
      - name: Upload resulting pack
        uses: actions/upload-artifact@v4
        with:
          name: mod-pack
          path: output/*.pack
      - name: Stop RPFM
        if: always() && steps.rpfm.outputs.container != ''
        env:
          RPFM_CONTAINER: ${{ steps.rpfm.outputs.container }}
        run: docker rm --force "$RPFM_CONTAINER"
```

This example pins the action to the commit validated by the workflow below.
`scripts/build_mod.py` and `output/*.pack` illustrate where your own build
script and outputs go; they are not included. Your script needs an MCP or
WebSocket client, since the former CLI arguments are not supported. Use
`smoke_test.py` as a minimal stdlib MCP client example.

For faster repeated runs, build with `docker/build-push-action` and a GitHub
Actions cache, then pass the loaded local image through the `image` input.
The supplied `server-ci.yml` workflow demonstrates this without publishing.
The action also accepts a `port` input if 45127 is already in use.

## Smoke test

With Python 3 installed on the host, run:

```sh
python3 smoke_test.py
```

On Windows, `py smoke_test.py` is an alternative. The test checks the exact
server version, HTTP endpoints, MCP initialization/tool discovery, WH3 schema
loading and creation/listing/closure of an empty in-memory pack. It does not
save files or touch existing packs. The GitHub Actions workflow builds the
image and additionally uses `--roundtrip` to save and reopen a temporary pack
under the mounted job workspace, checking container-to-host file permissions.
The temporary directory is removed afterward. It never publishes an image.

## Stop and update

```sh
docker compose down
```

This keeps the named configuration volume. `docker compose down -v` removes
it, including configuration, schema updates, caches and any stored autosaves.

RPFM source is pinned to the official 5.1.1 commit
`5204dab9e9a9376c438deabed8489de3bc319599`. The initial schema checkout is
pinned to `5d841c5c2a73d27495c6fed7282dc011c5517e1c`, matching that release.
Existing schema checkouts are retained on restart; use the server's schema
update tool when definitions change. Building a newer image alone does not
replace schemas in an existing configuration volume.

The builder uses the rolling stable `rust:bookworm` image. For fully locked
builds, override `RUST_IMAGE` with a tested tag or digest and pin the runtime
base digest too. `cargo --locked` retains upstream's dependency lockfile.
An upstream upgrade requires updating the commit pins, version label, image
tag and expected smoke-test version together, followed by a fresh build/test.

## Docker adaptations

RPFM 5.1.1 hard-codes its listener to `127.0.0.1:45127`. Rather than editing
upstream Rust code, a small `socat` proxy forwards container port 45128 to
that listener. Compose maps host localhost port 45127 to container port 45128.
`tini` and the entrypoint supervise both processes and forward shutdowns.
Compose restarts the service if either process exits, including RPFM's normal
shutdown after its last WebSocket session expires.

The server and desktop UI have separate client sessions. Connecting another
client does not expose packs already opened in a different session.
This container has no Qt desktop interface, browser interface, or remote desktop.

## Validation status

The build files, shell syntax, YAML and smoke-test source were checked locally.
Entrypoint supervision was exercised with substitute processes: server failure,
proxy failure and SIGTERM all propagated their expected exit codes and cleaned
up the companion process. Initial schema seeding was also checked.
The preparation environment had no Docker engine. The actual image build,
runtime dependency check and live MCP smoke test subsequently passed on a
GitHub-hosted Linux runner, including 155 MCP tools, WH3 schema loading,
pack creation and saving/reopening through the mounted workspace.

[Successful CI run](https://github.com/Warhammer-Mods/rpfm_cli-docker/actions/runs/37256097535)
validated commit `d8e9d8c2cea27c04657431b70f3cf890aeffd8d9`.
This validates the headless backend workflow, not every RPFM operation or
in-game compatibility of packs created with it.

RPFM is created by [Frodo45127](https://github.com/Frodo45127/rpfm) and its
contributors, under the MIT license. See the root repository LICENSE.

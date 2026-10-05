#!/bin/bash
set -euo pipefail

mkdir -p /config/rpfm
if [[ ! -e /config/rpfm/schemas ]]; then
    # Seed once. Never replace a user's existing schema checkout on startup.
    cp -R /opt/rpfm-seed/schemas /config/rpfm/schemas
fi

server_pid=''
proxy_pid=''
cleanup() {
    trap - EXIT TERM INT
    [[ -z "$proxy_pid" ]] || kill "$proxy_pid" 2>/dev/null || true
    [[ -z "$server_pid" ]] || kill "$server_pid" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

rpfm_server &
server_pid=$!
socat TCP-LISTEN:45128,bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:45127 &
proxy_pid=$!

# If either service dies, terminate the other and preserve the exit status.
# Compose restarts the container even after an upstream idle shutdown (exit 0).
set +e
wait -n "$server_pid" "$proxy_pid"
status=$?
set -e
exit "$status"

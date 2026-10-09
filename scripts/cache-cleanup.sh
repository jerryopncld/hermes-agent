#!/usr/bin/env bash
#
# cache-cleanup.sh — Weekly cache cleanup on hermes host (LXC 1014)
#
# Runs from cron, no LLM. Reclaims ~10-30 GB/week of build/download caches that
# are automatically regenerated and have no long-term value:
#   - uv archive/wheels/sdists (Python wheel cache; ~15 GB max)
#   - pip wheel/http cache (~250 MB)
#   - npm cache (~1-2 GB)
#   - go build cache (rebuilt on next go build; ~1-2 GB)
#
# Safe to leave HF (3.8 GB), browsers (Playwright/Puppeteer), and backups untouched.
# HF browser caches are excluded because they take long to re-download and could
# affect active skills; backups have retention value.
#
# Idempotent: only runs cleanup when disk >= 75% to avoid pointless churn.
# Exits 0 always; logs reclaimed MB to syslog for visibility.
#
# Cron:    0 4 * * 0 /home/ypyly/.hermes/scripts/cache-cleanup.sh >> /home/ypyly/.hermes/logs/cache-cleanup.log 2>&1
#
# Trigger also: from alertmanager recovery path after a disk_high webhook.

set -uo pipefail

LOG_TAG="cache-cleanup"
THRESHOLD_PCT="${THRESHOLD_PCT:-75}"
HOME_DIR="${HOME:-/home/ypyly}"

log() {
    logger -t "$LOG_TAG" "$*"
    echo "$*"
}

# Bail early when disk is healthy
USE_PCT="$(df --output=pcent "$HOME_DIR" 2>/dev/null | tail -1 | tr -dc '0-9')"
USE_PCT="${USE_PCT:-0}"
if [ "$USE_PCT" -lt "$THRESHOLD_PCT" ]; then
    log "skip: disk at ${USE_PCT}% (< ${THRESHOLD_PCT}% threshold)"
    exit 0
fi

log "starting: disk at ${USE_PCT}%"
START_FREE_KB="$(df --output=avail "$HOME_DIR" | tail -1 | tr -dc '0-9')"
START_FREE_KB="${START_FREE_KB:-0}"

# uv: prefer `uv cache clean` (respects UV_CACHE_DIR) — reclaims archive/wheels/sdists
if command -v uv >/dev/null 2>&1; then
    BEFORE="$(du -sk "$HOME_DIR/.cache/uv" 2>/dev/null | awk '{print $1}')"
    BEFORE="${BEFORE:-0}"
    uv cache clean >/dev/null 2>&1 || true
    AFTER="$(du -sk "$HOME_DIR/.cache/uv" 2>/dev/null | awk '{print $1}')"
    AFTER="${AFTER:-0}"
    log "uv cache: $((BEFORE - AFTER)) KB reclaimed"
fi

# pip
if command -v pip >/dev/null 2>&1; then
    BEFORE="$(du -sk "$HOME_DIR/.cache/pip" 2>/dev/null | awk '{print $1}')"
    BEFORE="${BEFORE:-0}"
    pip cache purge >/dev/null 2>&1 || true
    AFTER="$(du -sk "$HOME_DIR/.cache/pip" 2>/dev/null | awk '{print $1}')"
    AFTER="${AFTER:-0}"
    log "pip cache: $((BEFORE - AFTER)) KB reclaimed"
fi

# npm
if command -v npm >/dev/null 2>&1; then
    BEFORE="$(du -sk "$HOME_DIR/.npm" 2>/dev/null | awk '{print $1}')"
    BEFORE="${BEFORE:-0}"
    npm cache clean --force >/dev/null 2>&1 || true
    AFTER="$(du -sk "$HOME_DIR/.npm" 2>/dev/null | awk '{print $1}')"
    AFTER="${AFTER:-0}"
    log "npm cache: $((BEFORE - AFTER)) KB reclaimed"
fi

# go
if command -v go >/dev/null 2>&1; then
    BEFORE="$(du -sk "$HOME_DIR/.cache/go-build" 2>/dev/null | awk '{print $1}')"
    BEFORE="${BEFORE:-0}"
    go clean -cache >/dev/null 2>&1 || true
    AFTER="$(du -sk "$HOME_DIR/.cache/go-build" 2>/dev/null | awk '{print $1}')"
    AFTER="${AFTER:-0}"
    log "go cache: $((BEFORE - AFTER)) KB reclaimed"
fi

END_FREE_KB="$(df --output=avail "$HOME_DIR" | tail -1 | tr -dc '0-9')"
END_FREE_KB="${END_FREE_KB:-0}"
NEW_USE_PCT="$(df --output=pcent "$HOME_DIR" | tail -1 | tr -dc '0-9')"
log "done: ${USE_PCT}% -> ${NEW_USE_PCT}%, freed $(( (END_FREE_KB - START_FREE_KB) / 1024 )) MB"

exit 0

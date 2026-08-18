#!/usr/bin/env bash
#
# Talks to the AppRunner control plane on behalf of a workflow job.
#
# Every subcommand is a no-op when APPRUNNER_RUN_ID is empty, so the workflow
# can also be dispatched by hand to build the newest archive without a run to
# report against.
#
# Required environment:
#   APPRUNNER_URL   base URL of the control plane
#   APPRUNNER_KEY   CI key issued by AppRunner
# Optional:
#   APPRUNNER_RUN_ID   run to report progress against
set -euo pipefail

: "${APPRUNNER_URL:?APPRUNNER_URL is required}"
: "${APPRUNNER_KEY:?APPRUNNER_KEY is required}"
RUN_ID="${APPRUNNER_RUN_ID:-}"

API="${APPRUNNER_URL%/}/api/v1/ci"
AUTH=(-H "Authorization: Bearer ${APPRUNNER_KEY}")
# --http1.1 is load-bearing: large multipart bodies over HTTP/2 fail against
# the reverse proxy with "Error in the HTTP2 framing layer" and 502s, while
# small requests survive — so logs uploaded fine and 7 MB artifacts did not.
CURL=(curl --silent --show-error --fail-with-body --http1.1 --retry 3 --retry-delay 2 --retry-connrefused --max-time 300)

log() { printf '\033[1;35m[apprunner]\033[0m %s\n' "$*" >&2; }

# Reporting must never take the build down with it; a dropped status line is
# worth less than the build result it would discard.
soft() { "$@" || log "warning: reporting call failed, continuing"; }

# A here-string appends a newline, which would otherwise ride along into every
# detail string the pipeline rail shows.
json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))' <<<"${1-}"; }

require_run() {
  if [[ -z "$RUN_ID" ]]; then
    log "no run id set; skipping $1"
    return 1
  fi
  return 0
}

# ── resolve: print the archive metadata JSON ────────────────────────────────
cmd_resolve() {
  local query=""
  if [[ -n "$RUN_ID" ]]; then
    query="run=${RUN_ID}"
  elif [[ -n "${APPRUNNER_PROJECT:-}" ]]; then
    query="project=${APPRUNNER_PROJECT}"
  fi
  "${CURL[@]}" "${AUTH[@]}" "${API}/resolve?${query}"
}

# ── fetch: download and unpack the archive into a directory ─────────────────
cmd_fetch() {
  local dest="${1:?usage: apprunner.sh fetch <dir>}"
  local meta archive_url fmt prefix sha version slug

  meta="$(cmd_resolve)"
  archive_url="$(jq -r '.archive.downloadUrl' <<<"$meta")"
  fmt="$(jq -r '.archive.format' <<<"$meta")"
  prefix="$(jq -r '.archive.rootPrefix // ""' <<<"$meta")"
  sha="$(jq -r '.archive.sha256' <<<"$meta")"
  version="$(jq -r '.archive.version' <<<"$meta")"
  slug="$(jq -r '.project.slug' <<<"$meta")"

  log "fetching ${slug} v${version} (${fmt})"

  local tmp
  tmp="$(mktemp -d)"
  local file="${tmp}/archive.${fmt}"
  "${CURL[@]}" "${AUTH[@]}" -L -o "$file" "$archive_url"

  local actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | cut -d' ' -f1)"
  else
    actual="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  fi
  if [[ "$actual" != "$sha" ]]; then
    log "checksum mismatch: expected ${sha}, got ${actual}"
    exit 1
  fi

  mkdir -p "$dest"
  if [[ "$fmt" == "zip" ]]; then
    unzip -q "$file" -d "${tmp}/x"
  else
    mkdir -p "${tmp}/x"
    tar -xzf "$file" -C "${tmp}/x"
  fi

  # AppRunner records the shared leading directory so uploads and GitHub
  # tarballs (which always nest under `repo-<sha>/`) unpack identically.
  local src="${tmp}/x"
  if [[ -n "$prefix" && -d "${tmp}/x/${prefix}" ]]; then
    src="${tmp}/x/${prefix}"
  fi

  if [[ ! -f "${src}/pubspec.yaml" ]]; then
    log "no pubspec.yaml in the unpacked archive"
    exit 1
  fi

  cp -R "${src}/." "$dest/"
  rm -rf "$tmp"

  # Hand the metadata back to later steps.
  {
    echo "apprunner_project=${slug}"
    echo "apprunner_version=${version}"
    echo "apprunner_commit=$(jq -r '.archive.commitSha // ""' <<<"$meta")"
  } >> "${GITHUB_OUTPUT:-/dev/null}"

  log "unpacked into ${dest}"
}

# ── run lifecycle ───────────────────────────────────────────────────────────
cmd_start() {
  require_run start || return 0
  local url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
  soft "${CURL[@]}" "${AUTH[@]}" -X POST -H 'Content-Type: application/json' \
    -d "{\"gh_run_id\":\"${GITHUB_RUN_ID:-}\",\"gh_run_url\":\"${url}\"}" \
    "${API}/runs/${RUN_ID}/start" >/dev/null
}

cmd_stage() {
  local stage="${1:?usage: apprunner.sh stage <key> <status> [detail]}"
  local status="${2:?usage: apprunner.sh stage <key> <status> [detail]}"
  local detail="${3-}"
  require_run "stage ${stage}" || return 0
  soft "${CURL[@]}" "${AUTH[@]}" -X POST -H 'Content-Type: application/json' \
    -d "{\"stage\":\"${stage}\",\"status\":\"${status}\",\"detail\":$(json_escape "$detail")}" \
    "${API}/runs/${RUN_ID}/stage" >/dev/null
}

cmd_event() {
  local level="${1:?usage: apprunner.sh event <level> <message>}"
  local message="${2:?usage: apprunner.sh event <level> <message>}"
  require_run event || return 0
  soft "${CURL[@]}" "${AUTH[@]}" -X POST -H 'Content-Type: application/json' \
    -d "{\"level\":\"${level}\",\"message\":$(json_escape "$message")}" \
    "${API}/runs/${RUN_ID}/events" >/dev/null
}

cmd_log() {
  local stage="${1:?usage: apprunner.sh log <stage> <name> <file>}"
  local name="${2:?usage: apprunner.sh log <stage> <name> <file>}"
  local file="${3:?usage: apprunner.sh log <stage> <name> <file>}"
  require_run "log ${name}" || return 0
  [[ -s "$file" ]] || { log "log ${file} is empty, not uploading"; return 0; }
  soft "${CURL[@]}" "${AUTH[@]}" -X POST -F "file=@${file}" \
    "${API}/runs/${RUN_ID}/logs?stage=${stage}&name=${name}" >/dev/null
}

cmd_artifact() {
  local kind="${1:?usage: apprunner.sh artifact <kind> <file>}"
  local file="${2:?usage: apprunner.sh artifact <kind> <file>}"
  require_run "artifact ${kind}" || return 0
  [[ -s "$file" ]] || { log "artifact ${file} is missing or empty"; return 0; }
  log "uploading $(basename "$file") ($(du -h "$file" | cut -f1))"

  if "${CURL[@]}" --max-time 1800 "${AUTH[@]}" -X POST -F "file=@${file}" \
      "${API}/runs/${RUN_ID}/artifacts?kind=${kind}&filename=$(basename "$file")" >/dev/null; then
    return 0
  fi

  # Loud, not soft: a run that says "passed" with nothing to download is worse
  # than one that says the upload failed.
  log "ERROR: failed to upload $(basename "$file")"
  cmd_event error "Build succeeded but $(basename "$file") could not be uploaded."
  return 1
}

cmd_finish() {
  local status="${1:?usage: apprunner.sh finish <status> [summary]}"
  local summary="${2-}"
  require_run finish || return 0
  soft "${CURL[@]}" "${AUTH[@]}" -X POST -H 'Content-Type: application/json' \
    -d "{\"status\":\"${status}\",\"summary\":$(json_escape "$summary")}" \
    "${API}/runs/${RUN_ID}/finish" >/dev/null
}

case "${1:?usage: apprunner.sh <resolve|fetch|start|stage|event|log|artifact|finish> ...}" in
  resolve)  shift; cmd_resolve "$@" ;;
  fetch)    shift; cmd_fetch "$@" ;;
  start)    shift; cmd_start "$@" ;;
  stage)    shift; cmd_stage "$@" ;;
  event)    shift; cmd_event "$@" ;;
  log)      shift; cmd_log "$@" ;;
  artifact) shift; cmd_artifact "$@" ;;
  finish)   shift; cmd_finish "$@" ;;
  *) log "unknown command: $1"; exit 2 ;;
esac

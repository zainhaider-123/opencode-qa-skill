#!/usr/bin/env bash
#
# figma-qa-delegator.sh
#
# Delegates Figma Design QA runs across multiple sites/pages or queues them
# for parallel execution using agent-browser sessions.
#
# Usage:
#   Single run:
#     ./figma-qa-delegator.sh run <site-url> <figma-url> [frame-width]
#
#   Batch from JSON config:
#     ./figma-qa-delegator.sh batch <config.json>
#
#   Config JSON format for batch:
#     [
#       {"siteUrl": "https://example.com", "figmaUrl": "https://figma.com/...", "frameWidth": 1920},
#       ...
#     ]
#
# Author: Generated for figma-design-qa skill with agent-browser

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION="${1:?Usage: $0 <run|batch> [args...]}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[DELEGATOR]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[DELEGATOR]${NC} $1"; }
log_error() { echo -e "${RED}[DELEGATOR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[DELEGATOR]${NC} $1"; }

# Generate a run folder name from hostname
generate_run_folder() {
  local url="$1"
  local hostname
  hostname=$(echo "$url" | sed -E 's|https?://||' | sed -E 's|/.*||' | sed -E 's|[^a-zA-Z0-9.-]|_|g')
  local timestamp
  timestamp=$(date +"%Y-%m-%d_%H-%M")
  echo "${timestamp}_${hostname}"
}

# Single run
run_single() {
  local site_url="${1:?Usage: $0 run <site-url> <figma-url> [frame-width]}"
  local figma_url="${2:?Usage: $0 run <site-url> <figma-url> [frame-width]}"
  local frame_width="${3:-1920}"

  local run_folder
  run_folder=$(generate_run_folder "$site_url")

  log_step "========================================"
  log_step "Single QA Run"
  log_step "========================================"
  log_info "Site URL:      $site_url"
  log_info "Figma URL:     $figma_url"
  log_info "Frame Width:   $frame_width"
  log_info "Run Folder:    $run_folder"
  log_info ""

  # Step A: Collect live site data
  log_step "STEP A: Collecting live site data..."
  bash "$SCRIPT_DIR/figma-qa-collect-live-site.sh" "$site_url" "$run_folder" "$frame_width"

  # Step B: Pull Figma design data
  log_step "STEP B: Pulling Figma design data..."
  bash "$SCRIPT_DIR/figma-qa-pull-figma.sh" "$figma_url" "$run_folder"

  # Step C: Generate report
  log_step "STEP C: Generating QA report..."
  bash "$SCRIPT_DIR/figma-qa-generate-report.sh" "$run_folder"

  log_step "========================================"
  log_info "QA Run Complete! Report at:"
  log_info "  ./figma-design-qa-reports/$run_folder/report.pdf"
  log_step "========================================"
}

# Batch run from JSON config
run_batch() {
  local config_file="${1:?Usage: $0 batch <config.json>}"

  if [[ ! -f "$config_file" ]]; then
    log_error "Config file not found: $config_file"
    exit 1
  fi

  if ! command -v jq &>/dev/null; then
    log_error "jq is required for batch mode."
    exit 1
  fi

  local total
  total=$(jq 'length' "$config_file")

  log_step "========================================"
  log_step "Batch QA Run"
  log_step "Jobs: $total"
  log_step "========================================"

  local i=0
  while IFS= read -r job; do
    i=$((i + 1))
    local site_url figma_url frame_width
    site_url=$(echo "$job" | jq -r '.siteUrl')
    figma_url=$(echo "$job" | jq -r '.figmaUrl')
    frame_width=$(echo "$job" | jq -r '.frameWidth // 1920')

    log_step ""
    log_step "--- Job $i/$total ---"
    log_info "Site:  $site_url"
    log_info "Figma: $figma_url"

    run_single "$site_url" "$figma_url" "$frame_width" || {
      log_error "Job $i failed! Continuing with remaining jobs..."
    }

    # Small delay between runs to avoid overwhelming the browser
    if [[ $i -lt $total ]]; then
      log_info "Waiting 3s before next job..."
      sleep 3
    fi
  done < <(jq -c '.[]' "$config_file")

  log_step "========================================"
  log_info "Batch run complete! All reports in:"
  log_info "  ./figma-design-qa-reports/"
  log_step "========================================"
}

# Usage/help
show_help() {
  cat <<EOF
Figma Design QA Delegator

Usage:
  $0 run  <site-url> <figma-url> [frame-width]
  $0 batch <config.json>

Examples:
  # Single run
  $0 run "https://dev.webnhubs.com/laura-couture/" \
         "https://www.figma.com/design/2ccVTVMYcSblKswGQ6oJO8/Lauras-Couture---Alterations-LLC--Final-File-?node-id=535-336" \
         1920

  # Batch run
  $0 batch ./qa-jobs.json

Config JSON format for batch:
  [
    {
      "siteUrl": "https://example.com",
      "figmaUrl": "https://figma.com/design/...",
      "frameWidth": 1920
    }
  ]
EOF
}

# Main dispatcher
case "$ACTION" in
  run)
    shift
    run_single "$@"
    ;;
  batch)
    shift
    run_batch "$@"
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    log_error "Unknown action: $ACTION"
    show_help
    exit 1
    ;;
esac

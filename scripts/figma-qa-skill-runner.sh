#!/usr/bin/env bash
#
# figma-qa-skill-runner.sh
#
# Wrapper around the figma-design-qa skill scripts (qa-collect.sh + qa-generate-report.js).
# This script delegates to the skill's official scripts located under:
#   .agents/skills/figma-design-qa/scripts/
#
# Usage:
#   Step 1 — Collect live-site data:
#     ./figma-qa-skill-runner.sh collect <site-url> [run-folder]
#
#   Step 2 — Generate report (after Figma data has been pulled):
#     ./figma-qa-skill-runner.sh report <run-folder>
#
#   Step 3 — Full pipeline (collect + report):
#     ./figma-qa-skill-runner.sh full <site-url> [run-folder]
#
# Arguments:
#   site-url    — Full URL of the live site to test
#   run-folder  — Name of the run folder under ./figma-design-qa-reports/
#                 (default: auto-generated from timestamp + hostname)
#
# Requires:
#   - Bash 4+
#   - agent-browser CLI on PATH
#   - node.js on PATH
#
# Author: Generated for figma-design-qa skill wrapper

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$PROJECT_ROOT/.agents/skills/figma-design-qa"
COLLECT_SCRIPT="$SKILL_DIR/scripts/qa-collect.sh"
REPORT_SCRIPT="$SKILL_DIR/scripts/qa-generate-report.js"
REPORTS_ROOT="$PROJECT_ROOT/figma-design-qa-reports"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

# ------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------
check_prerequisites() {
  log_step "Checking prerequisites..."

  if [[ ! -f "$COLLECT_SCRIPT" ]]; then
    log_error "Skill collect script not found: $COLLECT_SCRIPT"
    log_error "Ensure the figma-design-qa skill is installed under .agents/skills/"
    exit 1
  fi

  if [[ ! -f "$REPORT_SCRIPT" ]]; then
    log_error "Skill report script not found: $REPORT_SCRIPT"
    exit 1
  fi

  if ! command -v agent-browser &>/dev/null; then
    log_error "agent-browser is not installed or not on PATH."
    log_error "Install with: npm i -g agent-browser && agent-browser install"
    exit 1
  fi

  if ! command -v node &>/dev/null; then
    log_error "node.js is required but not installed."
    exit 1
  fi

  log_info "All prerequisites satisfied."
}

# ------------------------------------------------------------------
# Resolve run folder name
# ------------------------------------------------------------------
resolve_run_folder() {
  local site_url="${1:-}"
  local explicit_folder="${2:-}"

  if [[ -n "$explicit_folder" ]]; then
    echo "$explicit_folder"
    return
  fi

  local slug
  slug=$(echo "$site_url" | sed -E 's|https?://||' | sed -E 's|/.*||' | sed -E 's|[^a-zA-Z0-9._-]|_|g')
  local timestamp
  timestamp=$(date -u +"%Y-%m-%d_%H-%M")
  echo "${timestamp}_${slug}"
}

# ------------------------------------------------------------------
# Step 1 — Collect live-site data
# ------------------------------------------------------------------
run_collect() {
  local site_url="${1:?Usage: collect <site-url> [run-folder]}"
  local run_folder
  run_folder=$(resolve_run_folder "$site_url" "${2:-}")
  local output_dir="$REPORTS_ROOT/$run_folder"

  log_step "Step 1/2 — Collecting live-site data..."
  log_info "Site URL:     $site_url"
  log_info "Run folder:   $run_folder"
  log_info "Output dir:   $output_dir"

  mkdir -p "$output_dir"

  # The skill script expects: bash <script> <site-url> [output-directory]
  bash "$COLLECT_SCRIPT" "$site_url" "$output_dir"

  log_info "Collection complete. Data saved to: $output_dir/data/"
  log_info "Screenshots saved to: $output_dir/screenshots/"
}

# ------------------------------------------------------------------
# Step 2 — Generate report
# ------------------------------------------------------------------
run_report() {
  local run_folder="${1:?Usage: report <run-folder>}"
  local output_dir="$REPORTS_ROOT/$run_folder"

  log_step "Step 2/2 — Generating QA report..."
  log_info "Run folder:   $run_folder"
  log_info "Output dir:   $output_dir"

  if [[ ! -d "$output_dir/data" ]]; then
    log_error "No data directory found at $output_dir/data"
    log_error "Run 'collect' first or verify the run folder name."
    exit 1
  fi

  # The skill script expects: node <script> <collection-directory>
  node "$REPORT_SCRIPT" "$output_dir"

  log_info "Report generation complete."
  log_info "HTML report:  $output_dir/report.html"
  log_info "CSV report:   $output_dir/report.csv"
  if [[ -f "$output_dir/report.pdf" ]]; then
    log_info "PDF report:   $output_dir/report.pdf"
  fi
}

# ------------------------------------------------------------------
# Step 3 — Full pipeline
# ------------------------------------------------------------------
run_full() {
  local site_url="${1:?Usage: full <site-url> [run-folder]}"
  local run_folder
  run_folder=$(resolve_run_folder "$site_url" "${2:-}")

  run_collect "$site_url" "$run_folder"
  run_report "$run_folder"

  log_step "========================================"
  log_step "Full pipeline complete!"
  log_step "========================================"
  log_info "Artifacts location: $REPORTS_ROOT/$run_folder"
}

# ------------------------------------------------------------------
# Help
# ------------------------------------------------------------------
show_help() {
  cat <<EOF
Figma Design QA Skill Runner
==============================

This script wraps the official figma-design-qa skill scripts:
  Collect : $COLLECT_SCRIPT
  Report  : $REPORT_SCRIPT

Usage:
  $0 collect <site-url> [run-folder]
      → Collect live-site data (screenshots, JSON data, breakpoints)

  $0 report <run-folder>
      → Generate HTML/CSV/PDF report from previously collected data

  $0 full <site-url> [run-folder]
      → Run collect + report in one go

  $0 help
      → Show this help message

Examples:
  $0 collect https://example.com/my-site
  $0 collect https://example.com/my-site 2024-01-15_example.com
  $0 report 2024-01-15_example.com
  $0 full  https://example.com/my-site

EOF
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
main() {
  local cmd="${1:-help}"
  shift || true

  case "$cmd" in
    collect)
      check_prerequisites
      run_collect "$@"
      ;;
    report)
      check_prerequisites
      run_report "$@"
      ;;
    full)
      check_prerequisites
      run_full "$@"
      ;;
    help|--help|-h)
      show_help
      ;;
    *)
      log_error "Unknown command: $cmd"
      show_help
      exit 1
      ;;
  esac
}

main "$@"

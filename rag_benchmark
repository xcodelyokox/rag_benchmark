#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# rag_benchmark.sh - permissive-license RAG benchmark for OpenAI-compatible chat endpoints.
set -Eeuo pipefail

SCRIPT_NAME="rag_benchmark.sh"
VERSION="2026.05.12"

RAGBENCH_HOME="${RAGBENCH_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/rag_benchmark}"
VENV_DIR="${RAGBENCH_VENV_DIR:-$RAGBENCH_HOME/venv}"
INSTALL=1
FORCE_TUI=0
PLAIN=0
EXTRA_PIP=""
PY_ARGS=()
SHOW_BASH_HELP=0

is_tty() { [[ -t 1 ]]; }
has_tty_in() { [[ -e /dev/tty ]] && ( : < /dev/tty ) >/dev/null 2>&1 && ( : > /dev/tty ) >/dev/null 2>&1; }

ansi() {
  if [[ "$PLAIN" -eq 0 ]] && is_tty; then printf '\033[%sm' "$1"; fi
}
resetc() { ansi 0; }
bold() { ansi 1; }
dim() { ansi 2; }
cyan() { ansi 36; }
green() { ansi 32; }
yellow() { ansi 33; }
red() { ansi 31; }
blue() { ansi 34; }

say() { printf '%s\n' "$*"; }
say_tty() { if has_tty_in; then printf '%s\n' "$*" > /dev/tty; else printf '%s\n' "$*"; fi; }

usage() {
  cat <<'USAGE'
rag_benchmark.sh - permissive-license RAG benchmark for OpenAI-compatible chat endpoints

Common usage:
  ./rag_benchmark.sh --endpoint http://127.0.0.1:8000/v1 --model MODEL_ID --quick
  curl -fsSL https://raw.githubusercontent.com/user/rag_benchmark/main/rag_benchmark.sh | bash
  curl -fsSL https://raw.githubusercontent.com/user/rag_benchmark/main/rag_benchmark.sh | bash -s -- --endpoint http://127.0.0.1:8000/v1 --model MODEL_ID

When run with no arguments from a terminal, the script launches an interactive TUI wizard.
The wizard works even when the script itself is piped through stdin, because prompts read from /dev/tty.

Bootstrap options handled by Bash:
  --tui                    Force the interactive terminal wizard.
  --no-install             Do not create/use a virtualenv or install packages.
  --venv-dir DIR           Virtualenv directory. Default: $RAGBENCH_HOME/venv
  --state-dir DIR          Cache/venv root. Useful for CI tests. Default: ~/.cache/rag_benchmark
  --extra-pip "PKGS"       Extra packages appended to pip install.
  --plain                  Disable colors and live terminal styling.
  -h, --help               Show this help.

Benchmark options passed to Python:
  --endpoint URL           OpenAI-compatible base URL, with or without /v1.
  --model ID               Model id. If omitted, GET /v1/models is used when available.
  --api-key KEY            Bearer token. Default: OPENAI_API_KEY, or EMPTY.
  --quick                  Small smoke profile.
  --db-sizes LIST          Comma-separated vector DB sizes, e.g. 10000,50000,100000.
  --rag-workers N          Concurrent RAG workers. Default: min(cpu_count, 8).
  --rag-runs N             Repeated concurrent RAG runs.
  --rag-queries-per-worker N
  --output FILE            JSON result path.
  --cache-dir DIR          Corpus and embedding cache dir.
  --corpus synthetic       Default. Locally generated MIT-compatible synthetic fixture.
  --corpus local-jsonl     User-provided JSONL corpus; requires --corpus-license.
  --corpus-file FILE       JSONL path when --corpus local-jsonl.
  --corpus-license SPDX    Required for local-jsonl. Must be permissive.
  --license-audit          Print dependency/corpus license posture and exit.
  --self-test              Run against a local mock OpenAI-compatible endpoint.

Environment shortcuts:
  RAG_ENDPOINT             Used as --endpoint when no endpoint argument is supplied.
  RAG_MODEL                Used as --model when no model argument is supplied.
  OPENAI_API_KEY           Used as bearer token unless --api-key is supplied.
  RAGBENCH_HOME            Cache root for curl|bash runs. Default: ~/.cache/rag_benchmark

Direct benchmark Python packages installed by default:
  bootstrap tools: pip, setuptools, wheel
  runtime packages: numpy, faiss-cpu
USAGE
}

has_arg() {
  local needle="$1"; shift || true
  local x
  for x in "$@"; do
    if [[ "$x" == "$needle" || "$x" == "$needle="* ]]; then return 0; fi
  done
  return 1
}

has_endpoint_arg() {
  local prev="" x
  for x in "$@"; do
    if [[ "$prev" == "--endpoint" ]]; then return 0; fi
    if [[ "$x" == --endpoint=* ]]; then return 0; fi
    if [[ "$x" == http://* || "$x" == https://* ]]; then return 0; fi
    prev="$x"
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tui)
      FORCE_TUI=1
      shift
      ;;
    --no-install)
      INSTALL=0
      shift
      ;;
    --venv-dir)
      if [[ $# -lt 2 ]]; then echo "Missing value for --venv-dir" >&2; exit 2; fi
      VENV_DIR="$2"
      shift 2
      ;;
    --state-dir)
      if [[ $# -lt 2 ]]; then echo "Missing value for --state-dir" >&2; exit 2; fi
      RAGBENCH_HOME="$2"
      VENV_DIR="${RAGBENCH_VENV_DIR:-$RAGBENCH_HOME/venv}"
      shift 2
      ;;
    --extra-pip)
      if [[ $# -lt 2 ]]; then echo "Missing value for --extra-pip" >&2; exit 2; fi
      EXTRA_PIP="$2"
      shift 2
      ;;
    --plain)
      PLAIN=1
      PY_ARGS+=("--plain")
      shift
      ;;
    -h|--help)
      SHOW_BASH_HELP=1
      shift
      ;;
    *)
      PY_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ "$SHOW_BASH_HELP" -eq 1 ]]; then
  usage
  exit 0
fi

clear_tty() {
  if [[ "$PLAIN" -eq 0 ]] && has_tty_in; then printf '\033[2J\033[H' > /dev/tty; fi
}

box_line() {
  local width="$1" char="$2"
  printf '+%*s+\n' "$((width - 2))" '' | tr ' ' "$char"
}

center_text() {
  local text="$1" width="$2" pad left right
  if (( ${#text} >= width - 2 )); then printf '| %s |\n' "${text:0:$((width-4))}"; return; fi
  pad=$((width - 2 - ${#text}))
  left=$((pad / 2))
  right=$((pad - left))
  printf '|%*s%s%*s|\n' "$left" '' "$text" "$right" ''
}

prompt_tty() {
  local label="$1" default="${2:-}" value
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$label" "$default" > /dev/tty
  else
    printf '%s: ' "$label" > /dev/tty
  fi
  IFS= read -r value < /dev/tty || value=""
  if [[ -z "$value" ]]; then value="$default"; fi
  printf '%s' "$value"
}

prompt_secret_tty() {
  local label="$1" value
  printf '%s: ' "$label" > /dev/tty
  IFS= read -rs value < /dev/tty || value=""
  printf '\n' > /dev/tty
  printf '%s' "$value"
}

pause_tty() {
  printf '\nPress Enter to continue...' > /dev/tty
  IFS= read -r _ < /dev/tty || true
}

render_tui() {
  local endpoint="${RAG_ENDPOINT:-${OPENAI_BASE_URL:-}}"
  local model="${RAG_MODEL:-${OPENAI_MODEL:-}}"
  local api_mode="env"
  local profile="quick"
  local db_sizes="10000"
  local batch_queries="300"
  local runs="3"
  local rag_workers="2"
  local rag_runs="2"
  local rag_qpw="5"
  local rag_db_size="5000"
  local top_k="5"
  local max_tokens="80"
  local context_chars="1200"
  local request_timeout="120"
  local temperature="0"
  local stream_mode="yes"
  local corpus="synthetic"
  local corpus_file=""
  local corpus_license=""
  local output="./rag_benchmark_result_$(date +%Y%m%d_%H%M%S).json"
  local index_backend="auto"
  local cache_dir="$RAGBENCH_HOME/cache"
  local choice secret install_label plain_label profile_label

  if ! has_tty_in; then
    say "No interactive terminal is available for the TUI."
    say "Provide --endpoint, or set RAG_ENDPOINT, e.g.:"
    say "  curl -fsSL URL | RAG_ENDPOINT=http://127.0.0.1:8000/v1 RAG_MODEL=my-model bash"
    exit 2
  fi

  while true; do
    case "$profile" in
      quick) profile_label="quick smoke" ;;
      standard) profile_label="standard" ;;
      custom) profile_label="custom" ;;
      *) profile_label="$profile" ;;
    esac
    if [[ "$INSTALL" -eq 1 ]]; then install_label="venv install on"; else install_label="no install"; fi
    if [[ "$PLAIN" -eq 1 ]]; then plain_label="plain output"; else plain_label="styled TUI"; fi

    clear_tty
    { cyan; box_line 78 '='; center_text "RAG BENCHMARK LAUNCHER" 78; center_text "OpenAI-compatible endpoint + local permissive RAG corpus" 78; box_line 78 '='; resetc; } > /dev/tty
    printf '\n' > /dev/tty
    printf '  %-2s %-22s %s\n' '1)' 'Endpoint URL' "${endpoint:-<required>}" > /dev/tty
    printf '  %-2s %-22s %s\n' '2)' 'Model ID' "${model:-<auto-detect from /v1/models>}" > /dev/tty
    printf '  %-2s %-22s %s\n' '3)' 'API key' "$api_mode" > /dev/tty
    printf '  %-2s %-22s %s\n' '4)' 'Run profile' "$profile_label" > /dev/tty
    printf '  %-2s %-22s %s\n' '5)' 'Vector DB sizes' "$db_sizes" > /dev/tty
    printf '  %-2s %-22s batch=%s runs=%s top_k=%s\n' '6)' 'Search settings' "$batch_queries" "$runs" "$top_k" > /dev/tty
    printf '  %-2s %-22s workers=%s runs=%s q/worker=%s rag_db=%s\n' '7)' 'Concurrent RAG' "$rag_workers" "$rag_runs" "$rag_qpw" "$rag_db_size" > /dev/tty
    printf '  %-2s %-22s %s%s\n' '8)' 'Corpus' "$corpus" "${corpus_file:+ file=$corpus_file license=$corpus_license}" > /dev/tty
    printf '  %-2s %-22s %s\n' '9)' 'Output JSON' "$output" > /dev/tty
    printf '  %-2s %-22s backend=%s max_tokens=%s stream=%s\n' '10)' 'Advanced' "$index_backend" "$max_tokens" "$stream_mode" > /dev/tty
    printf '  %-2s %-22s %s, %s\n' '11)' 'Runtime' "$install_label" "$plain_label" > /dev/tty
    printf '  %-2s %-22s %s\n' 'L)' 'License audit' 'show permissive dependency/corpus posture' > /dev/tty
    printf '  %-2s %-22s %s\n' 'T)' 'Self-test' 'run local mock OpenAI-compatible endpoint' > /dev/tty
    printf '  %-2s %-22s %s\n' 'S)' 'Start benchmark' 'run now' > /dev/tty
    printf '  %-2s %-22s %s\n' 'Q)' 'Quit' 'exit without running' > /dev/tty
    printf '\nChoose an option: ' > /dev/tty
    IFS= read -r choice < /dev/tty || choice=""
    case "${choice,,}" in
      1)
        endpoint="$(prompt_tty 'OpenAI-compatible endpoint URL' "$endpoint")"
        ;;
      2)
        model="$(prompt_tty 'Model ID (blank = auto-detect)' "$model")"
        ;;
      3)
        clear_tty
        say_tty "API key mode:"
        say_tty "  1) Use OPENAI_API_KEY from environment (default)"
        say_tty "  2) Send EMPTY token"
        say_tty "  3) Type/paste key now (hidden; exported only for this run)"
        printf 'Choice: ' > /dev/tty
        IFS= read -r choice < /dev/tty || choice=""
        case "$choice" in
          2) api_mode="empty"; export OPENAI_API_KEY="EMPTY" ;;
          3) secret="$(prompt_secret_tty 'API key')"; export OPENAI_API_KEY="$secret"; api_mode="prompted" ;;
          *) api_mode="env" ;;
        esac
        ;;
      4)
        clear_tty
        say_tty "Profiles:"
        say_tty "  1) quick    - smoke test, low cost"
        say_tty "  2) standard - broader local retrieval benchmark"
        say_tty "  3) custom   - keep current values and edit manually"
        printf 'Choice: ' > /dev/tty
        IFS= read -r choice < /dev/tty || choice=""
        case "$choice" in
          2) profile="standard"; db_sizes="50000,100000"; batch_queries="1000"; runs="5"; rag_workers="4"; rag_runs="3"; rag_qpw="10"; rag_db_size="10000"; top_k="10" ;;
          3) profile="custom" ;;
          *) profile="quick"; db_sizes="10000"; batch_queries="300"; runs="3"; rag_workers="2"; rag_runs="2"; rag_qpw="5"; rag_db_size="5000"; top_k="5" ;;
        esac
        ;;
      5)
        profile="custom"
        db_sizes="$(prompt_tty 'Comma-separated DB sizes' "$db_sizes")"
        ;;
      6)
        profile="custom"
        batch_queries="$(prompt_tty 'Batch vector-search queries per run' "$batch_queries")"
        runs="$(prompt_tty 'Repeated runs' "$runs")"
        top_k="$(prompt_tty 'Top-k retrieval' "$top_k")"
        ;;
      7)
        profile="custom"
        rag_workers="$(prompt_tty 'Concurrent RAG workers' "$rag_workers")"
        rag_runs="$(prompt_tty 'RAG repeated runs' "$rag_runs")"
        rag_qpw="$(prompt_tty 'RAG queries per worker per run' "$rag_qpw")"
        rag_db_size="$(prompt_tty 'RAG DB size' "$rag_db_size")"
        ;;
      8)
        clear_tty
        say_tty "Corpus options:"
        say_tty "  1) synthetic   - generated locally, no third-party source text (default)"
        say_tty "  2) local-jsonl - your own JSONL with a permissive SPDX license declaration"
        printf 'Choice: ' > /dev/tty
        IFS= read -r choice < /dev/tty || choice=""
        case "$choice" in
          2)
            corpus="local-jsonl"
            corpus_file="$(prompt_tty 'JSONL corpus file path' "$corpus_file")"
            corpus_license="$(prompt_tty 'Corpus SPDX license (MIT/Apache-2.0/BSD-3-Clause/CC0-1.0/etc.)' "$corpus_license")"
            ;;
          *) corpus="synthetic"; corpus_file=""; corpus_license="" ;;
        esac
        ;;
      9)
        output="$(prompt_tty 'Output JSON path' "$output")"
        ;;
      10)
        index_backend="$(prompt_tty 'Index backend (auto/faiss/numpy)' "$index_backend")"
        max_tokens="$(prompt_tty 'Max generation tokens per request' "$max_tokens")"
        context_chars="$(prompt_tty 'Context characters per request' "$context_chars")"
        temperature="$(prompt_tty 'Temperature' "$temperature")"
        request_timeout="$(prompt_tty 'Request timeout seconds' "$request_timeout")"
        stream_mode="$(prompt_tty 'Use streaming for TTFT? (yes/no)' "$stream_mode")"
        cache_dir="$(prompt_tty 'Cache directory' "$cache_dir")"
        ;;
      11)
        clear_tty
        say_tty "Runtime options:"
        say_tty "  1) Use/create venv and install numpy faiss-cpu"
        say_tty "  2) No install; use current Python environment"
        printf 'Choice: ' > /dev/tty
        IFS= read -r choice < /dev/tty || choice=""
        case "$choice" in 2) INSTALL=0 ;; *) INSTALL=1 ;; esac
        clear_tty
        say_tty "Terminal style:"
        say_tty "  1) Styled TUI output"
        say_tty "  2) Plain CI-safe output"
        printf 'Choice: ' > /dev/tty
        IFS= read -r choice < /dev/tty || choice=""
        case "$choice" in 2) PLAIN=1 ;; *) PLAIN=0 ;; esac
        ;;
      l)
        PY_ARGS=("--license-audit")
        if [[ "$PLAIN" -eq 1 ]]; then PY_ARGS+=("--plain"); fi
        return
        ;;
      t)
        PY_ARGS=("--self-test" "--output" "./rag_benchmark_selftest_result_$(date +%Y%m%d_%H%M%S).json" "--cache-dir" "$cache_dir" "--index-backend" "$index_backend")
        if [[ "$PLAIN" -eq 1 ]]; then PY_ARGS+=("--plain"); fi
        return
        ;;
      s)
        if [[ -z "$endpoint" ]]; then
          red > /dev/tty; say_tty "Endpoint URL is required."; resetc > /dev/tty; pause_tty
          continue
        fi
        PY_ARGS=("--endpoint" "$endpoint" "--output" "$output" "--cache-dir" "$cache_dir" "--db-sizes" "$db_sizes" "--batch-queries" "$batch_queries" "--runs" "$runs" "--top-k" "$top_k" "--rag-workers" "$rag_workers" "--rag-runs" "$rag_runs" "--rag-queries-per-worker" "$rag_qpw" "--rag-db-size" "$rag_db_size" "--corpus" "$corpus" "--index-backend" "$index_backend" "--max-tokens" "$max_tokens" "--context-chars" "$context_chars" "--temperature" "$temperature" "--request-timeout" "$request_timeout")
        case "${stream_mode,,}" in n|no|false|0) PY_ARGS+=("--no-stream") ;; esac
        if [[ -n "$model" ]]; then PY_ARGS+=("--model" "$model"); fi
        if [[ "$profile" == "quick" ]]; then PY_ARGS+=("--quick"); fi
        if [[ "$corpus" == "local-jsonl" ]]; then PY_ARGS+=("--corpus-file" "$corpus_file" "--corpus-license" "$corpus_license"); fi
        if [[ "$PLAIN" -eq 1 ]]; then PY_ARGS+=("--plain"); fi
        return
        ;;
      q)
        exit 0
        ;;
      *) ;;
    esac
  done
}

# If the user supplies no endpoint/model args, curl|bash should still be a complete experience.
if [[ "$FORCE_TUI" -eq 1 ]] || { ! has_endpoint_arg "${PY_ARGS[@]}" && ! has_arg "--self-test" "${PY_ARGS[@]}" && ! has_arg "--license-audit" "${PY_ARGS[@]}"; }; then
  if [[ "$FORCE_TUI" -eq 1 ]]; then
    render_tui
  elif [[ -n "${RAG_ENDPOINT:-}" ]]; then
    PY_ARGS=("--endpoint" "$RAG_ENDPOINT" "${PY_ARGS[@]}")
    if [[ -n "${RAG_MODEL:-}" ]] && ! has_arg "--model" "${PY_ARGS[@]}"; then PY_ARGS+=("--model" "$RAG_MODEL"); fi
  elif [[ ${#PY_ARGS[@]} -eq 0 ]]; then
    render_tui
  elif has_tty_in; then
    render_tui
  else
    usage >&2
    exit 2
  fi
fi

if [[ -n "${RAG_MODEL:-}" ]] && ! has_arg "--model" "${PY_ARGS[@]}"; then
  PY_ARGS+=("--model" "$RAG_MODEL")
fi
if [[ "$PLAIN" -eq 1 ]] && ! has_arg "--plain" "${PY_ARGS[@]}"; then
  PY_ARGS+=("--plain")
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required. In WSL2, install it with:" >&2
  echo "  sudo apt update && sudo apt install -y python3 python3-venv python3-pip" >&2
  exit 1
fi
SYSTEM_PYTHON="$(command -v python3)"

# License audit and help-like metadata can run without installing benchmark packages.
SKIP_INSTALL=0
if has_arg "--license-audit" "${PY_ARGS[@]}"; then SKIP_INSTALL=1; fi

PYTHON_BIN="python3"
if [[ "$INSTALL" -eq 1 && "$SKIP_INSTALL" -eq 0 ]]; then
  mkdir -p "$RAGBENCH_HOME"
  if [[ ! -d "$VENV_DIR" ]]; then
    bold; say "Creating Python virtualenv: $VENV_DIR"; resetc
    if ! python3 -m venv "$VENV_DIR"; then
      echo "Could not create virtualenv. On WSL2/Ubuntu, install:" >&2
      echo "  sudo apt update && sudo apt install -y python3-venv python3-pip" >&2
      exit 1
    fi
  fi
  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"
  PYTHON_BIN="python"
  bold; say "Installing/updating permissive benchmark packages in $VENV_DIR"; resetc
  PIP_TIMEOUT="${RAGBENCH_PIP_TIMEOUT:-20}"
  PIP_RETRIES="${RAGBENCH_PIP_RETRIES:-1}"
  PIP_INSTALL=("$PYTHON_BIN" -m pip --disable-pip-version-check --no-input --timeout "$PIP_TIMEOUT" --retries "$PIP_RETRIES" install --upgrade)

  if ! "${PIP_INSTALL[@]}" pip setuptools wheel; then
    echo "warning: pip bootstrap upgrade failed; continuing with the existing pip tooling." >&2
  fi

  if ! "$PYTHON_BIN" - <<'PY_CHECK_NUMPY' >/dev/null 2>&1
import numpy
PY_CHECK_NUMPY
  then
    if ! "${PIP_INSTALL[@]}" numpy; then
      echo "warning: numpy installation failed inside the venv." >&2
    fi
  fi

  if ! "$PYTHON_BIN" - <<'PY_CHECK_NUMPY2' >/dev/null 2>&1
import numpy
PY_CHECK_NUMPY2
  then
    if "$SYSTEM_PYTHON" - <<'PY_CHECK_SYS_NUMPY' >/dev/null 2>&1
import numpy
PY_CHECK_SYS_NUMPY
    then
      echo "warning: using system python because numpy is unavailable in the venv." >&2
      deactivate >/dev/null 2>&1 || true
      PYTHON_BIN="$SYSTEM_PYTHON"
    else
      echo "numpy is required and could not be imported or installed." >&2
      echo "Install it manually, or re-run with network access: python3 -m pip install numpy" >&2
      exit 1
    fi
  fi

  # FAISS is MIT licensed and enables the HNSW build/search path. If it cannot be
  # installed, the Python runner falls back to an exact NumPy index unless
  # --index-backend faiss is explicitly requested.
  if ! "$PYTHON_BIN" - <<'PY_CHECK_FAISS' >/dev/null 2>&1
import faiss
PY_CHECK_FAISS
  then
    if ! "${PIP_INSTALL[@]}" faiss-cpu; then
      echo "warning: faiss-cpu installation failed; NumPy fallback will be used unless --index-backend faiss is requested." >&2
    fi
  fi

  if [[ -n "$EXTRA_PIP" ]]; then
    # shellcheck disable=SC2206
    EXTRA_PKGS=( $EXTRA_PIP )
    "${PIP_INSTALL[@]}" "${EXTRA_PKGS[@]}"
  fi
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rag-benchmark.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
RUNNER="$WORK_DIR/runner.py"

cat > "$RUNNER" <<'PYTHON'
from __future__ import annotations

import argparse
import concurrent.futures
import datetime as _dt
import gc
import hashlib
import http.server
import json
import math
import os
import platform
import random
import re
import socket
import socketserver
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import Request, urlopen

VERSION = "2026.05.12"
DIRECT_LICENSES = [
    {"component": "rag_benchmark.sh", "license": "MIT", "role": "script", "source": "this file"},
    {"component": "synthetic RAG corpus", "license": "MIT-compatible generated fixture", "role": "default corpus", "source": "generated locally; no third-party source text"},
    {"component": "Python", "license": "PSF-2.0", "role": "runtime", "source": "system/venv interpreter"},
    {"component": "pip", "license": "MIT", "role": "package installer bootstrap", "source": "pip package pip"},
    {"component": "setuptools", "license": "MIT", "role": "package build/install bootstrap", "source": "pip package setuptools"},
    {"component": "wheel", "license": "MIT", "role": "package wheel support bootstrap", "source": "pip package wheel"},
    {"component": "NumPy", "license": "BSD-3-Clause", "role": "array math", "source": "pip package numpy"},
    {"component": "FAISS / faiss-cpu", "license": "MIT", "role": "HNSW vector index", "source": "pip package faiss-cpu"},
    {"component": "OpenBLAS", "license": "BSD-3-Clause", "role": "BLAS backend where bundled by Linux wheels", "source": "NumPy/faiss-cpu wheel dependency path"},
]
PERMISSIVE_LICENSES = {
    "MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC", "0BSD", "Zlib",
    "Unlicense", "CC0-1.0", "Public-Domain", "CC-BY-3.0", "CC-BY-4.0", "PSF-2.0",
}
LICENSE_ALIASES = {
    "apache2": "Apache-2.0", "apache-2": "Apache-2.0", "apache 2": "Apache-2.0", "apache 2.0": "Apache-2.0",
    "bsd3": "BSD-3-Clause", "bsd-3": "BSD-3-Clause", "bsd 3": "BSD-3-Clause", "bsd-3-clause": "BSD-3-Clause",
    "bsd2": "BSD-2-Clause", "bsd-2": "BSD-2-Clause", "bsd 2": "BSD-2-Clause", "bsd-2-clause": "BSD-2-Clause",
    "public domain": "Public-Domain", "pd": "Public-Domain", "cc0": "CC0-1.0", "cc-by-4": "CC-BY-4.0",
}


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Run a RAG benchmark against an OpenAI-compatible /v1/chat/completions endpoint.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("endpoint_pos", nargs="?", help="Endpoint URL, with or without /v1.")
    p.add_argument("--endpoint", help="Endpoint URL, with or without /v1.")
    p.add_argument("--api-key", default=os.environ.get("OPENAI_API_KEY", "EMPTY"), help="Bearer token sent to the endpoint.")
    p.add_argument("--model", default=None, help="Model id. If omitted, tries GET /v1/models and uses the first id.")
    p.add_argument("--output", default=None, help="JSON output file path.")
    p.add_argument("--cache-dir", default=str(Path.home() / ".cache" / "rag_benchmark" / "cache"), help="Cache directory for embeddings.")

    p.add_argument("--corpus", choices=["synthetic", "local-jsonl"], default="synthetic", help="Corpus source. Default avoids third-party database text.")
    p.add_argument("--corpus-file", default=None, help="JSONL file for --corpus local-jsonl. Each line should contain a text field.")
    p.add_argument("--corpus-license", default=None, help="SPDX license for local-jsonl corpus. Must be permissive.")
    p.add_argument("--jsonl-text-key", default="text", help="Text field name for local-jsonl corpus.")
    p.add_argument("--refresh-embeddings", action="store_true", help="Ignore cached local embeddings and rebuild them.")
    p.add_argument("--embedding-dim", type=int, default=384, help="Dimension for the built-in hashing-vectorizer embeddings.")

    p.add_argument("--db-sizes", default="100000,200000", help="Comma-separated vector database sizes.")
    p.add_argument("--batch-queries", type=int, default=3000, help="Queries per vector-search run.")
    p.add_argument("--runs", type=int, default=10, help="Runs for vector search and index build.")
    p.add_argument("--trim", type=float, default=0.05, help="Fraction trimmed from each side when averaging repeated runs.")
    p.add_argument("--top-k", type=int, default=10, help="Retrieved passages per RAG request.")
    p.add_argument("--hnsw-m", type=int, default=32, help="FAISS HNSW M parameter.")
    p.add_argument("--hnsw-ef", type=int, default=64, help="HNSW efSearch parameter.")
    p.add_argument("--hnsw-ef-construction", type=int, default=200, help="HNSW efConstruction parameter.")
    p.add_argument("--index-backend", choices=["auto", "faiss", "numpy"], default="auto", help="Vector index backend. Use faiss for full HNSW results.")
    p.add_argument("--threads", type=int, default=0, help="FAISS OMP threads. Default uses cpu_count.")

    p.add_argument("--rag-workers", type=int, default=0, help="Concurrent RAG workers. Default min(cpu_count, 8).")
    p.add_argument("--rag-runs", type=int, default=5, help="Concurrent RAG repeated runs.")
    p.add_argument("--rag-queries-per-worker", type=int, default=20, help="RAG requests per worker per run.")
    p.add_argument("--rag-db-size", type=int, default=10000, help="Per-worker RAG index size.")
    p.add_argument("--context-chars", type=int, default=1200, help="Maximum context characters placed in each prompt.")
    p.add_argument("--max-tokens", type=int, default=80, help="Max generation tokens for chat completions.")
    p.add_argument("--temperature", type=float, default=0.0, help="Chat completion temperature.")
    p.add_argument("--request-timeout", type=float, default=120.0, help="Per-request timeout seconds.")
    p.add_argument("--connect-timeout", type=float, default=10.0, help="HTTP connect/probe timeout seconds.")
    p.add_argument("--cooldown", type=float, default=2.0, help="Sleep between repeated benchmark runs.")
    p.add_argument("--no-stream", action="store_true", help="Use non-streaming chat completions. TTFT becomes total latency.")
    p.add_argument("--disable-nonstream-fallback", action="store_true", help="Fail if streaming fails instead of retrying non-streaming.")
    p.add_argument("--fail-on-endpoint-error", action="store_true", help="Abort on any RAG request failure.")

    p.add_argument("--skip-search", action="store_true", help="Skip batch vector-search benchmark.")
    p.add_argument("--skip-build", action="store_true", help="Skip HNSW index-build benchmark.")
    p.add_argument("--skip-rag", action="store_true", help="Skip concurrent RAG benchmark.")
    p.add_argument("--quick", action="store_true", help="Use smaller sizes and fewer runs for a smoke benchmark.")
    p.add_argument("--self-test", action="store_true", help="Run a tiny benchmark against a local mock endpoint.")
    p.add_argument("--license-audit", action="store_true", help="Print license posture and exit.")
    p.add_argument("--plain", action="store_true", help="Disable ANSI styling/live updates.")
    args = p.parse_args(argv)
    return args


class UI:
    def __init__(self, plain: bool = False) -> None:
        self.plain = plain or not sys.stdout.isatty()
        self.last_progress_len = 0

    def c(self, code: str, s: str) -> str:
        return s if self.plain else f"\033[{code}m{s}\033[0m"

    def bold(self, s: str) -> str:
        return self.c("1", s)

    def dim(self, s: str) -> str:
        return self.c("2", s)

    def green(self, s: str) -> str:
        return self.c("32", s)

    def yellow(self, s: str) -> str:
        return self.c("33", s)

    def red(self, s: str) -> str:
        return self.c("31", s)

    def cyan(self, s: str) -> str:
        return self.c("36", s)

    def blue(self, s: str) -> str:
        return self.c("34", s)

    def print(self, s: str = "") -> None:
        print(s, flush=True)

    def rule(self, title: str = "") -> None:
        width = 88
        if title:
            label = f" {title} "
            left = max(0, (width - len(label)) // 2)
            right = max(0, width - len(label) - left)
            self.print(self.cyan("=" * left + label + "=" * right))
        else:
            self.print(self.cyan("=" * width))

    def box(self, title: str, lines: Sequence[str]) -> None:
        width = 88
        self.print(self.cyan("+" + "=" * (width - 2) + "+"))
        t = f" {title} "
        pad = max(0, width - 2 - len(t))
        self.print(self.cyan("|") + self.bold(t + " " * pad) + self.cyan("|"))
        self.print(self.cyan("+" + "-" * (width - 2) + "+"))
        for line in lines:
            raw = strip_ansi(line)
            if len(raw) > width - 4:
                line = raw[: width - 7] + "..."
                raw = line
            self.print(self.cyan("|") + " " + line + " " * max(0, width - 3 - len(raw)) + self.cyan("|"))
        self.print(self.cyan("+" + "=" * (width - 2) + "+"))

    def table(self, title: str, headers: Sequence[str], rows: Sequence[Sequence[Any]]) -> None:
        self.rule(title)
        text_rows = [[str(x) for x in row] for row in rows]
        widths = [len(str(h)) for h in headers]
        for row in text_rows:
            for i, cell in enumerate(row):
                widths[i] = max(widths[i], len(strip_ansi(cell)))
        fmt = "  ".join("{:<" + str(w) + "}" for w in widths)
        self.print(self.bold(fmt.format(*headers)))
        self.print("  ".join("-" * w for w in widths))
        for row in text_rows:
            padded = []
            for i, cell in enumerate(row):
                padded.append(cell + " " * max(0, widths[i] - len(strip_ansi(cell))))
            self.print("  ".join(padded))
        self.print()

    def progress(self, label: str, current: int, total: int) -> None:
        if self.plain:
            if current == total or current == 1 or current % max(1, total // 10) == 0:
                self.print(f"{label}: {current}/{total}")
            return
        width = 28
        frac = current / total if total else 1.0
        filled = min(width, int(width * frac))
        bar = "#" * filled + "." * (width - filled)
        msg = f"\r\033[K{label} [{bar}] {current}/{total} {frac*100:5.1f}%"
        print(self.c("36", msg), end="", flush=True)
        if current >= total:
            print(flush=True)

    def status(self, msg: str) -> None:
        if self.plain:
            self.print(msg)
        else:
            print(self.c("36", "\r\033[K" + msg), end="", flush=True)

    def end_status(self) -> None:
        if not self.plain:
            print("\r\033[K", end="", flush=True)


def strip_ansi(s: str) -> str:
    return re.sub(r"\x1b\[[0-9;]*m", "", str(s))


def now_utc_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat()


def parse_db_sizes(raw: str) -> List[int]:
    sizes: List[int] = []
    for part in raw.split(","):
        part = part.strip().replace("_", "")
        if not part:
            continue
        value = int(part)
        if value <= 0:
            raise ValueError("db sizes must be positive")
        sizes.append(value)
    if not sizes:
        raise ValueError("no db sizes provided")
    return sorted(set(sizes))


def apply_quick_defaults(args: argparse.Namespace) -> None:
    if not args.quick:
        return
    args.db_sizes = "10000"
    args.batch_queries = min(args.batch_queries, 300)
    args.runs = min(args.runs, 3)
    args.rag_runs = min(args.rag_runs, 2)
    args.rag_queries_per_worker = min(args.rag_queries_per_worker, 5)
    if args.rag_workers == 0:
        args.rag_workers = 2
    else:
        args.rag_workers = min(args.rag_workers, 2)
    args.rag_db_size = min(args.rag_db_size, 5000)
    args.cooldown = min(args.cooldown, 0.5)
    args.context_chars = min(args.context_chars, 800)


def normalize_endpoint(url: str) -> str:
    url = (url or "").strip()
    if not url:
        raise ValueError("empty endpoint URL")
    if "://" not in url:
        url = "http://" + url
    parts = urlsplit(url)
    if not parts.netloc:
        raise ValueError(f"invalid endpoint URL: {url}")
    path = parts.path.rstrip("/")
    if re.search(r"(^|/)v1$", path):
        new_path = path
    elif "/v1/" in path + "/":
        new_path = path[: path.index("/v1") + 3]
    else:
        new_path = path + "/v1"
    return urlunsplit((parts.scheme, parts.netloc, new_path, "", ""))


def chat_url(base: str) -> str:
    return base.rstrip("/") + "/chat/completions"


def models_url(base: str) -> str:
    return base.rstrip("/") + "/models"


def import_numpy():
    try:
        import numpy as np  # type: ignore
    except Exception as exc:
        raise SystemExit("Missing numpy. Re-run without --no-install, or install: pip install numpy") from exc
    return np


def faiss_available() -> bool:
    try:
        import faiss  # noqa: F401
        return True
    except Exception:
        return False


def choose_backend(requested: str) -> str:
    if requested == "numpy":
        return "numpy"
    if requested == "faiss":
        if not faiss_available():
            raise SystemExit("FAISS is required for --index-backend faiss. Install with: pip install faiss-cpu")
        return "faiss"
    return "faiss" if faiss_available() else "numpy"


def cmd_output(cmd: List[str], timeout: float = 5.0) -> str:
    try:
        return subprocess.check_output(cmd, stderr=subprocess.DEVNULL, text=True, timeout=timeout).strip()
    except Exception:
        return ""


def is_wsl() -> bool:
    texts = [platform.release(), platform.version()]
    try:
        texts.append(Path("/proc/version").read_text(errors="ignore"))
    except Exception:
        pass
    blob = " ".join(texts).lower()
    return "microsoft" in blob or "wsl" in blob


def cpu_model() -> str:
    if Path("/proc/cpuinfo").exists():
        try:
            for line in Path("/proc/cpuinfo").read_text(errors="ignore").splitlines():
                if line.lower().startswith("model name"):
                    return line.split(":", 1)[1].strip()
        except Exception:
            pass
    out = cmd_output(["lscpu"])
    for line in out.splitlines():
        if line.startswith("Model name:"):
            return line.split(":", 1)[1].strip()
    return platform.processor() or "unknown"


def memory_gb() -> float:
    try:
        for line in Path("/proc/meminfo").read_text(errors="ignore").splitlines():
            if line.startswith("MemTotal:"):
                kb = float(line.split()[1])
                return round(kb / 1024.0 / 1024.0, 2)
    except Exception:
        pass
    return 0.0


def l3_cache() -> str:
    out = cmd_output(["lscpu"])
    for line in out.splitlines():
        if "L3 cache" in line:
            return line.split(":", 1)[1].strip()
    return "unknown"


def system_info() -> Dict[str, Any]:
    return {
        "utc_time": now_utc_iso(),
        "platform": platform.platform(),
        "python": sys.version.split()[0],
        "cpu_model": cpu_model(),
        "cpu_count": os.cpu_count() or 1,
        "memory_gb": memory_gb(),
        "l3_cache": l3_cache(),
        "is_wsl": is_wsl(),
    }


def trimmed(values: Sequence[float], trim: float) -> List[float]:
    if not values:
        return []
    arr = sorted(float(v) for v in values)
    cut = int(len(arr) * trim)
    if cut > 0 and len(arr) > 2 * cut:
        return arr[cut:-cut]
    return arr


def mean(values: Sequence[float]) -> float:
    return float(sum(values) / len(values)) if values else 0.0


def stddev(values: Sequence[float]) -> float:
    if not values:
        return 0.0
    m = mean(values)
    return math.sqrt(sum((float(v) - m) ** 2 for v in values) / len(values))


def percentile(values: Sequence[float], p: float) -> float:
    if not values:
        return 0.0
    arr = sorted(float(v) for v in values)
    if len(arr) == 1:
        return arr[0]
    pos = (len(arr) - 1) * (p / 100.0)
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return arr[lo]
    return arr[lo] * (hi - pos) + arr[hi] * (pos - lo)


def summarize_seconds(values: Sequence[float], trim: float = 0.0) -> Dict[str, float]:
    vals = list(values)
    tv = trimmed(vals, trim)
    avg = mean(tv)
    sd = stddev(tv)
    return {
        "count": len(vals),
        "mean_ms": round(avg * 1000.0, 3),
        "stddev_ms": round(sd * 1000.0, 3),
        "p50_ms": round(percentile(vals, 50) * 1000.0, 3),
        "p95_ms": round(percentile(vals, 95) * 1000.0, 3),
        "p99_ms": round(percentile(vals, 99) * 1000.0, 3),
    }


def summarize_rate(values: Sequence[float], trim: float) -> Dict[str, Any]:
    vals = list(values)
    tv = trimmed(vals, trim)
    avg = mean(tv)
    sd = stddev(tv)
    cv = (sd / avg * 100.0) if avg > 0 else 0.0
    return {
        "mean": round(avg, 3),
        "stddev": round(sd, 3),
        "cv_percent": round(cv, 3),
        "runs": [round(v, 3) for v in vals],
    }


def sparkline(values: Sequence[float]) -> str:
    vals = list(values)
    if not vals:
        return ""
    chars = " .:-=+*#%@"
    lo, hi = min(vals), max(vals)
    if hi <= lo:
        return chars[-1] * len(vals)
    out = []
    for v in vals:
        idx = int((v - lo) / (hi - lo) * (len(chars) - 1))
        out.append(chars[idx])
    return "".join(out)


def fmt_num(x: Any, decimals: int = 2) -> str:
    try:
        f = float(x)
    except Exception:
        return str(x)
    if abs(f) >= 1000:
        return f"{f:,.{decimals}f}"
    return f"{f:.{decimals}f}"


def fmt_ms(ms: Any) -> str:
    try:
        return f"{float(ms):,.1f} ms"
    except Exception:
        return str(ms)


def clean_text(s: str, limit: int = 900) -> str:
    s = re.sub(r"\s+", " ", s or "").strip()
    if len(s) > limit:
        s = s[:limit].rsplit(" ", 1)[0]
    return s


def canonical_license(label: Optional[str]) -> str:
    if not label:
        return ""
    raw = label.strip()
    if raw in PERMISSIVE_LICENSES:
        return raw
    key = re.sub(r"\s+", " ", raw.lower().replace("_", "-")).strip()
    return LICENSE_ALIASES.get(key, raw)


def require_permissive_license(label: Optional[str]) -> str:
    canon = canonical_license(label)
    if canon not in PERMISSIVE_LICENSES:
        allowed = ", ".join(sorted(PERMISSIVE_LICENSES))
        raise SystemExit(
            f"Local corpus license '{label or '<missing>'}' is not accepted by this benchmark. "
            f"Use a permissive corpus license and pass --corpus-license. Accepted: {allowed}"
        )
    return canon


def synthetic_db_texts(total: int) -> List[str]:
    topics = [
        "astronomy orbital mechanics", "urban water systems", "medieval trade routes",
        "machine learning evaluation", "renewable energy storage", "marine coral ecology",
        "ancient agriculture", "computer architecture caches", "public health logistics",
        "railway signaling systems", "language documentation", "volcanic island geology",
    ]
    regions = ["north", "south", "east", "west", "central"]
    methods = ["survey", "simulation", "field report", "archive review", "sensor log", "case study"]
    docs: List[str] = []
    for i in range(total):
        topic = topics[i % len(topics)]
        region = regions[(i // len(topics)) % len(regions)]
        method = methods[i % len(methods)]
        fact = f"RBFACT{i:07d}"
        metric = 17 + ((i * 37) % 83)
        doc = (
            f"Passage {i}. Topic: {topic}. Retrieval key {fact}. "
            f"The {region} {method} records measurement {metric} and describes causes, constraints, "
            f"tradeoffs, and practical outcomes. This synthetic passage is generated locally for RAG "
            f"benchmarking and contains no third-party source text."
        )
        docs.append(doc)
    return docs


def query_for_doc(doc: str, doc_id: int, qid: int) -> str:
    topic_match = re.search(r"Topic: ([^.]+)", doc)
    fact_match = re.search(r"RBFACT\d+", doc)
    topic = topic_match.group(1) if topic_match else clean_text(doc, 80)
    fact = fact_match.group(0) if fact_match else f"document {doc_id}"
    return f"For retrieval query {qid}, summarize the passage about {topic} with key {fact}."


def load_local_jsonl(path: str, text_key: str) -> List[str]:
    p = Path(path).expanduser()
    if not p.exists():
        raise SystemExit(f"Local corpus file does not exist: {p}")
    texts: List[str] = []
    with p.open("r", encoding="utf-8") as fh:
        for line_no, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SystemExit(f"Invalid JSONL at line {line_no}: {exc}") from exc
            if isinstance(row, dict):
                text = row.get(text_key)
                if text is None:
                    for value in row.values():
                        if isinstance(value, str) and len(value.strip()) >= 20:
                            text = value
                            break
            elif isinstance(row, str):
                text = row
            else:
                text = None
            text = clean_text(str(text or ""))
            if len(text) >= 40:
                texts.append(text)
    if not texts:
        raise SystemExit(f"No usable text rows found in {p}")
    return texts


def load_corpus(args: argparse.Namespace, max_db: int, q_count: int, ui: UI) -> Tuple[List[str], List[str], List[int], Dict[str, Any]]:
    if args.corpus == "synthetic":
        db_texts = synthetic_db_texts(max_db)
        license_label = "MIT synthetic fixture / no third-party source text"
        source = "synthetic-generated-local"
        corpus_file = None
    else:
        license_label = require_permissive_license(args.corpus_license)
        if not args.corpus_file:
            raise SystemExit("--corpus-file is required when --corpus local-jsonl")
        source = "local-jsonl"
        corpus_file = str(Path(args.corpus_file).expanduser())
        ui.print(f"Loading local JSONL corpus: {corpus_file}")
        db_texts = load_local_jsonl(corpus_file, args.jsonl_text_key)
        if len(db_texts) < max_db:
            repeats = (max_db // max(1, len(db_texts))) + 1
            db_texts = (db_texts * repeats)[:max_db]
        else:
            db_texts = db_texts[:max_db]

    query_doc_ids = [((i * 9973) % max_db) for i in range(q_count)]
    q_texts = [query_for_doc(db_texts[doc_id], doc_id, i) for i, doc_id in enumerate(query_doc_ids)]
    info = {
        "source": source,
        "license": license_label,
        "count_db": len(db_texts),
        "count_query": len(q_texts),
        "corpus_file": corpus_file,
        "jsonl_text_key": args.jsonl_text_key if args.corpus == "local-jsonl" else None,
        "notes": "Default corpus is generated locally and does not include third-party database text.",
    }
    return db_texts, q_texts, query_doc_ids, info


TOKEN_RE = re.compile(r"[a-z0-9][a-z0-9_-]*")


def token_hash(token: str, dim: int) -> Tuple[int, float]:
    digest = hashlib.blake2b(token.encode("utf-8", errors="ignore"), digest_size=8).digest()
    value = int.from_bytes(digest, "little", signed=False)
    return value % dim, 1.0 if ((value >> 63) & 1) == 0 else -1.0


def hashed_lexical_embeddings(texts: Sequence[str], dim: int, ui: UI, label: str):
    np = import_numpy()
    arr = np.zeros((len(texts), dim), dtype=np.float32)
    cache: Dict[str, Tuple[int, float]] = {}
    total = len(texts)
    update_every = max(1, total // 100)
    for i, text in enumerate(texts):
        tokens = TOKEN_RE.findall(text.lower())
        # Unigrams with extra weight for synthetic retrieval keys.
        for tok in tokens:
            item = cache.get(tok)
            if item is None:
                item = token_hash(tok, dim)
                cache[tok] = item
            idx, sign = item
            weight = 3.0 if tok.startswith("rbfact") else 1.0
            arr[i, idx] += sign * weight
        # A few adjacent-token features improve lexical retrieval without external models.
        for a, b in zip(tokens[:80], tokens[1:81]):
            if len(a) < 3 or len(b) < 3:
                continue
            tok = "bi:" + a + "_" + b
            item = cache.get(tok)
            if item is None:
                item = token_hash(tok, dim)
                cache[tok] = item
            idx, sign = item
            arr[i, idx] += sign * 0.5
        norm = float(np.linalg.norm(arr[i]))
        if norm > 0:
            arr[i] /= norm
        if (i + 1) % update_every == 0 or i + 1 == total:
            ui.progress(f"Embedding {label}", i + 1, total)
    return arr


def hash_texts_for_cache(texts: Sequence[str]) -> str:
    h = hashlib.sha256()
    for text in texts:
        h.update(text.encode("utf-8", errors="ignore"))
        h.update(b"\0")
    return h.hexdigest()


def embedding_cache_key(args: argparse.Namespace, db_texts: Sequence[str], q_texts: Sequence[str], corpus_info: Dict[str, Any]) -> str:
    payload = {
        "version": 3,
        "embedding": "built-in-hashing-vectorizer",
        "embedding_dim": args.embedding_dim,
        "corpus_source": corpus_info.get("source"),
        "corpus_license": corpus_info.get("license"),
        "db_count": len(db_texts),
        "q_count": len(q_texts),
        "text_hash": hash_texts_for_cache(list(db_texts) + list(q_texts)),
    }
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()[:20]


def load_or_build_embeddings(args: argparse.Namespace, db_texts: List[str], q_texts: List[str], corpus_info: Dict[str, Any], ui: UI):
    np = import_numpy()
    cache_dir = Path(args.cache_dir).expanduser()
    cache_dir.mkdir(parents=True, exist_ok=True)
    key = embedding_cache_key(args, db_texts, q_texts, corpus_info)
    db_path = cache_dir / f"db_embeddings_{key}.npy"
    q_path = cache_dir / f"query_embeddings_{key}.npy"
    meta_path = cache_dir / f"embedding_meta_{key}.json"
    if not args.refresh_embeddings and db_path.exists() and q_path.exists() and meta_path.exists():
        ui.print(f"Loading cached embeddings: {db_path.name}, {q_path.name}")
        db = np.load(str(db_path))
        q = np.load(str(q_path))
        meta = json.loads(meta_path.read_text())
        meta["loaded_from_cache"] = True
        return db.astype(np.float32, copy=False), q.astype(np.float32, copy=False), meta

    ui.rule("Local embeddings")
    t0 = time.perf_counter()
    db = hashed_lexical_embeddings(db_texts, args.embedding_dim, ui, "documents")
    q = hashed_lexical_embeddings(q_texts, args.embedding_dim, ui, "queries")
    elapsed = time.perf_counter() - t0
    np.save(str(db_path), db)
    np.save(str(q_path), q)
    meta = {
        "backend": "built-in-hashing-vectorizer",
        "license": "part of MIT benchmark script; no external embedding model",
        "embedding_dim": args.embedding_dim,
        "db_shape": list(db.shape),
        "query_shape": list(q.shape),
        "build_seconds": round(elapsed, 3),
        "db_path": str(db_path),
        "query_path": str(q_path),
        "loaded_from_cache": False,
    }
    meta_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    ui.print(f"Saved embedding cache: {db_path.name}, {q_path.name}")
    return db, q, meta


class NumpyFlatIndex:
    name = "numpy_flat_inner_product"

    def __init__(self, vectors: Any):
        np = import_numpy()
        self.vectors = np.asarray(vectors, dtype=np.float32).copy()
        self.ntotal = int(self.vectors.shape[0])
        self.dim = int(self.vectors.shape[1])

    def search(self, queries: Any, k: int):
        np = import_numpy()
        q = np.asarray(queries, dtype=np.float32)
        if q.ndim == 1:
            q = q.reshape(1, -1)
        k = min(k, self.vectors.shape[0])
        chunk = 128
        all_d: List[Any] = []
        all_i: List[Any] = []
        for start in range(0, q.shape[0], chunk):
            sub = q[start:start + chunk]
            sims = sub @ self.vectors.T
            idx = np.argpartition(-sims, kth=k - 1, axis=1)[:, :k]
            vals = np.take_along_axis(sims, idx, axis=1)
            order = np.argsort(-vals, axis=1)
            idx = np.take_along_axis(idx, order, axis=1)
            vals = np.take_along_axis(vals, order, axis=1)
            all_d.append(vals.astype(np.float32, copy=False))
            all_i.append(idx.astype(np.int64, copy=False))
        return np.vstack(all_d), np.vstack(all_i)


def build_index(vectors: Any, args: argparse.Namespace, backend: str):
    np = import_numpy()
    vecs = np.asarray(vectors, dtype=np.float32)
    if backend == "numpy":
        return NumpyFlatIndex(vecs)
    import faiss  # type: ignore
    if args.threads and args.threads > 0:
        faiss.omp_set_num_threads(args.threads)
    dim = int(vecs.shape[1])
    try:
        index = faiss.IndexHNSWFlat(dim, int(args.hnsw_m), faiss.METRIC_INNER_PRODUCT)
    except TypeError:
        index = faiss.IndexHNSWFlat(dim, int(args.hnsw_m))
    index.hnsw.efConstruction = int(args.hnsw_ef_construction)
    index.add(vecs)
    index.hnsw.efSearch = int(args.hnsw_ef)
    return index


def index_name(index: Any, backend: str) -> str:
    if backend == "numpy":
        return getattr(index, "name", "numpy")
    return "faiss_hnsw_inner_product"


def select_queries(q_embeddings: Any, count: int, seed: int):
    np = import_numpy()
    rng = np.random.default_rng(seed)
    if q_embeddings.shape[0] >= count:
        idx = rng.choice(q_embeddings.shape[0], size=count, replace=False)
    else:
        idx = rng.choice(q_embeddings.shape[0], size=count, replace=True)
    return q_embeddings[idx]


def run_build_benchmark(args: argparse.Namespace, db_embeddings: Any, db_sizes: Sequence[int], backend: str, ui: UI) -> List[Dict[str, Any]]:
    results: List[Dict[str, Any]] = []
    if args.skip_build:
        return results
    ui.rule("HNSW index build")
    for size in db_sizes:
        times: List[float] = []
        for r in range(args.runs):
            gc.collect()
            t0 = time.perf_counter()
            idx = build_index(db_embeddings[:size], args, backend)
            elapsed = time.perf_counter() - t0
            times.append(elapsed)
            del idx
            ui.progress(f"Build DB={size:,}", r + 1, args.runs)
            if args.cooldown > 0 and r + 1 < args.runs:
                time.sleep(args.cooldown)
        summary = summarize_seconds(times, args.trim)
        results.append({
            "db_size": int(size),
            "backend": backend,
            "index": "faiss_hnsw_inner_product" if backend == "faiss" else "numpy_flat_build_copy",
            "times_seconds": [round(t, 6) for t in times],
            "summary": summary,
        })
    return results


def run_search_benchmark(args: argparse.Namespace, db_embeddings: Any, q_embeddings: Any, db_sizes: Sequence[int], backend: str, ui: UI) -> List[Dict[str, Any]]:
    results: List[Dict[str, Any]] = []
    if args.skip_search:
        return results
    ui.rule("Batch vector search")
    for size in db_sizes:
        ui.print(f"Building search index for DB={size:,} ...")
        idx = build_index(db_embeddings[:size], args, backend)
        qps_values: List[float] = []
        elapsed_values: List[float] = []
        for r in range(args.runs):
            qs = select_queries(q_embeddings, args.batch_queries, seed=1000 + r + size)
            t0 = time.perf_counter()
            idx.search(qs, args.top_k)
            elapsed = time.perf_counter() - t0
            qps = args.batch_queries / elapsed if elapsed > 0 else 0.0
            qps_values.append(qps)
            elapsed_values.append(elapsed)
            ui.progress(f"Search DB={size:,}", r + 1, args.runs)
            if args.cooldown > 0 and r + 1 < args.runs:
                time.sleep(args.cooldown)
        results.append({
            "db_size": int(size),
            "backend": backend,
            "index": index_name(idx, backend),
            "top_k": int(args.top_k),
            "batch_queries": int(args.batch_queries),
            "qps": summarize_rate(qps_values, args.trim),
            "elapsed_seconds": [round(t, 6) for t in elapsed_values],
        })
        del idx
        gc.collect()
    return results


def http_headers(api_key: str, extra: Optional[Dict[str, str]] = None) -> Dict[str, str]:
    headers = {"Content-Type": "application/json"}
    if api_key is not None and api_key != "":
        headers["Authorization"] = f"Bearer {api_key}"
    if extra:
        headers.update(extra)
    return headers


def http_json(method: str, url: str, api_key: str, payload: Optional[Dict[str, Any]], timeout: float) -> Dict[str, Any]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = Request(url, data=data, headers=http_headers(api_key), method=method)
    try:
        with urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
            return json.loads(body) if body else {}
    except HTTPError as exc:
        body = exc.read(4000).decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} from {url}: {body}") from exc
    except URLError as exc:
        raise RuntimeError(f"Connection error for {url}: {exc}") from exc


def detect_model(base: str, api_key: str, timeout: float) -> Optional[str]:
    try:
        data = http_json("GET", models_url(base), api_key, None, timeout)
        items = data.get("data") or []
        for item in items:
            mid = item.get("id") if isinstance(item, dict) else None
            if mid:
                return str(mid)
    except Exception:
        return None
    return None


def chat_completion(base: str, api_key: str, model: str, messages: List[Dict[str, str]], args: argparse.Namespace) -> Dict[str, Any]:
    payload = {
        "model": model,
        "messages": messages,
        "temperature": args.temperature,
        "max_tokens": args.max_tokens,
        "stream": not args.no_stream,
    }
    if args.no_stream:
        return chat_completion_nonstream(base, api_key, payload, args.request_timeout)
    try:
        return chat_completion_stream(base, api_key, payload, args.request_timeout)
    except Exception as exc:
        if args.disable_nonstream_fallback:
            raise
        fallback_payload = dict(payload)
        fallback_payload["stream"] = False
        data = chat_completion_nonstream(base, api_key, fallback_payload, args.request_timeout)
        data["stream_fallback_error"] = str(exc)
        return data


def chat_completion_nonstream(base: str, api_key: str, payload: Dict[str, Any], timeout: float) -> Dict[str, Any]:
    t0 = time.perf_counter()
    data = http_json("POST", chat_url(base), api_key, payload, timeout)
    total = time.perf_counter() - t0
    content = ""
    choices = data.get("choices") or []
    if choices:
        msg = choices[0].get("message") or {}
        content = str(msg.get("content") or "")
    usage = data.get("usage") or {}
    return {
        "ttft_seconds": total,
        "total_seconds": total,
        "content": content,
        "output_chars": len(content),
        "approx_output_tokens": max(1, len(content.split())) if content else 0,
        "usage": usage,
        "streamed": False,
    }


def chat_completion_stream(base: str, api_key: str, payload: Dict[str, Any], timeout: float) -> Dict[str, Any]:
    data = json.dumps(payload).encode("utf-8")
    req = Request(chat_url(base), data=data, headers=http_headers(api_key, {"Accept": "text/event-stream"}), method="POST")
    t0 = time.perf_counter()
    first_content: Optional[float] = None
    chunks: List[str] = []
    try:
        with urlopen(req, timeout=timeout) as resp:
            for raw in resp:
                line = raw.decode("utf-8", errors="replace").strip()
                if not line or line.startswith(":"):
                    continue
                if not line.startswith("data:"):
                    continue
                value = line[5:].strip()
                if value == "[DONE]":
                    break
                try:
                    event = json.loads(value)
                except json.JSONDecodeError:
                    continue
                choices = event.get("choices") or []
                if not choices:
                    continue
                delta = choices[0].get("delta") or {}
                content = delta.get("content") or ""
                if content:
                    if first_content is None:
                        first_content = time.perf_counter() - t0
                    chunks.append(str(content))
    except HTTPError as exc:
        body = exc.read(4000).decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} from {chat_url(base)}: {body}") from exc
    except URLError as exc:
        raise RuntimeError(f"Connection error for {chat_url(base)}: {exc}") from exc
    total = time.perf_counter() - t0
    content = "".join(chunks)
    return {
        "ttft_seconds": first_content if first_content is not None else total,
        "total_seconds": total,
        "content": content,
        "output_chars": len(content),
        "approx_output_tokens": max(1, len(content.split())) if content else 0,
        "usage": {},
        "streamed": True,
    }


def probe_endpoint(args: argparse.Namespace, ui: UI) -> Tuple[str, str, Dict[str, Any]]:
    endpoint = normalize_endpoint(args.endpoint or args.endpoint_pos or "")
    model = args.model
    detected = None
    if not model:
        detected = detect_model(endpoint, args.api_key, args.connect_timeout)
        if detected:
            model = detected
    if not model:
        raise SystemExit("Model id is required because /v1/models did not return an id. Re-run with --model MODEL_ID.")
    messages = [
        {"role": "system", "content": "Reply with a short health-check phrase."},
        {"role": "user", "content": "health check"},
    ]
    probe_args = argparse.Namespace(**vars(args))
    probe_args.no_stream = True
    probe_args.max_tokens = min(args.max_tokens, 8)
    t0 = time.perf_counter()
    resp = chat_completion(endpoint, args.api_key, model, messages, probe_args)
    elapsed = time.perf_counter() - t0
    info = {
        "base_url": endpoint,
        "chat_url": chat_url(endpoint),
        "models_url": models_url(endpoint),
        "model": model,
        "model_auto_detected": detected is not None,
        "probe_seconds": round(elapsed, 4),
        "probe_output_chars": resp.get("output_chars", 0),
    }
    ui.print(ui.green(f"Endpoint OK: {endpoint} model={model} probe={elapsed*1000:.1f} ms"))
    return endpoint, model, info


def make_rag_messages(question: str, contexts: Sequence[str], context_chars: int) -> List[Dict[str, str]]:
    joined_parts: List[str] = []
    used = 0
    for i, ctx in enumerate(contexts, 1):
        part = f"[Context {i}] {clean_text(ctx, 900)}"
        if used + len(part) > context_chars:
            remain = max(0, context_chars - used)
            if remain > 80:
                joined_parts.append(part[:remain])
            break
        joined_parts.append(part)
        used += len(part)
    context = "\n".join(joined_parts)
    user = (
        "Use only the context below. If the answer is not in the context, say that the context is insufficient.\n\n"
        f"Context:\n{context}\n\nQuestion: {question}\n\nAnswer in two concise sentences."
    )
    return [
        {"role": "system", "content": "You are a precise RAG benchmark answerer."},
        {"role": "user", "content": user},
    ]


def run_rag_benchmark(args: argparse.Namespace, endpoint: str, model: str, db_texts: List[str], db_embeddings: Any, q_texts: List[str], q_embeddings: Any, backend: str, ui: UI) -> Dict[str, Any]:
    if args.skip_rag:
        return {}
    np = import_numpy()
    workers = args.rag_workers or min(os.cpu_count() or 1, 8)
    rag_db_size = min(args.rag_db_size, len(db_texts), int(db_embeddings.shape[0]))
    total_per_run = workers * args.rag_queries_per_worker
    ui.rule("Concurrent RAG")
    ui.print(f"Building RAG retrieval index: db={rag_db_size:,}, workers={workers}, requests/run={total_per_run}")
    retrieval_index = build_index(db_embeddings[:rag_db_size], args, backend)

    all_ttft: List[float] = []
    all_total: List[float] = []
    all_retrieval: List[float] = []
    run_rows: List[Dict[str, Any]] = []
    errors: List[str] = []
    completed_total = 0
    chars_total = 0
    approx_tokens_total = 0
    fallback_count = 0

    def one_request(global_qid: int) -> Dict[str, Any]:
        qid = global_qid % len(q_texts)
        qv = np.asarray(q_embeddings[qid:qid + 1], dtype=np.float32)
        rt0 = time.perf_counter()
        _, ids = retrieval_index.search(qv, args.top_k)
        retrieval_seconds = time.perf_counter() - rt0
        doc_ids = [int(x) for x in ids[0].tolist() if int(x) >= 0]
        contexts = [db_texts[i] for i in doc_ids[: args.top_k]]
        messages = make_rag_messages(q_texts[qid], contexts, args.context_chars)
        resp = chat_completion(endpoint, args.api_key, model, messages, args)
        return {
            "retrieval_seconds": retrieval_seconds,
            "ttft_seconds": float(resp["ttft_seconds"]),
            "total_seconds": float(resp["total_seconds"]),
            "output_chars": int(resp.get("output_chars", 0)),
            "approx_output_tokens": int(resp.get("approx_output_tokens", 0)),
            "streamed": bool(resp.get("streamed")),
            "fallback": "stream_fallback_error" in resp,
            "doc_ids": doc_ids[: args.top_k],
        }

    for run in range(args.rag_runs):
        run_t0 = time.perf_counter()
        run_completed = 0
        run_chars = 0
        run_tokens = 0
        run_errors = 0
        futures = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            base_qid = run * total_per_run
            for j in range(total_per_run):
                futures.append(pool.submit(one_request, base_qid + j))
            for n, fut in enumerate(concurrent.futures.as_completed(futures), 1):
                try:
                    item = fut.result()
                    run_completed += 1
                    completed_total += 1
                    run_chars += item["output_chars"]
                    run_tokens += item["approx_output_tokens"]
                    chars_total += item["output_chars"]
                    approx_tokens_total += item["approx_output_tokens"]
                    fallback_count += 1 if item.get("fallback") else 0
                    all_retrieval.append(item["retrieval_seconds"])
                    all_ttft.append(item["ttft_seconds"])
                    all_total.append(item["total_seconds"])
                except Exception as exc:
                    run_errors += 1
                    msg = str(exc)
                    errors.append(msg)
                    if args.fail_on_endpoint_error:
                        raise
                ui.progress(f"RAG run {run + 1}/{args.rag_runs}", n, total_per_run)
        wall = time.perf_counter() - run_t0
        row = {
            "run": run + 1,
            "requests": total_per_run,
            "completed": run_completed,
            "errors": run_errors,
            "wall_seconds": round(wall, 6),
            "requests_per_second": round(run_completed / wall, 4) if wall > 0 else 0.0,
            "chars_per_second": round(run_chars / wall, 3) if wall > 0 else 0.0,
            "approx_tokens_per_second": round(run_tokens / wall, 3) if wall > 0 else 0.0,
        }
        run_rows.append(row)
        if args.cooldown > 0 and run + 1 < args.rag_runs:
            time.sleep(args.cooldown)

    wall_sum = sum(r["wall_seconds"] for r in run_rows)
    return {
        "backend": backend,
        "index": "faiss_hnsw_inner_product" if backend == "faiss" else "numpy_flat_inner_product",
        "rag_db_size": rag_db_size,
        "workers": workers,
        "runs": args.rag_runs,
        "queries_per_worker": args.rag_queries_per_worker,
        "top_k": args.top_k,
        "completed": completed_total,
        "errors": len(errors),
        "error_samples": errors[:5],
        "stream_fallback_count": fallback_count,
        "requests_per_second_mean": round(mean([r["requests_per_second"] for r in run_rows]), 4),
        "requests_per_second_runs": [r["requests_per_second"] for r in run_rows],
        "chars_per_second_mean": round(chars_total / wall_sum, 3) if wall_sum > 0 else 0.0,
        "approx_tokens_per_second_mean": round(approx_tokens_total / wall_sum, 3) if wall_sum > 0 else 0.0,
        "retrieval_latency": summarize_seconds(all_retrieval),
        "ttft_latency": summarize_seconds(all_ttft),
        "total_latency": summarize_seconds(all_total),
        "run_rows": run_rows,
    }


class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True


def start_mock_server() -> Tuple[str, ThreadingHTTPServer]:
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, format: str, *args: Any) -> None:
            return

        def do_GET(self) -> None:
            if self.path.rstrip("/") == "/v1/models":
                body = json.dumps({"object": "list", "data": [{"id": "mock-rag-model", "object": "model"}]}).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_response(404)
                self.end_headers()

        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length", "0") or "0")
            raw = self.rfile.read(length) if length else b"{}"
            try:
                payload = json.loads(raw.decode("utf-8"))
            except Exception:
                payload = {}
            stream = bool(payload.get("stream"))
            content = "Mock RAG answer: the supplied context contains the requested retrieval key."
            if self.path.rstrip("/") != "/v1/chat/completions":
                self.send_response(404)
                self.end_headers()
                return
            if stream:
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
                self.end_headers()
                for piece in ["Mock RAG answer: ", "the supplied context ", "contains the requested retrieval key."]:
                    evt = {"choices": [{"delta": {"content": piece}, "index": 0}]}
                    self.wfile.write(("data: " + json.dumps(evt) + "\n\n").encode())
                    self.wfile.flush()
                    time.sleep(0.005)
                self.wfile.write(b"data: [DONE]\n\n")
                self.wfile.flush()
            else:
                body = json.dumps({
                    "id": "mock", "object": "chat.completion", "model": payload.get("model", "mock-rag-model"),
                    "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
                    "usage": {"prompt_tokens": 10, "completion_tokens": 12, "total_tokens": 22},
                }).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    host, port = sock.getsockname()
    sock.close()
    server = ThreadingHTTPServer((host, port), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return f"http://{host}:{port}/v1", server


def license_audit(ui: UI) -> Dict[str, Any]:
    audit = {
        "policy": "Default benchmark path uses only permissively licensed direct dependencies and a generated local corpus.",
        "direct_components": DIRECT_LICENSES,
        "accepted_local_corpus_licenses": sorted(PERMISSIVE_LICENSES),
        "rejected_by_default": ["GPL family", "AGPL", "LGPL", "CC-BY-SA", "CC-BY-NC", "proprietary", "unknown/no license"],
        "notes": [
            "The default synthetic corpus is generated locally and contains no third-party database/source text.",
            "A local JSONL corpus is allowed only when --corpus-license declares a known permissive license.",
            "This script does not download Hugging Face datasets, Wikipedia dumps, or external embedding models.",
            "Bash, curl, OS libraries, and system package managers are treated as the user's execution environment, not bundled benchmark artifacts.",
            "Packages supplied through --extra-pip are user-selected and are not covered by this built-in audit.",
            "This is engineering metadata, not legal advice.",
        ],
    }
    rows = [[c["component"], c["license"], c["role"]] for c in DIRECT_LICENSES]
    ui.table("License audit", ["component", "license", "role"], rows)
    ui.print("Accepted local corpus licenses: " + ", ".join(audit["accepted_local_corpus_licenses"]))
    ui.print("Default corpus: generated locally; no third-party source text.")
    return audit


def print_start_dashboard(args: argparse.Namespace, ui: UI, endpoint_info: Optional[Dict[str, Any]], corpus_info: Optional[Dict[str, Any]], backend: str, sysinfo: Dict[str, Any]) -> None:
    lines = [
        f"Version          : {VERSION}",
        f"Endpoint         : {(endpoint_info or {}).get('base_url', '<self-test/audit>')}",
        f"Model            : {(endpoint_info or {}).get('model', args.model or '<auto>')}",
        f"Index backend    : {backend}",
        f"Corpus           : {(corpus_info or {}).get('source', args.corpus)}",
        f"Corpus license   : {(corpus_info or {}).get('license', 'pending')}",
        f"DB sizes         : {args.db_sizes}",
        f"RAG concurrency  : workers={args.rag_workers or min(os.cpu_count() or 1, 8)} runs={args.rag_runs} q/worker={args.rag_queries_per_worker}",
        f"System           : CPUs={sysinfo['cpu_count']} RAM={sysinfo['memory_gb']} GB WSL={sysinfo['is_wsl']}",
    ]
    ui.box("RAG BENCHMARK DASHBOARD", lines)


def print_summary(result: Dict[str, Any], ui: UI) -> None:
    ui.rule("Benchmark output")
    build_rows = []
    for item in result.get("benchmarks", {}).get("index_build", []):
        s = item["summary"]
        build_rows.append([f"{item['db_size']:,}", item["index"], fmt_ms(s["mean_ms"]), fmt_ms(s["p95_ms"])])
    if build_rows:
        ui.table("Index build", ["DB size", "index", "mean", "p95"], build_rows)

    search_rows = []
    for item in result.get("benchmarks", {}).get("vector_search", []):
        q = item["qps"]
        search_rows.append([f"{item['db_size']:,}", item["index"], f"{q['mean']:,.2f}", f"{q['cv_percent']:.2f}%", sparkline(q["runs"])])
    if search_rows:
        ui.table("Vector search", ["DB size", "index", "QPS mean", "CV", "runs"], search_rows)

    rag = result.get("benchmarks", {}).get("rag", {})
    if rag:
        rows = [
            ["Completed", rag.get("completed", 0)],
            ["Errors", rag.get("errors", 0)],
            ["Requests/sec mean", fmt_num(rag.get("requests_per_second_mean", 0), 4)],
            ["Approx tokens/sec", fmt_num(rag.get("approx_tokens_per_second_mean", 0), 3)],
            ["Chars/sec", fmt_num(rag.get("chars_per_second_mean", 0), 3)],
            ["TTFT p50/p95/p99", f"{fmt_ms(rag['ttft_latency']['p50_ms'])} / {fmt_ms(rag['ttft_latency']['p95_ms'])} / {fmt_ms(rag['ttft_latency']['p99_ms'])}"],
            ["Total p50/p95/p99", f"{fmt_ms(rag['total_latency']['p50_ms'])} / {fmt_ms(rag['total_latency']['p95_ms'])} / {fmt_ms(rag['total_latency']['p99_ms'])}"],
            ["Retrieval p50/p95", f"{fmt_ms(rag['retrieval_latency']['p50_ms'])} / {fmt_ms(rag['retrieval_latency']['p95_ms'])}"],
            ["Throughput runs", sparkline(rag.get("requests_per_second_runs", []))],
            ["Stream fallbacks", rag.get("stream_fallback_count", 0)],
        ]
        ui.table("Concurrent RAG", ["metric", "value"], rows)
        if rag.get("error_samples"):
            ui.print(ui.yellow("Error samples:"))
            for sample in rag["error_samples"]:
                ui.print("  - " + str(sample)[:240])

    out = result.get("output_path")
    if out:
        ui.box("Saved result", [str(out)])


def run(args: argparse.Namespace) -> Dict[str, Any]:
    ui = UI(args.plain)
    if args.license_audit:
        audit = license_audit(ui)
        return {"license_audit": audit}

    if args.self_test:
        endpoint, server = start_mock_server()
        args.endpoint = endpoint
        args.model = "mock-rag-model"
        args.quick = False
        args.db_sizes = "256"
        args.batch_queries = min(args.batch_queries, 64)
        args.runs = min(args.runs, 2)
        args.rag_workers = 2
        args.rag_runs = 2
        args.rag_queries_per_worker = 2
        args.rag_db_size = 128
        args.index_backend = "numpy" if args.index_backend == "auto" else args.index_backend
        args.output = args.output or str(Path.cwd() / "rag_benchmark_selftest_result.json")
    else:
        server = None

    apply_quick_defaults(args)
    db_sizes = parse_db_sizes(args.db_sizes)
    max_db = max(max(db_sizes), args.rag_db_size)
    workers = args.rag_workers or min(os.cpu_count() or 1, 8)
    q_count = max(args.batch_queries, workers * args.rag_queries_per_worker * max(1, args.rag_runs), 128)
    backend = choose_backend(args.index_backend)
    sysinfo = system_info()

    try:
        endpoint, model, endpoint_info = probe_endpoint(args, ui)
        db_texts, q_texts, query_doc_ids, corpus_info = load_corpus(args, max_db, q_count, ui)
        print_start_dashboard(args, ui, endpoint_info, corpus_info, backend, sysinfo)
        license_info = license_audit(ui)
        db_embeddings, q_embeddings, embedding_info = load_or_build_embeddings(args, db_texts, q_texts, corpus_info, ui)

        build_results = run_build_benchmark(args, db_embeddings, db_sizes, backend, ui)
        search_results = run_search_benchmark(args, db_embeddings, q_embeddings, db_sizes, backend, ui)
        rag_result = run_rag_benchmark(args, endpoint, model, db_texts, db_embeddings, q_texts, q_embeddings, backend, ui)

        output_path = args.output or f"rag_benchmark_result_{_dt.datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        result = {
            "schema_version": 1,
            "benchmark": "openai-compatible-rag-benchmark",
            "version": VERSION,
            "created_utc": now_utc_iso(),
            "system": sysinfo,
            "endpoint": endpoint_info,
            "config": {
                "db_sizes": db_sizes,
                "batch_queries": args.batch_queries,
                "runs": args.runs,
                "trim": args.trim,
                "top_k": args.top_k,
                "hnsw_m": args.hnsw_m,
                "hnsw_ef": args.hnsw_ef,
                "hnsw_ef_construction": args.hnsw_ef_construction,
                "index_backend": backend,
                "rag_workers": workers,
                "rag_runs": args.rag_runs,
                "rag_queries_per_worker": args.rag_queries_per_worker,
                "rag_db_size": args.rag_db_size,
                "context_chars": args.context_chars,
                "max_tokens": args.max_tokens,
                "temperature": args.temperature,
                "stream": not args.no_stream,
            },
            "license_audit": license_info,
            "corpus": corpus_info,
            "query_doc_ids_sample": query_doc_ids[:20],
            "embeddings": embedding_info,
            "benchmarks": {
                "index_build": build_results,
                "vector_search": search_results,
                "rag": rag_result,
            },
            "output_path": str(output_path),
        }
        Path(output_path).expanduser().parent.mkdir(parents=True, exist_ok=True)
        Path(output_path).expanduser().write_text(json.dumps(result, indent=2), encoding="utf-8")
        print_summary(result, ui)
        return result
    finally:
        if server is not None:
            server.shutdown()


def main(argv: Sequence[str]) -> int:
    args = parse_args(argv)
    try:
        run(args)
        return 0
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
PYTHON

"$PYTHON_BIN" "$RUNNER" "${PY_ARGS[@]}"

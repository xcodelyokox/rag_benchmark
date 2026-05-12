#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# rag_benchmark.sh - deterministic X3D-style RAG benchmark for OpenAI-compatible endpoints.
set -Eeuo pipefail

SCRIPT_NAME="rag_benchmark.sh"
VERSION="2026.05.12-5-x3d100k"
GITHUB_RAW_URL="https://raw.githubusercontent.com/xcodelyokox/rag_benchmark/main/rag_benchmark.sh"

RAGBENCH_HOME="${RAGBENCH_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/rag_benchmark}"
VENV_DIR="${RAGBENCH_VENV_DIR:-$RAGBENCH_HOME/venv}"
INSTALL=1
SYSTEM_INSTALL=1
RECREATE_VENV=0
FORCE_TUI=0
PLAIN=0
EXTRA_PIP=""
PY_ARGS=()
ORIGINAL_ARGC=$#

is_tty_out() { [[ -t 1 ]]; }
has_tty() { [[ -e /dev/tty ]] && ( : < /dev/tty ) >/dev/null 2>&1 && ( : > /dev/tty ) >/dev/null 2>&1; }
ansi() { if [[ "$PLAIN" -eq 0 ]] && is_tty_out; then printf '\033[%sm' "$1"; fi; }
resetc() { ansi 0; }
bold() { ansi 1; }
dim() { ansi 2; }
cyan() { ansi 36; }
green() { ansi 32; }
yellow() { ansi 33; }
red() { ansi 31; }
blue() { ansi 34; }

say() { printf '%s\n' "$*"; }
info() { printf '%s\n' "$(cyan)[$SCRIPT_NAME]$(resetc) $*"; }
warn() { printf '%s\n' "$(yellow)[$SCRIPT_NAME warning]$(resetc) $*" >&2; }
die() { printf '%s\n' "$(red)[$SCRIPT_NAME error]$(resetc) $*" >&2; exit 1; }

usage() {
  cat <<USAGE
rag_benchmark.sh $VERSION
Deterministic X3D-style RAG benchmark for OpenAI-compatible chat endpoints.

Curl-pipe interactive TUI:
  curl -fsSL $GITHUB_RAW_URL | bash

Non-interactive examples:
  curl -fsSL $GITHUB_RAW_URL | bash -s -- --endpoint http://127.0.0.1:8000/v1 --model MODEL_ID
  ./rag_benchmark.sh --endpoint http://127.0.0.1:8000/v1 --model MODEL_ID --profile x3d-100k
  ./rag_benchmark.sh --self-test --plain

What the default profile measures:
  1. [x3d-rag-benchmark] Batch Search 100K (QPS)
  2. [x3d-rag-benchmark] Index Build 100K (seconds + vec/s)
  3. [x3d-rag-benchmark] Throughput (req/s)

Bash/bootstrap options:
  --tui                    Force the interactive terminal wizard.
  --no-install             Use current Python only; do not create venv, pip install, or apt install.
  --system-install         Allow apt-based fresh WSL2 dependency bootstrap. Default.
  --no-system-install      Do not run apt/sudo; only create/repair venv and pip packages.
  --recreate-venv          Delete and recreate the benchmark virtualenv.
  --state-dir DIR          Cache/venv root. Default: ~/.cache/rag_benchmark
  --venv-dir DIR           Virtualenv directory. Default: ~/.cache/rag_benchmark/venv
  --extra-pip "PKGS"       Extra packages appended to pip install.
  --plain                  Disable colors/live styling.
  -h, --help               Show this help.

Benchmark options passed to Python:
  --endpoint URL           OpenAI-compatible base URL, with or without /v1.
  --model ID               Model id. If omitted, GET /v1/models is used when available.
  --api-key KEY            Bearer token. Default: OPENAI_API_KEY, or empty.
  --profile NAME           x3d-100k (default), quick, or custom.
  --quick                  Alias for --profile quick.
  --db-sizes LIST          Comma-separated DB sizes. Default x3d-100k: 100000.
  --batch-queries N        Batch vector-search queries per timed run. Default: 3000.
  --runs N                 Batch-search timed runs. Default: 10.
  --build-runs N           Index-build timed runs. Default: 5.
  --rag-workers N          Concurrent RAG workers. Default x3d-100k: fixed 8.
  --rag-runs N             Repeated concurrent RAG runs. Default: 5.
  --rag-queries-per-worker N  RAG requests per worker per run. Default: 20.
  --rag-db-size N          Per-worker RAG retrieval index size. Default: 10000.
  --label NAME             Label used in terminal charts and result JSON.
  --output FILE            JSON result path.
  --cache-dir DIR          Embedding/cache directory. Default: ~/.cache/rag_benchmark/cache
  --index-backend NAME     faiss (default), auto, or numpy. X3D-comparable runs require faiss.
  --seed N                 Master deterministic workload seed. Default: 1337.
  --license-audit          Print dependency/corpus license posture and exit.
  --self-test              Run against a local mock OpenAI-compatible endpoint.

Fresh WSL2 note:
  The exact curl one-liner requires curl to already exist. After the script starts, it can
  install or repair Python, python3-venv, python3-pip, NumPy, and faiss-cpu on apt-based WSL2.

Environment shortcuts:
  RAG_ENDPOINT             Used when --endpoint is omitted.
  RAG_MODEL                Used when --model is omitted.
  OPENAI_API_KEY           Used as bearer token unless --api-key is supplied.
  RAGBENCH_HOME            Cache root. Default: ~/.cache/rag_benchmark
USAGE
}

prompt_tty() {
  local prompt="$1" default="${2:-}" answer
  if ! has_tty; then
    die "Interactive prompt requested but /dev/tty is unavailable. Re-run with explicit --endpoint/--model options."
  fi
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
  else
    printf '%s: ' "$prompt" > /dev/tty
  fi
  IFS= read -r answer < /dev/tty || answer=""
  if [[ -z "$answer" ]]; then
    printf '%s' "$default"
  else
    printf '%s' "$answer"
  fi
}

pause_tty() {
  if has_tty; then
    printf 'Press Enter to continue...' > /dev/tty
    IFS= read -r _ < /dev/tty || true
  fi
}

tui_draw() {
  local endpoint="$1" model="$2" profile="$3" label="$4" output="$5" runtime="$6" api_mode="$7" index_backend="$8"
  if has_tty; then
    printf '\033[2J\033[H' > /dev/tty || true
    {
      printf '%s\n' "$(bold)$(cyan)rag_benchmark.sh $VERSION$(resetc)"
      printf '%s\n' "Deterministic X3D-style RAG benchmark for OpenAI-compatible endpoints"
      printf '\n'
      printf '  %-2s %-22s %s\n' '1)' 'Endpoint' "${endpoint:-<auto from RAG_ENDPOINT / required>}"
      printf '  %-2s %-22s %s\n' '2)' 'Model' "${model:-<auto-detect from /v1/models>}"
      printf '  %-2s %-22s %s\n' '3)' 'API key' "$api_mode"
      printf '  %-2s %-22s %s\n' '4)' 'Profile' "$profile"
      printf '  %-2s %-22s %s\n' '5)' 'Result label' "$label"
      printf '  %-2s %-22s %s\n' '6)' 'Output JSON' "$output"
      printf '  %-2s %-22s %s\n' '7)' 'Runtime install mode' "$runtime"
      printf '  %-2s %-22s %s\n' '8)' 'Index backend' "$index_backend"
      printf '\n'
      printf '  %-2s %s\n' 'r)' 'Run benchmark'
      printf '  %-2s %s\n' 't)' 'Run local self-test instead of real endpoint'
      printf '  %-2s %s\n' 'l)' 'License audit'
      printf '  %-2s %s\n' 'h)' 'Help'
      printf '  %-2s %s\n' 'q)' 'Quit'
      printf '\n'
      printf 'Choice: '
    } > /dev/tty
  fi
}

launch_tui() {
  if ! has_tty; then
    usage
    die "No arguments were supplied and /dev/tty is unavailable, so the interactive TUI cannot run."
  fi
  local endpoint="${RAG_ENDPOINT:-}"
  local model="${RAG_MODEL:-}"
  local profile="x3d-100k"
  local label="$(hostname 2>/dev/null || printf 'this-system')"
  local output="./rag_benchmark_result_$(date +%Y%m%d_%H%M%S).json"
  local runtime="full preflight with apt/sudo + venv"
  local api_mode="OPENAI_API_KEY env or empty"
  local api_key_arg=""
  local index_backend="faiss"
  local choice
  while true; do
    tui_draw "$endpoint" "$model" "$profile" "$label" "$output" "$runtime" "$api_mode" "$index_backend"
    IFS= read -r choice < /dev/tty || choice="q"
    case "$choice" in
      1) endpoint="$(prompt_tty 'OpenAI-compatible endpoint URL' "${endpoint:-http://127.0.0.1:8000/v1}")" ;;
      2) model="$(prompt_tty 'Model id (blank = auto-detect)' "$model")" ;;
      3)
         local key
         key="$(prompt_tty 'API key (blank = OPENAI_API_KEY env or no bearer token)' '')"
         if [[ -n "$key" ]]; then api_key_arg="$key"; api_mode="provided in TUI"; else api_key_arg=""; api_mode="OPENAI_API_KEY env or empty"; fi
         ;;
      4)
         printf 'Profiles:\n  1) x3d-100k: 100K vectors, 3000-query batch, 10 search runs, 5 build runs, 8-worker RAG\n  2) quick: small smoke run\n  3) custom: you will pass additional flags after download/run\nSelect profile [1]: ' > /dev/tty
         IFS= read -r p < /dev/tty || p="1"
         case "${p:-1}" in 2) profile="quick" ;; 3) profile="custom" ;; *) profile="x3d-100k" ;; esac
         ;;
      5) label="$(prompt_tty 'Chart/result label' "$label")" ;;
      6) output="$(prompt_tty 'Output JSON path' "$output")" ;;
      7)
         printf 'Runtime modes:\n  1) full preflight with apt/sudo + venv (fresh WSL2 default)\n  2) venv/pip only, no apt/sudo\n  3) no install, use current Python\nSelect mode [1]: ' > /dev/tty
         IFS= read -r m < /dev/tty || m="1"
         case "${m:-1}" in
           2) runtime="venv/pip only, no apt/sudo"; INSTALL=1; SYSTEM_INSTALL=0 ;;
           3) runtime="no install, current Python"; INSTALL=0; SYSTEM_INSTALL=0 ;;
           *) runtime="full preflight with apt/sudo + venv"; INSTALL=1; SYSTEM_INSTALL=1 ;;
         esac
         ;;
      8)
         printf 'Index backends:\n  1) faiss - X3D-comparable HNSW path (recommended)\n  2) auto - FAISS if available, otherwise NumPy smoke fallback\n  3) numpy - smoke fallback, not X3D-comparable\nSelect backend [1]: ' > /dev/tty
         IFS= read -r b < /dev/tty || b="1"
         case "${b:-1}" in 2) index_backend="auto" ;; 3) index_backend="numpy" ;; *) index_backend="faiss" ;; esac
         ;;
      h) usage > /dev/tty; pause_tty ;;
      l) PY_ARGS=("--license-audit"); [[ "$PLAIN" -eq 1 ]] && PY_ARGS+=("--plain"); return ;;
      t) PY_ARGS=("--self-test" "--profile" "quick" "--label" "self-test" "--output" "./rag_benchmark_selftest_$(date +%Y%m%d_%H%M%S).json" "--index-backend" "auto"); [[ "$PLAIN" -eq 1 ]] && PY_ARGS+=("--plain"); return ;;
      r)
         if [[ -z "$endpoint" ]]; then
           endpoint="$(prompt_tty 'OpenAI-compatible endpoint URL' "http://127.0.0.1:8000/v1")"
         fi
         PY_ARGS=("--endpoint" "$endpoint" "--profile" "$profile" "--label" "$label" "--output" "$output" "--index-backend" "$index_backend")
         [[ -n "$model" ]] && PY_ARGS+=("--model" "$model")
         [[ -n "$api_key_arg" ]] && PY_ARGS+=("--api-key" "$api_key_arg")
         [[ "$PLAIN" -eq 1 ]] && PY_ARGS+=("--plain")
         return
         ;;
      q|Q) exit 0 ;;
      *) ;;
    esac
  done
}

apt_install_packages() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  if [[ "$SYSTEM_INSTALL" -eq 0 ]]; then
    warn "Missing system packages: ${pkgs[*]}; --no-system-install is active."
    return 1
  fi
  command -v apt-get >/dev/null 2>&1 || return 1
  info "Installing missing system packages with apt: ${pkgs[*]}"
  if [[ "$(id -u)" -eq 0 ]]; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
  else
    if ! command -v sudo >/dev/null 2>&1; then
      warn "sudo is unavailable; cannot apt install: ${pkgs[*]}"
      return 1
    fi
    sudo -v
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkgs[@]}"
  fi
}

ensure_system_dependencies() {
  [[ "$INSTALL" -eq 0 ]] && return 0
  mkdir -p "$RAGBENCH_HOME"
  local missing=()
  command -v ca-certificates >/dev/null 2>&1 || true
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  command -v python3 >/dev/null 2>&1 || missing+=(python3)
  if [[ ${#missing[@]} -gt 0 ]]; then
    apt_install_packages ca-certificates "${missing[@]}" || true
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    die "python3 is still missing. Install Python 3, then re-run."
  fi
  if ! python3 -m venv --help >/dev/null 2>&1; then
    apt_install_packages python3-venv python3-pip || true
  fi
  if ! python3 -m venv --help >/dev/null 2>&1; then
    apt_install_packages python3-full || true
  fi
  if ! python3 -m venv --help >/dev/null 2>&1; then
    die "python3 venv support is unavailable. Install python3-venv or python3-full, then re-run."
  fi
}

ensure_venv() {
  if [[ "$INSTALL" -eq 0 ]]; then
    if command -v python3 >/dev/null 2>&1; then
      PYTHON_BIN="$(command -v python3)"
    elif command -v python >/dev/null 2>&1; then
      PYTHON_BIN="$(command -v python)"
    else
      die "No Python executable found and --no-install was requested."
    fi
    export PYTHON_BIN
    return 0
  fi

  mkdir -p "$(dirname "$VENV_DIR")"
  if [[ "$RECREATE_VENV" -eq 1 && -d "$VENV_DIR" ]]; then
    info "Recreating virtualenv: $VENV_DIR"
    rm -rf "$VENV_DIR"
  fi
  if [[ -d "$VENV_DIR" && ! -x "$VENV_DIR/bin/python" ]]; then
    warn "Virtualenv appears broken; recreating: $VENV_DIR"
    rm -rf "$VENV_DIR"
  fi
  if [[ ! -d "$VENV_DIR" ]]; then
    info "Creating virtualenv: $VENV_DIR"
    python3 -m venv "$VENV_DIR" || {
      warn "venv creation failed; trying apt repair."
      apt_install_packages python3-venv python3-full python3-pip || true
      python3 -m venv "$VENV_DIR"
    }
  fi
  PYTHON_BIN="$VENV_DIR/bin/python"
  export PYTHON_BIN
  "$PYTHON_BIN" -m ensurepip --upgrade >/dev/null 2>&1 || true
  if ! "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
    warn "pip is missing inside venv; recreating virtualenv."
    rm -rf "$VENV_DIR"
    python3 -m venv "$VENV_DIR"
    PYTHON_BIN="$VENV_DIR/bin/python"
    export PYTHON_BIN
    "$PYTHON_BIN" -m ensurepip --upgrade >/dev/null 2>&1 || true
  fi
  "$PYTHON_BIN" -m pip install --upgrade pip setuptools wheel >/dev/null
  if ! "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1
import numpy
PY
  then
    info "Installing Python package: numpy"
    "$PYTHON_BIN" -m pip install --upgrade numpy
  fi
  if ! "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1
import faiss
PY
  then
    info "Installing Python package: faiss-cpu"
    if ! "$PYTHON_BIN" -m pip install --upgrade faiss-cpu; then
      warn "faiss-cpu install failed. The benchmark can still run only with --index-backend numpy/auto quick fallback; X3D-comparable runs need FAISS."
    fi
  fi
  if [[ -n "$EXTRA_PIP" ]]; then
    info "Installing extra pip packages: $EXTRA_PIP"
    # shellcheck disable=SC2086
    "$PYTHON_BIN" -m pip install --upgrade $EXTRA_PIP
  fi
}

parse_bash_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --tui) FORCE_TUI=1; shift ;;
      --plain) PLAIN=1; PY_ARGS+=("--plain"); shift ;;
      --no-install) INSTALL=0; SYSTEM_INSTALL=0; shift ;;
      --system-install) SYSTEM_INSTALL=1; shift ;;
      --no-system-install) SYSTEM_INSTALL=0; shift ;;
      --recreate-venv) RECREATE_VENV=1; shift ;;
      --state-dir)
        [[ $# -ge 2 ]] || die "--state-dir requires a directory"
        RAGBENCH_HOME="$2"; VENV_DIR="$RAGBENCH_HOME/venv"; PY_ARGS+=("--cache-dir" "$RAGBENCH_HOME/cache"); shift 2 ;;
      --venv-dir)
        [[ $# -ge 2 ]] || die "--venv-dir requires a directory"
        VENV_DIR="$2"; shift 2 ;;
      --extra-pip)
        [[ $# -ge 2 ]] || die "--extra-pip requires a package string"
        EXTRA_PIP="$2"; shift 2 ;;
      *) PY_ARGS+=("$1"); shift ;;
    esac
  done
}

parse_bash_args "$@"
if [[ "$FORCE_TUI" -eq 1 || "$ORIGINAL_ARGC" -eq 0 ]]; then
  launch_tui
fi

ensure_system_dependencies
ensure_venv
export PYTHONHASHSEED=0
export OMP_DYNAMIC=FALSE
export RAGBENCH_HOME

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rag-benchmark.XXXXXX")"
RUNNER="$WORK_DIR/rag_benchmark_runner.py"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

cat > "$RUNNER" <<'PY'
#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
from __future__ import annotations

import argparse
import concurrent.futures
import datetime as _dt
import gc
import hashlib
import json
import math
import os
import platform
import random
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

VERSION = "2026.05.12-5-x3d100k"
DEFAULT_CACHE_DIR = str(Path.home() / ".cache" / "rag_benchmark" / "cache")

PERMISSIVE_LICENSES = {
    "MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "ISC", "0BSD", "Zlib",
    "Unlicense", "Public-Domain", "CC0-1.0", "CC-BY-3.0", "CC-BY-4.0",
}
LICENSE_ALIASES = {
    "apache 2": "Apache-2.0", "apache-2": "Apache-2.0", "apache 2.0": "Apache-2.0",
    "apache license 2.0": "Apache-2.0", "bsd 3 clause": "BSD-3-Clause",
    "bsd-3": "BSD-3-Clause", "bsd 2 clause": "BSD-2-Clause", "public domain": "Public-Domain",
    "cc0": "CC0-1.0", "cc by 4": "CC-BY-4.0", "cc-by-4": "CC-BY-4.0",
}

TOPICS = [
    "computer architecture cache behavior", "retrieval augmented generation", "graph nearest neighbor search",
    "renewable energy storage", "urban water logistics", "marine coral ecology",
    "railway signaling systems", "astronomy orbital mechanics", "public health routing",
    "distributed database indexing", "compiler optimization notes", "volcanic island geology",
    "language documentation projects", "supply chain scheduling", "sensor network calibration",
    "medieval trade routes", "agricultural soil monitoring", "robotics motion planning",
    "privacy preserving analytics", "data center cooling", "satellite image cataloging",
    "financial anomaly detection", "medical triage simulation", "geospatial disaster response",
    "education curriculum mapping", "acoustic wildlife monitoring", "battery materials testing",
    "weather station quality control", "library archive restoration", "manufacturing defect analysis",
    "legal document retrieval", "protein folding summaries",
]


def import_numpy():
    try:
        import numpy as np  # type: ignore
    except Exception as exc:
        raise SystemExit("NumPy is required. Re-run without --no-install, or install numpy.") from exc
    return np


def import_faiss(required: bool):
    try:
        import faiss  # type: ignore
        return faiss
    except Exception as exc:
        if required:
            raise SystemExit("FAISS is required for X3D-comparable HNSW runs. Re-run without --no-install, or install faiss-cpu, or use --index-backend numpy for a smoke-only fallback.") from exc
        return None


class UI:
    def __init__(self, plain: bool = False):
        self.plain = plain or (not sys.stdout.isatty())
        self.last_len = 0

    def c(self, code: str) -> str:
        return "" if self.plain else f"\033[{code}m"

    def bold(self, s: str) -> str:
        return self.c("1") + s + self.c("0")

    def dim(self, s: str) -> str:
        return self.c("2") + s + self.c("0")

    def cyan(self, s: str) -> str:
        return self.c("36") + s + self.c("0")

    def green(self, s: str) -> str:
        return self.c("32") + s + self.c("0")

    def yellow(self, s: str) -> str:
        return self.c("33") + s + self.c("0")

    def red(self, s: str) -> str:
        return self.c("31") + s + self.c("0")

    def blue(self, s: str) -> str:
        return self.c("34") + s + self.c("0")

    def print(self, msg: str = "") -> None:
        if self.last_len:
            sys.stdout.write("\n")
            self.last_len = 0
        print(msg, flush=True)

    def rule(self, title: str) -> None:
        self.print("\n" + self.bold(self.cyan(title)))
        self.print("-" * min(96, max(30, len(title) + 8)))

    def progress(self, label: str, current: int, total: int) -> None:
        if self.plain:
            if current == total or current == 1 or current % max(1, total // 10) == 0:
                self.print(f"{label}: {current}/{total}")
            return
        width = 34
        frac = 0.0 if total <= 0 else min(1.0, current / total)
        filled = int(width * frac)
        bar = "█" * filled + "░" * (width - filled)
        line = f"\r{self.cyan(label)} [{bar}] {current:,}/{total:,}"
        sys.stdout.write(line + " " * max(0, self.last_len - len(line)))
        sys.stdout.flush()
        self.last_len = len(line)
        if current >= total:
            sys.stdout.write("\n")
            sys.stdout.flush()
            self.last_len = 0

    def table(self, title: str, headers: Sequence[str], rows: Sequence[Sequence[Any]]) -> None:
        self.rule(title)
        data = [[str(c) for c in row] for row in rows]
        widths = [len(str(h)) for h in headers]
        for row in data:
            for i, cell in enumerate(row):
                widths[i] = max(widths[i], len(cell))
        fmt = "  " + "  ".join("{:<" + str(w) + "}" for w in widths)
        self.print(fmt.format(*headers))
        self.print("  " + "  ".join("-" * w for w in widths))
        for row in data:
            self.print(fmt.format(*row))

    def box(self, title: str, lines: Sequence[str]) -> None:
        content = [title] + list(lines)
        width = max(50, min(110, max(len(strip_ansi(x)) for x in content) + 4))
        tl, tr, bl, br, h, v = ("+", "+", "+", "+", "-", "|") if self.plain else ("╭", "╮", "╰", "╯", "─", "│")
        self.print(tl + h * (width - 2) + tr)
        self.print(v + " " + self.bold(title).ljust(width - 3 + len(self.bold(title)) - len(title)) + v)
        self.print(v + " " * (width - 2) + v)
        for line in lines:
            pad = width - 3 - len(strip_ansi(line))
            self.print(v + " " + line + " " * max(0, pad) + v)
        self.print(bl + h * (width - 2) + br)

    def bar_chart(self, title: str, rows: Sequence[Tuple[str, float, str]], unit: str, subtitle: str = "", lower_is_better: bool = False) -> None:
        self.rule(title)
        if subtitle:
            self.print(self.dim(subtitle))
        if not rows:
            self.print("No data")
            return
        max_value = max(abs(v) for _, v, _ in rows) or 1.0
        label_w = min(28, max(len(label) for label, _, _ in rows))
        bar_w = 48
        for label, value, color in rows:
            frac = min(1.0, abs(value) / max_value)
            filled = max(1, int(bar_w * frac)) if value > 0 else 0
            bar_char = "#" if self.plain else "█"
            bar = bar_char * filled
            if not self.plain:
                color_code = {"green": "32", "blue": "34", "red": "31", "yellow": "33", "cyan": "36"}.get(color, "37")
                bar = self.c(color_code) + bar + self.c("0")
            val = format_value(value, unit)
            arrow = " lower is better" if lower_is_better else ""
            self.print(f"  {label:<{label_w}}  {bar:<{bar_w}}  {val}{arrow}")


ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
def strip_ansi(s: str) -> str:
    return ANSI_RE.sub("", s)


def format_value(value: float, unit: str) -> str:
    if unit == "qps":
        return f"{value:,.0f} QPS"
    if unit == "req/s":
        return f"{value:,.2f} req/s"
    if unit == "s":
        return f"{value:,.2f} s"
    if unit == "vec/s":
        return f"{value:,.0f} vec/s"
    if unit == "ms":
        return f"{value:,.1f} ms"
    return f"{value:,.3f} {unit}"


def percentile(values: Sequence[float], p: float) -> float:
    if not values:
        return 0.0
    np = import_numpy()
    return float(np.percentile(np.array(values, dtype=np.float64), p, method="linear"))


def trimmed(values: Sequence[float], trim: float) -> List[float]:
    vals = sorted(float(v) for v in values)
    if not vals:
        return []
    cut = int(len(vals) * trim)
    if cut > 0 and len(vals) > 2 * cut:
        return vals[cut:-cut]
    return vals


def mean(values: Sequence[float]) -> float:
    vals = list(values)
    return float(sum(vals) / len(vals)) if vals else 0.0


def stddev(values: Sequence[float]) -> float:
    vals = list(values)
    if len(vals) < 2:
        return 0.0
    m = mean(vals)
    return math.sqrt(sum((x - m) ** 2 for x in vals) / len(vals))


def summarize_rates(values: Sequence[float], trim: float) -> Dict[str, Any]:
    tv = trimmed(values, trim)
    m = mean(tv)
    sd = stddev(tv)
    return {
        "mean": round(m, 6),
        "stddev": round(sd, 6),
        "cv_percent": round((sd / m * 100.0) if m > 0 else 0.0, 4),
        "runs": [round(float(v), 6) for v in values],
    }


def summarize_seconds(values: Sequence[float], trim: float) -> Dict[str, Any]:
    tv = trimmed(values, trim)
    m = mean(tv)
    sd = stddev(tv)
    return {
        "mean_s": round(m, 6),
        "stddev_s": round(sd, 6),
        "cv_percent": round((sd / m * 100.0) if m > 0 else 0.0, 4),
        "p50_s": round(percentile(values, 50), 6),
        "p95_s": round(percentile(values, 95), 6),
        "p99_s": round(percentile(values, 99), 6),
        "runs_s": [round(float(v), 6) for v in values],
    }


def latency_summary(values: Sequence[float]) -> Dict[str, Any]:
    vals = list(values)
    return {
        "count": len(vals),
        "mean_ms": round(mean(vals) * 1000.0, 4),
        "p50_ms": round(percentile(vals, 50) * 1000.0, 4),
        "p95_ms": round(percentile(vals, 95) * 1000.0, 4),
        "p99_ms": round(percentile(vals, 99) * 1000.0, 4),
    }


def parse_db_sizes(raw: str) -> List[int]:
    out = []
    for part in str(raw).split(','):
        part = part.strip().replace('_', '')
        if not part:
            continue
        n = int(part)
        if n <= 0:
            raise SystemExit("DB sizes must be positive")
        out.append(n)
    return out or [100000]


def canonical_license(label: Optional[str]) -> str:
    if not label:
        return ""
    raw = label.strip()
    if raw in PERMISSIVE_LICENSES:
        return raw
    key = re.sub(r"\s+", " ", raw.lower().replace("_", "-")).strip()
    return LICENSE_ALIASES.get(key, raw)


def require_permissive(label: Optional[str]) -> str:
    canon = canonical_license(label)
    if canon not in PERMISSIVE_LICENSES:
        raise SystemExit(f"Local corpus license '{label or '<missing>'}' is not on the permissive allow-list: {', '.join(sorted(PERMISSIVE_LICENSES))}")
    return canon


def system_info() -> Dict[str, Any]:
    cpu = platform.processor() or "Unknown CPU"
    try:
        if Path("/proc/cpuinfo").exists():
            for line in Path("/proc/cpuinfo").read_text(errors="ignore").splitlines():
                if line.lower().startswith("model name"):
                    cpu = line.split(":", 1)[1].strip()
                    break
    except Exception:
        pass
    l3 = "Unknown"
    try:
        out = subprocess.check_output(["lscpu"], text=True, stderr=subprocess.DEVNULL, timeout=3)
        for line in out.splitlines():
            if "L3 cache" in line:
                l3 = line.split(":", 1)[1].strip()
                break
    except Exception:
        pass
    mem_gb = 0.0
    try:
        for line in Path("/proc/meminfo").read_text(errors="ignore").splitlines():
            if line.startswith("MemTotal"):
                mem_gb = round(int(line.split()[1]) / 1024 / 1024, 2)
                break
    except Exception:
        pass
    is_wsl = False
    try:
        txt = Path("/proc/version").read_text(errors="ignore").lower()
        is_wsl = "microsoft" in txt or "wsl" in txt
    except Exception:
        pass
    gpu = "N/A"
    try:
        gpu = subprocess.check_output(["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader"], text=True, stderr=subprocess.DEVNULL, timeout=3).strip() or "N/A"
    except Exception:
        pass
    return {
        "cpu": cpu,
        "cpu_count": os.cpu_count() or 1,
        "l3_cache": l3,
        "memory_gb": mem_gb,
        "gpu": gpu,
        "platform": platform.platform(),
        "python": sys.version.split()[0],
        "is_wsl": is_wsl,
        "hostname": socket.gethostname(),
    }


def doc_cluster(doc_id: int, clusters: int, seed: int) -> int:
    return int(((doc_id * 2654435761 + seed * 1013904223) & 0xFFFFFFFF) % clusters)


def doc_text(doc_id: int, clusters: int, seed: int) -> str:
    cl = doc_cluster(doc_id, clusters, seed)
    topic = TOPICS[cl % len(TOPICS)]
    region = ["north", "south", "east", "west", "central"][doc_id % 5]
    method = ["survey", "simulation", "field report", "archive review", "sensor log", "case study"][doc_id % 6]
    metric = 17 + ((doc_id * 37) % 83)
    return (
        f"Passage {doc_id:07d}. Retrieval key RB{doc_id:07d}. Topic: {topic}. "
        f"The {region} {method} records measurement {metric} and notes causes, constraints, "
        f"tradeoffs, and practical outcomes. This synthetic benchmark passage is generated locally "
        f"and contains no third-party source text."
    )


def question_for_doc(doc_id: int, qid: int, clusters: int, seed: int) -> str:
    cl = doc_cluster(doc_id, clusters, seed)
    topic = TOPICS[cl % len(TOPICS)]
    return f"For query {qid:06d}, answer briefly using the context for retrieval key RB{doc_id:07d} about {topic}."


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
                obj = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SystemExit(f"Invalid JSONL line {line_no}: {exc}") from exc
            txt = None
            if isinstance(obj, dict):
                txt = obj.get(text_key)
                if txt is None:
                    for v in obj.values():
                        if isinstance(v, str) and len(v.strip()) >= 20:
                            txt = v
                            break
            elif isinstance(obj, str):
                txt = obj
            if txt:
                cleaned = re.sub(r"\s+", " ", str(txt)).strip()
                if len(cleaned) >= 40:
                    texts.append(cleaned[:1200])
    if not texts:
        raise SystemExit(f"No usable text found in {p}")
    return texts


def normalize_rows(arr: Any) -> Any:
    np = import_numpy()
    norms = np.linalg.norm(arr, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    return (arr / norms).astype(np.float32, copy=False)


def workload_dict(args: argparse.Namespace, db_sizes: Sequence[int], q_count: int, endpoint_model: Optional[str] = None) -> Dict[str, Any]:
    workers = args.rag_workers or min(os.cpu_count() or 1, 8)
    return {
        "benchmark_version": VERSION,
        "profile": args.profile,
        "db_sizes": list(map(int, db_sizes)),
        "batch_queries": args.batch_queries,
        "runs": args.runs,
        "warmup_batches": args.warmup_batches,
        "build_runs": args.build_runs,
        "top_k": args.top_k,
        "hnsw_m": args.hnsw_m,
        "hnsw_ef": args.hnsw_ef,
        "hnsw_ef_construction": args.hnsw_ef_construction,
        "embedding_dim": args.embedding_dim,
        "cluster_count": args.cluster_count,
        "seed": args.seed,
        "query_seed": args.query_seed,
        "q_count": q_count,
        "corpus": args.corpus,
        "rag_workers": workers,
        "rag_runs": args.rag_runs,
        "rag_queries_per_worker": args.rag_queries_per_worker,
        "rag_db_size": args.rag_db_size,
        "max_tokens": args.max_tokens,
        "temperature": args.temperature,
        "context_chars": args.context_chars,
        "send_seed": args.send_seed,
        "request_seed": args.request_seed,
        "endpoint_model": endpoint_model or args.model or "<auto>",
    }


def stable_hash(payload: Any, n: int = 16) -> str:
    return hashlib.sha256(json.dumps(payload, sort_keys=True, default=str).encode("utf-8")).hexdigest()[:n]


def generate_synthetic_embeddings(args: argparse.Namespace, max_db: int, q_count: int, ui: UI) -> Tuple[Any, Any, Any, Dict[str, Any]]:
    np = import_numpy()
    cache_dir = Path(args.cache_dir).expanduser()
    cache_dir.mkdir(parents=True, exist_ok=True)
    cache_payload = {
        "version": 4,
        "kind": "clustered-synthetic-dense-vectors",
        "max_db": max_db,
        "q_count": q_count,
        "dim": args.embedding_dim,
        "clusters": args.cluster_count,
        "seed": args.seed,
        "query_seed": args.query_seed,
        "corpus": args.corpus,
    }
    key = stable_hash(cache_payload, 20)
    db_path = cache_dir / f"x3dsynthetic_db_{key}.npy"
    q_path = cache_dir / f"x3dsynthetic_q_{key}.npy"
    ids_path = cache_dir / f"x3dsynthetic_qids_{key}.npy"
    meta_path = cache_dir / f"x3dsynthetic_meta_{key}.json"
    if not args.refresh_cache and db_path.exists() and q_path.exists() and ids_path.exists() and meta_path.exists():
        ui.print(f"Loading deterministic embedding cache: {db_path.name}")
        return np.load(str(db_path), mmap_mode="r"), np.load(str(q_path), mmap_mode="r"), np.load(str(ids_path), mmap_mode="r"), json.loads(meta_path.read_text())

    ui.rule("Generating deterministic synthetic workload")
    rng = np.random.default_rng(args.seed)
    centers = rng.normal(0, 1, size=(args.cluster_count, args.embedding_dim)).astype(np.float32)
    centers = normalize_rows(centers)
    db = np.empty((max_db, args.embedding_dim), dtype=np.float32)
    chunk = 4096
    for start in range(0, max_db, chunk):
        end = min(max_db, start + chunk)
        ids = np.arange(start, end, dtype=np.int64)
        cids = ((ids * 2654435761 + args.seed * 1013904223) & 0xFFFFFFFF) % args.cluster_count
        noise = rng.normal(0, 1, size=(end - start, args.embedding_dim)).astype(np.float32)
        block = centers[cids.astype(np.int64)] * 0.86 + noise * 0.14
        db[start:end] = normalize_rows(block)
        ui.progress("Synthetic DB vectors", end, max_db)

    qrng = np.random.default_rng(args.query_seed)
    qids = ((np.arange(q_count, dtype=np.int64) * 9973 + 17) % max_db).astype(np.int64)
    qcids = ((qids * 2654435761 + args.seed * 1013904223) & 0xFFFFFFFF) % args.cluster_count
    q = np.empty((q_count, args.embedding_dim), dtype=np.float32)
    for start in range(0, q_count, chunk):
        end = min(q_count, start + chunk)
        noise = qrng.normal(0, 1, size=(end - start, args.embedding_dim)).astype(np.float32)
        block = centers[qcids[start:end].astype(np.int64)] * 0.92 + noise * 0.08
        q[start:end] = normalize_rows(block)
        ui.progress("Synthetic query vectors", end, q_count)

    np.save(str(db_path), db)
    np.save(str(q_path), q)
    np.save(str(ids_path), qids)
    meta = {
        "source": "synthetic-generated-local",
        "license": "MIT synthetic fixture / no third-party source text",
        "db_path": str(db_path),
        "query_path": str(q_path),
        "query_doc_ids_path": str(ids_path),
        "cache_key": key,
        "cache_payload": cache_payload,
        "notes": "Dense clustered vectors are generated deterministically from fixed seeds; no third-party text or embeddings are downloaded.",
    }
    meta_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return np.load(str(db_path), mmap_mode="r"), np.load(str(q_path), mmap_mode="r"), np.load(str(ids_path), mmap_mode="r"), meta


def hashed_embeddings_for_local(args: argparse.Namespace, texts: Sequence[str], q_texts: Sequence[str], ui: UI) -> Tuple[Any, Any, Any, Dict[str, Any]]:
    np = import_numpy()
    cache_dir = Path(args.cache_dir).expanduser()
    cache_dir.mkdir(parents=True, exist_ok=True)
    h = hashlib.sha256()
    for t in list(texts) + list(q_texts):
        h.update(t.encode("utf-8", errors="ignore")); h.update(b"\0")
    key = stable_hash({"version": 4, "kind": "local-hash", "text_hash": h.hexdigest(), "dim": args.embedding_dim}, 20)
    db_path = cache_dir / f"localhash_db_{key}.npy"
    q_path = cache_dir / f"localhash_q_{key}.npy"
    ids_path = cache_dir / f"localhash_qids_{key}.npy"
    meta_path = cache_dir / f"localhash_meta_{key}.json"
    if not args.refresh_cache and db_path.exists() and q_path.exists() and ids_path.exists() and meta_path.exists():
        return np.load(str(db_path), mmap_mode="r"), np.load(str(q_path), mmap_mode="r"), np.load(str(ids_path), mmap_mode="r"), json.loads(meta_path.read_text())
    token_re = re.compile(r"[a-z0-9][a-z0-9_-]*")
    def token_hash(tok: str) -> Tuple[int, float]:
        d = hashlib.blake2b(tok.encode(), digest_size=8).digest()
        v = int.from_bytes(d, "little")
        return v % args.embedding_dim, 1.0 if ((v >> 63) & 1) == 0 else -1.0
    def embed(seq: Sequence[str], label: str) -> Any:
        arr = np.zeros((len(seq), args.embedding_dim), dtype=np.float32)
        cache: Dict[str, Tuple[int, float]] = {}
        for i, text in enumerate(seq):
            for tok in token_re.findall(text.lower())[:256]:
                idx, sign = cache.get(tok) or token_hash(tok)
                cache[tok] = (idx, sign)
                arr[i, idx] += sign
            n = float(np.linalg.norm(arr[i]))
            if n > 0:
                arr[i] /= n
            ui.progress(label, i + 1, len(seq))
        return arr
    db = embed(texts, "Local corpus vectors")
    q = embed(q_texts, "Local query vectors")
    qids = np.array([((i * 9973 + 17) % len(texts)) for i in range(len(q_texts))], dtype=np.int64)
    np.save(str(db_path), db); np.save(str(q_path), q); np.save(str(ids_path), qids)
    meta = {"source": "local-jsonl", "license": require_permissive(args.corpus_license), "cache_key": key, "notes": "Local JSONL corpus; user-declared permissive license."}
    meta_path.write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return np.load(str(db_path), mmap_mode="r"), np.load(str(q_path), mmap_mode="r"), np.load(str(ids_path), mmap_mode="r"), meta


class NumpyFlatIndex:
    name = "numpy_flat_inner_product"
    def __init__(self, vectors: Any):
        self.np = import_numpy()
        self.vectors = self.np.array(vectors, dtype=self.np.float32, copy=True)
    def search(self, q: Any, k: int) -> Tuple[Any, Any]:
        scores = self.np.asarray(q, dtype=self.np.float32) @ self.vectors.T
        if k >= scores.shape[1]:
            idx = self.np.argsort(-scores, axis=1)[:, :k]
        else:
            part = self.np.argpartition(-scores, kth=k-1, axis=1)[:, :k]
            vals = self.np.take_along_axis(scores, part, axis=1)
            order = self.np.argsort(-vals, axis=1)
            idx = self.np.take_along_axis(part, order, axis=1)
        vals = self.np.take_along_axis(scores, idx, axis=1)
        return vals, idx


def choose_backend(name: str) -> str:
    if name == "numpy":
        return "numpy"
    if name == "faiss":
        import_faiss(required=True)
        return "faiss"
    if import_faiss(required=False) is not None:
        return "faiss"
    return "numpy"


def build_index(vectors: Any, args: argparse.Namespace, backend: str, threads: Optional[int] = None):
    np = import_numpy()
    vecs = np.array(vectors, dtype=np.float32, copy=True)
    if backend == "numpy":
        return NumpyFlatIndex(vecs)
    faiss = import_faiss(required=True)
    if threads is not None:
        try:
            faiss.omp_set_num_threads(max(1, int(threads)))
        except Exception:
            pass
    dim = int(vecs.shape[1])
    try:
        idx = faiss.IndexHNSWFlat(dim, int(args.hnsw_m), faiss.METRIC_INNER_PRODUCT)
    except TypeError:
        idx = faiss.IndexHNSWFlat(dim, int(args.hnsw_m))
    idx.hnsw.efConstruction = int(args.hnsw_ef_construction)
    idx.add(vecs)
    idx.hnsw.efSearch = int(args.hnsw_ef)
    return idx


def run_index_build(args: argparse.Namespace, db: Any, db_sizes: Sequence[int], backend: str, ui: UI) -> List[Dict[str, Any]]:
    if args.skip_build:
        return []
    ui.rule("Index build benchmark")
    old_gc = gc.isenabled(); gc.disable()
    results: List[Dict[str, Any]] = []
    try:
        for size in db_sizes:
            if backend == "faiss":
                faiss = import_faiss(required=True)
                try: faiss.omp_set_num_threads(os.cpu_count() or 1)
                except Exception: pass
            times: List[float] = []
            for r in range(args.build_runs):
                t0 = time.perf_counter()
                idx = build_index(db[:size], args, backend, threads=os.cpu_count() or 1)
                elapsed = time.perf_counter() - t0
                times.append(elapsed)
                del idx
                gc.collect()
                ui.progress(f"Index build {size//1000}K", r + 1, args.build_runs)
                if args.cooldown > 0 and r + 1 < args.build_runs:
                    time.sleep(args.cooldown)
            summary = summarize_seconds(times, args.trim)
            summary["vectors_per_s"] = round(size / max(summary["mean_s"], 1e-9), 3)
            results.append({
                "db_size": int(size), "backend": backend,
                "index": "faiss_hnsw_inner_product" if backend == "faiss" else "numpy_flat_inner_product",
                "hnsw_m": args.hnsw_m, "ef_construction": args.hnsw_ef_construction,
                "summary": summary,
            })
    finally:
        if old_gc: gc.enable()
    return results


def run_batch_search(args: argparse.Namespace, db: Any, q: Any, db_sizes: Sequence[int], backend: str, ui: UI) -> List[Dict[str, Any]]:
    if args.skip_search:
        return []
    ui.rule("Batch vector search benchmark")
    old_gc = gc.isenabled(); gc.disable()
    results: List[Dict[str, Any]] = []
    try:
        needed = args.batch_queries * (args.warmup_batches + args.runs)
        if q.shape[0] < needed:
            raise SystemExit(f"Internal error: not enough query vectors ({q.shape[0]}) for needed workload ({needed}).")
        for size in db_sizes:
            ui.print(f"Building FAISS/HNSW search index for DB={size:,} ..." if backend == "faiss" else f"Building NumPy search index for DB={size:,} ...")
            idx = build_index(db[:size], args, backend, threads=os.cpu_count() or 1)
            # Warmup uses fixed query slices, then timed runs use fixed query slices.
            for w in range(args.warmup_batches):
                start = w * args.batch_queries
                end = start + args.batch_queries
                idx.search(q[start:end], args.top_k)
                ui.progress(f"Warmup {size//1000}K", w + 1, args.warmup_batches)
            qps_runs: List[float] = []
            elapsed_runs: List[float] = []
            base = args.warmup_batches * args.batch_queries
            for r in range(args.runs):
                start = base + r * args.batch_queries
                end = start + args.batch_queries
                t0 = time.perf_counter()
                idx.search(q[start:end], args.top_k)
                elapsed = time.perf_counter() - t0
                elapsed_runs.append(elapsed)
                qps_runs.append(args.batch_queries / max(elapsed, 1e-9))
                ui.progress(f"Batch search {size//1000}K", r + 1, args.runs)
                if args.cooldown > 0 and r + 1 < args.runs:
                    time.sleep(args.cooldown)
            results.append({
                "db_size": int(size), "backend": backend,
                "index": "faiss_hnsw_inner_product" if backend == "faiss" else "numpy_flat_inner_product",
                "top_k": args.top_k, "batch_queries": args.batch_queries,
                "qps": summarize_rates(qps_runs, args.trim),
                "elapsed_seconds": [round(float(x), 6) for x in elapsed_runs],
            })
            del idx
            gc.collect()
    finally:
        if old_gc: gc.enable()
    return results


def normalize_base_url(url: str) -> str:
    u = (url or "").strip().rstrip("/")
    if not u:
        return ""
    if not u.endswith("/v1"):
        u += "/v1"
    return u


def http_headers(api_key: str) -> Dict[str, str]:
    h = {"Content-Type": "application/json"}
    if api_key:
        h["Authorization"] = f"Bearer {api_key}"
    return h


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
        data = http_json("GET", base + "/models", api_key, None, timeout)
        for item in data.get("data", []):
            if isinstance(item, dict) and item.get("id"):
                return str(item["id"])
    except Exception:
        return None
    return None


def make_messages(question: str, contexts: Sequence[str], context_chars: int) -> List[Dict[str, str]]:
    context = "\n\n".join(contexts)[:context_chars]
    return [
        {"role": "system", "content": "You answer using only the supplied synthetic benchmark context. Keep the answer to one short sentence."},
        {"role": "user", "content": f"Context:\n{context}\n\nQuestion:\n{question}\n\nAnswer briefly:"},
    ]


def parse_stream_line(line: bytes) -> Optional[str]:
    s = line.decode("utf-8", errors="replace").strip()
    if not s or s.startswith(":"):
        return None
    if s.startswith("data:"):
        data = s[5:].strip()
    else:
        data = s
    if data == "[DONE]":
        return "__DONE__"
    try:
        obj = json.loads(data)
    except Exception:
        return None
    try:
        ch = obj.get("choices", [{}])[0]
        delta = ch.get("delta") or {}
        if isinstance(delta, dict) and delta.get("content"):
            return str(delta.get("content"))
        msg = ch.get("message") or {}
        if isinstance(msg, dict) and msg.get("content"):
            return str(msg.get("content"))
        if ch.get("text"):
            return str(ch.get("text"))
    except Exception:
        return None
    return None


def chat_completion(base: str, api_key: str, model: str, messages: List[Dict[str, str]], args: argparse.Namespace, qid: int) -> Dict[str, Any]:
    payload: Dict[str, Any] = {
        "model": model,
        "messages": messages,
        "temperature": args.temperature,
        "max_tokens": args.max_tokens,
        "stream": not args.no_stream,
    }
    if args.send_seed:
        payload["seed"] = int(args.request_seed + qid)
    url = base + "/chat/completions"
    start = time.perf_counter()
    stream_fallback = False
    chars = 0
    first: Optional[float] = None
    if payload["stream"]:
        req = Request(url, data=json.dumps(payload).encode("utf-8"), headers=http_headers(api_key), method="POST")
        try:
            with urlopen(req, timeout=args.request_timeout) as resp:
                while True:
                    line = resp.readline()
                    if not line:
                        break
                    token = parse_stream_line(line)
                    if token is None:
                        continue
                    if token == "__DONE__":
                        break
                    if first is None:
                        first = time.perf_counter()
                    chars += len(token)
            end = time.perf_counter()
            return {"ok": True, "ttft_s": (first or end) - start, "total_s": end - start, "chars": chars, "stream_fallback": False}
        except Exception:
            if not args.allow_stream_fallback:
                raise
            stream_fallback = True
            payload["stream"] = False
    data = http_json("POST", url, api_key, payload, args.request_timeout)
    end = time.perf_counter()
    text = ""
    try:
        text = data.get("choices", [{}])[0].get("message", {}).get("content", "")
    except Exception:
        text = ""
    return {"ok": True, "ttft_s": end - start, "total_s": end - start, "chars": len(text), "stream_fallback": stream_fallback}


def get_contexts(indices: Iterable[int], local_texts: Optional[Sequence[str]], args: argparse.Namespace) -> List[str]:
    out: List[str] = []
    for i in indices:
        ii = int(i)
        if local_texts is not None:
            out.append(str(local_texts[ii % len(local_texts)]))
        else:
            out.append(doc_text(ii, args.cluster_count, args.seed))
    return out


def run_rag(args: argparse.Namespace, base: str, api_key: str, model: str, db: Any, q: Any, qids: Any, backend: str, local_texts: Optional[Sequence[str]], ui: UI) -> Dict[str, Any]:
    if args.skip_rag:
        return {}
    ui.rule("Concurrent RAG benchmark")
    workers = args.rag_workers or min(os.cpu_count() or 1, 8)
    workers = max(1, min(int(workers), 64))
    rag_db = min(int(args.rag_db_size), int(db.shape[0]))
    total_per_run = workers * int(args.rag_queries_per_worker)
    if q.shape[0] < total_per_run:
        raise SystemExit("Internal error: not enough query vectors for RAG workload")
    if backend == "faiss":
        faiss = import_faiss(required=True)
        try: faiss.omp_set_num_threads(1)
        except Exception: pass
    ui.print(f"Preparing {workers} per-worker retrieval indexes: rag_db={rag_db:,}, top_k={args.top_k}")
    worker_indexes = []
    for w in range(workers):
        worker_indexes.append(build_index(db[:rag_db], args, backend, threads=1))
        ui.progress("RAG worker indexes", w + 1, workers)

    all_ttft: List[float] = []
    all_total: List[float] = []
    all_retrieval: List[float] = []
    run_tps: List[float] = []
    error_samples: List[str] = []
    stream_fallbacks = 0
    completed = 0
    errors = 0
    chars_total = 0
    lock = threading.Lock()

    def one_request(worker_id: int, local_j: int) -> Dict[str, Any]:
        q_index = worker_id * args.rag_queries_per_worker + local_j
        qv = q[q_index:q_index + 1]
        rid = int(qids[q_index]) if qids is not None else q_index
        t0 = time.perf_counter()
        _, inds = worker_indexes[worker_id].search(qv, args.top_k)
        retrieval_s = time.perf_counter() - t0
        contexts = get_contexts(inds[0], local_texts, args)
        top_doc = int(inds[0][0]) if len(inds[0]) else rid
        question = question_for_doc(top_doc, q_index, args.cluster_count, args.seed)
        messages = make_messages(question, contexts, args.context_chars)
        r = chat_completion(base, api_key, model, messages, args, q_index)
        r["retrieval_s"] = retrieval_s
        return r

    # Warm up endpoint with a fixed minimal request.
    try:
        warm_msg = [{"role": "user", "content": "Reply with: ready"}]
        chat_completion(base, api_key, model, warm_msg, args, 0)
    except Exception as exc:
        ui.print(ui.yellow(f"Endpoint warmup warning: {str(exc)[:180]}"))

    for run_i in range(args.rag_runs):
        start = time.perf_counter()
        futures = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            for w in range(workers):
                for j in range(args.rag_queries_per_worker):
                    futures.append(pool.submit(one_request, w, j))
            done_count = 0
            for fut in concurrent.futures.as_completed(futures):
                done_count += 1
                try:
                    r = fut.result()
                    with lock:
                        completed += 1
                        all_ttft.append(float(r.get("ttft_s", 0.0)))
                        all_total.append(float(r.get("total_s", 0.0)))
                        all_retrieval.append(float(r.get("retrieval_s", 0.0)))
                        chars_total += int(r.get("chars", 0))
                        stream_fallbacks += 1 if r.get("stream_fallback") else 0
                except Exception as exc:
                    with lock:
                        errors += 1
                        if len(error_samples) < 5:
                            error_samples.append(str(exc)[:500])
                ui.progress(f"RAG run {run_i + 1}/{args.rag_runs}", done_count, total_per_run)
        wall = time.perf_counter() - start
        run_tps.append(total_per_run / max(wall, 1e-9))
        if args.cooldown > 0 and run_i + 1 < args.rag_runs:
            time.sleep(args.cooldown)

    for idx in worker_indexes:
        del idx
    gc.collect()
    return {
        "workers": workers,
        "runs": args.rag_runs,
        "queries_per_worker": args.rag_queries_per_worker,
        "rag_db_size": rag_db,
        "total_attempted": total_per_run * args.rag_runs,
        "completed": completed,
        "errors": errors,
        "requests_per_second": summarize_rates(run_tps, args.trim),
        "ttft_latency": latency_summary(all_ttft),
        "total_latency": latency_summary(all_total),
        "retrieval_latency": latency_summary(all_retrieval),
        "chars_total": chars_total,
        "chars_per_second_mean": round(chars_total / max(sum(all_total), 1e-9), 6) if all_total else 0.0,
        "stream_fallback_count": stream_fallbacks,
        "error_samples": error_samples,
    }


class MockHandler(BaseHTTPRequestHandler):
    server_version = "RagBenchmarkMock/1.0"
    def log_message(self, fmt: str, *args: Any) -> None:
        return
    def _send(self, code: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def do_GET(self) -> None:
        if self.path.rstrip("/") == "/v1/models":
            self._send(200, json.dumps({"object":"list","data":[{"id":"mock-rag-model","object":"model"}]}).encode())
        else:
            self._send(404, b"{}")
    def do_POST(self) -> None:
        if self.path.rstrip("/") != "/v1/chat/completions":
            self._send(404, b"{}")
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        payload = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        if payload.get("stream"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for token in ["Synthetic ", "RAG ", "answer."]:
                chunk = {"choices":[{"delta":{"content":token}}]}
                self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode()); self.wfile.flush(); time.sleep(0.005)
            self.wfile.write(b"data: [DONE]\n\n"); self.wfile.flush()
        else:
            body = {"choices":[{"message":{"content":"Synthetic RAG answer."}}], "model": payload.get("model", "mock-rag-model")}
            self._send(200, json.dumps(body).encode())


def start_mock_server() -> Tuple[str, ThreadingHTTPServer]:
    server = ThreadingHTTPServer(("127.0.0.1", 0), MockHandler)
    th = threading.Thread(target=server.serve_forever, daemon=True)
    th.start()
    return f"http://127.0.0.1:{server.server_address[1]}/v1", server


def license_audit(ui: UI) -> Dict[str, Any]:
    audit = {
        "script": {"component": "rag_benchmark.sh", "license": "MIT", "source": "this repository"},
        "runtime_dependencies": [
            {"component": "Python", "license": "PSF-2.0-compatible", "role": "runtime"},
            {"component": "NumPy", "license": "BSD-3-Clause", "role": "array math"},
            {"component": "faiss-cpu", "license": "MIT", "role": "FAISS HNSW vector index"},
        ],
        "default_corpus": {"source": "synthetic-generated-local", "license": "MIT synthetic fixture / no third-party source text"},
        "accepted_local_corpus_licenses": sorted(PERMISSIVE_LICENSES),
        "note": "No third-party database text, Wikipedia dumps, Hugging Face datasets, or downloaded embedding models are used by the default benchmark path.",
    }
    ui.box("License audit", [
        "Script: MIT",
        "Default corpus: synthetic local fixture; no third-party source text",
        "Direct Python packages: NumPy (BSD-3-Clause), faiss-cpu (MIT)",
        "Local JSONL corpora require a declared permissive SPDX license",
    ])
    return audit


def probe_endpoint(args: argparse.Namespace, ui: UI) -> Tuple[str, str, Dict[str, Any]]:
    base = normalize_base_url(args.endpoint or os.environ.get("RAG_ENDPOINT", ""))
    api_key = args.api_key if args.api_key is not None else os.environ.get("OPENAI_API_KEY", "")
    model = args.model or os.environ.get("RAG_MODEL", "")
    if not base:
        raise SystemExit("--endpoint is required unless --self-test or --license-audit is used")
    detected = None
    if not model:
        detected = detect_model(base, api_key, args.request_timeout)
        if detected:
            model = detected
    if not model:
        raise SystemExit("--model was not supplied and /v1/models did not return a model id")
    return base, model, {"base_url": base, "model": model, "model_detected": detected is not None, "api_key_used": bool(api_key)}


def apply_profile(args: argparse.Namespace) -> None:
    if args.quick:
        args.profile = "quick"
    if args.profile == "quick":
        args.db_sizes = args.db_sizes or "10000"
        args.batch_queries = min(args.batch_queries, 300)
        args.runs = min(args.runs, 3)
        args.build_runs = min(args.build_runs, 2)
        args.warmup_batches = min(args.warmup_batches, 1)
        args.rag_workers = args.rag_workers or 2
        args.rag_runs = min(args.rag_runs, 2)
        args.rag_queries_per_worker = min(args.rag_queries_per_worker, 2)
        args.rag_db_size = min(args.rag_db_size, 2000)
        args.max_tokens = min(args.max_tokens, 16)
    elif args.profile == "x3d-100k":
        args.db_sizes = args.db_sizes or "100000"
        if not args.rag_workers:
            args.rag_workers = 8
    elif args.profile == "custom":
        args.db_sizes = args.db_sizes or "100000"
    else:
        raise SystemExit(f"Unknown profile: {args.profile}")


def print_start(args: argparse.Namespace, endpoint_info: Optional[Dict[str, Any]], backend: str, sysinfo: Dict[str, Any], work_hash: str, ui: UI) -> None:
    db_sizes = args.db_sizes or "100000"
    workers = args.rag_workers or min(os.cpu_count() or 1, 8)
    ui.box("X3D-STYLE RAG BENCHMARK", [
        f"Version          : {VERSION}",
        f"Label            : {args.label}",
        f"Endpoint         : {(endpoint_info or {}).get('base_url', '<self-test/audit>')}",
        f"Model            : {(endpoint_info or {}).get('model', args.model or '<auto>')}",
        f"Profile          : {args.profile}",
        f"Index backend    : {backend}",
        f"DB sizes         : {db_sizes}",
        f"Search workload  : batch={args.batch_queries} runs={args.runs} warmup={args.warmup_batches} top_k={args.top_k}",
        f"Build workload   : runs={args.build_runs} HNSW M={args.hnsw_m} efC={args.hnsw_ef_construction} efS={args.hnsw_ef}",
        f"RAG workload     : workers={workers} runs={args.rag_runs} q/worker={args.rag_queries_per_worker} rag_db={args.rag_db_size}",
        f"Workload hash    : {work_hash}",
        f"System           : {sysinfo['cpu_count']} CPUs | L3 {sysinfo['l3_cache']} | RAM {sysinfo['memory_gb']} GB | WSL {sysinfo['is_wsl']}",
    ])


def print_summary(result: Dict[str, Any], ui: UI) -> None:
    label = result.get("meta", {}).get("label") or "this-system"
    profile = result.get("meta", {}).get("profile", "")
    sysinfo = result.get("system", {})
    subtitle = f"{sysinfo.get('cpu','Unknown CPU')} | L3 {sysinfo.get('l3_cache','?')} | profile {profile} | workload {result.get('meta',{}).get('workload_hash','')}"
    heads = result.get("headline", {})
    db_label = int(heads.get("db_size", 100000)) // 1000
    if heads.get("batch_search_qps") is not None:
        ui.bar_chart(f"[x3d-rag-benchmark] Batch Search {db_label}K (QPS)", [(label, float(heads["batch_search_qps"]), "blue")], "qps", subtitle)
    if heads.get("index_build_seconds") is not None:
        ui.bar_chart(f"[x3d-rag-benchmark] Index Build {db_label}K (seconds)", [(label, float(heads["index_build_seconds"]), "red")], "s", subtitle, lower_is_better=True)
        ui.bar_chart(f"[x3d-rag-benchmark] Index Build {db_label}K (vec/s)", [(label, float(heads.get("index_build_vec_per_s", 0.0)), "cyan")], "vec/s", subtitle)
    if heads.get("rag_throughput_req_s") is not None:
        ui.bar_chart("[x3d-rag-benchmark] Throughput (req/s)", [(label, float(heads["rag_throughput_req_s"]), "green")], "req/s", subtitle)

    rows: List[List[Any]] = []
    if heads.get("batch_search_qps") is not None:
        rows.append(["Batch Search", f"{heads['batch_search_qps']:,.2f} QPS", f"CV {heads.get('batch_search_cv_percent',0):.2f}%"])
    if heads.get("index_build_seconds") is not None:
        rows.append(["Index Build", f"{heads['index_build_seconds']:,.3f} s", f"{heads.get('index_build_vec_per_s',0):,.0f} vec/s"])
    if heads.get("rag_throughput_req_s") is not None:
        rows.append(["RAG Throughput", f"{heads['rag_throughput_req_s']:,.3f} req/s", f"completed {heads.get('rag_completed',0)} errors {heads.get('rag_errors',0)}"])
    if rows:
        ui.table("Headline metrics", ["metric", "value", "detail"], rows)
    rag = result.get("benchmarks", {}).get("rag") or {}
    if rag:
        ui.table("RAG latency", ["metric", "p50", "p95", "p99"], [
            ["TTFT", f"{rag['ttft_latency']['p50_ms']:,.1f} ms", f"{rag['ttft_latency']['p95_ms']:,.1f} ms", f"{rag['ttft_latency']['p99_ms']:,.1f} ms"],
            ["Total", f"{rag['total_latency']['p50_ms']:,.1f} ms", f"{rag['total_latency']['p95_ms']:,.1f} ms", f"{rag['total_latency']['p99_ms']:,.1f} ms"],
            ["Retrieval", f"{rag['retrieval_latency']['p50_ms']:,.3f} ms", f"{rag['retrieval_latency']['p95_ms']:,.3f} ms", f"{rag['retrieval_latency']['p99_ms']:,.3f} ms"],
        ])
        if rag.get("error_samples"):
            ui.print(ui.yellow("Error samples:"))
            for e in rag["error_samples"]:
                ui.print("  - " + str(e)[:240])
    if result.get("output_path"):
        ui.box("Saved result", [result["output_path"]])


def make_headline(bench: Dict[str, Any], db_sizes: Sequence[int]) -> Dict[str, Any]:
    target = int(db_sizes[0])
    headline: Dict[str, Any] = {"db_size": target}
    for item in bench.get("vector_search", []):
        if int(item.get("db_size", -1)) == target:
            headline["batch_search_qps"] = float(item["qps"]["mean"])
            headline["batch_search_cv_percent"] = float(item["qps"]["cv_percent"])
            break
    for item in bench.get("index_build", []):
        if int(item.get("db_size", -1)) == target:
            headline["index_build_seconds"] = float(item["summary"]["mean_s"])
            headline["index_build_vec_per_s"] = float(item["summary"]["vectors_per_s"])
            headline["index_build_cv_percent"] = float(item["summary"]["cv_percent"])
            break
    rag = bench.get("rag") or {}
    if rag:
        headline["rag_throughput_req_s"] = float(rag["requests_per_second"]["mean"])
        headline["rag_throughput_cv_percent"] = float(rag["requests_per_second"].get("cv_percent", 0.0))
        headline["rag_completed"] = int(rag.get("completed", 0))
        headline["rag_errors"] = int(rag.get("errors", 0))
    return headline


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Deterministic X3D-style RAG benchmark for OpenAI-compatible endpoints")
    p.add_argument("--endpoint", default=None)
    p.add_argument("--model", default=None)
    p.add_argument("--api-key", default=None)
    p.add_argument("--profile", choices=["x3d-100k", "quick", "custom"], default="x3d-100k")
    p.add_argument("--quick", action="store_true")
    p.add_argument("--label", default=None)
    p.add_argument("--output", default=None)
    p.add_argument("--cache-dir", default=DEFAULT_CACHE_DIR)
    p.add_argument("--index-backend", choices=["faiss", "auto", "numpy"], default="faiss")
    p.add_argument("--db-sizes", default=None)
    p.add_argument("--batch-queries", type=int, default=3000)
    p.add_argument("--runs", type=int, default=10)
    p.add_argument("--warmup-batches", type=int, default=5)
    p.add_argument("--build-runs", type=int, default=5)
    p.add_argument("--trim", type=float, default=0.05)
    p.add_argument("--cooldown", type=float, default=2.0)
    p.add_argument("--top-k", type=int, default=10)
    p.add_argument("--hnsw-m", type=int, default=32)
    p.add_argument("--hnsw-ef", type=int, default=64)
    p.add_argument("--hnsw-ef-construction", type=int, default=200)
    p.add_argument("--embedding-dim", type=int, default=384)
    p.add_argument("--cluster-count", type=int, default=4096)
    p.add_argument("--seed", type=int, default=1337)
    p.add_argument("--query-seed", type=int, default=7331)
    p.add_argument("--refresh-cache", action="store_true")
    p.add_argument("--corpus", choices=["synthetic", "local-jsonl"], default="synthetic")
    p.add_argument("--corpus-file", default=None)
    p.add_argument("--corpus-license", default=None)
    p.add_argument("--jsonl-text-key", default="text")
    p.add_argument("--rag-workers", type=int, default=0)
    p.add_argument("--rag-runs", type=int, default=5)
    p.add_argument("--rag-queries-per-worker", type=int, default=20)
    p.add_argument("--rag-db-size", type=int, default=10000)
    p.add_argument("--max-tokens", type=int, default=48)
    p.add_argument("--context-chars", type=int, default=900)
    p.add_argument("--temperature", type=float, default=0.0)
    p.add_argument("--request-timeout", type=float, default=120.0)
    p.add_argument("--request-seed", type=int, default=4242)
    p.add_argument("--send-seed", action="store_true", help="Include seed in chat payload. Some OpenAI-compatible servers reject this; off by default.")
    p.add_argument("--no-stream", action="store_true")
    p.add_argument("--allow-stream-fallback", action="store_true", default=True)
    p.add_argument("--skip-search", action="store_true")
    p.add_argument("--skip-build", action="store_true")
    p.add_argument("--skip-rag", action="store_true")
    p.add_argument("--license-audit", action="store_true")
    p.add_argument("--self-test", action="store_true")
    p.add_argument("--plain", action="store_true")
    return p


def run(args: argparse.Namespace) -> Dict[str, Any]:
    ui = UI(args.plain)
    if args.label is None:
        args.label = socket.gethostname() or "this-system"
    if args.license_audit:
        return {"version": VERSION, "license_audit": license_audit(ui)}

    server = None
    if args.self_test:
        endpoint, server = start_mock_server()
        args.endpoint = endpoint
        args.model = "mock-rag-model"
        args.profile = "quick"
        if args.index_backend == "faiss":
            args.index_backend = "auto"
        args.output = args.output or str(Path.cwd() / "rag_benchmark_selftest_result.json")

    apply_profile(args)
    db_sizes = parse_db_sizes(args.db_sizes or "100000")
    max_db = max(max(db_sizes), args.rag_db_size)
    workers = args.rag_workers or min(os.cpu_count() or 1, 8)
    q_count = max(args.batch_queries * (args.warmup_batches + args.runs), workers * args.rag_queries_per_worker, 512)
    if args.corpus == "local-jsonl":
        require_permissive(args.corpus_license)
    backend = choose_backend(args.index_backend)
    sysinfo = system_info()

    base, model, endpoint_info = probe_endpoint(args, ui)
    api_key = args.api_key if args.api_key is not None else os.environ.get("OPENAI_API_KEY", "")
    wd = workload_dict(args, db_sizes, q_count, endpoint_model=model)
    work_hash = stable_hash(wd, 16)
    print_start(args, endpoint_info, backend, sysinfo, work_hash, ui)
    license_info = license_audit(ui)

    local_texts: Optional[List[str]] = None
    if args.corpus == "synthetic":
        db, q, qids, corpus_info = generate_synthetic_embeddings(args, max_db, q_count, ui)
    else:
        if not args.corpus_file:
            raise SystemExit("--corpus-file is required when --corpus local-jsonl")
        texts = load_local_jsonl(args.corpus_file, args.jsonl_text_key)
        if len(texts) < max_db:
            texts = (texts * ((max_db // len(texts)) + 1))[:max_db]
        else:
            texts = texts[:max_db]
        local_texts = texts
        q_texts = [texts[((i * 9973 + 17) % len(texts))] for i in range(q_count)]
        db, q, qids, corpus_info = hashed_embeddings_for_local(args, texts, q_texts, ui)

    bench: Dict[str, Any] = {}
    bench["index_build"] = run_index_build(args, db, db_sizes, backend, ui)
    bench["vector_search"] = run_batch_search(args, db, q, db_sizes, backend, ui)
    bench["rag"] = run_rag(args, base, api_key, model, db, q, qids, backend, local_texts, ui)

    headline = make_headline(bench, db_sizes)
    now = _dt.datetime.now().astimezone()
    result: Dict[str, Any] = {
        "schema": "rag_benchmark.x3d_style.v1",
        "version": VERSION,
        "meta": {
            "timestamp": now.isoformat(),
            "label": args.label,
            "profile": args.profile,
            "workload_hash": work_hash,
            "workload": wd,
            "reproducibility": {
                "deterministic_workload": True,
                "fixed_seeds": {"seed": args.seed, "query_seed": args.query_seed, "request_seed": args.request_seed},
                "fixed_query_slices": True,
                "temperature": args.temperature,
                "note": "The retrieval/index workload is deterministic. Endpoint generation runtime can still vary with server scheduling and model implementation.",
            },
            "endpoint": endpoint_info,
            "corpus": corpus_info,
            "license_audit": license_info,
        },
        "system": sysinfo,
        "benchmarks": bench,
        "headline": headline,
    }
    out = args.output or f"rag_benchmark_{now.strftime('%Y%m%d_%H%M%S')}.json"
    out_path = Path(out).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    result["output_path"] = str(out_path)
    # Write output_path into the file too.
    out_path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    print_summary(result, ui)
    if server is not None:
        server.shutdown()
    return result


def main() -> None:
    random.seed(1337)
    parser = build_parser()
    args = parser.parse_args()
    try:
        run(args)
    except KeyboardInterrupt:
        raise SystemExit("Interrupted")


if __name__ == "__main__":
    main()
PY

"$PYTHON_BIN" "$RUNNER" "${PY_ARGS[@]}"

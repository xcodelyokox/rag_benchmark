# RAG Benchmark for OpenAI-Compatible Endpoints

A single-file, WSL2-friendly RAG benchmark for models served behind an OpenAI-compatible API.

The benchmark is designed for the flow where you already have a model loaded and exposed through an endpoint such as `http://127.0.0.1:8000/v1`. The script creates a local permissive-license RAG corpus by default, builds vector indexes, runs retrieval, calls your `/v1/chat/completions` endpoint, and prints a terminal dashboard with latency and throughput metrics.

## Highlights

- Runs as one Bash script: `rag_benchmark.sh`.
- Works from GitHub with `curl | bash`.
- Launches an interactive terminal TUI when no arguments are provided.
- Reads prompts from `/dev/tty`, so the TUI still works when the script itself is piped through stdin.
- Accepts OpenAI-compatible endpoint URLs with or without `/v1`.
- Uses a generated local synthetic corpus by default; no Wikipedia, Hugging Face datasets, or third-party database text are downloaded.
- Uses a built-in hashing-vectorizer embedding path; no external embedding model is downloaded.
- Supports FAISS HNSW when `faiss-cpu` is available, with a NumPy fallback.
- Prints terminal tables for index build, vector search, concurrent RAG, TTFT, total latency, retrieval latency, throughput, and error counts.
- Writes a structured JSON result file for later comparison.

## Quick start

### Interactive TUI from GitHub

```bash
curl -fsSL https://raw.githubusercontent.com/user/rag_benchmark/main/rag_benchmark.sh | bash
```

This opens the terminal launcher. From there you can enter:

- endpoint URL,
- model ID or auto-detect from `/v1/models`,
- API key mode,
- quick, standard, or custom profile,
- vector DB sizes,
- RAG concurrency,
- corpus source,
- output JSON path,
- index backend,
- streaming mode,
- runtime install mode,
- license audit,
- self-test.

### Non-interactive benchmark

```bash
curl -fsSL https://raw.githubusercontent.com/user/rag_benchmark/main/rag_benchmark.sh | \
  bash -s -- \
    --endpoint http://127.0.0.1:8000/v1 \
    --model your-model-id \
    --quick
```

### Local script usage

```bash
chmod +x rag_benchmark.sh

./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --quick
```

## Run a self-test

The self-test starts a local mock OpenAI-compatible endpoint and runs a tiny benchmark. It does not require a real model server.

```bash
./rag_benchmark.sh --self-test
```

Or through GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/user/rag_benchmark/main/rag_benchmark.sh | \
  bash -s -- --self-test
```

Use plain output for CI logs:

```bash
./rag_benchmark.sh --self-test --plain
```

## Requirements

For WSL2 or Ubuntu-style Linux environments, make sure Bash, curl, Python, venv support, and pip are available:

```bash
sudo apt update
sudo apt install -y bash curl python3 python3-venv python3-pip
```

The script creates its own virtual environment by default, so you do not need to preinstall NumPy or FAISS unless you run with `--no-install`.

## What gets measured

The benchmark has three main phases.

### 1. Index build

Builds a vector index for each configured DB size and records build latency. With FAISS available, this uses HNSW. With the NumPy backend, the script uses a brute-force normalized-vector fallback.

### 2. Batch vector search

Runs repeated top-k retrieval batches and reports vector-search QPS, coefficient of variation, and run-to-run sparkline summaries.

### 3. Concurrent RAG

For each RAG request, the script:

1. embeds the query using the built-in local hashing-vectorizer path,
2. retrieves top-k context chunks,
3. builds a compact RAG prompt,
4. sends the prompt to `/v1/chat/completions`,
5. measures time to first token when streaming is enabled,
6. measures total latency and approximate output throughput.

The terminal summary includes:

- completed requests,
- errors,
- requests per second,
- approximate tokens per second,
- characters per second,
- TTFT p50/p95/p99,
- total latency p50/p95/p99,
- retrieval latency p50/p95,
- stream fallback count,
- output JSON path.

## TUI launcher

Running the script with no endpoint arguments opens the TUI:

```bash
./rag_benchmark.sh
```

The same works when piped from GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/user/rag_benchmark/main/rag_benchmark.sh | bash
```

The launcher menu looks like this:

```text
+============================================================================+
|                          RAG BENCHMARK LAUNCHER                            |
|        OpenAI-compatible endpoint + local permissive RAG corpus             |
+============================================================================+

  1) Endpoint URL           <required>
  2) Model ID               <auto-detect from /v1/models>
  3) API key                env
  4) Run profile            quick smoke
  5) Vector DB sizes        10000
  6) Search settings        batch=300 runs=3 top_k=5
  7) Concurrent RAG         workers=2 runs=2 q/worker=5 rag_db=5000
  8) Corpus                 synthetic
  9) Output JSON            ./rag_benchmark_result_YYYYMMDD_HHMMSS.json
  10) Advanced              backend=auto max_tokens=80 stream=yes
  11) Runtime               venv install on, styled TUI
  L) License audit          show permissive dependency/corpus posture
  T) Self-test              run local mock OpenAI-compatible endpoint
  S) Start benchmark        run now
  Q) Quit                   exit without running
```

## Endpoint requirements

The benchmark expects an OpenAI-compatible chat completions endpoint.

Required:

```text
POST /v1/chat/completions
```

Optional but useful:

```text
GET /v1/models
```

If `--model` is omitted, the script tries `GET /v1/models` and uses the first returned model ID. If your server does not implement `/v1/models`, pass `--model` explicitly.

The endpoint URL can be either:

```text
http://127.0.0.1:8000
http://127.0.0.1:8000/v1
```

Both are normalized internally.

## API keys

By default, the script uses `OPENAI_API_KEY` when present. If no key is set, it sends `EMPTY` as the bearer token, which works for many local OpenAI-compatible servers.

```bash
export OPENAI_API_KEY=sk-your-key
./rag_benchmark.sh --endpoint http://127.0.0.1:8000/v1 --model your-model-id
```

Or pass a key directly:

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --api-key sk-your-key
```

For local servers that ignore authentication:

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --api-key EMPTY
```

## WSL2 notes

If the model server is running inside WSL2, `127.0.0.1` usually works:

```bash
./rag_benchmark.sh --endpoint http://127.0.0.1:8000/v1 --model your-model-id --quick
```

If the model server is running on Windows and the script is running inside WSL2, use the Windows host IP visible from WSL2:

```bash
WIN_HOST_IP="$(awk '/nameserver/ {print $2; exit}' /etc/resolv.conf)"

./rag_benchmark.sh \
  --endpoint "http://${WIN_HOST_IP}:8000/v1" \
  --model your-model-id \
  --quick
```

## Install behavior

By default, the script creates a persistent virtual environment under:

```text
~/.cache/rag_benchmark/venv
```

It also uses a cache directory under:

```text
~/.cache/rag_benchmark/cache
```

Default installed Python packages:

```text
numpy
faiss-cpu
```

Bootstrap packages:

```text
pip
setuptools
wheel
```

To use your current Python environment instead:

```bash
./rag_benchmark.sh \
  --no-install \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --quick
```

To change the persistent state directory:

```bash
./rag_benchmark.sh \
  --state-dir ~/.cache/my_rag_benchmark \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id
```

To change only the virtualenv location:

```bash
./rag_benchmark.sh \
  --venv-dir ./.venv-ragbench \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id
```

## Example benchmark profiles

### Quick smoke run

Good for verifying endpoint compatibility and TUI flow.

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --quick
```

### Standard local run

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --db-sizes 50000,100000 \
  --batch-queries 1000 \
  --runs 5 \
  --rag-workers 4 \
  --rag-runs 3 \
  --rag-queries-per-worker 10 \
  --rag-db-size 10000
```

### Larger retrieval run

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --db-sizes 100000,200000 \
  --batch-queries 3000 \
  --runs 10 \
  --rag-workers 8 \
  --rag-runs 5 \
  --rag-queries-per-worker 20 \
  --rag-db-size 20000 \
  --top-k 10
```

### Force FAISS HNSW

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --index-backend faiss
```

### Force NumPy fallback

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --index-backend numpy
```

### Non-streaming endpoint

If your endpoint does not support streamed chat completions:

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --no-stream
```

When `--no-stream` is used, TTFT is reported as total request latency because there is no first streamed token event.

## Corpus and licensing

The default corpus is synthetic and generated locally by the script. It does not download third-party database text.

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --corpus synthetic
```

You can run the built-in license audit:

```bash
./rag_benchmark.sh --license-audit
```

The built-in audit reports the default direct dependency/corpus posture:

| Component | License posture |
|---|---|
| `rag_benchmark.sh` | MIT |
| Synthetic RAG corpus | Generated locally; MIT-compatible fixture; no third-party source text |
| Python runtime | PSF-2.0 |
| `pip` | MIT |
| `setuptools` | MIT |
| `wheel` | MIT |
| NumPy | BSD-3-Clause |
| FAISS / `faiss-cpu` | MIT |
| OpenBLAS, where bundled by wheels | BSD-3-Clause |

This is engineering metadata, not legal advice. Packages supplied through `--extra-pip`, the operating system, shell, curl, system libraries, and user-provided corpora are outside the built-in audit.

## Local JSONL corpus

A local JSONL corpus is supported, but the script requires an explicit permissive license declaration.

Each line should contain a text field. By default, the field is `text`:

```jsonl
{"text":"The retrieval document text goes here."}
{"text":"Another retrieval document goes here."}
```

Run with:

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --corpus local-jsonl \
  --corpus-file ./my_corpus.jsonl \
  --corpus-license MIT
```

Use a different text key:

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --corpus local-jsonl \
  --corpus-file ./my_corpus.jsonl \
  --jsonl-text-key body \
  --corpus-license Apache-2.0
```

Accepted local corpus license labels include:

```text
MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, 0BSD, Zlib,
Unlicense, Public-Domain, CC0-1.0, CC-BY-3.0, CC-BY-4.0, PSF-2.0
```

Rejected by default:

```text
GPL family, AGPL, LGPL, CC-BY-SA, CC-BY-NC, proprietary, unknown/no license
```

## Output JSON

The script prints the benchmark dashboard in the terminal and writes a JSON result file.

Specify the output path:

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --output ./results/my_run.json
```

The JSON includes:

```text
schema_version
benchmark
version
created_utc
system
endpoint
corpus
embeddings
license_audit
config
benchmarks.index_build
benchmarks.vector_search
benchmarks.rag
output_path
```

The RAG section includes completed requests, errors, requests/sec, approximate tokens/sec, chars/sec, TTFT latency, total latency, retrieval latency, per-run throughput, and sampled errors.

## CLI reference

### Bootstrap options handled by Bash

| Option | Description |
|---|---|
| `--tui` | Force the interactive terminal wizard. |
| `--no-install` | Do not create or use a virtualenv and do not install packages. |
| `--venv-dir DIR` | Virtualenv directory. Default: `$RAGBENCH_HOME/venv`. |
| `--state-dir DIR` | Cache and venv root. Default: `~/.cache/rag_benchmark`. |
| `--extra-pip "PKGS"` | Extra packages appended to the default pip install. User-selected packages are not covered by the built-in license audit. |
| `--plain` | Disable colors and live terminal styling. |
| `-h`, `--help` | Show Bash-level help. |

### Benchmark options passed to Python

| Option | Default | Description |
|---|---:|---|
| `--endpoint URL` | none | OpenAI-compatible base URL, with or without `/v1`. |
| positional endpoint | none | Endpoint may also be supplied as the first positional argument. |
| `--api-key KEY` | `OPENAI_API_KEY` or `EMPTY` | Bearer token sent to the endpoint. |
| `--model ID` | auto | Model ID. If omitted, the script tries `/v1/models`. |
| `--output FILE` | timestamped JSON | Output JSON file path. |
| `--cache-dir DIR` | `~/.cache/rag_benchmark/cache` | Corpus and embedding cache directory. |
| `--corpus synthetic` | `synthetic` | Use generated local corpus. |
| `--corpus local-jsonl` | `synthetic` | Use user-provided JSONL corpus. Requires `--corpus-file` and `--corpus-license`. |
| `--corpus-file FILE` | none | JSONL file path for local corpus. |
| `--corpus-license SPDX` | none | Required permissive license declaration for local corpus. |
| `--jsonl-text-key KEY` | `text` | Field containing text in each JSONL row. |
| `--refresh-embeddings` | off | Ignore cached embeddings and rebuild. |
| `--embedding-dim N` | `384` | Dimension for built-in hashing-vectorizer embeddings. |
| `--db-sizes LIST` | `100000,200000` | Comma-separated vector database sizes. |
| `--batch-queries N` | `3000` | Queries per vector-search run. |
| `--runs N` | `10` | Runs for vector search and index build. |
| `--trim FLOAT` | `0.05` | Fraction trimmed from each side when averaging repeated runs. |
| `--top-k N` | `10` | Retrieved chunks per RAG request. |
| `--hnsw-m N` | `32` | FAISS HNSW M parameter. |
| `--hnsw-ef N` | `64` | FAISS HNSW efSearch parameter. |
| `--hnsw-ef-construction N` | `200` | FAISS HNSW efConstruction parameter. |
| `--index-backend auto` | `auto` | Use FAISS when available, otherwise NumPy. |
| `--index-backend faiss` | `auto` | Require FAISS HNSW. |
| `--index-backend numpy` | `auto` | Use NumPy brute-force fallback. |
| `--threads N` | `0` | FAISS OMP threads. `0` uses CPU count. |
| `--rag-workers N` | `0` | Concurrent RAG workers. `0` means `min(cpu_count, 8)`. |
| `--rag-runs N` | `5` | Repeated concurrent RAG runs. |
| `--rag-queries-per-worker N` | `20` | RAG requests per worker per run. |
| `--rag-db-size N` | `10000` | Vector DB size used for RAG requests. |
| `--context-chars N` | `1200` | Maximum retrieved context characters placed in each prompt. |
| `--max-tokens N` | `80` | Max generation tokens per chat completion. |
| `--temperature FLOAT` | `0.0` | Chat completion temperature. |
| `--request-timeout FLOAT` | `120.0` | Per-request timeout in seconds. |
| `--connect-timeout FLOAT` | `10.0` | HTTP connect/probe timeout in seconds. |
| `--cooldown FLOAT` | `2.0` | Sleep between repeated benchmark runs. |
| `--no-stream` | off | Use non-streaming chat completions. |
| `--disable-nonstream-fallback` | off | Fail if streaming fails instead of retrying non-streaming. |
| `--fail-on-endpoint-error` | off | Abort on any RAG request failure. |
| `--skip-search` | off | Skip batch vector-search benchmark. |
| `--skip-build` | off | Skip index-build benchmark. |
| `--skip-rag` | off | Skip concurrent RAG benchmark. |
| `--quick` | off | Use smaller sizes and fewer runs for smoke testing. |
| `--self-test` | off | Run against a local mock endpoint. |
| `--license-audit` | off | Print dependency/corpus license posture and exit. |
| `--plain` | off | Disable ANSI styling/live updates. |

## Environment variables

| Variable | Description |
|---|---|
| `RAG_ENDPOINT` | Used as `--endpoint` when no endpoint argument is supplied. |
| `RAG_MODEL` | Used as `--model` when no model argument is supplied. |
| `OPENAI_API_KEY` | Used as bearer token unless `--api-key` is supplied. |
| `RAGBENCH_HOME` | Cache root for `curl | bash` runs. Default: `~/.cache/rag_benchmark`. |
| `RAGBENCH_VENV_DIR` | Overrides virtualenv directory. |
| `OPENAI_BASE_URL` | Used by the TUI as an initial endpoint value when `RAG_ENDPOINT` is unset. |
| `OPENAI_MODEL` | Used by the TUI as an initial model value when `RAG_MODEL` is unset. |

## GitHub usage notes

For a public README, replace `user` in the examples with your GitHub owner or organization:

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/rag_benchmark/main/rag_benchmark.sh | bash
```

For reproducible usage, prefer pinning to a tag or commit SHA:

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/rag_benchmark/<tag-or-commit>/rag_benchmark.sh | bash
```

For security-sensitive environments, inspect the script before executing it:

```bash
curl -fsSL https://raw.githubusercontent.com/<owner>/rag_benchmark/main/rag_benchmark.sh -o rag_benchmark.sh
less rag_benchmark.sh
bash rag_benchmark.sh --self-test
```

## Troubleshooting

### `python3 is required`

Install Python and venv support inside WSL2:

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip
```

### Endpoint probe fails

Check that your server is reachable from the same shell:

```bash
curl http://127.0.0.1:8000/v1/models
```

If `/v1/models` is unsupported, pass the model explicitly:

```bash
./rag_benchmark.sh --endpoint http://127.0.0.1:8000/v1 --model your-model-id
```

### Streaming fails

Some OpenAI-compatible servers do not implement streaming exactly like OpenAI. Try non-streaming mode:

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --no-stream
```

### FAISS installation fails

Use the NumPy backend:

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --index-backend numpy
```

For full HNSW index-build/search metrics, install or enable `faiss-cpu` and use:

```bash
./rag_benchmark.sh \
  --endpoint http://127.0.0.1:8000/v1 \
  --model your-model-id \
  --index-backend faiss
```

### `curl | bash` does not open the TUI

The TUI requires an interactive terminal attached to `/dev/tty`. In CI or non-interactive shells, pass arguments explicitly:

```bash
curl -fsSL https://raw.githubusercontent.com/user/rag_benchmark/main/rag_benchmark.sh | \
  bash -s -- --endpoint http://127.0.0.1:8000/v1 --model your-model-id --quick --plain
```

### Local Windows server is unreachable from WSL2

Use the Windows host IP from WSL2:

```bash
WIN_HOST_IP="$(awk '/nameserver/ {print $2; exit}' /etc/resolv.conf)"
curl "http://${WIN_HOST_IP}:8000/v1/models"
```

Then use the same host in the benchmark endpoint.

## Repository layout

Suggested minimal repository:

```text
rag_benchmark/
├── README.md
├── LICENSE
└── rag_benchmark.sh
```

## License

`rag_benchmark.sh` is marked with:

```text
SPDX-License-Identifier: MIT
```

Add an MIT `LICENSE` file to the repository if you publish this project as MIT.

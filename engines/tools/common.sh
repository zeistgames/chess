# SPDX-License-Identifier: AGPL-3.0-or-later
# Sourced by engines/<id>/build.sh. Sets paths and helpers.
set -euo pipefail

ENGINES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ID="$(basename "$(cd "$(dirname "$0")" && pwd)")"
SRC_DIR="$ENGINES_DIR/$ID"
WORK="$ENGINES_DIR/build/$ID"
# Packs are written to a staging folder and checked there. tools/promote.sh
# moves a pack into dist/ only after both checks pass.
OUT="$ENGINES_DIR/build/$ID/pack"
mkdir -p "$WORK"

# The Emscripten version every port is built with.
EMSDK_VERSION="6.0.9"

log() { printf '[%s] %s\n' "$ID" "$*" >&2; }

# fetch URL SHA256 DEST: download once, verify the hash every time.
fetch() {
  local url="$1" sum="$2" dest="$3"
  if [ ! -f "$dest" ] || ! echo "$sum  $dest" | shasum -a 256 -c - >/dev/null 2>&1; then
    log "fetch $url"
    curl -fsSL --retry 3 -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
  fi
  echo "$sum  $dest" | shasum -a 256 -c - >/dev/null || { log "sha256 mismatch for $dest"; exit 1; }
}

# git_checkout URL COMMIT DIR: shallow fetch of one pinned commit, reset clean.
git_checkout() {
  local url="$1" commit="$2" dir="$3"
  if [ ! -d "$dir/.git" ]; then
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
  fi
  if ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
    log "fetch $url at $commit"
    git -C "$dir" fetch -q --depth 1 origin "$commit"
  fi
  git -C "$dir" -c advice.detachedHead=false checkout -q -f "$commit"
  git -C "$dir" clean -qfdx
  git -C "$dir" submodule -q update --init --depth 1 --recursive 2>/dev/null || true
}

# apply_patches DIR: apply engines/<id>/patches/*.patch in order.
apply_patches() {
  local dir="$1" p
  for p in "$SRC_DIR"/patches/*.patch; do
    [ -e "$p" ] || continue
    log "patch $(basename "$p")"
    git -C "$dir" apply --whitespace=nowarn "$p"
  done
}

# use_emsdk: put Emscripten on PATH. EMSDK may point at an emsdk checkout.
use_emsdk() {
  if ! command -v emcc >/dev/null 2>&1; then
    local d="${EMSDK:-}"
    [ -f "$d/emsdk_env.sh" ] || { log "emsdk not found; set EMSDK to an emsdk checkout with $EMSDK_VERSION active"; exit 1; }
    # shellcheck disable=SC1091
    EMSDK_QUIET=1 source "$d/emsdk_env.sh" >/dev/null 2>&1
  fi
  emcc --version | head -1 | grep -q " $EMSDK_VERSION " || { log "need emcc $EMSDK_VERSION, found: $(emcc --version | head -1)"; exit 1; }
}

# start_pack: empty engines/dist/<id>/.
start_pack() { rm -rf "$OUT"; mkdir -p "$OUT"; }

# finish_pack: write manifest.json with computed sizes and hashes.
finish_pack() { node "$ENGINES_DIR/tools/pack.mjs" "$ID" "$OUT"; }

GLUE="$ENGINES_DIR/tools/glue"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || nproc)"

# Flags every port links with. The output is a dedicated-worker script that
# speaks UCI one line per message (see tools/glue/worker-pre.js).
EM_LDFLAGS_COMMON=(
  -O3 -msimd128
  -sENVIRONMENT=worker
  -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=67108864 -sMAXIMUM_MEMORY=2147483648
  -sSTACK_SIZE=16777216
  -sEXIT_RUNTIME=0 -sINVOKE_RUN=0 -sFORCE_FILESYSTEM=1
  -sEXPORTED_FUNCTIONS=_main,_zeist_uci
  -sEXPORTED_RUNTIME_METHODS=ccall,callMain,FS,addRunDependency,removeRunDependency
)

# em_compile OBJDIR "CXXFLAGS" SRC...: compile sources in parallel (C or C++ by extension).
em_compile() {
  local objdir="$1" flags="$2"; shift 2
  mkdir -p "$objdir"
  cat > "$objdir/.cc.sh" <<CC
#!/bin/sh
src="\$1"; obj="$objdir/\$(echo "\$src" | tr "/" "_").o"
case "\$src" in *.c) cc=emcc ;; *) cc=em++ ;; esac
exec \$cc $flags -c "\$src" -o "\$obj"
CC
  chmod +x "$objdir/.cc.sh"
  printf '%s\n' "$@" | xargs -n 1 -P "$JOBS" "$objdir/.cc.sh"
}

# em_link OUT_JS CONFIG_JS EXTRA_LDFLAGS... -- OBJS...: link a worker script.
# CONFIG_JS sets Module.zeistFiles / Module.zeistArgs.
em_link() {
  local out="$1" config="$2"; shift 2
  local extra=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do extra+=("$1"); shift; done
  shift
  emcc -O3 -c "$GLUE/zeist_glue.c" -o "$WORK/zeist_glue.o"
  em++ -O3 -c "$GLUE/zeist_flush.cpp" -o "$WORK/zeist_flush.o"
  em++ "${EM_LDFLAGS_COMMON[@]}" ${extra[@]+"${extra[@]}"} \
    --pre-js "$config" --pre-js "$GLUE/worker-pre.js" \
    "$@" "$WORK/zeist_glue.o" "$WORK/zeist_flush.o" -o "$out"
}

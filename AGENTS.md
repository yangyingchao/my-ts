# my-ts — tree-sitter parser collection for Emacs

Monorepo of tree-sitter grammar submodules, built as shared libraries for Emacs tree-sitter integration.

## Build

```sh
./build.sh            # build all parsers + core
./build.sh core       # tree-sitter C library only
./build.sh python     # single parser (any: bash/c/cpp/css/elisp/go/...)
```

Output: `~/.local/lib/libtree-sitter-<lang>.so` (or `.dylib`/`.dll`).

**Prerequisites**: `gcc`/`g++`, standard C toolchain.

**Special parser names** (mapped internally by `build.sh`):

| arg        | builds                          |
| ---------- | ------------------------------- |
| `go-mod`     | `gomod`                           |
| `php`        | `php` (from `tree-sitter-php/php/`) |
| `typescript` | both `typescript` + `tsx`           |
| `markdown`   | both `markdown` + `markdown-inline` |

## Add / update parsers

```sh
./build.sh -a <git-url>   # add submodule + build
./build.sh -u             # update all submodules to latest tag
```

## Emacs awareness

Build script detects `INSIDE_EMACS` — if set, new `.so` gets `_new` suffix to avoid in-use library crash. Rename after Emacs restarts.

## Structure

- `tree-sitter/` — core C library submodule (upstream)
- `tree-sitter-<lang>/` — per-parser submodule
- `build.sh` — build orchestrator
- `yc_build_env.sh` — optional env overrides, sourced by `build.sh`

## No test infra at repo level

No CI, no package.json, no formatter/linter config at root. Each submodule has its own tests upstream — repo is about building and installing only.

# clui — Development Guidelines

## Design philosophy

### 1. LEGO composability

clui components are small, single-purpose, and composable — like LEGO bricks.
Each source file in `src/` provides one concern (screen, input, draw, widgets).
Widgets are built from primitives, not monoliths.

**Rules:**
- Every widget must work standalone when given only the primitives it depends on.
- Widgets must not call other widgets (no implicit coupling between peers).
- New components go in `src/widgets/` if they are interactive, `src/` if primitive.
- Document every public function's inputs, outputs, and globals in the source file.

Future direction: support a YAML-based widget composition format (`.clui.yaml`)
that declares UI layouts as includes of named components, so callers can assemble
UIs declaratively and source only what they need.

### 2. Full-featured UI library, not just primitives

clui should cover the full lifecycle of gathering and using input from humans:

- **Input gathering**: prompts, free-text fields, password fields, confirmations
- **Selection**: single-select lists, multi-select lists, action-lists
- **Feedback**: progress bars, spinners, status lines, banners
- **Navigation**: paged lists, tabbed views, modal dialogs
- **Output**: formatted tables, colored text, column layout

Every widget maps directly to a data shape: a list widget yields an array index,
a prompt yields a string, a multi-select yields a set of flags. The caller gets
clean data, not screen output.

### 3. Two audiences, one library

**Human users** (people running tools built with clui):
- Keyboard behavior must be predictable and documented in every widget's footer.
- Arrow keys, Enter, Space, Tab, `q` must work as expected everywhere.
- No surprise terminal state left behind on exit or Ctrl-C.

**Developer users** (PHP/bash tools that `source` or shell-out to clui):
- Every widget returns a predictable exit code (0 = confirmed, 1 = cancelled).
- Return values go to stdout; UI rendering goes to `/dev/tty`.
- Globals follow the `CLUI_<WIDGET>_*` naming convention so they namespace cleanly.
- The library must be sourceable with no side effects until a function is called.

### 4. Self-configuration and portability

clui auto-detects the runtime environment on first load and writes a local
config file (`.toolrc.local` in the project root, gitignored) so settings are
computed once and reused.

**On load, clui detects and persists:**
- Bash version (affects `read -t` precision, fd allocation syntax, `printf` behavior)
- Whether `{var}` fd allocation is available (bash 4.1+; macOS has 3.2)
- Whether `read -t` accepts decimals (bash 4+; 3.2 requires integers)
- Terminal capabilities (`tput` availability, `$TERM` value)

**Feature flags written to `.toolrc.local`:**
```bash
CLUI_BASH_VERSION=3      # major version
CLUI_FD_ALLOC=0          # 1 if {varname}>&1 syntax works
CLUI_READ_DECIMAL_T=0    # 1 if read -t 0.1 works
CLUI_TPUT_OK=1           # 1 if tput is functional
```

These flags are sourced by `clui.sh` at load time. Individual functions check
them to select the right code path rather than duplicating version detection.

### 5. Docker-based cross-version test suite

To ensure portability across bash versions, clui includes a Docker-based driver
suite that runs the test suite against multiple bash versions:

```
tests/
└── docker/
    ├── run-matrix.sh        # runs tests against all image tags
    ├── Dockerfile.bash3     # FROM bash:3.2 (simulates macOS)
    ├── Dockerfile.bash4     # FROM bash:4.4
    └── Dockerfile.bash5     # FROM bash:5.2
```

Run with: `bash tests/docker/run-matrix.sh`

Each container mounts the repo and runs `tests/run.sh`. A failure in any
version is a bug. The matrix must pass before merging changes to `src/`.

## Coding conventions

- All public symbols are prefixed `clui_` (functions) or `CLUI_` (globals/constants).
- Internal helpers are prefixed `_clui_` and must not be called by consumers.
- Use `local` for all function-scoped variables. Never pollute the caller's scope.
- Use `printf` for all output; never bare `echo` (behavior varies across systems).
- For bash 3.2 compatibility:
  - Use `$'\n'` not `"\n"` in comparisons.
  - Use integer `-t` values with `read`.
  - Use explicit fd numbers (3, 4…), not `{varname}` fd allocation.
  - Use `$(...)` not `<<<` when bash 3.2 `herestring` behavior matters.
- Always restore terminal state (`stty`, cursor, alternate screen) in an EXIT trap.

## Gitignore

`.toolrc.local` must be gitignored — it is per-machine, not per-repo.

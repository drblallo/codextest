# Rulebook (`rlc`) compiler field guide

Use this file when implementing or reviewing games in this repository. It is a
practical compiler-focused summary of the official Rulebook documentation at
<https://rl-language.github.io/> (consulted 2026-09-04) and the locally
installed `rlc` 0.4.12 toolchain. Prefer the installed compiler's diagnostics
when the website and the installed version disagree.

## Scope and mental model

- Rulebook source files use the `.rl` extension. The language is compiled,
  statically checked, indentation-sensitive, and deliberately resembles Python
  in layout but not in all syntax.
- Put ordinary calculations and data manipulation in `fun` functions. Put an
  interactive game sequence in an `act` function.
- An action function is a resumable coroutine and declares its resulting state
  type: `act play() -> Game:` creates a `Game` state. Calling `play()` runs up to
  the first available action; invoking an action resumes it to the next action
  or completion.
- An `act move(...)` statement is a suspension/input point, not a conventional
  function declaration. Its optional `{ condition }` is the legality rule.
  Check it with `can game.move(...)` before applying it. `game.is_done()` tests
  whether the sequence has ended.
- The host/game engine owns the main loop. Rulebook should describe the game
  rules synchronously, expose legal actions and state, and avoid embedding UI,
  rendering, or input polling into the rules.

## First commands to run

```bash
command -v rlc
rlc --version
rlc --help
command -v rlc-test rlc-random rlc-action
```

The pip installation in this environment supplies all four helper tools. For
the exact flags supported by this installed build, trust each command's
`--help`; the online documentation can describe a newer or older build.

## Minimal compile/run loop

```rlc
# hello.rl
import serialization.print

fun main() -> Int:
    print("hello")
    return 0
```

```bash
rlc hello.rl -o hello       # compile and link a native executable
./hello
rlc --format hello.rl       # writes formatted source to stdout; inspect first
rlc --format hello.rl > hello.formatted.rl
```

Useful compiler outputs and flags:

```bash
rlc game.rl -o game                    # executable (requires main)
rlc game.rl -o game.o --compile        # object/static output, no link
rlc game.rl -o libgame.so --shared     # shared library, no main symbol
rlc game.rl --header -o game.h         # generated C ABI header
rlc game.rl --python -o game.py        # generated Python wrapper
rlc game.rl -O2 -o game                # optimized; runtime checks disabled
rlc game.rl -g --sanitize -o game_dbg  # debugging/sanitizer build
rlc game.rl -i path/to/modules -o game # add an import search directory
```

During development, do **not** default to `-O2`: unoptimized compilation emits
array-bound and precondition checks. `-O2` disables those checks unless they
are explicitly requested with `--emit-bound-checks` and
`--emit-precondition-checks`. Never rely on calling an illegal action merely
because optimized code does not abort.

Imports omit `.rl` and use dotted paths, for example
`import collections.vector`, `import serialization.print`, `import action`,
and `import bounded_arg`. Imports are recursive. Use
`rlc game.rl --print-included-files --hide-standard-lib-files` when resolving
an unexpected import.

## Core syntax quick reference

```rlc
import bounded_arg

const BOARD_SIZE = 9

enum Player:
    x
    o

cls Board:
    Int[BOARD_SIZE] cells
    Bool finished

fun add(Int left, Int right) -> Int:
    return left + right

fun first_cell(Board board) -> ref Int:
    return board.cells[0]
```

- Primitive types include `Int` (signed 64-bit), `Float` (64-bit), `Byte`,
  `Bool`, and `StringLiteral`. Standard-library types include owned `String`
  (`"text"s`) and `Vector<T>`.
- Fixed arrays are `T[N]`; initialize ordinary declarations with `let x: T`.
  Default initialization recursively initializes members. If defining a custom
  `init`, the type is responsible for initializing its fields, so avoid a
  custom initializer unless it is needed and verified by compilation/tests.
- Bounded types such as `BInt<0, 9>` represent an enumerable range with an
  exclusive upper bound and expose the integer as `.value`. Import
  `bounded_arg` explicitly. Prefer bounded/enumerable action parameters for
  board positions, choices, dice, cards, and other finite inputs.
- Alternatives use `A | B` and can be narrowed with `if value is A:`. Enums are
  referenced as `Player::x` and expose `.value`.
- Function arguments are written type-first and are already passed by reference;
  do not prefix an argument type with `ref`. A return
  is copied unless its type is marked `ref`. Functions and methods use `fun`;
  declarations are `let value = expression` or `let value: Type`; references
  use `ref value = reference_expression`.
- Control flow includes `if`/`else`, `while`, `for value in range(...)`,
  `break`, and `continue`. Boolean operators are `and`, `or`, and `!`.
- Names beginning with `_` are file-private. Prefer small pure helper functions
  for board queries, win detection, scoring, and transformations.

## A game-shaped example

```rlc
import bounded_arg

cls Board:
    Int[9] cells
    Int current_player

    fun full() -> Bool:
        let index = 0
        while index != 9:
            if self.cells[index] == 0:
                return false
            index = index + 1
        return true

@classes
act play() -> Game:
    frm board: Board
    while !board.full():
        act mark(BInt<0, 9> cell) {
            board.cells[cell.value] == 0
        }
        board.cells[cell.value] = board.current_player + 1
        board.current_player = 1 - board.current_player
```

Design rules:

1. Use the conventional entry point `act play() -> Game` so generic game tools
   such as `rlc-random` can discover the program.
2. Put persistent or externally inspectable coroutine data in `frm` variables.
   Any local used across suspension points must be `frm`; compiler diagnostics
   will normally identify omissions. `frm` action arguments also become state.
3. Put every legality constraint in the action precondition: turn ownership,
   bounds beyond the type's bounds, occupancy, resources, and phase rules.
   Do not include an action argument when it is already determined by frame
   state. For example, a two-player `place` action should use
   `current_player` rather than accepting a caller-controlled player ID.
4. Return from the action function when a win, loss, draw, or other terminal
   condition is reached. Otherwise `is_done()` will remain false.
5. Make action parameters finite whenever possible. Generic enumeration,
   exhaustive exploration, random play, and fuzzing work best when every input
   has a finite representation.
6. Add `@classes` when actions must be first-class values for enumeration,
   trace storage/replay, fuzzing, or host integration. It generates one class
   per action and an alternative such as `AnyGameAction`; `can apply(action,
   state)` and `apply(action, state)` then provide generic dispatch. Import
   `action` for the supporting helpers.

### Treat decoded actions as untrusted input

Static types constrain normal Rulebook code, but action values reconstructed
from arbitrary serialized bytes can contain invalid raw enum values or invalid
`.value` fields inside bounded integers. A `can apply(...)` call is only safe
when its precondition validates those representations **before** using them as
array indices or dispatch values.

```rlc
fun valid_cell(BInt<0, 10> cell) -> Bool:
    return cell.value >= 0 and cell.value < 10

fun valid_piece(Piece piece) -> Bool:
    return piece.value >= 0 and piece.value < NUM_PIECES

fun can_select(Board board, Piece piece, BInt<0, 10> cell) -> Bool:
    if !valid_piece(piece) or !valid_cell(cell):
        return false
    return board.cells[cell.value] == 0
```

Keep these checks at the start of the helper called by the action precondition.
Short-circuiting `or`/`and` then prevents unsafe indexing. Add a deterministic
regression test that manually assigns malformed `.value` fields as well as a
fuzz campaign; bounded types alone are not a serialization trust boundary.

## State ownership and composition

- `frm T value` is copied into the generated action-state object. It survives
  suspension and is inspectable (for example `game.board`). Keep game-rule
  state here using copyable/default-constructible values.
- `ctx T value` remains outside the action state. It must normally be supplied
  on subsequent action calls. Use it for non-copyable engine-owned context or
  intentionally shared state, not routine game data.
- Use `subaction* child = other_sequence(...)` to expose all of a nested action
  sequence's actions until that child completes. This is the principal way to
  build a large game from reusable phases (setup, turn, combat, scoring).
- Use `subaction child` (without `*`) when only one inner action should execute
  before the outer sequence resumes. Multiple child states may be listed when
  actions from several sequences should be concurrently available.
- Context forwarding can be written on subactions when nested sequences share
  caller-owned data. Compile a tiny isolated example before relying on advanced
  `ctx`/subaction syntax because this area has evolved between releases.

## Testing workflow

### Fast deterministic tests

`rlc-test` discovers every no-argument function whose name starts with `test_`
and whose return type is `Bool`:

```rlc
fun test_first_move() -> Bool:
    let game = play()
    let cell: BInt<0, 9>
    cell.value = 3
    if !(can game.mark(cell)):
        return false
    game.mark(cell)
    return game.board.cells[3] == 1 and !(can game.mark(cell))
```

```bash
rlc-test game.rl
```

Test the happy path, rejected moves through `can`, phase transitions, every
terminal outcome, and state visible after each action. Never apply an action
known to be invalid: debug builds abort on failed preconditions. Use `assert`
inside rules for invariants that must hold for every valid trace; return
`false` from `test_*` for ordinary test expectations.

Put a short semantic comment immediately above each `test_*` function. State
the rule being proved and the important expected transition—not a line-by-line
translation of the test. This makes a failing test useful to someone who does
not yet know the game and helps reviewers notice when an assertion does not
match its intended rule.

### Compile and static diagnostics

```bash
rlc game.rl -o /tmp/game-check
rlc --type-checked game.rl > /tmp/game.typechecked
rlc --dot game.rl > /tmp/game.dot
rlc --graph game.rl > /tmp/game.graph
```

`--token`, `--unchecked`, `--type-checked`, `--after-implicit`, `--flattened`,
`--rlc`, `--mlir`, and `--ir` expose progressively lower compiler stages.
`--dot` visualizes action control flow, while `--graph` emits a
machine-readable action graph. Add `--graph-filter=<name>` to focus on one
action and `--graph-only-actions` to remove ordinary functions.

### Random and trace-based game testing

```bash
rlc-random game.rl > trace.txt
rlc-action game.rl trace.txt
rlc-action game.rl trace.txt --print-all
rlc-action game.rl - --show-actions
```

`rlc-random` expects `act play() -> Game` and enumerable action statements. It
chooses valid actions until the program ends and prints a replayable trace.
Therefore ensure the game always terminates (or use a shell timeout while
developing). `rlc-action` applies a trace and can list available actions;
consult `rlc-action --help` for state load/save and pretty-print flags.

Keep checked-in golden traces strict: include action lines only and replay them
without `--ignore-invalid`. Use `--print-all` to confirm the number of accepted
actions matches the number of trace lines. A trace should cover setup, normal
transitions, and a terminal outcome, not merely prove that actions parse.

### Fuzzing and exhaustive exploration

- For generic fuzzing, annotate the action function with `@classes`, import
  `action`, and expose the following target (replace `Game` if the generated
  state type has another name):

  ```rlc
  fun fuzz(Vector<Byte> input):
      if input.size() == 0:
          return
      let state = play()
      let action: AnyGameAction
      let parsed_actions = parse_actions(action, input)
      for current_action in parsed_actions:
          if can apply(current_action, state):
              apply(current_action, state)
  ```

  `actions` is a language keyword, so use a name such as `parsed_actions` for
  the local vector. Compile and run a bounded campaign with:

  ```bash
  rlc game.rl --fuzzer -o /tmp/game-fuzzer
  test -x /tmp/game-fuzzer
  /tmp/game-fuzzer -runs=100000 -max_len=4096 -timeout=10 \
      -print_final_stats=1
  ```

  Always replay a discovered artifact directly after fixing it, then start a
  fresh campaign. Do not report a successful fuzz run merely because compilation
  returned zero: verify that the executable exists, because some `rlc` linker
  failures have been observed to print missing-runtime errors without returning
  a failing status. If compiler-rt fuzzer/ASan libraries are missing, use a
  compatible Clang/compiler-rt installation rather than dropping sanitizer
  instrumentation.
- For a small finite game, use `enumerate(any_action)` on the generated
  `AnyGameAction`, copy each frontier state, and `apply` every legal action.
  This can exhaustively prove that no valid sequence reaches an assertion, but
  state growth is exponential. Keep exhaustive tests focused on small phases.
- Copying a Rulebook action state is intentional and useful: branch from a
  saved state to explore alternate moves. This also makes exact trace replay a
  preferred debugging method.

## Implementation checklist

1. Model data with `cls`, enums, fixed arrays, bounded integers, and small
   helpers; compile immediately after introducing each unfamiliar construct.
2. Write the smallest `act play() -> Game`, with explicit terminal returns and
   all persistent state marked `frm`.
3. Add preconditions and verify both allowed and rejected inputs with `can`.
   Validate raw enum and bounded values before indexing, and derive action
   parameters from frame state whenever possible.
4. Add commented deterministic `test_*() -> Bool` tests before adding more game
   phases.
5. Run `rlc-test`, compile an unoptimized executable, and inspect the action
   graph when control flow is unclear.
6. Run bounded random games and replay a trace with `rlc-action`.
7. Use `@classes` plus exhaustive or fuzzer testing for rule-heavy components;
   replay every crash artifact after its fix and run a fresh fuzz campaign.
8. Only then optimize with `-O2` or generate a shared library/wrapper for a
   host. Keep rendering and controller concerns outside the rulebook module.

## Common failure modes

- **`No known type named BInt`**: add `import bounded_arg`.
- **State disappears or the compiler requests promotion**: mark the local or
  action argument `frm` because it crosses an action boundary.
- **Action call aborts**: ask `can state.action(args)` first; inspect phase and
  precondition state. Do not suppress the check to hide a rules bug.
- **Fuzzer crashes inside a precondition**: validate deserialized enum and
  bounded `.value` fields before any array access. `can apply` invokes the
  precondition; it cannot protect unsafe operations performed by that
  precondition itself.
- **`--fuzzer` prints linker errors but the command appears successful**: check
  `test -x <output>`. Ensure the selected Clang has matching libFuzzer and ASan
  compiler-rt archives.
- **`rlc-random` cannot drive the game**: confirm the exact `play`/`Game`
  signature and replace unbounded action arguments (`Int`, arbitrary strings)
  with finite enums or bounded types.
- **Random play never exits**: add terminal conditions or a finite turn cap,
  and use `timeout` during diagnosis.
- **Optimized and debug behavior differ**: reproduce without `-O2`; optimized
  builds omit safety checks by default.
- **Formatter overwrites useful source**: `rlc --format` prints to stdout.
  Redirect to a temporary file, inspect the diff, then replace the source.
- **Documentation example does not compile**: check imports, run the smallest
  possible reproduction against installed 0.4.12, read the diagnostic, and
  prefer verified local syntax over copying a website snippet verbatim.

## Official references

- Documentation home: <https://rl-language.github.io/>
- Language tour: <https://rl-language.github.io/language_tour.html>
- Language/compiler reference:
  <https://rl-language.github.io/language-reference.html>
- Compiler and tool guide: <https://rl-language.github.io/rlc.html>
- Board-game design notes: <https://rl-language.github.io/board_games.html>
- Upstream compiler: <https://github.com/rl-language/rlc>

# Battleship example playout

`battleship.trace` is a complete, deterministic two-player game accepted by the
Rulebook action runner. Replay it from the repository root with:

```bash
rlc-action battleship.rl battleship.trace
```

The trace intentionally contains only actions—no prose or ignored invalid
lines—so the command fails immediately if any placement or shot violates the
game's action preconditions.

## What happens

1. Player one places a horizontal fleet in rows 0 through 4.
2. Player two places a vertical fleet in columns 0, 2, 4, 6, and 8.
3. Both players miss at `(9, 9)` and `(8, 8)`, demonstrating normal misses and
   turn alternation.
4. The players then exchange hits. Player one targets player two's vertical
   fleet while player two targets player one's horizontal fleet.
5. Player one hits `(1, 8)` on the final turn and sinks player two's last ship.
   Player two has only one ship segment remaining, making this a close but
   complete game rather than a one-sided synthetic victory.

The `place` actions do not contain a player identifier. During placement the
game's `current_player` selects the board being modified; completing player
one's fleet automatically advances placement to player two. After player two's
fleet is complete, the same state returns the turn to player one and enters the
battle phase.

Successful replay ends with these important fields in the printed `Game`:

```text
remaining_segments: [1, 0]
phase: 2
winner: 0
last_player: 0
last_row: 1
last_column: 8
last_hit: true
```

`resume_index: -1` and `phase: 2` show that the action function reached its
terminal state. `winner: 0` identifies player one, and player two's zero
remaining segments explains why the game ended.

To see every accepted action numbered as it is applied, run:

```bash
rlc-action battleship.rl battleship.trace --print-all
```

## Fuzzing

The game includes a `fuzz(Vector<Byte>)` entry point that decodes arbitrary
input into generated `AnyGameAction` values, checks each action with `can
apply`, and applies only legal actions. Build and run it with:

```bash
rlc battleship.rl --fuzzer -o battleship-fuzzer
./battleship-fuzzer -runs=100000 -max_len=4096 -timeout=10
```

Action values decoded from arbitrary bytes can contain malformed enum or
coordinate representations. The placement and firing preconditions validate
those representations before using them as array indices.

# Catan Rulebook implementation

`catan.rl` is a four-player, engine-driven implementation of the Catan base
rules on a generated standard 19-hex island. It models the full 54-intersection,
72-path graph rather than embedding presentation concerns in the rules.

## Flow

The `play() -> Game` action first exposes `configure(player_count)` for three
or four players, then generates the island and uses the official snake setup order
(0, 1, 2, 3, 3, 2, 1, 0). Each settlement is immediately followed by an
incident road, and the second settlement awards adjacent starting resources.
Board generation exposes one finite choice at a time: all 19 terrain tiles are
shuffled into the island using the official 3/4/4/4/3 plus desert inventory,
18 number tokens are placed with official multiplicities, no adjacent red
6/8 tokens, and forward checking that rejects choices which could strand the
remaining red tokens. Four generic plus five resource harbors are shuffled
across nine distinct coastal frame locations. The desert receives no token and starts
with the robber.

A normal turn then exposes:

1. `roll(first, second)` for production or robber activation;
2. `discard(resource)` as many times as required after a seven;
3. `move_robber(destination, victim, stolen)`; and
4. an `actions` block exposing `build_road`, `build_settlement`, `build_city`,
   `buy_development`, `maritime_trade`, `play_knight`, and `end_turn`.

For a robber move with no eligible victim, pass the current player as `victim`.
`play_knight(destination, victim, stolen)` names only its actual decisions; each
other turn alternative likewise has its own action and purpose-specific finite
arguments. There is no caller-selected command tag or unused payload.

## Generation validation

Every generation action checks the remaining physical-component inventory. A
completed island is additionally checked by `valid_generated_board` for exact
terrain, token, desert, robber, and harbor inventories; valid production values;
red-number separation; matching harbor endpoints; and coastal harbor edges.
Player setup cannot begin unless this complete-board invariant holds.

## Implemented rules

- official piece limits, building costs, connectivity, and distance rule;
- settlement/city production and robber blocking;
- mandatory half-hand discards on seven;
- robber adjacency and resource ownership checks;
- 4:1 bank, 3:1 generic harbor, and 2:1 resource harbor trades;
- development-card purchase delay and one playable card per turn;
- Largest Army transfer and its two-point bonus;
- ten-point victory during the active player's turn;
- malformed enum and bounded-value rejection in preconditions; and
- generated action classes plus a serialized-action fuzz target.

The development deck is intentionally represented as opaque usable cards in
this rules-layer API: a usable card can be played as a knight, while victory
cards can be assigned by a scenario/deck host through the visible player state.
Domestic trades are negotiated by the host and can likewise be reflected in
resource state; the rules module directly validates deterministic bank trades.

## Minimal action arguments

Actions accept only decisions the caller must make. In particular, the player
who must discard after a seven is derived from `discard_remaining` and the
configured player count, so `discard(resource)` does not accept a caller-chosen
owner. Setup ownership, the active builder, the robber-moving player, and turn
rotation are likewise derived internally.

## Class-oriented rules API

Operations whose behavior belongs to one model are methods on that model.
`Board` owns topology, placement legality, production, robber, harbor, and piece
count operations; `PlayerState` owns hand totals, payments, and point scoring.
Only cross-player coordination, bounded-value construction, generated-game
accessors, and action orchestration remain as free functions.

## Derived state

The action state stores authoritative facts only. Piece totals are calculated
with `road_count`, `settlement_count`, and `city_count` from board ownership;
`development_cards_left` calculates the deck size from player card zones; and
`largest_army_points` calculates its bonus from the retained award owner. The
setup player, pending setup intersection, active player, victory-point total,
and winner are likewise exposed as accessors instead of synchronized counters.

## Checks

```bash
rlc-test catan.rl
rlc catan.rl -o /tmp/catan.o --compile
rlc --type-checked catan.rl > /tmp/catan.typechecked
rlc --graph catan.rl --graph-only-actions > /tmp/catan.graph
rlc-action catan.rl catan.trace --print-all
rlc catan.rl --fuzzer --clang=/usr/bin/clang-19 -o /tmp/catan-fuzzer
/tmp/catan-fuzzer -runs=200000 -max_len=4096 -timeout=10 -print_final_stats=1
```

The checked-in `catan.trace` is a strict 196-action multi-round replay. It
covers four-player configuration, complete terrain/token/harbor generation, all
eight setup settlement/road pairs, eleven rounds of production and turn handoff,
two city upgrades, a harbor trade, road-network expansion, and a seven with
every mandatory derived-owner discard followed by a legal robber theft. Replay it
without `--ignore-invalid`; `--print-all` must report all 196 numbered actions.

The locally installed `rlc` emits LLVM 21 objects. This environment uses the
distribution's Clang 19 plus `libclang-rt-19-dev`; the compiler-rt fuzzer and
ASan archives are exposed at the LLVM 21 resource path expected by `rlc`.

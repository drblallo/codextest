import bounded_arg
import serialization.print
import action

const BOARD_WIDTH = 10
const BOARD_CELLS = 100
const FLEET_SIZE = 5
const FLEET_SEGMENTS = 17

using Row = BInt<0, BOARD_WIDTH>
using Column = BInt<0, BOARD_WIDTH>

enum Ship:
  carrier
  battleship
  cruiser
  submarine
  destroyer

enum Orientation:
  horizontal
  vertical

cls Board:
  # Zero means water; ship values are stored as Ship.value + 1.
  Int[BOARD_CELLS] ships
  Bool[BOARD_CELLS] shots
  Bool[FLEET_SIZE] placed

fun index(Int row, Int column) -> Int:
  return row * BOARD_WIDTH + column

fun ship_length(Ship ship) -> Int:
  if ship.value == Ship::carrier.value:
    return 5
  if ship.value == Ship::battleship.value:
    return 4
  if ship.value == Ship::cruiser.value:
    return 3
  if ship.value == Ship::submarine.value:
    return 3
  return 2

fun other_player(Int player) -> Int:
  return 1 - player

fun valid_ship(Ship ship) -> Bool:
  return ship.value >= 0 and ship.value < FLEET_SIZE

fun valid_orientation(Orientation orientation) -> Bool:
  return orientation.value == Orientation::horizontal.value or orientation.value == Orientation::vertical.value

fun valid_coordinate(BInt<0, 10> coordinate) -> Bool:
  return coordinate.value >= 0 and coordinate.value < BOARD_WIDTH

fun can_place_ship(Board board, Ship ship, BInt<0, 10> row, BInt<0, 10> column, Orientation orientation) -> Bool:
  if !valid_ship(ship) or !valid_orientation(orientation) or !valid_coordinate(row) or !valid_coordinate(column):
    return false
  if board.placed[ship.value]:
    return false

  let length = ship_length(ship)
  if orientation.value == Orientation::horizontal.value:
    if column.value + length > BOARD_WIDTH:
      return false
  else if row.value + length > BOARD_WIDTH:
    return false

  let offset = 0
  while offset != length:
    let target_row = row.value
    let target_column = column.value
    if orientation.value == Orientation::horizontal.value:
      target_column = target_column + offset
    else:
      target_row = target_row + offset
    if board.ships[index(target_row, target_column)] != 0:
      return false
    offset = offset + 1
  return true

fun place_ship(Board board, Ship ship, BInt<0, 10> row, BInt<0, 10> column, Orientation orientation):
  let length = ship_length(ship)
  let offset = 0
  while offset != length:
    let target_row = row.value
    let target_column = column.value
    if orientation.value == Orientation::horizontal.value:
      target_column = target_column + offset
    else:
      target_row = target_row + offset
    board.ships[index(target_row, target_column)] = ship.value + 1
    offset = offset + 1
  board.placed[ship.value] = true

fun fleet_is_placed(Board board) -> Bool:
  let ship = 0
  while ship != FLEET_SIZE:
    if !board.placed[ship]:
      return false
    ship = ship + 1
  return true

fun cell_has_ship(Board board, Int row, Int column) -> Bool:
  return board.ships[index(row, column)] != 0

fun cell_was_shot(Board board, Int row, Int column) -> Bool:
  return board.shots[index(row, column)]

fun can_fire_at(Board board, BInt<0, 10> row, BInt<0, 10> column) -> Bool:
  if !valid_coordinate(row) or !valid_coordinate(column):
    return false
  return !board.shots[index(row.value, column.value)]

@classes
act play() -> Game:
  frm boards : Board[2]
  frm remaining_segments : Int[2]
  frm current_player = 0
  # Phases: 0 is fleet placement, 1 is battle, and 2 is finished.
  frm phase = 0
  frm winner = -1
  frm last_player = -1
  frm last_row = -1
  frm last_column = -1
  frm last_hit = false

  while !fleet_is_placed(boards[0]) or !fleet_is_placed(boards[1]):
    act place(Ship ship, BInt<0, 10> row, BInt<0, 10> column, Orientation orientation) { can_place_ship(boards[current_player], ship, row, column, orientation) }

    place_ship(boards[current_player], ship, row, column, orientation)
    remaining_segments[current_player] = remaining_segments[current_player] + ship_length(ship)
    if fleet_is_placed(boards[current_player]):
      current_player = other_player(current_player)

  phase = 1
  while true:
    act fire(BInt<0, 10> row, BInt<0, 10> column) { can_fire_at(boards[other_player(current_player)], row, column) }

    let target_player = other_player(current_player)
    let target_index = index(row.value, column.value)
    boards[target_player].shots[target_index] = true
    last_player = current_player
    last_row = row.value
    last_column = column.value
    last_hit = boards[target_player].ships[target_index] != 0

    if last_hit:
      remaining_segments[target_player] = remaining_segments[target_player] - 1
      if remaining_segments[target_player] == 0:
        winner = current_player
        phase = 2
        return
    current_player = target_player

fun make_row(Int value) -> BInt<0, 10>:
  let result : Row
  result.value = value
  return result

fun make_column(Int value) -> BInt<0, 10>:
  let result : Column
  result.value = value
  return result

fun place_standard_fleet(Game game):
  game.place(Ship::carrier, make_row(0), make_column(0), Orientation::horizontal)

  game.place(Ship::battleship, make_row(1), make_column(0), Orientation::horizontal)

  game.place(Ship::cruiser, make_row(2), make_column(0), Orientation::horizontal)

  game.place(Ship::submarine, make_row(3), make_column(0), Orientation::horizontal)

  game.place(Ship::destroyer, make_row(4), make_column(0), Orientation::horizontal)

fun ready_game(Game game):
  place_standard_fleet(game)
  place_standard_fleet(game)

# The classic fleet must occupy 17 cells: carrier 5, battleship 4,
# cruiser 3, submarine 3, and destroyer 2.
fun test_ship_lengths() -> Bool:
  return ship_length(Ship::carrier) == 5 and ship_length(Ship::battleship) == 4 and ship_length(Ship::cruiser) == 3 and ship_length(Ship::submarine) == 3 and ship_length(Ship::destroyer) == 2

# Board coordinates use row-major storage, including both corner cells.
fun test_board_indexing() -> Bool:
  return index(0, 0) == 0 and index(3, 7) == 37 and index(9, 9) == 99

# A fresh game starts with player one placing ships, no winner, and an
# unfinished action sequence.
fun test_new_game_is_in_placement_phase() -> Bool:
  let game = play()
  return game.phase == 0 and game.current_player == 0 and game.winner == -1 and !game.is_done()

# A legal horizontal destroyer occupies exactly two adjacent cells, marks that
# ship as placed, and adds both segments to the active player's fleet total.
fun test_horizontal_placement_records_every_segment() -> Bool:
  let game = play()
  game.place(Ship::destroyer, make_row(4), make_column(5), Orientation::horizontal)

  return game.boards[0].ships[index(4, 5)] == Ship::destroyer.value + 1 and game.boards[0].ships[index(4, 6)] == Ship::destroyer.value + 1 and game.boards[0].placed[Ship::destroyer.value] and game.remaining_segments[0] == 2

# A legal vertical cruiser occupies three cells down one column and contributes
# three remaining segments to the active player's board.
fun test_vertical_placement_records_every_segment() -> Bool:
  let game = play()
  game.place(Ship::cruiser, make_row(5), make_column(8), Orientation::vertical)

  return game.boards[0].ships[index(5, 8)] == Ship::cruiser.value + 1 and game.boards[0].ships[index(6, 8)] == Ship::cruiser.value + 1 and game.boards[0].ships[index(7, 8)] == Ship::cruiser.value + 1 and game.remaining_segments[0] == 3

# Horizontal placement rejects a carrier extending past the right edge while
# accepting the last starting column at which all five cells fit.
fun test_horizontal_ship_must_fit() -> Bool:
  let game = play()
  return !(can game.place(Ship::carrier, make_row(0), make_column(6), Orientation::horizontal)) and can game.place(Ship::carrier, make_row(0), make_column(5), Orientation::horizontal)

# Vertical placement rejects a battleship extending below the board while
# accepting the last starting row at which all four cells fit.
fun test_vertical_ship_must_fit() -> Bool:
  let game = play()
  return !(can game.place(Ship::battleship, make_row(7), make_column(0), Orientation::vertical)) and can game.place(Ship::battleship, make_row(6), make_column(0), Orientation::vertical)

# Fuzzer-decoded actions may contain invalid raw enum or bounded-integer values;
# preconditions must reject all of them before they can index board arrays.
fun test_malformed_action_values_are_rejected() -> Bool:
  let game = play()
  let ship = Ship::carrier
  ship.value = 38
  let orientation = Orientation::horizontal
  orientation.value = -1
  return !(can game.place(ship, make_row(0), make_column(0), Orientation::horizontal)) and !(can game.place(Ship::carrier, make_row(0), make_column(0), orientation)) and !(can game.place(Ship::carrier, make_row(10), make_column(0), Orientation::horizontal))

# A new ship may not cross an occupied cell, but another non-overlapping
# placement remains legal on the same board.
fun test_ships_cannot_overlap() -> Bool:
  let game = play()
  game.place(Ship::carrier, make_row(2), make_column(1), Orientation::horizontal)

  return !(can game.place(Ship::destroyer, make_row(1), make_column(3), Orientation::vertical)) and can game.place(Ship::destroyer, make_row(0), make_column(0), Orientation::vertical)

# Each player owns one instance of every fleet member, so relocating or adding
# a second submarine for the same player is illegal.
fun test_each_ship_can_only_be_placed_once() -> Bool:
  let game = play()
  game.place(Ship::submarine, make_row(0), make_column(0), Orientation::horizontal)

  return !(can game.place(Ship::submarine, make_row(5), make_column(5), Orientation::horizontal))

# Finishing player one's fleet advances placement to player two without copying
# placement flags; player two can place the same ship at the same coordinates.
fun test_players_have_independent_boards() -> Bool:
  let game = play()
  place_standard_fleet(game)

  return game.current_player == 1 and game.boards[0].placed[Ship::carrier.value] and !game.boards[1].placed[Ship::carrier.value] and can game.place(Ship::carrier, make_row(0), make_column(0), Orientation::horizontal)

# Board query helpers distinguish occupied cells from neighboring water and do
# not report an un-fired-upon ship cell as already shot.
fun test_cell_queries_report_board_state() -> Bool:
  let game = play()
  game.place(Ship::destroyer, make_row(6), make_column(6), Orientation::vertical)

  return cell_has_ship(game.boards[0], 6, 6) and cell_has_ship(game.boards[0], 7, 6) and !cell_has_ship(game.boards[0], 6, 7) and !cell_was_shot(game.boards[0], 6, 6)

# Fire is unavailable until both players have completed fleet placement.
fun test_cannot_fire_during_placement() -> Bool:
  let game = play()
  return !(can game.fire(make_row(0), make_column(0)))

# Two complete standard fleets transition the game to battle with 17 live
# segments apiece and expose the first fire action without ending the game.
fun test_battle_starts_after_both_fleets() -> Bool:
  let game = play()
  ready_game(game)
  return game.phase == 1 and game.remaining_segments[0] == FLEET_SEGMENTS and game.remaining_segments[1] == FLEET_SEGMENTS and can game.fire(make_row(9), make_column(9)) and !game.is_done()

# Placement is no longer an available action after the battle phase begins.
fun test_cannot_place_during_battle() -> Bool:
  let game = play()
  ready_game(game)
  return !(can game.place(Ship::carrier, make_row(8), make_column(0), Orientation::horizontal))

# A miss marks the opponent's targeted cell, records the shot metadata, leaves
# its fleet count unchanged, and passes the turn to the opponent.
fun test_miss_is_recorded_and_changes_turn() -> Bool:
  let game = play()
  ready_game(game)
  game.fire(make_row(9), make_column(9))
  return game.boards[1].shots[index(9, 9)] and !game.last_hit and game.last_player == 0 and game.last_row == 9 and game.last_column == 9 and game.current_player == 1 and game.remaining_segments[1] == FLEET_SEGMENTS

# A hit marks the opponent's targeted cell, reports a hit, removes exactly one
# live segment, and still passes the turn under standard alternating play.
fun test_hit_is_recorded_and_reduces_segments() -> Bool:
  let game = play()
  ready_game(game)
  game.fire(make_row(0), make_column(0))
  return game.boards[1].shots[index(0, 0)] and game.last_hit and game.current_player == 1 and game.remaining_segments[1] == FLEET_SEGMENTS - 1

# Consecutive turns write to different target boards: player one attacks board
# two, player two attacks board one, then control returns to player one.
fun test_each_player_fires_on_the_opponents_board() -> Bool:
  let game = play()
  ready_game(game)
  game.fire(make_row(9), make_column(9))
  game.fire(make_row(8), make_column(8))
  return game.boards[1].shots[index(9, 9)] and !game.boards[0].shots[index(9, 9)] and game.boards[0].shots[index(8, 8)] and !game.boards[1].shots[index(8, 8)] and game.current_player == 0

# Shot history is board-specific: both players may use the same coordinate once
# against different boards, but player one cannot repeat it against board two.
fun test_same_cell_cannot_be_fired_on_twice() -> Bool:
  let game = play()
  ready_game(game)
  game.fire(make_row(9), make_column(9))
  game.fire(make_row(9), make_column(9))
  return !(can game.fire(make_row(9), make_column(9)))

fun fire_hit_then_miss(Game game, Int hit_row, Int hit_column, Int miss_row, Int miss_column):
  game.fire(make_row(hit_row), make_column(hit_column))
  game.fire(make_row(miss_row), make_column(miss_column))

# Destroying all 17 segments of player two's fleet ends the action sequence,
# records player one as winner, and preserves the final successful shot metadata.
fun test_sinking_the_fleet_wins_the_game() -> Bool:
  let game = play()
  ready_game(game)

  # Player one hits every occupied cell on player two's standard fleet.
  # Player two replies with distinct misses on rows 8 and 9.
  fire_hit_then_miss(game, 0, 0, 9, 0)
  fire_hit_then_miss(game, 0, 1, 9, 1)
  fire_hit_then_miss(game, 0, 2, 9, 2)
  fire_hit_then_miss(game, 0, 3, 9, 3)
  fire_hit_then_miss(game, 0, 4, 9, 4)
  fire_hit_then_miss(game, 1, 0, 9, 5)
  fire_hit_then_miss(game, 1, 1, 9, 6)
  fire_hit_then_miss(game, 1, 2, 9, 7)
  fire_hit_then_miss(game, 1, 3, 9, 8)
  fire_hit_then_miss(game, 2, 0, 9, 9)
  fire_hit_then_miss(game, 2, 1, 8, 0)
  fire_hit_then_miss(game, 2, 2, 8, 1)
  fire_hit_then_miss(game, 3, 0, 8, 2)
  fire_hit_then_miss(game, 3, 1, 8, 3)
  fire_hit_then_miss(game, 3, 2, 8, 4)
  fire_hit_then_miss(game, 4, 0, 8, 5)
  game.fire(make_row(4), make_column(1))

  return game.is_done() and game.phase == 2 and game.winner == 0 and game.remaining_segments[1] == 0 and game.last_hit and game.last_player == 0

fun fuzz(Vector<Byte> input):
  if input.size() == 0:
    return

  let game = play()
  let action : AnyGameAction
  let parsed_actions = parse_actions(action, input)
  for current_action in parsed_actions:
    if can apply(current_action, game):
      apply(current_action, game)

fun main() -> Int:
  let game = play()
  print(game)
  return 0


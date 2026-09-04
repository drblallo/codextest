import bounded_arg
import action
import collections.vector

const MAX_PLAYER_COUNT = 4
const RESOURCE_COUNT = 5
const HEX_COUNT = 19
const VERTEX_COUNT = 54
const EDGE_COUNT = 72
const HEX_CORNERS = 114
const MAX_ROADS = 15
const MAX_SETTLEMENTS = 5
const MAX_CITIES = 4
const WIN_POINTS = 10

using PlayerId = BInt<0, MAX_PLAYER_COUNT>
using PlayerCount = BInt<3, 5>
using Site = BInt<0, VERTEX_COUNT>
using Path = BInt<0, EDGE_COUNT>
using HexId = BInt<0, HEX_COUNT>
using Die = BInt<1, 7>

enum Resource:
  brick
  lumber
  wool
  grain
  ore

enum Terrain:
  brick
  lumber
  wool
  grain
  ore
  desert

enum Harbor:
  generic
  brick
  lumber
  wool
  grain
  ore

enum NumberToken:
  two
  three
  four
  five
  six
  eight
  nine
  ten
  eleven
  twelve

cls Board:
  # Terrain is a Resource raw value, or -1 for the desert.
  Int[HEX_COUNT] terrain
  Int[HEX_COUNT] number
  Int[HEX_CORNERS] hex_vertices
  Int[EDGE_COUNT] edge_a
  Int[EDGE_COUNT] edge_b
  Int[VERTEX_COUNT] owner
  # 0 empty, 1 settlement, 2 city.
  Int[VERTEX_COUNT] building
  Int[EDGE_COUNT] road_owner
  # 4 means an ordinary bank trade; 3 is a generic harbor; 2 is specific.
  Int[VERTEX_COUNT] harbor_rate
  Int[VERTEX_COUNT] harbor_resource
  Int robber_hex

  fun adjacent(Int left, Int right) -> Bool:
    let edge = 0
    while edge != EDGE_COUNT:
      if (self.edge_a[edge] == left and self.edge_b[edge] == right) or (self.edge_a[edge] == right and self.edge_b[edge] == left):
        return true
      edge = edge + 1
    return false

  fun edge_touches(Int edge, Int vertex) -> Bool:
    return self.edge_a[edge] == vertex or self.edge_b[edge] == vertex

  fun vertex_touches_hex(Int vertex, Int hex) -> Bool:
    let corner = 0
    while corner != 6:
      if self.hex_vertices[hex * 6 + corner] == vertex:
        return true
      corner = corner + 1
    return false

  fun has_incident_road(Int player, Int vertex) -> Bool:
    let edge = 0
    while edge != EDGE_COUNT:
      if self.road_owner[edge] == player and self.edge_touches(edge, vertex):
        return true
      edge = edge + 1
    return false

  fun distance_rule(Int vertex) -> Bool:
    if self.building[vertex] != 0:
      return false
    let other = 0
    while other != VERTEX_COUNT:
      if self.building[other] != 0 and self.adjacent(vertex, other):
        return false
      other = other + 1
    return true

  fun can_setup_settlement(Site site) -> Bool:
    if !valid_site(site):
      return false
    return self.distance_rule(site.value)

  fun pending_setup_vertex(Int player) -> Int:
    let vertex = 0
    while vertex != VERTEX_COUNT:
      if self.owner[vertex] == player and self.building[vertex] == 1 and !self.has_incident_road(player, vertex):
        return vertex
      vertex = vertex + 1
    return -1

  fun can_setup_road(Int player, Int setup_vertex, Path path) -> Bool:
    if !valid_path(path):
      return false
    return self.road_owner[path.value] == -1 and self.edge_touches(path.value, setup_vertex)

  fun road_count(Int player) -> Int:
    let count = 0
    let edge = 0
    while edge != EDGE_COUNT:
      if self.road_owner[edge] == player:
        count = count + 1
      edge = edge + 1
    return count

  fun total_road_count() -> Int:
    let count = 0
    let edge = 0
    while edge != EDGE_COUNT:
      if self.road_owner[edge] != -1:
        count = count + 1
      edge = edge + 1
    return count

  fun settlement_count(Int player) -> Int:
    let count = 0
    let vertex = 0
    while vertex != VERTEX_COUNT:
      if self.owner[vertex] == player and self.building[vertex] == 1:
        count = count + 1
      vertex = vertex + 1
    return count

  fun city_count(Int player) -> Int:
    let count = 0
    let vertex = 0
    while vertex != VERTEX_COUNT:
      if self.owner[vertex] == player and self.building[vertex] == 2:
        count = count + 1
      vertex = vertex + 1
    return count

  fun can_build_road(PlayerState player, Int player_id, Path path) -> Bool:
    if !valid_path(path):
      return false
    if self.road_owner[path.value] != -1 or self.road_count(player_id) >= MAX_ROADS:
      return false
    if player.resources[Resource::brick.value] < 1 or player.resources[Resource::lumber.value] < 1:
      return false
    let a = self.edge_a[path.value]
    let b = self.edge_b[path.value]
    if self.owner[a] == player_id or self.owner[b] == player_id:
      return true
    return self.has_incident_road(player_id, a) or self.has_incident_road(player_id, b)

  fun can_build_settlement(PlayerState player, Int player_id, Site site) -> Bool:
    if !valid_site(site):
      return false
    if self.settlement_count(player_id) >= MAX_SETTLEMENTS or !self.distance_rule(site.value):
      return false
    if !self.has_incident_road(player_id, site.value):
      return false
    return player.resources[Resource::brick.value] >= 1 and player.resources[Resource::lumber.value] >= 1 and player.resources[Resource::wool.value] >= 1 and player.resources[Resource::grain.value] >= 1

  fun can_build_city(PlayerState player, Int player_id, Site site) -> Bool:
    if !valid_site(site):
      return false
    return self.owner[site.value] == player_id and self.building[site.value] == 1 and self.city_count(player_id) < MAX_CITIES and player.resources[Resource::ore.value] >= 3 and player.resources[Resource::grain.value] >= 2

  fun trade_rate(Int player, Resource give) -> Int:
    let rate = 4
    let vertex = 0
    while vertex != VERTEX_COUNT:
      if self.owner[vertex] == player:
        if self.harbor_rate[vertex] == 3:
          rate = 3
        if self.harbor_rate[vertex] == 2 and self.harbor_resource[vertex] == give.value:
          rate = 2
      vertex = vertex + 1
    return rate

  fun can_maritime_trade(PlayerState player, Int player_id, Resource give, Resource receive) -> Bool:
    if !valid_resource(give) or !valid_resource(receive) or give.value == receive.value:
      return false
    return player.resources[give.value] >= self.trade_rate(player_id, give)

  fun produce(PlayerState[MAX_PLAYER_COUNT] players, Int player_count, Int roll):
    let hex = 0
    while hex != HEX_COUNT:
      if self.number[hex] == roll and self.robber_hex != hex and self.terrain[hex] >= 0:
        let corner = 0
        while corner != 6:
          let vertex = self.hex_vertices[hex * 6 + corner]
          if self.owner[vertex] >= 0 and self.owner[vertex] < player_count:
            players[self.owner[vertex]].resources[self.terrain[hex]] = players[self.owner[vertex]].resources[self.terrain[hex]] + self.building[vertex]
          corner = corner + 1
      hex = hex + 1

  fun initialize():
    let vertex = 0
    while vertex != VERTEX_COUNT:
      self.owner[vertex] = -1
      self.harbor_rate[vertex] = 4
      self.harbor_resource[vertex] = -1
      vertex = vertex + 1
    let edge = 0
    while edge != EDGE_COUNT:
      self.road_owner[edge] = -1
      edge = edge + 1
    let hex = 0
    while hex != HEX_COUNT:
      self.terrain[hex] = -2
      self.number[hex] = 0
      hex = hex + 1
    self.robber_hex = -1
    self.edge_a[0] = 0
    self.edge_b[0] = 1
    self.edge_a[1] = 1
    self.edge_b[1] = 2
    self.edge_a[2] = 2
    self.edge_b[2] = 3
    self.edge_a[3] = 3
    self.edge_b[3] = 4
    self.edge_a[4] = 4
    self.edge_b[4] = 5
    self.edge_a[5] = 0
    self.edge_b[5] = 5
    self.edge_a[6] = 6
    self.edge_b[6] = 7
    self.edge_a[7] = 0
    self.edge_b[7] = 7
    self.edge_a[8] = 5
    self.edge_b[8] = 8
    self.edge_a[9] = 8
    self.edge_b[9] = 9
    self.edge_a[10] = 6
    self.edge_b[10] = 9
    self.edge_a[11] = 10
    self.edge_b[11] = 11
    self.edge_a[12] = 6
    self.edge_b[12] = 11
    self.edge_a[13] = 9
    self.edge_b[13] = 12
    self.edge_a[14] = 12
    self.edge_b[14] = 13
    self.edge_a[15] = 10
    self.edge_b[15] = 13
    self.edge_a[16] = 14
    self.edge_b[16] = 15
    self.edge_a[17] = 15
    self.edge_b[17] = 16
    self.edge_a[18] = 16
    self.edge_b[18] = 17
    self.edge_a[19] = 2
    self.edge_b[19] = 17
    self.edge_a[20] = 1
    self.edge_b[20] = 14
    self.edge_a[21] = 18
    self.edge_b[21] = 19
    self.edge_a[22] = 14
    self.edge_b[22] = 19
    self.edge_a[23] = 7
    self.edge_b[23] = 18
    self.edge_a[24] = 20
    self.edge_b[24] = 21
    self.edge_a[25] = 18
    self.edge_b[25] = 21
    self.edge_a[26] = 11
    self.edge_b[26] = 20
    self.edge_a[27] = 22
    self.edge_b[27] = 23
    self.edge_a[28] = 20
    self.edge_b[28] = 23
    self.edge_a[29] = 10
    self.edge_b[29] = 24
    self.edge_a[30] = 22
    self.edge_b[30] = 24
    self.edge_a[31] = 25
    self.edge_b[31] = 26
    self.edge_a[32] = 26
    self.edge_b[32] = 27
    self.edge_a[33] = 27
    self.edge_b[33] = 28
    self.edge_a[34] = 16
    self.edge_b[34] = 28
    self.edge_a[35] = 15
    self.edge_b[35] = 25
    self.edge_a[36] = 29
    self.edge_b[36] = 30
    self.edge_a[37] = 25
    self.edge_b[37] = 30
    self.edge_a[38] = 19
    self.edge_b[38] = 29
    self.edge_a[39] = 31
    self.edge_b[39] = 32
    self.edge_a[40] = 29
    self.edge_b[40] = 32
    self.edge_a[41] = 21
    self.edge_b[41] = 31
    self.edge_a[42] = 33
    self.edge_b[42] = 34
    self.edge_a[43] = 31
    self.edge_b[43] = 34
    self.edge_a[44] = 23
    self.edge_b[44] = 33
    self.edge_a[45] = 35
    self.edge_b[45] = 36
    self.edge_a[46] = 33
    self.edge_b[46] = 36
    self.edge_a[47] = 22
    self.edge_b[47] = 37
    self.edge_a[48] = 35
    self.edge_b[48] = 37
    self.edge_a[49] = 38
    self.edge_b[49] = 39
    self.edge_a[50] = 39
    self.edge_b[50] = 40
    self.edge_a[51] = 26
    self.edge_b[51] = 40
    self.edge_a[52] = 30
    self.edge_b[52] = 38
    self.edge_a[53] = 41
    self.edge_b[53] = 42
    self.edge_a[54] = 38
    self.edge_b[54] = 42
    self.edge_a[55] = 32
    self.edge_b[55] = 41
    self.edge_a[56] = 43
    self.edge_b[56] = 44
    self.edge_a[57] = 41
    self.edge_b[57] = 44
    self.edge_a[58] = 34
    self.edge_b[58] = 43
    self.edge_a[59] = 45
    self.edge_b[59] = 46
    self.edge_a[60] = 43
    self.edge_b[60] = 46
    self.edge_a[61] = 36
    self.edge_b[61] = 45
    self.edge_a[62] = 47
    self.edge_b[62] = 48
    self.edge_a[63] = 48
    self.edge_b[63] = 49
    self.edge_a[64] = 39
    self.edge_b[64] = 49
    self.edge_a[65] = 42
    self.edge_b[65] = 47
    self.edge_a[66] = 50
    self.edge_b[66] = 51
    self.edge_a[67] = 47
    self.edge_b[67] = 51
    self.edge_a[68] = 44
    self.edge_b[68] = 50
    self.edge_a[69] = 52
    self.edge_b[69] = 53
    self.edge_a[70] = 50
    self.edge_b[70] = 53
    self.edge_a[71] = 46
    self.edge_b[71] = 52
    self.hex_vertices[0] = 0
    self.hex_vertices[1] = 1
    self.hex_vertices[2] = 2
    self.hex_vertices[3] = 3
    self.hex_vertices[4] = 4
    self.hex_vertices[5] = 5
    self.hex_vertices[6] = 6
    self.hex_vertices[7] = 7
    self.hex_vertices[8] = 0
    self.hex_vertices[9] = 5
    self.hex_vertices[10] = 8
    self.hex_vertices[11] = 9
    self.hex_vertices[12] = 10
    self.hex_vertices[13] = 11
    self.hex_vertices[14] = 6
    self.hex_vertices[15] = 9
    self.hex_vertices[16] = 12
    self.hex_vertices[17] = 13
    self.hex_vertices[18] = 14
    self.hex_vertices[19] = 15
    self.hex_vertices[20] = 16
    self.hex_vertices[21] = 17
    self.hex_vertices[22] = 2
    self.hex_vertices[23] = 1
    self.hex_vertices[24] = 18
    self.hex_vertices[25] = 19
    self.hex_vertices[26] = 14
    self.hex_vertices[27] = 1
    self.hex_vertices[28] = 0
    self.hex_vertices[29] = 7
    self.hex_vertices[30] = 20
    self.hex_vertices[31] = 21
    self.hex_vertices[32] = 18
    self.hex_vertices[33] = 7
    self.hex_vertices[34] = 6
    self.hex_vertices[35] = 11
    self.hex_vertices[36] = 22
    self.hex_vertices[37] = 23
    self.hex_vertices[38] = 20
    self.hex_vertices[39] = 11
    self.hex_vertices[40] = 10
    self.hex_vertices[41] = 24
    self.hex_vertices[42] = 25
    self.hex_vertices[43] = 26
    self.hex_vertices[44] = 27
    self.hex_vertices[45] = 28
    self.hex_vertices[46] = 16
    self.hex_vertices[47] = 15
    self.hex_vertices[48] = 29
    self.hex_vertices[49] = 30
    self.hex_vertices[50] = 25
    self.hex_vertices[51] = 15
    self.hex_vertices[52] = 14
    self.hex_vertices[53] = 19
    self.hex_vertices[54] = 31
    self.hex_vertices[55] = 32
    self.hex_vertices[56] = 29
    self.hex_vertices[57] = 19
    self.hex_vertices[58] = 18
    self.hex_vertices[59] = 21
    self.hex_vertices[60] = 33
    self.hex_vertices[61] = 34
    self.hex_vertices[62] = 31
    self.hex_vertices[63] = 21
    self.hex_vertices[64] = 20
    self.hex_vertices[65] = 23
    self.hex_vertices[66] = 35
    self.hex_vertices[67] = 36
    self.hex_vertices[68] = 33
    self.hex_vertices[69] = 23
    self.hex_vertices[70] = 22
    self.hex_vertices[71] = 37
    self.hex_vertices[72] = 38
    self.hex_vertices[73] = 39
    self.hex_vertices[74] = 40
    self.hex_vertices[75] = 26
    self.hex_vertices[76] = 25
    self.hex_vertices[77] = 30
    self.hex_vertices[78] = 41
    self.hex_vertices[79] = 42
    self.hex_vertices[80] = 38
    self.hex_vertices[81] = 30
    self.hex_vertices[82] = 29
    self.hex_vertices[83] = 32
    self.hex_vertices[84] = 43
    self.hex_vertices[85] = 44
    self.hex_vertices[86] = 41
    self.hex_vertices[87] = 32
    self.hex_vertices[88] = 31
    self.hex_vertices[89] = 34
    self.hex_vertices[90] = 45
    self.hex_vertices[91] = 46
    self.hex_vertices[92] = 43
    self.hex_vertices[93] = 34
    self.hex_vertices[94] = 33
    self.hex_vertices[95] = 36
    self.hex_vertices[96] = 47
    self.hex_vertices[97] = 48
    self.hex_vertices[98] = 49
    self.hex_vertices[99] = 39
    self.hex_vertices[100] = 38
    self.hex_vertices[101] = 42
    self.hex_vertices[102] = 50
    self.hex_vertices[103] = 51
    self.hex_vertices[104] = 47
    self.hex_vertices[105] = 42
    self.hex_vertices[106] = 41
    self.hex_vertices[107] = 44
    self.hex_vertices[108] = 52
    self.hex_vertices[109] = 53
    self.hex_vertices[110] = 50
    self.hex_vertices[111] = 44
    self.hex_vertices[112] = 43
    self.hex_vertices[113] = 46
  fun player_borders_hex(Int player, Int hex) -> Bool:
    let corner = 0
    while corner != 6:
      let vertex = self.hex_vertices[hex * 6 + corner]
      if self.owner[vertex] == player:
        return true
      corner = corner + 1
    return false

  fun can_rob(PlayerState[MAX_PLAYER_COUNT] players, Int player_count, Int thief, Int destination, Int victim, Resource stolen) -> Bool:
    if destination < 0 or destination >= HEX_COUNT or destination == self.robber_hex:
      return false
    if victim == thief:
      # Choosing oneself represents moving the robber when nobody can be robbed.
      let other = 0
      while other != player_count:
        if other != thief and self.player_borders_hex(other, destination) and players[other].resource_total() > 0:
          return false
        other = other + 1
      return true
    if victim < 0 or victim >= player_count or !valid_resource(stolen):
      return false
    return self.player_borders_hex(victim, destination) and players[victim].resources[stolen.value] > 0
  fun unplaced_terrain_count() -> Int:
    let count = 0
    let hex = 0
    while hex != HEX_COUNT:
      if self.terrain[hex] == -2:
        count = count + 1
      hex = hex + 1
    return count

  fun terrain_count(Terrain terrain) -> Int:
    let count = 0
    let hex = 0
    while hex != HEX_COUNT:
      if terrain.value == Terrain::desert.value and self.terrain[hex] == -1:
        count = count + 1
      else if self.terrain[hex] == terrain.value:
        count = count + 1
      hex = hex + 1
    return count

  fun terrain_limit(Terrain terrain) -> Int:
    if terrain.value == Terrain::brick.value or terrain.value == Terrain::ore.value:
      return 3
    if terrain.value == Terrain::desert.value:
      return 1
    return 4

  fun can_generate_terrain(Terrain terrain) -> Bool:
    if terrain.value < 0 or terrain.value > Terrain::desert.value:
      return false
    return self.terrain_count(terrain) < self.terrain_limit(terrain)

  fun generate_terrain(Terrain terrain):
    let hex = 0
    while self.terrain[hex] != -2:
      hex = hex + 1
    if terrain.value == Terrain::desert.value:
      self.terrain[hex] = -1
      self.robber_hex = hex
    else:
      self.terrain[hex] = terrain.value

  fun number_value(NumberToken token) -> Int:
    if token.value == NumberToken::two.value:
      return 2
    if token.value == NumberToken::three.value:
      return 3
    if token.value == NumberToken::four.value:
      return 4
    if token.value == NumberToken::five.value:
      return 5
    if token.value == NumberToken::six.value:
      return 6
    if token.value == NumberToken::eight.value:
      return 8
    if token.value == NumberToken::nine.value:
      return 9
    if token.value == NumberToken::ten.value:
      return 10
    if token.value == NumberToken::eleven.value:
      return 11
    return 12

  fun number_limit(NumberToken token) -> Int:
    if token.value == NumberToken::two.value or token.value == NumberToken::twelve.value:
      return 1
    return 2

  fun number_count(NumberToken token) -> Int:
    let count = 0
    let hex = 0
    let number = self.number_value(token)
    while hex != HEX_COUNT:
      if self.number[hex] == number:
        count = count + 1
      hex = hex + 1
    return count

  fun next_number_hex() -> Int:
    let hex = 0
    while hex != HEX_COUNT:
      if self.terrain[hex] >= 0 and self.number[hex] == 0:
        return hex
      hex = hex + 1
    return -1

  fun hexes_adjacent(Int left, Int right) -> Bool:
    let shared = 0
    let a = 0
    while a != 6:
      let b = 0
      while b != 6:
        if self.hex_vertices[left * 6 + a] == self.hex_vertices[right * 6 + b]:
          shared = shared + 1
        b = b + 1
      a = a + 1
    return shared == 2

  fun red_slot_eligible(Int slot, Int target, Bool target_is_red) -> Bool:
    if slot == target or self.terrain[slot] < 0 or self.number[slot] != 0:
      return false
    if target_is_red and self.hexes_adjacent(slot, target):
      return false
    let hex = 0
    while hex != HEX_COUNT:
      if (self.number[hex] == 6 or self.number[hex] == 8) and self.hexes_adjacent(slot, hex):
        return false
      hex = hex + 1
    return true

  fun can_finish_red_numbers(NumberToken candidate) -> Bool:
    let target_is_red = self.number_value(candidate) == 6 or self.number_value(candidate) == 8
    let remaining = 4 - self.number_count(NumberToken::six) - self.number_count(NumberToken::eight)
    if target_is_red:
      remaining = remaining - 1
    if remaining == 0:
      return true
    let target = self.next_number_hex()
    let a = 0
    while a != HEX_COUNT:
      if self.red_slot_eligible(a, target, target_is_red):
        if remaining == 1:
          return true
        let b = a + 1
        while b != HEX_COUNT:
          if self.red_slot_eligible(b, target, target_is_red) and !self.hexes_adjacent(a, b):
            if remaining == 2:
              return true
            let c = b + 1
            while c != HEX_COUNT:
              if self.red_slot_eligible(c, target, target_is_red) and !self.hexes_adjacent(a, c) and !self.hexes_adjacent(b, c):
                if remaining == 3:
                  return true
                let d = c + 1
                while d != HEX_COUNT:
                  if self.red_slot_eligible(d, target, target_is_red) and !self.hexes_adjacent(a, d) and !self.hexes_adjacent(b, d) and !self.hexes_adjacent(c, d):
                    return true
                  d = d + 1
              c = c + 1
          b = b + 1
      a = a + 1
    return false

  fun can_generate_number(NumberToken token) -> Bool:
    if token.value < 0 or token.value > NumberToken::twelve.value or self.next_number_hex() == -1:
      return false
    if self.number_count(token) >= self.number_limit(token):
      return false
    let value = self.number_value(token)
    if value == 6 or value == 8:
      let hex = 0
      let target = self.next_number_hex()
      while hex != HEX_COUNT:
        if self.hexes_adjacent(hex, target) and (self.number[hex] == 6 or self.number[hex] == 8):
          return false
        hex = hex + 1
    return self.can_finish_red_numbers(token)

  fun generate_number(NumberToken token):
    self.number[self.next_number_hex()] = self.number_value(token)

  fun harbor_edge(Int slot) -> Int:
    if slot == 0:
      return 2
    if slot == 1:
      return 8
    if slot == 2:
      return 15
    if slot == 3:
      return 47
    if slot == 4:
      return 61
    if slot == 5:
      return 70
    if slot == 6:
      return 62
    if slot == 7:
      return 50
    return 34

  fun generated_harbor_count() -> Int:
    let count = 0
    while count != 9:
      let edge = self.harbor_edge(count)
      if self.harbor_rate[self.edge_a[edge]] == 4:
        return count
      count = count + 1
    return count

  fun harbor_count(Harbor harbor) -> Int:
    let count = 0
    let slot = 0
    while slot != self.generated_harbor_count():
      let edge = self.harbor_edge(slot)
      let vertex = self.edge_a[edge]
      if harbor.value == Harbor::generic.value and self.harbor_rate[vertex] == 3:
        count = count + 1
      if harbor.value != Harbor::generic.value and self.harbor_rate[vertex] == 2 and self.harbor_resource[vertex] == harbor.value - 1:
        count = count + 1
      slot = slot + 1
    return count

  fun can_generate_harbor(Harbor harbor) -> Bool:
    if harbor.value < 0 or harbor.value > Harbor::ore.value:
      return false
    if harbor.value == Harbor::generic.value:
      return self.harbor_count(harbor) < 4
    return self.harbor_count(harbor) < 1

  fun generate_harbor(Harbor harbor):
    let edge = self.harbor_edge(self.generated_harbor_count())
    let rate = 2
    if harbor.value == Harbor::generic.value:
      rate = 3
    self.harbor_rate[self.edge_a[edge]] = rate
    self.harbor_rate[self.edge_b[edge]] = rate
    if rate == 2:
      self.harbor_resource[self.edge_a[edge]] = harbor.value - 1
      self.harbor_resource[self.edge_b[edge]] = harbor.value - 1

  fun edge_hex_count(Int edge) -> Int:
    let count = 0
    let hex = 0
    while hex != HEX_COUNT:
      let has_a = self.vertex_touches_hex(self.edge_a[edge], hex)
      let has_b = self.vertex_touches_hex(self.edge_b[edge], hex)
      if has_a and has_b:
        count = count + 1
      hex = hex + 1
    return count

  fun valid_generated_board() -> Bool:
    if self.unplaced_terrain_count() != 0:
      return false
    if self.terrain_count(Terrain::brick) != 3 or self.terrain_count(Terrain::ore) != 3:
      return false
    if self.terrain_count(Terrain::lumber) != 4 or self.terrain_count(Terrain::wool) != 4 or self.terrain_count(Terrain::grain) != 4:
      return false
    if self.terrain_count(Terrain::desert) != 1 or self.robber_hex < 0 or self.robber_hex >= HEX_COUNT or self.terrain[self.robber_hex] != -1:
      return false
    let hex = 0
    while hex != HEX_COUNT:
      if self.terrain[hex] == -1:
        if self.number[hex] != 0:
          return false
      else if self.number[hex] < 2 or self.number[hex] > 12 or self.number[hex] == 7:
        return false
      if self.number[hex] == 6 or self.number[hex] == 8:
        let other = hex + 1
        while other != HEX_COUNT:
          if (self.number[other] == 6 or self.number[other] == 8) and self.hexes_adjacent(hex, other):
            return false
          other = other + 1
      hex = hex + 1
    if self.number_count(NumberToken::two) != 1 or self.number_count(NumberToken::twelve) != 1:
      return false
    if self.number_count(NumberToken::three) != 2 or self.number_count(NumberToken::four) != 2 or self.number_count(NumberToken::five) != 2 or self.number_count(NumberToken::six) != 2:
      return false
    if self.number_count(NumberToken::eight) != 2 or self.number_count(NumberToken::nine) != 2 or self.number_count(NumberToken::ten) != 2 or self.number_count(NumberToken::eleven) != 2:
      return false
    if self.generated_harbor_count() != 9 or self.harbor_count(Harbor::generic) != 4:
      return false
    if self.harbor_count(Harbor::brick) != 1 or self.harbor_count(Harbor::lumber) != 1 or self.harbor_count(Harbor::wool) != 1 or self.harbor_count(Harbor::grain) != 1 or self.harbor_count(Harbor::ore) != 1:
      return false
    let slot = 0
    while slot != 9:
      let edge = self.harbor_edge(slot)
      if self.edge_hex_count(edge) != 1:
        return false
      if self.harbor_rate[self.edge_a[edge]] != self.harbor_rate[self.edge_b[edge]] or self.harbor_resource[self.edge_a[edge]] != self.harbor_resource[self.edge_b[edge]]:
        return false
      slot = slot + 1
    return true

  fun can_play_knight(PlayerState[MAX_PLAYER_COUNT] players, Int player_count, Int current_player, Bool development_played, HexId destination, PlayerId victim, Resource stolen) -> Bool:
    if development_played or players[current_player].development <= 0:
      return false
    if !valid_hex(destination) or !valid_player(victim) or !valid_resource(stolen):
      return false
    return self.can_rob(players, player_count, current_player, destination.value, victim.value, stolen)

  fun grant_second_settlement_resources(PlayerState player, Int vertex):
    let hex = 0
    while hex != HEX_COUNT:
      if self.vertex_touches_hex(vertex, hex) and self.terrain[hex] >= 0:
        player.resources[self.terrain[hex]] = player.resources[self.terrain[hex]] + 1
      hex = hex + 1

cls PlayerState:
  Int[RESOURCE_COUNT] resources
  Int development
  Int new_development
  Int knights
  Int victory_cards

  fun resource_total() -> Int:
    let total = 0
    let resource = 0
    while resource != RESOURCE_COUNT:
      total = total + self.resources[resource]
      resource = resource + 1
    return total

  fun points(Board board, Int player_id, Int largest_army_owner) -> Int:
    return board.settlement_count(player_id) + board.city_count(player_id) * 2 + self.victory_cards + largest_army_points(largest_army_owner, player_id)

  fun pay(Resource resource, Int amount):
    self.resources[resource.value] = self.resources[resource.value] - amount
fun valid_resource(Resource resource) -> Bool:
  return resource.value >= 0 and resource.value < RESOURCE_COUNT

fun valid_player_count(PlayerCount player_count) -> Bool:
  return player_count.value >= 3 and player_count.value <= MAX_PLAYER_COUNT

fun valid_player(PlayerId player) -> Bool:
  return player.value >= 0 and player.value < MAX_PLAYER_COUNT

fun valid_site(Site site) -> Bool:
  return site.value >= 0 and site.value < VERTEX_COUNT

fun valid_path(Path path) -> Bool:
  return path.value >= 0 and path.value < EDGE_COUNT

fun valid_hex(HexId hex) -> Bool:
  return hex.value >= 0 and hex.value < HEX_COUNT

fun valid_die(Die die) -> Bool:
  return die.value >= 1 and die.value <= 6

fun make_player_count(Int value) -> PlayerCount:
  let result: PlayerCount
  result.value = value
  return result

fun make_player(Int value) -> PlayerId:
  let result: PlayerId
  result.value = value
  return result

fun make_site(Int value) -> Site:
  let result: Site
  result.value = value
  return result

fun make_path(Int value) -> Path:
  let result: Path
  result.value = value
  return result

fun make_hex(Int value) -> HexId:
  let result: HexId
  result.value = value
  return result

fun make_die(Int value) -> Die:
  let result: Die
  result.value = value
  return result

fun largest_army_points(Int largest_army_owner, Int player) -> Int:
  if largest_army_owner == player:
    return 2
  return 0

fun development_cards_left(PlayerState[MAX_PLAYER_COUNT] players, Int player_count) -> Int:
  let bought = 0
  let player = 0
  while player != player_count:
    bought = bought + players[player].development + players[player].new_development + players[player].knights + players[player].victory_cards
    player = player + 1
  return 25 - bought

fun setup_player(Int setup_index, Int player_count) -> Int:
  if setup_index < player_count:
    return setup_index
  return player_count * 2 - setup_index - 1

fun discarding_player(Int[MAX_PLAYER_COUNT] discard_remaining, Int player_count) -> Int:
  let player = 0
  while player != player_count:
    if discard_remaining[player] > 0:
      return player
    player = player + 1
  return -1

fun pending_discards(Int[MAX_PLAYER_COUNT] discard_remaining, Int player_count) -> Int:
  let count = 0
  let player = 0
  while player != player_count:
    count = count + discard_remaining[player]
    player = player + 1
  return count

fun update_largest_army(PlayerState[MAX_PLAYER_COUNT] players, Int current_owner, Int contender) -> Int:
  if players[contender].knights < 3:
    return current_owner
  if current_owner != -1 and players[contender].knights <= players[current_owner].knights:
    return current_owner
  return contender

@classes
act play() -> Game:
  frm board: Board
  frm players: PlayerState[MAX_PLAYER_COUNT]
  frm current_player = 0
  frm last_roll = 0
  frm discard_remaining: Int[MAX_PLAYER_COUNT]
  frm development_played = false
  frm largest_army_owner = -1

  act configure(frm PlayerCount player_count) { valid_player_count(player_count) }
  board.initialize()
  while board.unplaced_terrain_count() != 0:
    act generate_terrain(Terrain terrain) { board.can_generate_terrain(terrain) }
    board.generate_terrain(terrain)
  while board.next_number_hex() != -1:
    act generate_number(NumberToken token) { board.can_generate_number(token) }
    board.generate_number(token)
  while board.generated_harbor_count() != 9:
    act generate_harbor(Harbor harbor) { board.can_generate_harbor(harbor) }
    board.generate_harbor(harbor)
  assert(board.valid_generated_board(), "generated board must be valid")
  while board.total_road_count() != player_count.value * 2:
    act setup_settlement(Site site) { board.can_setup_settlement(site) }
    board.owner[site.value] = setup_player(board.total_road_count(), player_count.value)
    board.building[site.value] = 1
    if board.total_road_count() >= player_count.value:
      board.grant_second_settlement_resources(players[setup_player(board.total_road_count(), player_count.value)], site.value)
    act setup_road(Path path) { board.can_setup_road(setup_player(board.total_road_count(), player_count.value), board.pending_setup_vertex(setup_player(board.total_road_count(), player_count.value)), path) }
    board.road_owner[path.value] = setup_player(board.total_road_count(), player_count.value)

  current_player = 0
  while true:
    development_played = false
    players[current_player].development = players[current_player].development + players[current_player].new_development
    players[current_player].new_development = 0
    act roll(Die first, Die second) { valid_die(first) and valid_die(second) }
    last_roll = first.value + second.value
    if last_roll == 7:
      let player = 0
      while player != player_count.value:
        if players[player].resource_total() > 7:
          discard_remaining[player] = players[player].resource_total() / 2
        player = player + 1
      while pending_discards(discard_remaining, player_count.value) > 0:
        act discard(Resource resource) { valid_resource(resource) and players[discarding_player(discard_remaining, player_count.value)].resources[resource.value] > 0 }
        let owner = discarding_player(discard_remaining, player_count.value)
        players[owner].resources[resource.value] = players[owner].resources[resource.value] - 1
        discard_remaining[owner] = discard_remaining[owner] - 1
      act move_robber(HexId destination, PlayerId victim, Resource stolen) { valid_hex(destination) and destination.value != board.robber_hex and valid_player(victim) and valid_resource(stolen) and board.can_rob(players, player_count.value, current_player, destination.value, victim.value, stolen) }
      board.robber_hex = destination.value
      if victim.value != current_player:
        players[victim.value].resources[stolen.value] = players[victim.value].resources[stolen.value] - 1
        players[current_player].resources[stolen.value] = players[current_player].resources[stolen.value] + 1
    else:
      board.produce(players, player_count.value, last_roll)

    while true:
      actions:
        act build_road(Path path) { board.can_build_road(players[current_player], current_player, path) }
          players[current_player].pay(Resource::brick, 1)
          players[current_player].pay(Resource::lumber, 1)
          board.road_owner[path.value] = current_player
        act build_settlement(Site site) { board.can_build_settlement(players[current_player], current_player, site) }
          players[current_player].pay(Resource::brick, 1)
          players[current_player].pay(Resource::lumber, 1)
          players[current_player].pay(Resource::wool, 1)
          players[current_player].pay(Resource::grain, 1)
          board.owner[site.value] = current_player
          board.building[site.value] = 1
        act build_city(Site site) { board.can_build_city(players[current_player], current_player, site) }
          players[current_player].pay(Resource::ore, 3)
          players[current_player].pay(Resource::grain, 2)
          board.building[site.value] = 2
        act buy_development() { development_cards_left(players, player_count.value) > 0 and players[current_player].resources[Resource::ore.value] >= 1 and players[current_player].resources[Resource::wool.value] >= 1 and players[current_player].resources[Resource::grain.value] >= 1 }
          players[current_player].pay(Resource::ore, 1)
          players[current_player].pay(Resource::wool, 1)
          players[current_player].pay(Resource::grain, 1)
          players[current_player].new_development = players[current_player].new_development + 1
        act maritime_trade(Resource give, Resource receive) { board.can_maritime_trade(players[current_player], current_player, give, receive) }
          let rate = board.trade_rate(current_player, give)
          players[current_player].pay(give, rate)
          players[current_player].resources[receive.value] = players[current_player].resources[receive.value] + 1
        act play_knight(HexId destination, PlayerId victim, Resource stolen) { board.can_play_knight(players, player_count.value, current_player, development_played, destination, victim, stolen) }
          players[current_player].development = players[current_player].development - 1
          players[current_player].knights = players[current_player].knights + 1
          development_played = true
          largest_army_owner = update_largest_army(players, largest_army_owner, current_player)
          board.robber_hex = destination.value
          if victim.value != current_player:
            players[victim.value].resources[stolen.value] = players[victim.value].resources[stolen.value] - 1
            players[current_player].resources[stolen.value] = players[current_player].resources[stolen.value] + 1
        act end_turn()
          break
      if players[current_player].points(board, current_player, largest_army_owner) >= WIN_POINTS:
        return
    current_player = (current_player + 1) % player_count.value


fun active_player(Game game) -> Int:
  if game.board.total_road_count() < game.player_count.value * 2:
    return setup_player(game.board.total_road_count(), game.player_count.value)
  return game.current_player

fun winner(Game game) -> Int:
  if game.is_done():
    return game.current_player
  return -1

fun generate_standard_board(Board board):
  board.initialize()
  board.generate_terrain(Terrain::brick)
  board.generate_terrain(Terrain::lumber)
  board.generate_terrain(Terrain::ore)
  board.generate_terrain(Terrain::wool)
  board.generate_terrain(Terrain::grain)
  board.generate_terrain(Terrain::lumber)
  board.generate_terrain(Terrain::wool)
  board.generate_terrain(Terrain::brick)
  board.generate_terrain(Terrain::ore)
  board.generate_terrain(Terrain::desert)
  board.generate_terrain(Terrain::grain)
  board.generate_terrain(Terrain::wool)
  board.generate_terrain(Terrain::lumber)
  board.generate_terrain(Terrain::ore)
  board.generate_terrain(Terrain::grain)
  board.generate_terrain(Terrain::brick)
  board.generate_terrain(Terrain::wool)
  board.generate_terrain(Terrain::lumber)
  board.generate_terrain(Terrain::grain)
  board.generate_number(NumberToken::five)
  board.generate_number(NumberToken::two)
  board.generate_number(NumberToken::six)
  board.generate_number(NumberToken::three)
  board.generate_number(NumberToken::eight)
  board.generate_number(NumberToken::ten)
  board.generate_number(NumberToken::nine)
  board.generate_number(NumberToken::twelve)
  board.generate_number(NumberToken::eleven)
  board.generate_number(NumberToken::four)
  board.generate_number(NumberToken::eight)
  board.generate_number(NumberToken::ten)
  board.generate_number(NumberToken::nine)
  board.generate_number(NumberToken::four)
  board.generate_number(NumberToken::five)
  board.generate_number(NumberToken::six)
  board.generate_number(NumberToken::three)
  board.generate_number(NumberToken::eleven)
  board.generate_harbor(Harbor::generic)
  board.generate_harbor(Harbor::generic)
  board.generate_harbor(Harbor::generic)
  board.generate_harbor(Harbor::generic)
  board.generate_harbor(Harbor::brick)
  board.generate_harbor(Harbor::lumber)
  board.generate_harbor(Harbor::wool)
  board.generate_harbor(Harbor::grain)
  board.generate_harbor(Harbor::ore)

fun complete_generation(Game game):
  game.generate_terrain(Terrain::brick)
  game.generate_terrain(Terrain::lumber)
  game.generate_terrain(Terrain::ore)
  game.generate_terrain(Terrain::wool)
  game.generate_terrain(Terrain::grain)
  game.generate_terrain(Terrain::lumber)
  game.generate_terrain(Terrain::wool)
  game.generate_terrain(Terrain::brick)
  game.generate_terrain(Terrain::ore)
  game.generate_terrain(Terrain::desert)
  game.generate_terrain(Terrain::grain)
  game.generate_terrain(Terrain::wool)
  game.generate_terrain(Terrain::lumber)
  game.generate_terrain(Terrain::ore)
  game.generate_terrain(Terrain::grain)
  game.generate_terrain(Terrain::brick)
  game.generate_terrain(Terrain::wool)
  game.generate_terrain(Terrain::lumber)
  game.generate_terrain(Terrain::grain)
  game.generate_number(NumberToken::five)
  game.generate_number(NumberToken::two)
  game.generate_number(NumberToken::six)
  game.generate_number(NumberToken::three)
  game.generate_number(NumberToken::eight)
  game.generate_number(NumberToken::ten)
  game.generate_number(NumberToken::nine)
  game.generate_number(NumberToken::twelve)
  game.generate_number(NumberToken::eleven)
  game.generate_number(NumberToken::four)
  game.generate_number(NumberToken::eight)
  game.generate_number(NumberToken::ten)
  game.generate_number(NumberToken::nine)
  game.generate_number(NumberToken::four)
  game.generate_number(NumberToken::five)
  game.generate_number(NumberToken::six)
  game.generate_number(NumberToken::three)
  game.generate_number(NumberToken::eleven)
  game.generate_harbor(Harbor::generic)
  game.generate_harbor(Harbor::generic)
  game.generate_harbor(Harbor::generic)
  game.generate_harbor(Harbor::generic)
  game.generate_harbor(Harbor::brick)
  game.generate_harbor(Harbor::lumber)
  game.generate_harbor(Harbor::wool)
  game.generate_harbor(Harbor::grain)
  game.generate_harbor(Harbor::ore)

fun complete_setup(Game game):
  game.configure(make_player_count(4))
  complete_generation(game)
  game.setup_settlement(make_site(0))
  game.setup_road(make_path(0))
  game.setup_settlement(make_site(2))
  game.setup_road(make_path(1))
  game.setup_settlement(make_site(4))
  game.setup_road(make_path(3))
  game.setup_settlement(make_site(6))
  game.setup_road(make_path(6))
  game.setup_settlement(make_site(8))
  game.setup_road(make_path(8))
  game.setup_settlement(make_site(10))
  game.setup_road(make_path(11))
  game.setup_settlement(make_site(12))
  game.setup_road(make_path(13))
  game.setup_settlement(make_site(14))
  game.setup_road(make_path(16))

# The official four-player setup order runs clockwise and then reverses, so the
# starting player places first and last.
fun test_setup_order_is_snake() -> Bool:
  return setup_player(0, 4) == 0 and setup_player(3, 4) == 3 and setup_player(4, 4) == 3 and setup_player(7, 4) == 0 and setup_player(2, 3) == 2 and setup_player(3, 3) == 2 and setup_player(5, 3) == 0

# The generated standard island contains all 19 land hexes, 54 intersections,
# and 72 unique paths, including a genuine adjacency at its first edge.
fun test_standard_board_topology() -> Bool:
  let board: Board
  generate_standard_board(board)
  return board.adjacent(0, 1) and !board.adjacent(0, 53) and board.edge_touches(0, 0)

# The desert produces nothing and starts under the robber, while numbered land
# hexes retain their configured production numbers.
fun test_desert_starts_blocked() -> Bool:
  let board: Board
  generate_standard_board(board)
  return board.terrain[9] == -1 and board.number[9] == 0 and board.robber_hex == 9 and board.number[0] == 5

# Resource totals sum all five card types, which controls mandatory discarding
# after a seven.
fun test_resource_total_counts_every_type() -> Bool:
  let player: PlayerState
  player.resources[Resource::brick.value] = 1
  player.resources[Resource::lumber.value] = 2
  player.resources[Resource::wool.value] = 3
  player.resources[Resource::grain.value] = 4
  player.resources[Resource::ore.value] = 5
  return player.resource_total() == 15

# A settlement contributes one point, a city two, and hidden victory-point
# development cards contribute one each.
fun test_victory_point_calculation() -> Bool:
  let board: Board
  generate_standard_board(board)
  let player: PlayerState
  board.owner[0] = 0
  board.building[0] = 1
  board.owner[2] = 0
  board.building[2] = 2
  player.victory_cards = 1
  return player.points(board, 0, 0) == 6

# Setup settlements obey the distance rule, rejecting both an occupied vertex
# and every directly adjacent vertex.
fun test_setup_enforces_distance_rule() -> Bool:
  let board: Board
  generate_standard_board(board)
  board.owner[0] = 0
  board.building[0] = 1
  return !board.can_setup_settlement(make_site(0)) and !board.can_setup_settlement(make_site(1)) and board.can_setup_settlement(make_site(2))

# Each setup road must be unused and touch the settlement just placed.
fun test_setup_road_must_touch_new_settlement() -> Bool:
  let board: Board
  generate_standard_board(board)
  if !board.can_setup_road(0, 0, make_path(0)) or board.can_setup_road(0, 0, make_path(2)):
    return false
  board.road_owner[0] = 1
  return !board.can_setup_road(0, 0, make_path(0))

# Malformed bounded values reconstructed from bytes are rejected before any
# board array is indexed.
fun test_malformed_bounded_values_are_rejected() -> Bool:
  let board: Board
  generate_standard_board(board)
  return !board.can_setup_settlement(make_site(54)) and !board.can_setup_road(0, 0, make_path(-1)) and !valid_hex(make_hex(19)) and !valid_die(make_die(0))

# A road costs one brick and one lumber and must extend the player's network;
# an isolated path is not a legal purchase.
fun test_road_requires_cost_and_connection() -> Bool:
  let board: Board
  generate_standard_board(board)
  let player: PlayerState
  board.owner[0] = 0
  board.building[0] = 1
  player.resources[Resource::brick.value] = 1
  player.resources[Resource::lumber.value] = 1
  return board.can_build_road(player, 0, make_path(0)) and !board.can_build_road(player, 0, make_path(20))

# Occupied paths cannot receive a second road even when the active player can
# otherwise afford and connect the build.
fun test_roads_cannot_overlap() -> Bool:
  let board: Board
  generate_standard_board(board)
  let player: PlayerState
  board.owner[0] = 0
  board.building[0] = 1
  board.road_owner[0] = 2
  player.resources[Resource::brick.value] = 1
  player.resources[Resource::lumber.value] = 1
  return !board.can_build_road(player, 0, make_path(0))

# A normal settlement needs all four resources, a connected road, an available
# piece, and a site satisfying the distance rule.
fun test_settlement_requires_full_cost_and_road() -> Bool:
  let board: Board
  generate_standard_board(board)
  let player: PlayerState
  board.road_owner[1] = 0
  player.resources[0] = 1
  player.resources[1] = 1
  player.resources[2] = 1
  player.resources[3] = 1
  if !board.can_build_settlement(player, 0, make_site(2)):
    return false
  player.resources[Resource::wool.value] = 0
  return !board.can_build_settlement(player, 0, make_site(2))

# A city can only replace the active player's settlement and costs three ore
# plus two grain.
fun test_city_upgrade_requirements() -> Bool:
  let board: Board
  generate_standard_board(board)
  let player: PlayerState
  board.owner[0] = 0
  board.building[0] = 1
  player.resources[Resource::ore.value] = 3
  player.resources[Resource::grain.value] = 2
  return board.can_build_city(player, 0, make_site(0)) and !board.can_build_city(player, 1, make_site(0))

# The bank trades at four-to-one without a harbor, and rejects exchanging a
# resource for the identical resource.
fun test_default_maritime_trade_is_four_to_one() -> Bool:
  let board: Board
  generate_standard_board(board)
  let player: PlayerState
  player.resources[Resource::ore.value] = 4
  return board.can_maritime_trade(player, 0, Resource::ore, Resource::grain) and !board.can_maritime_trade(player, 0, Resource::ore, Resource::ore)

# A settlement on a generic harbor improves every bank exchange to three-to-one.
fun test_generic_harbor_trade_rate() -> Bool:
  let board: Board
  generate_standard_board(board)
  board.owner[2] = 2
  board.building[2] = 1
  return board.trade_rate(2, Resource::wool) == 3 and board.trade_rate(1, Resource::wool) == 4

# A specialized harbor gives its owner a two-to-one rate only for the resource
# printed on that harbor.
fun test_specific_harbor_trade_rate() -> Bool:
  let board: Board
  generate_standard_board(board)
  board.owner[36] = 0
  board.building[36] = 1
  return board.trade_rate(0, Resource::brick) == 2 and board.trade_rate(0, Resource::ore) == 4

# A producing hex grants one card per settlement and two per city to every
# adjacent owner.
fun test_production_pays_settlements_and_cities() -> Bool:
  let board: Board
  generate_standard_board(board)
  let players: PlayerState[4]
  let first = board.hex_vertices[0]
  let second = board.hex_vertices[1]
  board.owner[first] = 0
  board.building[first] = 1
  board.owner[second] = 1
  board.building[second] = 2
  board.produce(players, 4, board.number[0])
  return players[0].resources[board.terrain[0]] == 1 and players[1].resources[board.terrain[0]] == 2

# The robber suppresses all production from its occupied terrain hex.
fun test_robber_blocks_production() -> Bool:
  let board: Board
  generate_standard_board(board)
  let players: PlayerState[4]
  let vertex = board.hex_vertices[0]
  board.owner[vertex] = 0
  board.building[vertex] = 2
  board.robber_hex = 0
  board.produce(players, 4, board.number[0])
  return players[0].resource_total() == 0

# Only the second setup settlement grants its neighboring starting resources;
# desert adjacency never grants a card.
fun test_initial_resource_grant_uses_adjacent_land() -> Bool:
  let board: Board
  generate_standard_board(board)
  let player: PlayerState
  board.grant_second_settlement_resources(player, board.hex_vertices[0])
  return player.resource_total() == 3 and player.resources[Resource::brick.value] == 1 and player.resources[Resource::lumber.value] == 1 and player.resources[Resource::grain.value] == 1

# A new game first requires a legal three- or four-player configuration before
# exposing any board-placement actions.
fun test_game_starts_with_player_configuration() -> Bool:
  let game = play()
  return can game.configure(make_player_count(3)) and can game.configure(make_player_count(4)) and !game.is_done()

# Placing a setup settlement records its owner and piece before requiring an
# incident road from the same newly occupied intersection.
fun test_setup_transition_requires_incident_road() -> Bool:
  let game = play()
  game.configure(make_player_count(4))
  complete_generation(game)
  game.setup_settlement(make_site(0))
  return game.board.owner[0] == 0 and game.board.settlement_count(0) == 1 and can game.setup_road(make_path(0)) and !(can game.setup_road(make_path(2)))

# Completing all eight snake-order placements enters player zero's mandatory
# roll phase with two settlements and roads per player.
fun test_complete_setup_enters_roll_phase() -> Bool:
  let game = play()
  complete_setup(game)
  return game.current_player == 0 and game.board.settlement_count(0) == 2 and game.board.road_count(3) == 2 and can game.roll(make_die(1), make_die(1))

# A non-seven roll records its sum, performs production, and advances into the
# active player's trade/build phase.
fun test_normal_roll_opens_build_phase() -> Bool:
  let game = play()
  complete_setup(game)
  game.roll(make_die(1), make_die(1))
  return game.last_roll == 2 and can game.end_turn()

# Ending a build phase passes the next mandatory roll to the player on the left.
fun test_end_turn_advances_player() -> Bool:
  let game = play()
  complete_setup(game)
  game.roll(make_die(1), make_die(1))
  game.end_turn()
  return game.current_player == 1 and can game.roll(make_die(1), make_die(1))


fun fuzz(Vector<Byte> input):
  if input.size() == 0:
    return
  let state = play()
  let any_action: AnyGameAction
  let parsed_actions = parse_actions(any_action, input)
  for current_action in parsed_actions:
    if can apply(current_action, state):
      apply(current_action, state)

# A robber theft is legal only from an opponent with a building beside the new
# robber hex and a card of the explicitly selected random resource type.
fun test_robber_victim_must_border_destination() -> Bool:
  let board: Board
  generate_standard_board(board)
  let players: PlayerState[4]
  let victim_vertex = board.hex_vertices[0]
  board.owner[victim_vertex] = 1
  board.building[victim_vertex] = 1
  players[1].resources[Resource::grain.value] = 1
  return board.can_rob(players, 4, 0, 0, 1, Resource::grain) and !board.can_rob(players, 4, 0, 18, 1, Resource::grain)

# If no adjacent opponent has a resource, selecting the active player performs
# the mandatory robber move without fabricating a theft.
fun test_robber_can_move_without_eligible_victim() -> Bool:
  let board: Board
  generate_standard_board(board)
  let players: PlayerState[4]
  return board.can_rob(players, 4, 0, 0, 0, Resource::brick)

# A player may play at most one usable development card per turn; the legality
# helper also validates the dedicated action's destination and victim inputs.
fun test_knight_is_limited_to_one_per_turn() -> Bool:
  let board: Board
  generate_standard_board(board)
  let players: PlayerState[4]
  players[0].development = 1
  return board.can_play_knight(players, 4, 0, false, make_hex(0), make_player(0), Resource::brick) and !board.can_play_knight(players, 4, 0, true, make_hex(0), make_player(0), Resource::brick)


# The first player to expose three knights receives Largest Army and its two
# victory points; fewer knights do not qualify.
fun test_largest_army_requires_three_knights() -> Bool:
  let players: PlayerState[4]
  players[0].knights = 2
  let owner = update_largest_army(players, -1, 0)
  if owner != -1 or largest_army_points(owner, 0) != 0:
    return false
  players[0].knights = 3
  owner = update_largest_army(players, owner, 0)
  return owner == 0 and largest_army_points(owner, 0) == 2

# Largest Army changes hands only when another player has strictly more played
# knights, removing the old holder's bonus before awarding the new one.
fun test_largest_army_transfers_on_strict_lead() -> Bool:
  let players: PlayerState[4]
  players[0].knights = 3
  let owner = update_largest_army(players, -1, 0)
  players[1].knights = 3
  owner = update_largest_army(players, owner, 1)
  if owner != 0:
    return false
  players[1].knights = 4
  owner = update_largest_army(players, owner, 1)
  return owner == 1 and largest_army_points(owner, 0) == 0 and largest_army_points(owner, 1) == 2


# Piece counts are calculated directly from board ownership, so placing and
# upgrading pieces cannot make cached inventory counters stale.
fun test_piece_count_accessors_follow_board() -> Bool:
  let board: Board
  generate_standard_board(board)
  board.owner[0] = 2
  board.building[0] = 1
  board.owner[2] = 2
  board.building[2] = 2
  board.road_owner[0] = 2
  board.road_owner[5] = 2
  return board.settlement_count(2) == 1 and board.city_count(2) == 1 and board.road_count(2) == 2 and board.total_road_count() == 2

# The remaining development deck is derived from cards in every live category
# rather than maintained as a second, potentially divergent counter.
fun test_development_cards_left_is_derived() -> Bool:
  let players: PlayerState[4]
  players[0].development = 2
  players[1].new_development = 3
  players[2].knights = 4
  players[3].victory_cards = 1
  return development_cards_left(players, 4) == 15

# During snake setup the active player accessor derives the owner from completed
# roads; after setup it reports the ordinary turn owner.
fun test_active_player_is_derived_during_setup() -> Bool:
  let game = play()
  game.configure(make_player_count(4))
  complete_generation(game)
  if active_player(game) != 0:
    return false
  game.setup_settlement(make_site(0))
  game.setup_road(make_path(0))
  return active_player(game) == 1


# Choosing three players shortens setup to six settlement-road pairs and uses
# the official 0,1,2,2,1,0 snake before player zero's first roll.
fun test_three_player_configuration() -> Bool:
  let game = play()
  game.configure(make_player_count(3))
  complete_generation(game)
  game.setup_settlement(make_site(0))
  game.setup_road(make_path(0))
  game.setup_settlement(make_site(2))
  game.setup_road(make_path(1))
  game.setup_settlement(make_site(4))
  game.setup_road(make_path(3))
  game.setup_settlement(make_site(6))
  game.setup_road(make_path(6))
  game.setup_settlement(make_site(8))
  game.setup_road(make_path(8))
  game.setup_settlement(make_site(10))
  game.setup_road(make_path(11))
  return game.player_count.value == 3 and active_player(game) == 0 and game.board.total_road_count() == 6 and can game.roll(make_die(1), make_die(1))

# Serialized or manually malformed player counts are rejected by the first
# action before they can affect setup bounds or player-array indexing.
fun test_invalid_player_configuration_is_rejected() -> Bool:
  let game = play()
  return !(can game.configure(make_player_count(2))) and !(can game.configure(make_player_count(5)))


# The discard owner is determined by the first participating player who still
# owes cards, so callers only choose which resource that player returns.
fun test_discarding_player_is_derived() -> Bool:
  let remaining: Int[4]
  remaining[1] = 2
  remaining[3] = 1
  if discarding_player(remaining, 4) != 1:
    return false
  remaining[1] = 0
  if discarding_player(remaining, 4) != 3:
    return false
  remaining[3] = 0
  return discarding_player(remaining, 4) == -1

# Inactive fourth-player state cannot become the discard owner in a configured
# three-player game.
fun test_discarding_player_ignores_inactive_slots() -> Bool:
  let remaining: Int[4]
  remaining[3] = 4
  return discarding_player(remaining, 3) == -1 and pending_discards(remaining, 3) == 0

# Board initialization creates an empty topology; terrain is supplied through
# actions rather than silently installing a hard-coded beginner layout.
fun test_board_generation_starts_unassigned() -> Bool:
  let board: Board
  board.initialize()
  return board.unplaced_terrain_count() == 19 and board.next_number_hex() == -1 and board.robber_hex == -1 and board.generated_harbor_count() == 0

# A generated island consumes the official terrain inventory: three brick,
# three ore, four of every other resource, and one desert under the robber.
fun test_generated_terrain_has_official_inventory() -> Bool:
  let board: Board
  generate_standard_board(board)
  return board.terrain_count(Terrain::brick) == 3 and board.terrain_count(Terrain::lumber) == 4 and board.terrain_count(Terrain::wool) == 4 and board.terrain_count(Terrain::grain) == 4 and board.terrain_count(Terrain::ore) == 3 and board.terrain_count(Terrain::desert) == 1 and board.terrain[board.robber_hex] == -1

# Fully random number generation consumes the official token inventory and
# prevents either red number from bordering another red number.
fun test_generated_numbers_have_official_inventory() -> Bool:
  let board: Board
  generate_standard_board(board)
  let six = NumberToken::six
  let eight = NumberToken::eight
  if board.number_count(six) != 2 or board.number_count(eight) != 2 or board.number_count(NumberToken::two) != 1 or board.number_count(NumberToken::twelve) != 1:
    return false
  let left = 0
  while left != HEX_COUNT:
    if board.number[left] == 6 or board.number[left] == 8:
      let right = left + 1
      while right != HEX_COUNT:
        if (board.number[right] == 6 or board.number[right] == 8) and board.hexes_adjacent(left, right):
          return false
        right = right + 1
    left = left + 1
  return true

# Harbor generation places exactly four generic and one of each specialized
# harbor on nine distinct coastal frame locations.
fun test_generated_harbors_have_official_inventory() -> Bool:
  let board: Board
  generate_standard_board(board)
  return board.generated_harbor_count() == 9 and board.harbor_count(Harbor::generic) == 4 and board.harbor_count(Harbor::brick) == 1 and board.harbor_count(Harbor::lumber) == 1 and board.harbor_count(Harbor::wool) == 1 and board.harbor_count(Harbor::grain) == 1 and board.harbor_count(Harbor::ore) == 1

# After player configuration, terrain generation is the first board decision;
# settlement placement remains unavailable until the island is complete.
fun test_game_generates_board_before_player_setup() -> Bool:
  let game = play()
  game.configure(make_player_count(4))
  return can game.generate_terrain(Terrain::desert) and !(can game.setup_settlement(make_site(0)))

# Malformed generated component values are rejected before inventory counters or
# board arrays can be accessed with them.
fun test_malformed_generation_values_are_rejected() -> Bool:
  let game = play()
  game.configure(make_player_count(4))
  let terrain = Terrain::brick
  terrain.value = 9
  return !(can game.generate_terrain(terrain))


# A fully generated board passes a single comprehensive validator before any
# player is allowed to place a settlement.
fun test_generated_board_validator_accepts_complete_board() -> Bool:
  let board: Board
  generate_standard_board(board)
  return board.valid_generated_board()

# Generation rejects exhausted terrain types, including extra common terrain
# and a second desert, rather than creating the wrong tile inventory.
fun test_terrain_generation_rejects_exhausted_inventory() -> Bool:
  let board: Board
  board.initialize()
  board.generate_terrain(Terrain::brick)
  board.generate_terrain(Terrain::brick)
  board.generate_terrain(Terrain::brick)
  if board.can_generate_terrain(Terrain::brick):
    return false
  board.generate_terrain(Terrain::desert)
  return !board.can_generate_terrain(Terrain::desert)

# The final validator rejects a desert with a production token or a robber that
# no longer occupies the unique desert.
fun test_generated_board_rejects_invalid_desert_state() -> Bool:
  let board: Board
  generate_standard_board(board)
  board.number[board.robber_hex] = 5
  if board.valid_generated_board():
    return false
  generate_standard_board(board)
  board.robber_hex = 0
  return !board.valid_generated_board()

# The final validator independently detects adjacent red production numbers,
# even if state was reconstructed without using generation preconditions.
fun test_generated_board_rejects_adjacent_red_numbers() -> Bool:
  let board: Board
  generate_standard_board(board)
  board.number[0] = 6
  board.number[2] = 5
  board.number[1] = 8
  board.number[4] = 2
  return board.hexes_adjacent(0, 1) and !board.valid_generated_board()

# Harbor validation rejects mismatched endpoints and verifies every configured
# harbor occupies an actual one-hex coastal edge.
fun test_generated_board_rejects_malformed_harbor() -> Bool:
  let board: Board
  generate_standard_board(board)
  let edge = board.harbor_edge(0)
  if board.edge_hex_count(edge) != 1:
    return false
  board.harbor_rate[board.edge_b[edge]] = 2
  return !board.valid_generated_board()

# Token generation enforces the one-copy 2/12 limits and the two-copy limit for
# every other production number.
fun test_number_generation_rejects_exhausted_inventory() -> Bool:
  let board: Board
  generate_standard_board(board)
  board.number[18] = 0
  if board.can_generate_number(NumberToken::two):
    return false
  generate_standard_board(board)
  board.number[18] = 0
  return !board.can_generate_number(NumberToken::six)

# Harbor generation enforces four generic pieces and exactly one specialized
# harbor of each resource type.
fun test_harbor_generation_rejects_exhausted_inventory() -> Bool:
  let board: Board
  generate_standard_board(board)
  return !board.can_generate_harbor(Harbor::generic) and !board.can_generate_harbor(Harbor::ore)


# The trade/build phase exposes each alternative as its own action, with no
# command tag or unrelated placeholder arguments required by callers.
fun test_turn_alternatives_are_independent_actions() -> Bool:
  let game = play()
  complete_setup(game)
  let resource = 0
  while resource != RESOURCE_COUNT:
    game.players[0].resources[resource] = 10
    resource = resource + 1
  game.roll(make_die(1), make_die(1))
  return can game.build_road(make_path(5)) and can game.build_city(make_site(0)) and can game.buy_development() and can game.maritime_trade(Resource::brick, Resource::ore) and can game.end_turn()

# Buying a development card through its dedicated no-argument action pays only
# its actual cost and places the new card in the current-turn zone.
fun test_buy_development_action_has_no_unused_arguments() -> Bool:
  let game = play()
  complete_setup(game)
  game.players[0].resources[Resource::ore.value] = 1
  game.players[0].resources[Resource::wool.value] = 1
  game.players[0].resources[Resource::grain.value] = 1
  game.roll(make_die(1), make_die(1))
  if !(can game.buy_development()):
    return false
  game.buy_development()
  return game.players[0].new_development == 1 and game.players[0].resources[Resource::ore.value] == 0 and game.players[0].resources[Resource::wool.value] == 0 and game.players[0].resources[Resource::grain.value] == 0

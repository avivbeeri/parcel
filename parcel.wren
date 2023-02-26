import "dome" for Window, Process, Platform, Log
import "graphics" for Canvas, Color, Font
import "collections" for PriorityQueue, Queue, Set, HashMap
import "math" for Vec, Elegant, M
import "json" for Json
import "random" for Random

var SCALE = 3
var MAX_TURN_SIZE = 30

class Event {
  construct new() {
    _cancelled = false
    // lower is better
    _priority = 1
    _turn = null
  }
  priority=(v) { _priority = v }
  priority { _priority }
  turn=(v) { _turn = v }
  turn { _turn }

  cancel() {
    _cancelled = true
  }
  cancelled { _cancelled }
}

class Stateful {
  construct new() {
    _data = {}
  }
  construct new(data) {
    _data = {}
    for (key in data.keys) {
      _data[key] = data[key]
    }
  }

  static copyValue(value) {
    if (value is Map) {
      var copy = {}
      for (key in value.keys) {
        copy[key] = copyValue(value[key])
      }
      return copy
    }
    if (value is List) {
      return value.map {|entry| copyValue(entry) }.toList
    }
    return value
  }

  data { _data }
  [key] { _data[key] }
  [key]=(v) { _data[key] = v }
  has(prop) { _data.containsKey(prop) && _data[prop] != null }
}


// ==================================

class ActionResult {
  static success { ActionResult.new(true) }
  static failure { ActionResult.new(false) }
  static valid { ActionResult.new(true, false) }
  static invalid { ActionResult.new(false, true) }

  construct new(success) {
    _success = success
    _invalid = false
    _alt = null
  }
  construct new(success, invalid) {
    _success = success
    _invalid = invalid
    _alt = null
  }

  construct alternate(action) {
    _success = true
    _invalid = false
    _alt = action
  }

  alternate { _alt }
  succeeded { _success }
  invalid { _invalid }
  toString { "ActionResult [%(succeeded), %(alternate)]"}
}
// ==================================

class Action {
  static none { Action.new() }
  construct new() {}
  bind(entity) {
    _source = entity
    return this
  }

  evaluate() {
    return ActionResult.success
  }
  perform() {
    return ActionResult.success
  }
  cost() { MAX_TURN_SIZE }

  ctx { _source.ctx }
  src { _source }
  source { _source }
  toString { (this.type == Action) ? "<no action>" : "<%(this.type.name)>" }
}

class FastAction is Action {
  construct new() {}
  evaluate() {
    return ActionResult.success
  }
  perform() {
    return ActionResult.success
  }
  cost() {
    if (src.name == "Player") {
      return MAX_TURN_SIZE / 3
    }
    return MAX_TURN_SIZE
  }
}
class FakeAction is Action {
  construct new() {}
  evaluate() {
    return ActionResult.success
  }
  perform() {
    src.zone = src.zone + 1
    return ActionResult.success
  }
}

class Entity is Stateful {
  construct new() {
    super()
    _state = 2 // Active
    _pos = Vec.new()
    _size = Vec.new(1, 1)
    _actions = Queue.new()
    _events = Queue.new()
    _lastTurn = 0
    _zone = 0
  }

  pushAction(action) { _actions.add(action) }

  bind(ctx, id) {
    _id = id
    _ctx = ctx
    return this
  }

  id { _id }
  ctx { _ctx }
  events { _events }

  state { _state }
  state=(v) { _state = v }
  zone { _zone }
  zone=(v) { _zone = v }
  pos { _pos }
  pos=(v) { _pos = v }
  size { _size }
  size=(v) { _size = v }
  lastTurn { _lastTurn }
  lastTurn=(v) { _lastTurn }

  // Entities don't update themselves
  // They supply the next action they want to perform
  // and the "world" applies it.
  hasActions() { !_actions.isEmpty }
  getAction() {
    return _actions.dequeue() || Action.none
  }
  endTurn() {}

  occupies(vec) { occupies(vec.x, vec.y) }
  occupies(x, y) {
    return pos != null &&
           pos.x <= x &&
           x <= pos.x + size.x - 1 &&
           pos.y <= y &&
           y <= pos.y + size.y - 1
  }

  name { null }
  toString { name ? name : "%(this.type.name) (id: %(_id))" }

  ref { EntityRef.new(ctx, entity.id) }
}

// Weak reference
class EntityRef {
  construct new(ctx, id) {
    _id = id
    _ctx = ctx
  }
  id { _id }
  hash() { _id }
  pushAction(action) {
    var actor = _ctx.getEntityById(_id)
    if (actor != null) {
      actor.pushAction(action)
    }
  }
}

class Zone is Stateful {
  construct new(map) {
    super()
    _map = map
  }
  map { _map }
  ctx { _ctx }
  ctx=(v) { _ctx = v }
}

class World is Stateful {
  construct new() {
    super()
    _started = false
    _complete = false
    _entities = {}
    _ghosts = {}
    _tagged = {}
    _nextId = 1
    _zones = []
    _zoneIndex = 0
    _step = 1
    _turn = -1
    _events = Queue.new()
    _queue = PriorityQueue.min()
  }
  start() { _started = true }

  // The size of a single timestep
  step { _step }
  step=(v) { _step = v }

  events { _events }

  // Does not guarantee an order
  allEntities { _entities.values.toList }
  otherEntities() { _entities.values.where{|entity| entity.zone != _zoneIndex }.toList  }
  entities() { _entities.values.where{|entity| entity.pos == null || entity.zone == _zoneIndex }.toList  }

  complete { _complete }
  complete=(v) { _complete = v }

  zoneIndex { _zoneIndex }

  changeZone(newZone) {
    _queue.clear()
    _zoneIndex = newZone
    for (entity in entities()) {
      _queue.add(entity.id, _turn)
    }
    // TODO emit event
  }

  nextId() {
    var id = _nextId
    _nextId = _nextId + 1
    return id
  }

  zone { _zones[_zoneIndex] }
  addZone(zone) {
    _zones.add(zone)
    zone.ctx = this
    return this
  }

  getEntityById(id) { _entities[id] || _ghosts[id] }
  getEntityByTag(tag) { _tagged[tag] }

  pushEvent(event) {
    _events.add(event)
    // TODO record in the event the turn it occurred
    entities().each{|entity| entity.events.add(event) }
  }

  addEntity(tag, entity) {
    var ref = addEntity(entity)
    _tagged[tag] = entity
    return ref
  }

  addEntity(entity) {
    var id = nextId()
    entity.zone = _zoneIndex
    _entities[id] = entity.bind(this, id)
    // TODO Add an event for adding an entity to the world
    var t = _turn
    if (_started && _queue.count > 0) {
      var remaining = MAX_TURN_SIZE - (_queue.peekPriority() % MAX_TURN_SIZE)
      Log.d("Remaining %(remaining / MAX_TURN_SIZE)")
      t = _queue.peekPriority()
      t = (t + remaining)
    }
    Log.d("Adding %(entity) at time %(t)")

    _queue.add(id, t)
    return EntityRef.new(this, entity.id)
  }

  removeEntity(ref) {
    var id
    var entity
    if (ref is Entity || ref is EntityRef) {
      id = ref.id
    }
    if (ref is Num) {
      id = ref
    }

    entity = _entities.remove(id)
    if (entity == null) {
      // we've already removed it or it doesn't exist
      return
    }

    _ghosts[id] = entity
    entity.state = 1

    // remove all tags for entity
    var entityTags = []
    for (tag in _tagged.keys) {
      if (_tagged[tag].id == id) {
        entityTags.add(tag)
        break
      }
    }
    entityTags.each {|tag| _tagged.remove(tag) }
    //  todo emit an event here for entity being removed
  }

  // Attempt to advance the world by one turn
  // returns true if something changed
  advance() {
    if (!_started) {
      Fiber.abort("Attempting to advance the world before start() has been called")
    }
    var actor = null
    var actorId
    var turn
    Log.d("begin advance")
    while (_queue.count > 0 && actor == null) {
      turn = _queue.peekPriority()
      actorId = _queue.remove()
      actor = getEntityById(actorId)
    }
    if (actor == null) {
      // No actors, no actions to perform
      return false
    }
    Log.d("Begin %(actor) turn %(turn)")

    _turn = turn
    var action = actor.getAction()
    if (action == null) {
        _queue.add(actorId, turn)
        // Actor isn't ready to provide action (player)
        return false
    }
    var result
    while (true) {
      Log.d("%(actor) evaluate: %(action)")
      result = action.bind(actor).evaluate()
      if (result.invalid) {
        // Action wasn't successful, allow retry
        _queue.add(actorId, turn)
        Log.d("%(actor): rejected, retry")
        return false
      }
      if (!result.alternate) {
        Log.d("%(actor): accepted")
        // No more actions to consider
        break
      }
      Log.d("%(actor): alternate")
      action = result.alternate
    }

    // TODO consider if this is the right place to clear the actor's events
    actor.events.clear()
    Log.i("%(actor): performing %(action)")
    result = action.perform()
    actor.endTurn()
    actor.lastTurn = turn
    if (actor.pos == null || actor.zone == _zoneIndex) {
      Log.d("%(actor): next turn is  %(turn + action.cost())")
      _queue.add(actorId, turn + action.cost())
    }

    if (!result.succeeded) {
      // Action wasn't successful, allow retry
      Log.i("%(actor): failed, time loss")
      return false
    } else {
      Log.i("%(actor): success")
      return true
    }
  }
}

// Generic element
class Element {
  construct new() {
    _elements = []
  }
  parent { _parent }
  parent=(v) { _parent = v }
  elements { _elements }

  update() {
    for (element in _elements) {
      element.update()
    }
  }
  process(events) {
    for (element in _elements) {
      element.process(events)
    }
  }
  draw() {
    for (element in _elements) {
      element.draw()
    }
  }

  addElement(element) {
    _elements.add(element)
    element.parent = this
  }
  removeSelf() {
    if (parent) {
      parent.removeElement(this)
    }
  }
  removeElement(element) {
    _elements.remove(element)
  }
}

class Scene is Element {
  construct new(args) {
    super()
  }

  game { _game }
  game=(v) { _game = v }
}

class ParcelMain {
  construct new(scene) {
    Window.lockstep = true
    Window.integerScale = true
    Window.title = Config && Config["title"] || "Parcel"
    Canvas.resize(768,576)
    Window.resize(Canvas.width*SCALE, Canvas.height*SCALE)
    _initial = scene
    _args = []
  }

  construct new(scene, args) {
    Window.lockstep = true
    Canvas.resize(768,576)
    Window.resize(Canvas.width*SCALE, Canvas.height*SCALE)
    Window.title = Config && Config["title"] || "Parcel"
    _initial = scene
    _args = args
  }

  init() {
    push(_initial, _args)
  }

  update() {
    if (_scene == null) {
      Process.exit()
      return
    }
    _scene.update()
  }
  draw(dt) {
    _scene.draw()
  }

  push(scene) { push(scene, []) }
  push(scene, args) {
    _scene = scene.new(args)
    _scene.game = this
  }
}

class Tile is Stateful {
  static void() {
    return Tile.new({ "void": true })
  }
  construct new() {
    super({})
  }
  construct new(data) {
    super(data)
  }

  toString { "Tile: %(data)" }
}


var DIR_FOUR = [
  Vec.new(-1, 0), // left
  Vec.new(0, -1), // up
  Vec.new(1, 0), // right
  Vec.new(0, 1) // down
]
var DIR_EIGHT = [
  Vec.new(-1, 0), // W
  Vec.new(0, -1), // N
  Vec.new(1, 0), // E
  Vec.new(0, 1), // S
  Vec.new(-1, -1), // NW
  Vec.new(1, -1), // NE
  Vec.new(1, 1), // SE
  Vec.new(-1, 1) // SW
]

class Graph {
  neighbours(pos) {}
  allNeighbours(pos) {}
  cost(aPos, bPos) { 1 }
  heuristic(aPos, bPos) { 0 }
}

class TileMap is Graph {
  construct new() {
    _tiles = {}
    _default = { "void": true }
    _undefTile = Tile.new(_default)
    _min = Vec.new()
    _max = Vec.new()
    _xRange = 0..0
    _yRange = 0..0
  }

  default { _default }
  default=(v) { _default = v }

  clearAll() { _tiles = {} }
  clear(vec) { clear(vec.x, vec.y) }
  clear(x, y) {
    var pair = Elegant.pair(x, y)
    _tiles[pair] = null
  }

  report() {
    for (key in _tiles.keys) {
      System.print(Elegant.unpair(key))
    }
  }

  [vec] {
    return this[vec.x, vec.y]
  }

  [vec]=(tile) {
    this[vec.x.floor, vec.y.floor] = tile
  }

  [x, y] {
    var pair = Elegant.pair(x, y)
    if (!_tiles[pair]) {
      return _undefTile
    }
    return _tiles[pair]
  }

  [x, y]=(tile) {
    _min.x = _min.x.min(x)
    _min.y = _min.y.min(y)
    _max.x = _max.x.max(x)
    _max.y = _max.y.max(y)
    _xRange = _min.x.._max.x
    _yRange = _min.y.._max.y
    var pair = Elegant.pair(x.floor, y.floor)
    _tiles[pair] = tile
  }

  inBounds(vec) { inBounds(vec.x, vec.y) }
  inBounds(x, y) { !this[x, y]["void"] }
  isSolid(vec) { isSolid(vec.x, vec.y) }
  isSolid(x, y) { !inBounds(x, y) || this[x, y]["solid"] }
  isFloor(vec) { isFloor(vec.x, vec.y) }
  isFloor(x, y) { inBounds(x, y) && !this[x, y]["solid"] }

  tiles { _tiles }
  xRange { _xRange }
  yRange { _yRange }
  width { _max.x - _min.x + 1 }
  height { _max.y - _min.y + 1 }
  cost(aPos, bPos) {
    if (this[bPos]["sticky"]) {
      return 2
    }
    return 1
  }
  heuristic(aPos, bPos) {
    return (aPos - bPos).manhattan
  }
}

class TileMap4 is TileMap {
  construct new() { super() }
  neighbours(pos) {
    return DIR_FOUR.map {|dir| pos + dir }.where{|pos| !this.isSolid(pos) }.toList
  }
  allNeighbours(pos) {
    return DIR_FOUR.map {|dir| pos + dir }.where{|pos| this.inBounds(pos) }.toList
  }
}
class TileMap8 is TileMap {
  construct new() { super() }
  neighbours(pos) {
    return DIR_EIGHT.map {|dir| pos + dir }.where{|pos| !this.isSolid(pos) }.toList
  }
  allNeighbours(pos) {
    return DIR_EIGHT.map {|dir| pos + dir }.where{|pos| this.inBounds(pos) }.toList
  }
  successors(current, start, end) {
    var successors = []
    for (node in neighbours(current)) {
      var dx = M.mid(-1, node.x - current.x, 1)
      var dy = M.mid(-1, node.y - current.y, 1)

      var jumpPoint = jump(current.x, current.y, dx, dy, start, end)
      if (jumpPoint) {
        successors.add(jumpPoint)
      }
    }
    return successors
  }

  jump(cx, cy, dx, dy, start, end) {
    var next = Vec.new(cx + dx, cy + dy)

    // Blocked, no jump
    if (isSolid(next)) {
      return null
    }

    // We can jump to goal
    if (next == end) {
      return next
    }

    // diagonal
    if (dx != 0 && dy != 0) {
      if (isSolid(cx + dx, cy)) {
        return next
      } else if (isSolid(cx, cy + dy)) {
        return next
      }

      // Check horizonstal and vertical neighbours
      if (jump(next.x, next.y, dx, 0, start, end) != null ||
          jump(next.x, next.y, 0, dy, start, end) != null) {

        return next
      }
    } else {
      // horizontal
      if (dx != 0) {
        if (isSolid(cx, cy + 1)) {
          if (!isSolid(cx + dx, cy + 1)) {
            return next
          }
        } else if (isSolid(cx, cy - 1)) {
          if (!isSolid(cx + dx, cy - 1)) {
            return next
          }
        }
      } else {
        if (isSolid(cx + 1, cy)) {
          if (!isSolid(cx + 1, cy + dy)) {
            return next
          }
        } else if (isSolid(cx - 1, cy)) {
          if (!isSolid(cx - 1, cy + dy)) {
            return next
          }
        }
      }
    }
    return jump(next.x, next.y, dx, dy, start, end)
  }
}

class BreadthFirst {
  static search(map, start, goal) {
    var cameFrom = HashMap.new()
    var frontier = Queue.new()
    if (!(start is Sequence)) {
      start = [ start ]
    }
    for (pos in start) {
      frontier.add(pos)
      cameFrom[pos] = null
    }
    while (!frontier.isEmpty) {
      var current = frontier.remove()
      if (current == goal) {
        break
      }
      for (next in map.neighbours(current)) {
        if (!cameFrom.containsKey(next)) {
          cameFrom[next] = current
          map[next]["cost"] = 0
          frontier.add(next)
        }
      }
    }
    var current = goal
    if (cameFrom[goal] == null) {
      return null // There is no valid path
    }

    var path = []
    while (!start.contains(current)) {
      path.add(current)
      current = cameFrom[current]
    }
    for (pos in path) {
      map[pos]["seen"] = true
    }
    return path
  }
}

class Dijkstra {
  static search(map, start, goal) {
    var frontier = PriorityQueue.min()
    var cameFrom = HashMap.new()
    var costSoFar = HashMap.new()
    if (!(start is Sequence)) {
      start = [ start ]
    }
    for (pos in start) {
      frontier.add(pos, 0)
      cameFrom[pos] = null
      costSoFar[pos] = 0
    }
    while (!frontier.isEmpty) {
      var current = frontier.remove()
      if (current == goal) {
        break
      }
      var currentCost = costSoFar[current]
      for (next in map.neighbours(current)) {
        var newCost = currentCost + map.cost(current, next)
        if (!costSoFar.containsKey(next) || newCost < costSoFar[next]) {
          costSoFar[next] = newCost
          map[next]["cost"] = newCost
          var priority = newCost
          frontier.add(next, newCost)
          cameFrom[next] = current
        }
      }
    }

    var current = goal
    if (cameFrom[goal] == null) {
      return null // There is no valid path
    }

    var path = []
    while (!start.contains(current)) {
      path.add(current)
      current = cameFrom[current]
    }
    for (pos in path) {
      map[pos]["seen"] = true
    }
    return path
  }
  static map(map, start) {
    var frontier = PriorityQueue.min()
    var cameFrom = HashMap.new()
    var costSoFar = HashMap.new()
    if (!(start is Sequence)) {
      start = [ start ]
    }
    for (pos in start) {
      frontier.add(pos, 0)
      cameFrom[pos] = null
      costSoFar[pos] = 0
    }
    while (!frontier.isEmpty) {
      var current = frontier.remove()
      var currentCost = costSoFar[current]
      var newCost = currentCost + 1
      for (next in map.neighbours(current)) {
        if (!cameFrom.containsKey(next) || newCost < costSoFar[next]) {
          costSoFar[next] = newCost
          var priority = newCost
          frontier.add(next, newCost)
          cameFrom[next] = current
        }
      }
    }
    return [costSoFar, cameFrom]
  }
}

class AStar {
  static fastSearch(map, start, goal) {
    if (goal == null) {
      Fiber.abort("AStarSearch doesn't work without a goal")
    }
    var frontier = PriorityQueue.min()
    var cameFrom = HashMap.new()
    var costSoFar = HashMap.new()
    if (start is Sequence) {
      Fiber.abort("fastSearch doesn't support multiple goals")
    }
    frontier.add(start, 0)
    cameFrom[start] = null
    costSoFar[start] = 0
    while (!frontier.isEmpty) {
      var current = frontier.remove()
      if (current == goal) {
        break
      }
      var currentCost = costSoFar[current]
      for (next in map.successors(current, start, goal)) {
        var newCost = currentCost + map.cost(current, next)
        if (!costSoFar.containsKey(next) || newCost < costSoFar[next]) {
          costSoFar[next] = newCost
          map[next]["cost"] = newCost
          var priority = newCost + map.heuristic(next, goal)
          frontier.add(next, priority)
          cameFrom[next] = current
        }
      }
    }
    return cameFrom
  }
  static buildFastPath(map, start, goal, cameFrom) {
    var current = goal
    if (!cameFrom) {
      Fiber.abort("There is no valid path")
      return
    }
    if (cameFrom[goal] == null) {
      return null // There is no valid path
    }

    var path = []
    var next = null
    while (start != current) {
      path.add(current)
      next = cameFrom[current]
      var d = next - current
      var unit = Vec.new(d.x.sign, d.y.sign)

      var intermediate = current
      while (intermediate != next && intermediate != start) {
        path.add(intermediate)
        intermediate = intermediate + unit
      }
      current = next
    }
    for (pos in path) {
      map[pos]["seen"] = true
    }

  }
  static search(map, start, goal) {
    if (goal == null) {
      Fiber.abort("AStarSearch doesn't work without a goal")
    }
    var frontier = PriorityQueue.min()
    var cameFrom = HashMap.new()
    var costSoFar = HashMap.new()
    if (!(start is Sequence)) {
      start = [ start ]
    }
    for (pos in start) {
      frontier.add(pos, 0)
      cameFrom[pos] = null
      costSoFar[pos] = 0
    }
    while (!frontier.isEmpty) {
      var current = frontier.remove()
      if (current == goal) {
        break
      }
      var currentCost = costSoFar[current]
      for (next in map.neighbours(current)) {
        var newCost = currentCost + map.cost(current, next)
        if (!costSoFar.containsKey(next) || newCost < costSoFar[next]) {
          costSoFar[next] = newCost
          map[next]["cost"] = newCost
          var priority = newCost + map.heuristic(next, goal)
          frontier.add(next, priority)
          cameFrom[next] = current
        }
      }
    }

    var current = goal
    if (cameFrom[goal] == null) {
      return null // There is no valid path
    }

    var path = []
    while (!start.contains(current)) {
      path.add(current)
      current = cameFrom[current]
    }
    for (pos in path) {
      map[pos]["seen"] = true
    }
    return path
  }
}

class Line {
  static walk(p0, p1) {
    var dx = p1.x-p0.x
    var dy = p1.y-p0.y
    var nx = dx.abs
    var ny = dy.abs
    var sign_x = dx > 0? 1 : -1
    var sign_y = dy > 0? 1 : -1

    var p = Vec.new(p0.x, p0.y)
    var points = [ Vec.new(p.x, p.y) ]
    var ix = 0
    var iy = 0
    while (ix < nx || iy < ny) {
      if ((1 + 2*ix) * ny < (1 + 2*iy) * nx) {
       // next step is horizontal
        p.x = p.x + sign_x
        ix = ix + 1
      } else {
        // next step is vertical
        p.y = p.y + sign_y
        iy = iy + 1
      }
      points.add(Vec.new(p.x, p.y))
    }
    return points
  }

  static linear(p0, p1) {
   var points = []
    var n = chebychev(p0,p1)
    for (step in 0..n) {
      var t = (n == 0) ? 0.0 : step / n
      points.add(vecRound(vecLerp(p0, t, p1)))
    }
    return points
  }

  static chebychev(v0, v1) {
    return M.max(v1.x-v0.x, v1.y-v0.y)
  }

  static vecRound(vec){
    return Vec.new(vec.x.round, vec.y.round, vec.z)
  }
  static vecLerp(v0, p, v1){
    return Vec.new(M.lerp(v0.x, p, v1.x), M.lerp(v0.y, p, v1.y))
  }
}


class DefaultFont {
  static getArea(text) {
    return Vec.new(text.count * 8, 8)
  }
}
class TextUtils {
  static print(text, settings) {
    text = text is String ? text : text.toString
    var color = settings["color"] || Color.black
    var align = settings["align"] || "left"
    var position = settings["position"] || Vec.new()
    // TODO vertical size?
    var size = settings["size"] || Vec.new(Canvas.width, Canvas.height)
    var font = settings["font"] || Font.default
    var fontObj = Font[settings["font"]] || DefaultFont
    var overflow = settings["overflow"] || false

    var lines = []
    var words = text.split(" ")
    var maxWidth = size.x
    var nextLine
    var lineDims = []
    var currentLine

    while (true) {
      currentLine = words.join(" ")
      var area = fontObj.getArea(currentLine)
      nextLine = []
      while (area.x > maxWidth && words.count > 1) {
        // remove the last word, add it to the start of the nextLine
        nextLine.insert(0, words.removeAt(-1))
        currentLine = words.join(" ")
        // compute the current line's area now
        area = fontObj.getArea(currentLine)
        // and recheck
      }

      lineDims.add(area)
      lines.add(currentLine)
      if (nextLine.count == 0) {
        break
      }
      words = nextLine
    }

    if (!overflow) {
      Canvas.clip(position.x, position.y, size.x, size.y)
    }

    var x
    var y = position.y
    for (lineNumber in 0...lines.count) {
      if (align == "left") {
        x = position.x
      } else if (align == "center") {
        x = ((size.x + position.x) - lineDims[lineNumber].x) / 2
      } else if (align == "right") {
        x = position.x + size.x - lineDims[lineNumber].x
      } else {
        Fiber.abort("invalid text alignment: %(align)")
      }
      Canvas.print(lines[lineNumber], x, y, color, font)
      y = y + lineDims[lineNumber].y
    }

    if (!overflow) {
      Canvas.clip()
    }
    return Vec.new(size.x, y - position.y)
  }
}


// ==================================
var Config
var RNG
var fiber = Fiber.new {
  Config = Json.load("config.json")
}
var error = fiber.try()
if (fiber.error) {
  Log.w(fiber.error)
}
Log.level = (Config && Config["logLevel"]) || "INFO"
var Seed = (Config && Config["seed"]) || Platform.time
Log.d("RNG Seed: %(Seed)")
RNG = Random.new(Seed)
// ==================================

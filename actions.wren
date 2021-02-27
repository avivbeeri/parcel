import "./core/action" for Action, ActionResult
import "math" for M, Vec
import "./events" for CollisionEvent, MoveEvent

class MoveAction is Action {
  construct new(dir) {
    super()
    _dir = dir
  }

  handleCollision(pos) {
    var solid = ctx.map[pos]["solid"]
    var occupying = ctx.getEntitiesAtTile(pos.x, pos.y).where {|entity| entity != source }
    var solidEntity = false
    for (entity in occupying) {
      var event = entity.notify(ctx, CollisionEvent.new(this, entity, pos))
      if (!event.cancelled) {
        ctx.events.add(event)
        solidEntity = true
      }
    }
    return solid || solidEntity
  }

  perform() {
    var old = source.pos * 1
    source.vel = _dir
    source.pos.x = source.pos.x + source.vel.x
    source.pos.y = source.pos.y + source.vel.y

    var result = ActionResult.failure

    if (source.pos != old && handleCollision(source.pos)) {
      source.pos = old
    }

    if (source.pos != old) {
      ctx.events.add(MoveEvent.new(source))
      result = ActionResult.success
    }

    if (source.vel.length > 0) {
      source.vel = Vec.new()
    }
    return result
  }
}

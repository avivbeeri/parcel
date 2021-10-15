import "graphics" for Canvas, Color, Font
import "math" for Vec, M
import "input" for Mouse
import "./keys" for InputActions
import "./palette" for EDG32, EDG32A
import "./core/scene" for Ui
import "./core/display" for Display
import "./widgets" for Button

class EntityAdd is Ui {
  construct new(ctx, id) {
    super(ctx)
    _id = id
  }
  finished { true }
  update() {
    ctx.addEntityView(_id)
  }
}
class EntityRemove is Ui {
  construct new(ctx, id) {
    super(ctx)
    _id = id
  }
  finished { true }
  update() {
    ctx.removeEntityView(_id)
  }
}
class EntityBulkLerp is Ui {
  construct new(ctx, entities) {
    super(ctx)
    _alpha = 0
    _entities = entities
    _starts = null
  }

  add(entityView) {
    _entities.add(entityView)
  }

  finished {
    return _alpha >= 1
  }

  speed { 1 / 15 }

  update() {
    if (!_starts) {
      _starts = _entities.map {|entity| entity.pos * 1 }.toList
    }
    _alpha = _alpha + speed
    for (i in 0..._entities.count) {
      var entity = _entities[i]
      var start = _starts[i]
      var dir = (entity.goal - start)
      if (_alpha < 1) {
        entity.pos.x = start.x + dir.x * _alpha
        entity.pos.y = start.y + dir.y * _alpha
      } else {
        entity.pos.x = entity.goal.x
        entity.pos.y = entity.goal.y
      }
    }
  }
  draw() { true }
  drawDiagetic() { true }
}

class CameraLerp is Ui {
  construct new(ctx, goal) {
    super(ctx)
    _camera = ctx.camera
    _start = ctx.camera * 1
    _alpha = 0
    _goal = goal
    _dir = (_goal - _camera)
  }

  finished {
    var dist = (_goal - _camera).length
    return _alpha >= 1 || dist <= speed
  }

  speed { 1 / 15 }

  update() {
    _alpha = _alpha + speed

    var cam = _start + _dir * _alpha

    if (finished) {
      cam = _goal
    }

    // We need to modify the camera in place
    _camera.x = cam.x
    _camera.y = cam.y
  }
  draw() { true }
  drawDiagetic() { true }
}


var Bg = EDG32[2]
var Red = EDG32[26]

class SuccessMessage is Ui {
  construct new(ctx) {
    super(ctx)
  }
  finished { false }

  update() {
    if (InputActions.confirm.justPressed) {
      ctx.game.push(WorldScene, [ WorldGenerator.generate() ])
    }
  }

  draw() {
    Canvas.rectfill(20, 20, Canvas.width - 40, Canvas.height - 40, Bg)
    var area = Display.printCentered("Congratulations!", 30, Color.black, "quiver64")
    Display.printCentered("You captured all the cards!", 30 + area.y + 40, Color.black, "m5x7")

    Display.printCentered("Press START to play again.", Canvas.height - 40, Color.black, "m5x7")
  }
}

class FailureMessage is Ui {
  construct new(ctx) {
    super(ctx)
  }
  finished { false }
  update() {
    if (InputActions.confirm.justPressed) {
      ctx.game.push(WorldScene, [ WorldGenerator.generate() ])
    }
  }

  draw() {
    Canvas.rectfill(20, 20, Canvas.width - 40, Canvas.height - 40, Color.black)
    Canvas.rect(20, 20, Canvas.width - 40, Canvas.height - 40, Red)
    var area = Display.print("You were defeated", {
      "position": Vec.new(30, 30),
      "font": "quiver64",
      "align": "center",
      "color": EDG32[19],
      "size": Vec.new(Canvas.width - 40, Canvas.height - 40),
      "overflow": true
    })
    Display.printCentered("Press START to try again.", Canvas.height - 40, Color.white, "m5x7")
  }
}

class Pause is Ui {
  construct new(ctx, time) {
    super(ctx)
    _end = time
    _t = 0
  }

  finished { _t >= _end}
  update() {
    _t = _t + 1
  }
}

class Animation is Ui {
  construct new(ctx, location, sprites, frameTime, linger) {
    _sprites = sprites
    _frameTime = frameTime
    _location = location
    _linger = linger
    _t = 0
    _end = frameTime * _sprites.count
  }
  construct new(ctx, location, sprites, frameTime) {
    super(ctx)
    _sprites = sprites
    _frameTime = frameTime
    _location = location
    _linger = 0
    _t = 0
    _end = frameTime * _sprites.count
    // spritesheet/list
  }

  finished { _t >= _end + _linger }
  update() {
    _t = _t + 1
  }
  drawDiagetic() {
    var f = (M.min(_end - 1, _t) / _frameTime).floor
    _sprites[f].draw(_location.x, _location.y)
    return true
  }
}

import "./generator" for WorldGenerator
import "./scene/game" for WorldScene

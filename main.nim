import std/times
import std/math
import std/random

import semicongine

type
  EnemyState = enum
    Searching, Targeting, Leaving
  Player = ref object of Entity
    life: int
  Bullet = ref object of Entity
    active: bool
    direction: Vec2f
  Enemy = ref object of Entity
    direction: Vec2f
    state: EnemyState
    startedTargeting: float32

var engine = initEngine("But overcome evil with good")

proc reset(player: Player) =
  player.transform = Unit4
  player.life = setting[int]("settings.player.life")

proc reset(enemy: Enemy) =
  var
    max_area_x = setting[float]("settings.level.max_area_x")
    max_area_y = setting[float]("settings.level.max_area_y")
  let dim = max(max_area_x, max_area_y)
  let spawnDir = rand(2 * PI)
  let spawnDist = dim * (rand(0.5) + 0.5)
  enemy.transform = translate3d(cos(spawnDir) * spawnDist, sin(spawnDir) * spawnDist)
  enemy.state = Searching
  let d = rand(2 * PI)
  enemy.direction = newVec2f(cos(d), sin(d))

  var colors: seq[Vec4f]
  for i in 0 ..< getMeshData[Vec4f](enemy["mesh", Mesh()], "color")[].len:
    colors.add hexToColorAlpha("FF0000FF")
  updateMeshData(enemy["mesh", Mesh()], "color", colors)

proc fire(bullet: Bullet, start: Vec2f, direction: Vec2f) =
  bullet.transform = translate3d(start.x, start.y)
  bullet.direction = direction
  bullet.active = true
  discard mixer[].play("bullet-fired")

proc remove(bullet: Bullet) =
  bullet.transform = Mat4()
  bullet.active = false

proc update(bullet: Bullet, player: Player, dt: float32) =
  var
    max_area_x = setting[float]("settings.level.max_area_x")
    max_area_y = setting[float]("settings.level.max_area_y")
  if bullet.position.x > max_area_x: bullet.remove()
  if bullet.position.x < -max_area_x: bullet.remove()
  if bullet.position.y > max_area_y: bullet.remove()
  if bullet.position.y < -max_area_y: bullet.remove()

  let maxspeed = setting[float]("settings.bullet.maxspeed")
  bullet.transform = bullet.transform * translate3d(bullet.direction.x * maxspeed * dt, bullet.direction.y * maxspeed * dt)
  if (player.position - bullet.position).length <= 0.5 and player.life > 0:
    bullet.remove()
    dec player.life
    if player.life <= 0:
      player.transform = Mat4()
      discard mixer[].play("die")
    else:
      let sound = 1 + rand(2)
      discard mixer[].play("bullet-impact-" & $sound)

proc update(enemy: Enemy, player: Player, bullets: seq[Bullet], t: float32, dt: float32) =

  let
    playerInRange = player.life > 0 and (player.position - enemy.position).length <= setting[float]("settings.enemy.detection_range")
    max_area_x = setting[float]("settings.level.max_area_x")
    max_area_y = setting[float]("settings.level.max_area_y")
    maxspeed = setting[float]("settings.enemy.maxspeed")

  case enemy.state:
    of Searching:
      if enemy.position.x < -max_area_x: enemy.direction.x = abs(enemy.direction.x)
      if enemy.position.x > max_area_x: enemy.direction.x = -abs(enemy.direction.x)
      if enemy.position.y < -max_area_y: enemy.direction.y = abs(enemy.direction.y)
      if enemy.position.y > max_area_y: enemy.direction.y = -abs(enemy.direction.y)
      if playerInRange:
        enemy.state = Targeting
        enemy.startedTargeting = t
    of Targeting:
      if not playerInRange:
        enemy.state = Searching
        let d = rand(2 * PI)
        enemy.direction = newVec2f(cos(d), sin(d))
      else:
        enemy.direction.x = 0.0
        enemy.direction.y = 0.0
        if (t - enemy.startedTargeting) >= setting[float]("settings.enemy.targeting_time"):
          for bullet in bullets:
            if not bullet.active:
              bullet.fire(enemy.position, (player.position - enemy.position).normalized)
              break
          enemy.startedTargeting = t
    of Leaving:
      if enemy.position.x < -max_area_x or enemy.position.x > max_area_x: enemy.direction = newVec2f()
      if enemy.position.y < -max_area_y or enemy.position.y > max_area_y: enemy.direction = newVec2f()

  if (player.position - enemy.position).length <= 1.0 and (engine.keyWasPressed(Space) or engine.keyWasPressed(Delete)) and enemy.state != Leaving:
    enemy.state = Leaving
    enemy.direction = enemy.position.normalized()
    var newColors: seq[Vec4f]
    for i in 0 ..< getMeshData[Vec4f](enemy["mesh", Mesh()], "color")[].len:
      newColors.add hexToColorAlpha("FF8888FF")
    updateMeshData(enemy["mesh", Mesh()], "color", newColors)
    discard mixer[].play("rescued", level=0.9)

  # movment
  let move = enemy.direction * maxspeed * dt
  enemy.transform = enemy.transform * translate3d(move.x, move.y)

proc update(player: Player, dt: float32) =
  var
    max_area_x = setting[float]("settings.level.max_area_x")
    max_area_y = setting[float]("settings.level.max_area_y")
  var dir = newVec2f()
  if engine.keyIsDown(A) and player.position.x > -max_area_x: dir = dir - newVec2f(1, 0)
  if engine.keyIsDown(D) and player.position.x < max_area_x: dir = dir + newVec2f(1, 0)
  if engine.keyIsDown(W) and player.position.y > -max_area_y: dir = dir - newVec2f(0, 1)
  if engine.keyIsDown(S) and player.position.y < max_area_y: dir = dir + newVec2f(0, 1)
  dir = dir.normalized()

  let maxspeed = setting[float]("settings.player.maxspeed")
  player.transform = player.transform * translate3d(dir.x * maxspeed * dt, dir.y * maxspeed * dt)

proc newPlayer(): Player =
  result = Player(name: "player")
  result["mesh"] = circle(color="FFFFFFFF")
  result.reset()

proc newEnemy(): Enemy =
  result = Enemy(name: "enemy")
  result["mesh"] = circle(color="FF0000FF")
  result.reset()

proc newBullet(): Bullet =
  result = Bullet(name: "bullet")
  var mesh = circle(color="232323FF")
  transform[Vec3f](mesh, "position", scale3d(0.2, 0.2))
  result["mesh"] = mesh
  result.transform = Mat4()

proc initRenderer(): (seq[ShaderAttribute], seq[ShaderAttribute]) =
  const
    vertexInput = @[
      attr[Vec3f]("position"),
      attr[Vec4f]("color", memoryPerformanceHint=PreferFastWrite),
      attr[Mat4]("transform", memoryPerformanceHint=PreferFastWrite, perInstance=true),
    ]
    uniforms = @[attr[Mat4]("perspective"), attr[Mat4]("view")]
    vertexOutput = @[attr[Vec4f]("outcolor")]
    fragOutput = @[attr[Vec4f]("color")]
    vertexCode = compileGlslShader(
      stage=VK_SHADER_STAGE_VERTEX_BIT,
      inputs=vertexInput,
      uniforms=uniforms,
      outputs=vertexOutput,
      main="""outcolor = color; gl_Position = vec4(position, 1) * (transform * Uniforms.view * Uniforms.perspective);"""
    )
    fragmentCode = compileGlslShader(
      stage=VK_SHADER_STAGE_FRAGMENT_BIT,
      inputs=vertexOutput,
      uniforms=uniforms,
      outputs=fragOutput,
      main="color = outcolor;"
    )

  var renderer = engine.gpuDevice().simpleForwardRenderPass(
    vertexCode=vertexCode,
    fragmentCode=fragmentCode,
    clearColor=Vec4f([0.01'f32, 0.01'f32, 0.01'f32, 1'f32])
  )
  engine.setRenderer(renderer)

  return (vertexInput, @[])

proc main() =
  randomize()

  # engine
  let (vertexInputs, samplers) = initRenderer()
  engine.hideSystemCursor()
  var fullscreen = not DEBUG
  engine.fullscreen(fullscreen)

  mixer[].loadSound("music", "music.ogg")
  mixer[].loadSound("bullet-fired", "bullet_fired.ogg")
  mixer[].loadSound("bullet-impact-1", "bullet_impact_1.ogg")
  mixer[].loadSound("bullet-impact-2", "bullet_impact_2.ogg")
  mixer[].loadSound("bullet-impact-3", "bullet_impact_3.ogg")
  mixer[].loadSound("die", "player_die.ogg")
  mixer[].loadSound("rescued", "rescued.ogg")
  mixer[].loadSound("finish", "level_finished.ogg")
  mixer[].addTrack("background", 0.5)
  discard mixer[].play("music", "background", loop=true, stopOtherSounds=true)

  # level
  var player = newPlayer()
  var health = newEntity("health", [("mesh", Component(rect(color="00FF0088")))])
  var enemies = newSeq[Enemy](1)
  var bullets = newSeq[Bullet](100)
  for i in 0 ..< enemies.len:
    enemies[i] = newEnemy()
  for i in 0 ..< bullets.len:
    bullets[i] = newBullet()

  var
    level1 = newScene("Level 1", newEntity( "root", []))
  for enemy in enemies:
    level1.root.add enemy
  level1.root.add player
  for bullet in bullets:
    level1.root.add bullet
  level1.root.add health

  engine.addScene(level1, vertexInputs, samplers)
  level1.addShaderGlobal("perspective", Unit4f32)
  level1.addShaderGlobal("view", scale3d(0.1, 0.1))

  # mainloop
  var lastTime = cpuTime()
  var timeScale = 1'f32
  var theTime = 0'f32
  var done = false
  while engine.updateInputs() == Running and not engine.keyIsDown(Escape):
    let
      t = cpuTime()
      dt = (t - lastTime) * timeScale
      configChanged = hadConfigUpdate()
    theTime += dt
    lastTime = t

    # game state/ui updates
    var winSize = engine.getWindow().size
    if engine.windowWasResized() or configChanged:
      level1.setShaderGlobal("perspective", orthoWindowAspect(winSize[1] / winSize[0]))
    if engine.keyWasPressed(R):
      player.reset()
      for enemy in enemies.mitems:
        enemy.reset()
    if engine.keyWasPressed(F11):
      fullscreen = not fullscreen
      engine.fullscreen(fullscreen)
    if engine.keyWasPressed(F1):
      timeScale *= 0.5
    if engine.keyWasPressed(F2):
      timeScale *= 2

    # actual game updates
    if player.life >= 0:
      player.update(dt)
    var activeEnemies = 0
    for enemy in enemies.mitems:
      if enemy.state != Leaving:
        inc activeEnemies
      enemy.update(player, bullets, theTime, dt)
    if activeEnemies == 0 and not done:
      done = true
      mixer[].stop("background")
      discard mixer[].play("finish", level=0.85, stopOtherSounds=true)
    for bullet in bullets.mitems:
      if bullet.active:
        bullet.update(player, dt)

    health.transform = translate3d(0, -9) * scale3d(float(player.life), 0.7)
    engine.updateAnimations(level1, dt)
    engine.renderScene(level1)

when isMainModule:
  main()

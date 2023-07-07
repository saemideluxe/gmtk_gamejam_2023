import std/sequtils
import std/strformat
import std/times
import std/random

import semicongine

type
  Player = ref object of Entity
    life: int
    direction: Vec2f
  Bullet = ref object of Entity
    radius: float32
    speed: float32
    direction: Vec2f
  Enemy = ref object of Entity
    life: int
    mesh: Mesh
    lastHit: float

const DEFAULT_BACKGROUND_LEVEL = 0.3
var engine = initEngine("Cosmic Breakout")

proc reset(player: var Player) =
  player.transform = Unit4
  player.life = setting("setting.player.life", 10)

proc reset(enemy: var Enemy) =
  enemy.transform = translate3d((rand(2'f32) - 1) * 10, (rand(2'f32) - 1) * 10)
  enemy.life = setting("setting.enemy.life", 10)

proc reset(bullet: var Bullet) =
  bullet.transform = Unit4
  bullet.direction[0] = 0
  bullet.direction[1] = 0
  bullet.speed = 1

proc update(player: var Player, dt: float32) =
  var dir = newVec2f()
  if engine.keyIsDown(A): dir = dir - newVec2f(1, 0)
  if engine.keyIsDown(D): dir = dir + newVec2f(1, 0)
  if engine.keyIsDown(W): dir = dir - newVec2f(0, 1)
  if engine.keyIsDown(S): dir = dir + newVec2f(0, 1)
  dir = dir.normalized()

  let maxspeed = setting("settings.player.maxspeed", 10.0)
  player.transform = player.transform * translate3d(dir.x * maxspeed * dt, dir.y * maxspeed * dt)

proc newPlayer(): Player =
  result = Player(name: "player")
  result["mesh"] = rect(width=1, height=1, color="FFFFFFFF")
  # result.hitbox = calculateHitbox(getMeshData[Vec3f](mesh, "position")[])
  # result["hitbox"] = result.hitbox
  result.reset()

proc newEnemy(): Enemy =
  result = Enemy(name: "enemy")
  result["mesh"] = rect(width=1, height=1, color="FF0000FF")
  result.reset()

proc newBullet(): Bullet =
  result = Bullet(name: "bullet", radius: 0.03)
  var mesh = circle(color="FFAAAAFF")
  transform[Vec3f](mesh, "position", scale3d(result.radius / 2, result.radius / 2))
  result["mesh"] = mesh
  result["hitsphere"] = calculateHitsphere(getMeshData[Vec3f](mesh, "position")[])
  result.reset()

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
    clearColor=Vec4f([0.05'f32, 0.02'f32, 0.02'f32, 1'f32])
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

  # level
  var player = newPlayer()
  var enemy1 = newEnemy()

  var
    level1 = newScene("Level 1", newEntity(
      "root",
      [],
      player,
      enemy1,
    ))
  engine.addScene(level1, vertexInputs, samplers)
  level1.addShaderGlobal("perspective", Unit4f32)
  level1.addShaderGlobal("view", scale3d(0.1, 0.1))

  # mainloop
  var lastTime = cpuTime()
  var lastRenderTime = lastTime
  var lastRenderTimeTmp = lastTime
  var timeScale = 1'f32
  while engine.updateInputs() == Running and not engine.keyIsDown(Escape):
    let
      dt = (cpuTime() - lastTime) * timeScale
      configChanged = hadConfigUpdate()
    lastTime = cpuTime()

    # game state/ui updates
    if engine.windowWasResized() or configChanged:
      var winSize = engine.getWindow().size
      level1.setShaderGlobal("perspective", orthoWindowAspect(winSize[1] / winSize[0]))
    if engine.keyWasPressed(R):
      player.reset()
      enemy1.reset()
    if engine.keyWasPressed(F):
      fullscreen = not fullscreen
      engine.fullscreen(fullscreen)
    if engine.keyWasPressed(`1`):
      timeScale *= 0.5
    if engine.keyWasPressed(`2`):
      timeScale *= 2

    # actual game updates
    player.update(dt)
    engine.updateAnimations(level1, dt)
    engine.renderScene(level1)


when isMainModule:
  main()

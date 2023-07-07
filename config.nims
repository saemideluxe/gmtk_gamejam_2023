import std/strformat
import std/strutils
import std/os

const BUILDBASE = "build"
const DEBUG = "debug"
const RELEASE = "release"
const LINUX = "linux"
const WINDOWS = "windows"

const BUNDLETYPE* {.strdefine.}: string = "exe" # dir, zip, exe
const RESOURCEROOT* {.strdefine.}: string = "resources"

task build, "build":
  switch("define", "BUNDLETYPE=" & BUNDLETYPE)
  switch("define", "RESOURCEROOT=" & RESOURCEROOT)
  switch("mm", "orc")
  switch("experimental", "strictEffects")
  switch("threads", "on")
  var buildType = DEBUG
  var platformDir = ""
  if defined(linux):
    switch("define", "VK_USE_PLATFORM_XLIB_KHR")
    platformDir = LINUX
  if defined(windows):
    switch("define", "VK_USE_PLATFORM_WIN32_KHR")
    platformDir = WINDOWS
  if defined(release):
    switch("app", "gui")
    buildType = RELEASE
  else:
    switch("debugger", "native")

  var outdir = getCurrentDir() / BUILDBASE / buildType / platformDir / projectName()
  switch("outdir", outdir)
  setCommand "c"
  rmDir(outdir)
  mkDir(outdir)
  cpFile(getCurrentDir() / "settings.ini", outdir / "settings.ini")
  let resourcedir = joinPath(projectDir(), RESOURCEROOT)
  if existsDir(resourcedir):
    let outdir_resources = joinPath(outdir, RESOURCEROOT)
    if BUNDLETYPE == "dir":
      cpDir(resourcedir, outdir_resources)
    elif BUNDLETYPE == "zip":
      mkDir(outdir_resources)
      for resource in listDirs(resourcedir):
        let
          oldcwd = getCurrentDir()
          outputfile = joinPath(outdir_resources, resource.splitPath().tail & ".zip")
          inputfile = resource.splitPath().tail
        cd(resource)
        if defined(linux):
          exec &"zip -r {outputfile} ."
        elif defined(windows):
          exec &"powershell Compress-Archive * {outputfile}"
        cd(oldcwd)

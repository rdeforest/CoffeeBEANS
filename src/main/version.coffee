# The app's version, worked out once at startup and never bumped by a commit.
# Robert decided on 2026-10-05 that package.json holds the release number,
# set by hand, and git supplies the rest: the commit count, the abbreviated
# commit id, and -dirty when the checkout has changes not yet committed --
# 0.0.1+142.c7e7f6a-dirty. A number bumped on every push would be a commit
# per push, and those collide between his two machines. Everything after the
# `+` is semver build metadata, so a tool that parses versions still reads
# the release.
#
# Its own module so the About text can be shared: Help > About shows it, and
# the feedback report carries the same lines.

{execFile} = require 'child_process'
fsp        = require 'fs/promises'
path       = require 'path'

RELEASE = require('../../package.json').version

# The seam for packaging. A packaged build has no .git, so the build step
# that makes it writes the string it derived into this file at the app's
# root, and the app reads its first line where there is no .git to ask.
# Derived from a full clone, not CI's default shallow one, which counts a
# single commit. Never read in a checkout: a stamp left there by a packaging
# run would otherwise name that commit forever. .gitignore'd for the same
# reason.
STAMP = 'version-stamp.txt'

# These are local reads and take milliseconds; the limit is for a git that
# hangs (a network filesystem, a wedged lock), so About still opens.
GIT_LIMIT = 5000

# Every GIT_* variable inherited is dropped first. A git hook in a linked
# worktree exports GIT_DIR and GIT_INDEX_FILE, and an app started from one
# would report the commit of whatever repository they name.
#
# The ceiling stops git looking above the app's own folder. A .git it does
# not accept -- an empty folder, a worktree whose main checkout has moved --
# would otherwise send it up the tree to whatever repository is there, a
# home directory kept in git, say, and the app would report that commit as
# its own. Measured by Claude, 2026-10-05: an empty .git in a folder inside
# this checkout answers this checkout's HEAD without the ceiling.
#
# GIT_TERMINAL_PROMPT and GIT_NO_LAZY_FETCH: starting the app must never
# raise a credentials prompt or fetch from a partial clone's remote.
gitEnv = (root) ->
  env = {}
  env[name] = value for name, value of process.env when not name.startsWith 'GIT_'
  Object.assign env,
    GIT_CEILING_DIRECTORIES: path.dirname root
    GIT_TERMINAL_PROMPT:     '0'
    GIT_NO_LAZY_FETCH:       '1'

# --no-optional-locks: `git status` otherwise refreshes the index under
# index.lock, and an app starting while Robert commits would fail his commit.
# core.fsmonitor=false: nor may it start an fsmonitor daemon that outlives it.
git = (root, args...) -> new Promise (resolve, reject) ->
  options =
    cwd:         root
    timeout:     GIT_LIMIT
    windowsHide: yes
    env:         gitEnv root
  execFile 'git', ['--no-optional-locks', '-c', 'core.fsmonitor=false', args...], options, (error, stdout, stderr) ->
    if error then reject Object.assign error, {stderr} else resolve stdout.trim()

whyNot = (error) ->
  return 'git is not installed' if error.code is 'ENOENT'
  return "git's answer passed execFile's maxBuffer (#{error.code})" if error.code is 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER'
  return "git took more than #{GIT_LIMIT / 1000}s" if error.killed
  "git said: #{(error.stderr.trim() or error.message).split('\n')[0]}"

# Without a commit id the release number is still worth showing, with the
# reason beside it rather than an error: a version is never why About fails.
bare = (why) -> {text: RELEASE, note: "no commit id: #{why}"}

stamped = (root) ->
  try
    line = (await fsp.readFile path.join(root, STAMP), 'utf8').split('\n')[0].trim()
  catch error
    return bare if error.code is 'ENOENT' then 'not a git checkout' else "#{STAMP}: #{error.message}"
  return bare "#{STAMP} is empty" unless line
  {text: line, note: null}

derive = (root) ->
  try
    await fsp.access path.join root, '.git'
  catch error
    return stamped root if error.code is 'ENOENT'
    return bare ".git: #{error.message}"

  try
    [count, commit, changes] = await Promise.all [
      git root, 'rev-list', '--count', 'HEAD'
      git root, 'rev-parse', '--short', 'HEAD'
      git root, 'status', '--porcelain', '--untracked-files=normal'
    ]
  catch error
    return bare whyNot error
  {text: "#{RELEASE}+#{count}.#{commit}#{if changes then '-dirty' else ''}", note: null}

# getSystemVersion rather than os.release: on macOS the latter is the Darwin
# kernel's number, which nobody filing a bug knows their Mac by.
OS_NAMES = darwin: 'macOS', win32: 'Windows', linux: 'Linux'

about = (version) ->
  noted = if version.note then "  (#{version.note})" else ''
  [
    "CoffeeBEANS #{version.text}#{noted}"
    "Electron    #{process.versions.electron}"
    "Chromium    #{process.versions.chrome}"
    "Node        #{process.versions.node}"
    "OS          #{OS_NAMES[process.platform] ? process.platform} #{process.getSystemVersion()} #{process.arch}"
  ].join '\n'

module.exports = {derive, about, RELEASE, STAMP}

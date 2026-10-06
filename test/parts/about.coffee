# Help > About, and the version it shows. The version comes from git at
# startup (src/main/version.coffee), so it is checked against git's own
# answer in the suite's checkout -- which is usually dirty while someone is
# working in it -- and never against a constant.

{execFileSync}                   = require 'child_process'
fs                               = require 'fs'
fsp                              = require 'fs/promises'
{devNull}                        = require 'os'
path                             = require 'path'
{BrowserWindow, Menu, clipboard} = require 'electron'
Version                          = require '../../src/main/version'

SHAPE = /^\d+\.\d+\.\d+\+\d+\.[0-9a-f]{7,}(-dirty)?$/

module.exports = (t) ->
  {js, check, click, waitFor, freshPage, paths} = t
  # Without the GIT_* variables a git hook in a linked worktree exports:
  # GIT_DIR and GIT_INDEX_FILE inherited would send the part's own `git
  # commit` into the repository they name, and answer for it.
  unhooked = ->
    env = {}
    env[name] = value for name, value of process.env when not name.startsWith 'GIT_'
    env
  run = (env, root, args...) ->
    execFileSync('git', ['--no-optional-locks', args...], {cwd: root, env, encoding: 'utf8', stdio: 'pipe'}).trim()
  git = (args...) -> run unhooked(), paths.root, args...
  # The part's own repositories answer to no one's config -- signing, hooks,
  # templates -- and need a name to commit under.
  gitIn = (root, args...) ->
    run {
      unhooked()...
      GIT_CONFIG_GLOBAL:   devNull
      GIT_CONFIG_NOSYSTEM: '1'
      GIT_AUTHOR_NAME:     'suite', GIT_AUTHOR_EMAIL:    'suite@invalid'
      GIT_COMMITTER_NAME:  'suite', GIT_COMMITTER_EMAIL: 'suite@invalid'
    }, root, args...

  {version, note, text} = await js "return await beans.about()"

  # The suite's checkout has a .git everywhere it runs today (here and CI);
  # a run from an unpacked tarball checks the fallback instead.
  if fs.existsSync path.join paths.root, '.git'
    dirty  = if git 'status', '--porcelain', '--untracked-files=normal' then '-dirty' else ''
    wanted = "#{Version.RELEASE}+#{git 'rev-list', '--count', 'HEAD'}.#{git 'rev-parse', '--short', 'HEAD'}#{dirty}"
    check 'the version is the release, the commit count, the commit id and -dirty, as git says',
      SHAPE.test(version) and version is wanted and note is null,
      "shown #{version}, git says #{wanted}#{if note then ", note #{note}" else ''}"
  else
    check 'outside a git checkout the version is the bare release, said plainly',
      version is Version.RELEASE and /not a git checkout/.test(note), "#{version} (#{note})"

  release = JSON.parse(await fsp.readFile path.join(paths.root, 'package.json'), 'utf8').version
  check 'the release number is package.json\'s', Version.RELEASE is release and version.startsWith(release),
    "#{Version.RELEASE} vs #{release}"

  # Folders inside the suite's own checkout, so git, asked carelessly, would
  # answer for the checkout around them.
  sandbox = path.join paths.data, 'versioncheck'
  plain   = path.join sandbox, 'plain'
  broken  = path.join sandbox, 'broken'
  stamped = path.join sandbox, 'stamped'
  blank   = path.join sandbox, 'blank'
  # A data folder a failed run left behind still holds the last run's
  # repositories, where `git commit` would find nothing to commit.
  await fsp.rm sandbox, recursive: yes, force: yes
  await fsp.mkdir plain, recursive: yes
  await fsp.mkdir path.join(broken, '.git'), recursive: yes
  await fsp.mkdir stamped, recursive: yes
  await fsp.mkdir blank, recursive: yes
  await fsp.writeFile path.join(stamped, Version.STAMP), "9.8.7+65.abcdef0\nmade by hand\n", 'utf8'
  await fsp.writeFile path.join(blank, Version.STAMP), "\n", 'utf8'

  bare = await Version.derive plain
  check 'no .git gives the bare release and says why',
    bare.text is Version.RELEASE and bare.note is 'no commit id: not a git checkout',
    JSON.stringify bare

  empty = await Version.derive broken
  check 'a .git git will not accept is not answered for by the checkout around it',
    empty.text is Version.RELEASE and /^no commit id: git said: /.test(empty.note),
    JSON.stringify empty

  # The suite's checkout is clean on CI and dirty while someone works in it,
  # so -dirty is checked both ways on a repository of the part's own.
  repo = path.join sandbox, 'repo'
  await fsp.mkdir repo, recursive: yes
  sketch = path.join repo, 'one.coffee'
  await fsp.writeFile sketch, "print 1\n", 'utf8'
  gitIn repo, 'init', '-q'
  gitIn repo, 'add', '.'
  gitIn repo, 'commit', '-q', '-m', 'one'
  commit = gitIn repo, 'rev-parse', '--short', 'HEAD'
  clean  = await Version.derive repo
  await fsp.writeFile sketch, "print 2\n", 'utf8'
  edited = await Version.derive repo
  check 'a clean checkout has no -dirty, and an edit adds it',
    clean.text is "#{Version.RELEASE}+1.#{commit}" and edited.text is "#{Version.RELEASE}+1.#{commit}-dirty",
    "clean #{clean.text}, edited #{edited.text}"

  # As an app started from a git hook in a linked worktree sees it: GIT_DIR
  # and GIT_INDEX_FILE naming another repository, which has a commit of its
  # own to answer with.
  other = path.join sandbox, 'other'
  await fsp.mkdir other, recursive: yes
  gitIn other, 'init', '-q'
  gitIn other, 'commit', '-q', '--allow-empty', '-m', 'other'
  hooked = GIT_DIR: path.join(other, '.git'), GIT_INDEX_FILE: path.join(other, '.git', 'index')
  before = {}
  before[name] = process.env[name] for name of hooked
  Object.assign process.env, hooked
  try
    inherited = await Version.derive repo
  finally
    for name, value of before
      if value? then process.env[name] = value else delete process.env[name]
  check 'GIT_DIR inherited from a hook does not change whose commit is reported',
    inherited.text is edited.text, "with GIT_DIR #{inherited.text}, without #{edited.text}"

  stamp = await Version.derive stamped
  check 'where there is no .git, the first line of a build\'s version stamp is the version',
    stamp.text is '9.8.7+65.abcdef0' and stamp.note is null, JSON.stringify stamp

  # A stamp left in a checkout by a packaging run names a commit that will
  # soon be old; git's answer is the one that stays true.
  await fsp.writeFile path.join(repo, Version.STAMP), "9.8.7+65.abcdef0\n", 'utf8'
  stale = await Version.derive repo
  check 'in a checkout git is asked and a version stamp is ignored', stale.text is edited.text,
    "#{stale.text}, git says #{edited.text}"

  blanked = await Version.derive blank
  check 'an empty version stamp gives the bare release and says so',
    blanked.text is Version.RELEASE and blanked.note is "no commit id: #{Version.STAMP} is empty",
    JSON.stringify blanked

  # The banner is printed once, at boot, so it takes a page of its own.
  banner = await freshPage """
    const shown = document.getElementById('console').textContent
    return shown.includes('Ctrl-Enter') && shown
  """
  check 'the banner names the derived version', "#{banner}".includes("CoffeeBEANS #{version}  --"),
    JSON.stringify "#{banner}"[...120]

  # The real menu item, handed the window as the menu hands it the focused
  # one -- the suite's window never has focus.
  item = Menu.getApplicationMenu().getMenuItemById 'about'
  win  = BrowserWindow.getAllWindows()[0]
  item?.click undefined, win, win.webContents
  opened = await waitFor "return document.getElementById('about').open"
  shown  = await js "return document.getElementById('aboutText').textContent"
  check 'Help > About opens the dialog, showing the version', opened and shown is text and shown.includes(version),
    "item=#{item?.label} open=#{opened} shown=#{JSON.stringify shown}"

  lines = [
    "Electron    #{process.versions.electron}"
    "Chromium    #{process.versions.chrome}"
    "Node        #{process.versions.node}"
  ]
  missing = (line for line in lines when line not in shown.split '\n')
  os      = shown.split('\n').find (line) -> line.startsWith 'OS '
  check 'About names Electron, Chromium, Node and the OS',
    missing.length is 0 and os?.includes(process.getSystemVersion()),
    "missing #{JSON.stringify missing}, os #{JSON.stringify os}"

  # The system clipboard is never touched: writing it back afterwards made
  # Electron its owner, and on Linux an owner's clipboard empties when it
  # exits, so every run cost Robert what he last copied (and anything not
  # text, everywhere). main calls clipboard.writeText on this same module
  # object when Copy asks, so a spy here sees exactly what would be written.
  written   = []
  writeText = clipboard.writeText
  clipboard.writeText = (text) -> written.push text
  try
    await click 'aboutCopy'
    await waitFor "return document.getElementById('aboutCopy').textContent === 'Copied'"
  finally
    clipboard.writeText = writeText
    await click 'aboutClose'
  check 'Copy hands exactly the shown text to the clipboard', written.length is 1 and written[0] is shown,
    JSON.stringify written

  closed = await waitFor "return !document.getElementById('about').open"
  check 'Close closes About', closed

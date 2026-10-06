# The 📣🐞 button's report, and the redaction it goes through. Robert's bar
# (2026-10-05): safe to post on a large billboard in a big city, while still
# saying what went wrong. So each pattern is fed a realistic line and must
# take out what identifies; and lines that only look like those -- a version,
# a line:col, CoffeeScript's `::` -- must come through untouched.

{execFileSync} = require 'child_process'
fs             = require 'fs'
fsp            = require 'fs/promises'
path           = require 'path'
{shell}        = require 'electron'
Redact         = require '../../src/main/redact'
Report         = require '../../src/main/report'

# A made-up player on two made-up machines, so every case reads the same on
# every runner.
ALICE =
  home: '/home/alice'
  user: 'alice'
  host: 'alices-laptop.lan'
  data: '/home/alice/.local/share/coffeebeans'
  app:  '/opt/CoffeeBEANS'
WINDOWS =
  home: 'C:\\Users\\alice'
  user: 'alice'
  host: 'DESKTOP-4F2A9QK'
  data: 'C:\\Users\\alice\\.local\\share\\coffeebeans'
  app:  'C:\\Program Files\\CoffeeBEANS'
# Each of these reaches a path or a name the folders above would miss.
# Windows shortens `Robert Smith` to `ROBERT~1`, and the account's name need
# not be the folder's.
SMITH =
  home: 'C:\\Users\\Robert Smith'
  user: 'rsmith'
  host: 'DESKTOP-4F2A9QK'
# Fedora Silverblue's /home is a link to /var/home, and this account was
# renamed after its folder was made.
LINKED =
  home: '/var/home/alice'
  user: 'asmith'
  host: 'silverblue'
# The same é, composed and decomposed.
JOSE     = home: '/home/jos\u00e9',  user: 'jos\u00e9',  host: 'jose-pc'
JOSE_NFD = home: '/home/jose\u0301', user: 'jose\u0301', host: 'jose-pc'
# A Raspberry Pi's default account.
PI = home: '/home/pi', user: 'pi', host: 'raspberrypi'

# Assembled at run time, so the source holds nothing a secret scanner would
# refuse a push for.
PEM    = "-----BEGIN #{'RSA PRIVATE'} KEY-----\nMIIEowIBAAKCAQEAx3Lq\n-----END #{'RSA PRIVATE'} KEY-----"
GITHUB = 'gh' + 'p_' + 'a1B2c3D4e5'.repeat 4
AWS    = 'AKIA' + 'IOSFODNN7EXAMPLE'
JWT    = ['eyJhbGciOiJIUzI1NiJ9', 'eyJzdWIiOiIxMjM0NTY3ODkwIn0', 'c2lnbmF0dXJlLWhlcmU'].join '.'
# Shaped like an AWS secret access key, slashes and all: no piece between
# them is 32 long. And a private key's body, pasted without its BEGIN line.
AWS_PIECES = ['wJalrXUtnFEMI', 'K7MDENG', 'bPxRfiCY3EXAMPLEKEY']
AWS_SECRET = AWS_PIECES.join '/'
BODY = ['MIIEowIBAAKCAQEAx3Lq/Z9f2kP0sH4yQe7Vb1nWm8cR/5tJ3uL6oD2gA0iXz+Y9e',
        'T4hKp1Wq8s7Fm3Nv2Bc5/Xr0Lz9Jd6Gy4Ht1Ue8Ka3/Op2Iq7Rs5Mw0Vb9Nc6Xd==']
# A body's last line can be any length.
TAIL = 'Ab3Cd5Ef7Gh9Ij=='
# AWS's documented example secret key: one digit, so random letters in both
# cases have to be enough. And a key with no digits at all.
AWS_EXAMPLE = ['wJalrXUtnFEMI', 'K7MDENG', 'bPxRfiCY' + 'EXAMPLEKEY']
NO_DIGITS   = 'qWeRtYuIoPaSdFgHjKl+' + 'ZxCvBnMqWeRtYuIoPaSd'

CASES = [
  # pattern, machine, a realistic line, what must be gone, what must be
  # left, and what tells this line from another for the same pattern
  ['private key', ALICE, "loaded #{PEM} from disk",
    ['MIIEow', 'PRIVATE KEY'], ['loaded <secret> from disk']]
  ['folder <data>', ALICE, "ENOENT: no such file or directory, open '/home/alice/.local/share/coffeebeans/sketches/ocean.coffee'",
    ['/home/alice', '.local/share'], ["open '<data>/sketches/ocean.coffee'"]]
  ['folder <app>', WINDOWS, 'not found: C:\\Program Files\\CoffeeBEANS\\src\\runtime\\sound.js (file:///C:/Program Files/CoffeeBEANS/src)',
    ['Program Files'], ['<app>\\src\\runtime\\sound.js', 'file:///<app>/src'], 'on Windows']
  # /home/alicebob is caught as someone's home; were the folder rule to eat
  # /home/alice off its front, `~bob` would be left.
  ['folder ~', ALICE, 'watch: /home/alice/projects/beans: EACCES, and /home/alicebob is someone else',
    ['/home/alice/', 'alicebob'], ['watch: ~/projects/beans: EACCES', 'and ~ is someone else']]
  ['folder ~', WINDOWS, 'EPERM: rename \'C:\\Users\\alice\\Desktop\\x.png\' {"path":"C:\\\\Users\\\\alice\\\\Desktop"}',
    ['Users'], ["rename '~\\Desktop\\x.png'", '{"path":"~\\\\Desktop"}'], 'on Windows']
  ['home-shaped folder', SMITH, "ENOENT: open 'C:\\Users\\ROBERT~1\\AppData\\Local\\Temp\\beans\\x.png'",
    ['ROBERT', 'Users'], ["open '~\\AppData\\Local\\Temp\\beans\\x.png'"], "Windows's 8.3 name"]
  ['home-shaped folder', SMITH, 'Not allowed to load local resource: file:///C:/Users/Robert%20Smith/Documents/beans/x.png',
    ['Robert', 'Smith'], ['file:///~/Documents/beans/x.png'], 'a file URL']
  ['home-shaped folder', JOSE, 'fetch failed: file:///home/jos%C3%A9/sketches/x.coffee',
    ['jos%C3%A9'], ['file://~/sketches/x.coffee'], 'percent-encoded']
  ['home-shaped folder', LINKED, "EACCES: open '/home/alice/sketches/x.coffee'",
    ['alice'], ["open '~/sketches/x.coffee'"], 'through a link']
  ['home-shaped folder', ALICE, "ENOENT: open '/Users/Mike Smith/Library/beans/x.png'",
    ['Mike', 'Smith'], ["open '~/Library/beans/x.png'"], 'a name with a space']
  ['network share', ALICE, 'EACCES: \\\\fileserver\\Users\\erin\\Documents and \\\\fs\\home$\\frank\\docs',
    ['fileserver', 'erin', 'fs\\', 'frank'], ['EACCES: \\\\<share>\\Documents and \\\\<share>\\docs']]
  ['mounted drive', PI, 'loaded /run/media/pi/BEANS/x.coffee from the stick at /media/pi',
    ['/pi'], ['/run/media/<user>/BEANS/x.coffee', 'the stick at /media/<user>']]
  ['home by account name', ALICE, 'open ~bob/.ssh/id_rsa failed; ~carol/games/x.coffee loaded',
    ['bob', 'carol'], ['open ~/.ssh/id_rsa failed; ~/games/x.coffee loaded']]
  ['password in a URL', ALICE, 'fetch https://bob:hunter2@example.com/feed.json failed: 401',
    ['bob', 'hunter2'], ['https://<secret>@example.com/feed.json']]
  ['JSON web token', ALICE, "session #{JWT} expired",
    ['eyJ'], ['session <secret> expired']]
  ['known key prefix', ALICE, "GitHub said 401 to #{GITHUB}; AWS refused #{AWS}",
    [GITHUB, AWS], ['401 to <secret>; AWS refused <secret>']]
  ['authorization header', ALICE, '401 from the server: Authorization: Basic YWxhZGRpbjpvcGVuc2VzYW1l',
    ['YWxhZGRp'], ['Authorization: Basic <secret>']]
  ['bearer token', ALICE, 'request sent with Bearer 7f3a9c2e1b4d8f60a5e7c3b2',
    ['7f3a9c'], ['with Bearer <secret>']]
  ['secret assignment', ALICE, "apiKey = 'k3y-for-the-weather'; GET /forecast?access_token=XYZ123&days=3; PASSWORD=hunter2",
    ['k3y-for', 'XYZ123', 'hunter2'], ['apiKey = <secret>;', 'access_token=<secret>&days=3', 'PASSWORD=<secret>']]
  ['secret assignment', ALICE, 'PASSWORD = hunter2',
    ['hunter2'], ['PASSWORD = <secret>'], 'spaced, ending its line']
  ['secret assignment', ALICE, "aws_secret_access_key = #{AWS_SECRET}",
    AWS_PIECES, ['aws_secret_access_key = <secret>'], 'from ~/.aws/credentials']
  ['secret assignment', ALICE, 'POST failed with client_secret=s3cr3t(1) in the body',
    ['s3cr3t', '(1)'], ['client_secret=<secret> in the body'], 'random, with parentheses']
  ['secret assignment', ALICE, 'PGPASSWORD=hunter2 SESSIONTOKEN=abc psql -h db',
    ['hunter2', '=abc'], ['PGPASSWORD=<secret> SESSIONTOKEN=<secret> psql'], 'glued in capitals']
  ['secret block', ALICE, "config.yml:\nsecret: |\n  hunter2-the-real-one\n\n  and-a-second-line\nnext: 1",
    ['hunter2', 'second-line'], ['secret: ', '\n  <secret>\nnext: 1']]
  ['cookie', ALICE, 'sent Cookie: session=abcdefg12345; theme=dark, got Set-Cookie: sid=s%3Aabc123xyz; Path=/',
    ['abcdefg12345', 'abc123xyz'], ['Cookie: session=<secret>; theme=', 'Set-Cookie: sid=<secret>;']]
  ['secret after its name', ALICE, 'machine api.example.com login bob password s3cr3t!x',
    ['s3cr3t'], ['login bob password <secret>'], 'from .netrc']
  ['secret after its name', ALICE, 'it said wrong password, but I typed password hunter2',
    ['hunter2'], ['wrong password, but I typed password <secret>'], 'ending its line']
  ['e-mail address', ALICE, 'sign-in failed for alice.smith+beans@example.co.uk',
    ['smith', 'example.co.uk'], ['failed for <email>']]
  ['e-mail address', ALICE, 'sign-in failed for jose\u0301.garci\u0301a@example.com',
    ['garci', 'example.com'], ['failed for <email>'], 'written decomposed']
  ['MAC address', ALICE, 'en0: ether 3c:22:fb:01:9a:7e, on Windows 3C-22-FB-01-9A-7E',
    ['3c:22', '3C-22'], ['ether <mac>, on Windows <mac>']]
  ['MAC address', ALICE, 'switch port Gi0/1 learned 3c22.fb01.9a7e.',
    ['3c22'], ['learned <mac>.'], "Cisco's dotted form"]
  ['MAC address after its name', ALICE, 'ether 3c22fb019a7e; ioreg: "IOMACAddress" = <3c22fb019a7e>',
    ['3c22'], ['ether <mac>;', '"IOMACAddress" = <<mac>>']]
  ['IPv4 address', ALICE, 'connect ECONNREFUSED 192.168.1.20:8080',
    ['192.168'], ['ECONNREFUSED <ip>:8080']]
  ['IPv6 address', ALICE, 'connect EHOSTUNREACH fe80::1c2d:3e4f:5a6b:7c8d%en0 via 2001:db8:85a3::8a2e:370:7334',
    ['fe80', '2001:db8'], ['EHOSTUNREACH <ip> via <ip>']]
  ['long random string', ALICE, 'asset cached as 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
    ['9f86d0'], ['cached as <secret>']]
  ['base64 run', ALICE, "AWS refused #{AWS_SECRET} for this bucket",
    AWS_PIECES, ['AWS refused <secret> for this bucket'], 'an AWS secret key']
  ['base64 run', ALICE, "pasted:\n#{BODY.join '\n'}\nand it failed",
    BODY.flatMap((line) -> line.split '/'), ['pasted:\n<secret>\n<secret>\nand it failed'], "a private key's body"]
  ['base64 run', ALICE, "AWS refused #{AWS_EXAMPLE.join '/'} for this bucket",
    AWS_EXAMPLE, ['AWS refused <secret> for this bucket'], "AWS's own example key"]
  ['base64 run', ALICE, "AWS refused #{NO_DIGITS} too",
    [NO_DIGITS[..19], NO_DIGITS[20..]], ['AWS refused <secret> too'], 'a key with no digits']
  ['base64 last line', ALICE, "pasted:\n#{BODY[0]}\n#{TAIL}\nand it failed",
    [TAIL[..13]], ['pasted:\n<secret>\n<secret>\nand it failed']]
  ['host name', ALICE, 'getaddrinfo ENOTFOUND alices-laptop.lan, and alices-laptop is not answering',
    ['alices-laptop'], ['ENOTFOUND <host>, and <host> is not']]
  ['user name', ALICE, 'Alice here: it froze when alice pressed space; malice is not a name',
    ['Alice here', 'when alice'], ['<user> here', 'when <user> pressed', 'malice']]
  ['user name', JOSE, 'jose\u0301 pressed space', ['jos\u00e9', 'jose\u0301'], ['<user> pressed space'], 'written decomposed']
  ['user name', JOSE_NFD, 'jos\u00e9 pressed space', ['jos\u00e9', 'jose\u0301'], ['<user> pressed space'], 'named decomposed']
  ['user name', PI, 'Math.pi is 3.14159; saved to /media/pi/usb/beans',
    ['/pi/'], ['Math.pi is 3.14159', '/media/<user>/usb'], 'shorter than 3, only as a folder']
]

# Lines that look like something above and are not, each of which a report
# needs whole to be any use.
KEEPS = [
  'CoffeeBEANS 0.0.1+153.b95079c-dirty'
  'Chromium    140.0.7339.41'
  'gamepad firmware 2.1.0.1043'
  '    at draw (beans-run-3.coffee:12:5)'
  'app://beans/src/renderer/renderer.coffee:1568:12'
  'started 12:34:56, stopped 12:35:02'
  'Face::add = (v) -> @::cafe v'
  'esbuild@0.28.2 and coffeescript@2.7.0'
  'secret = random 100'
  'token = nextToken()'
  "compass = 3; bypass = 4; author: 'Robert'; BYPASS=1 AUTHOR=Robert"
  'mask = ~bits; half = ~x/2; ~str.indexOf c'
  'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
  'opened sketches/level2/boss3/arena4/final5.coffee'
  'the token expired at noon'
  'HEAD is now at 3c22fb019a7e K6 fix'
]

# Each of these the V2 follow-up's review found taken, and each is what a
# report needs to say.
KEPT = [
  ['a sketch path in mixed case', "ENOENT: open 'sketches/Level2/Boss3/ArenaFinal/x.coffee'"]
  ['a web address with /home/, /users/ or /media/ in it',
    'load https://example.com/users/42/sprite.png failed: 404; https://cdn.site.com/home/hero.png, https://cdn.site.com/media/intro.webm']
  # Each changes when composed: the report might be about exactly that.
  ['letters that composing would change',
    'Greek question mark \u037e, Kelvin \u212a, ohm \u2126, angstrom \u212b, CJK \uf900, Hangul \u1100\u1161']
]

module.exports = (t) ->
  {js, check, click, setDoc, ask, waitFor, paths} = t

  # --- the patterns, one at a time --------------------------------------------

  named = (name for {name} in Redact.patterns ALICE)
  bare  = (name for name in named when not CASES.some ([pattern]) -> pattern is name)
  check 'every redaction pattern has a realistic line below', bare.length is 0, "none for #{bare.join ', '}"

  # Gone and kept through the whole redactor, and changed by the named
  # pattern on its own -- so no pattern is quietly covered by another.
  for [name, who, line, gone, kept, note] in CASES
    out      = Redact.redactor(who) line
    rule     = Redact.patterns(who).find (pattern) -> pattern.name is name
    alone    = rule? and line.replace(rule.find, rule.put) isnt line
    leaked   = (text for text in gone when out.includes text)
    lost     = (text for text in kept when not out.includes text)
    check "redaction: #{name}#{if note then ", #{note}" else ''}",
      alone and leaked.length is 0 and lost.length is 0,
      "pattern alone changed it=#{alone} leaked=#{JSON.stringify leaked} lost=#{JSON.stringify lost} -> #{JSON.stringify out}"

  changed = ([line, Redact.redactor(ALICE) line] for line in KEEPS).filter ([line, out]) -> out isnt line
  check 'versions, line:col, clocks, prototypes and computed values come through whole',
    changed.length is 0, JSON.stringify changed

  for [what, line] in KEPT
    out = Redact.redactor(ALICE) line
    check "comes through whole: #{what}", out is line, JSON.stringify out

  # The real machine's own: About says nothing a billboard would mind, so it
  # must come through whole -- redacted as a report redacts it, with the
  # user and host names left out of it.
  me    = Redact.identity data: paths.data, app: paths.root
  about = (await js "return await beans.about()").text
  check 'the About text comes through redaction unchanged', Redact.redactor(me, words: no)(about) is about,
    JSON.stringify Redact.redactor(me, words: no) about

  # Which is what a player called `node` on a host called `electron` needs:
  # About names both on every platform.
  namesake = home: '/home/node', user: 'node', host: 'electron'
  drafted  = Report.draft {about, words: 'electron froze when node pressed space', lines: [], sketch: null}, {}, namesake
  check 'a user called node on a host called electron leaves About whole, and is still taken out of the rest',
    drafted.includes("-- About\n#{about}\n") and drafted.includes('<host> froze when <user> pressed space'), JSON.stringify drafted

  # --- the button and the dialog ----------------------------------------------

  placed = await js """
    const button = document.getElementById('feedback')
    return document.querySelector('header b').nextElementSibling === button &&
           button.nextElementSibling.id === 'open' && button.textContent
  """
  check 'the 📣🐞 button sits between CoffeeBEANS and the open-folder button', placed is '📣🐞',
    JSON.stringify placed

  # What the player's own machine would put in a report: its home folder,
  # host name and user name, in the console and in the sketch.
  spoken = "#{me.home}#{path.sep}notes.txt on #{me.host} for #{me.user}"
  await ask JSON.stringify spoken
  MARK = 'report part sketch'
  await setDoc "# kept in #{me.home} by #{me.user}\nprint '#{MARK}'\n"

  # Without these, the suite would open Robert's file manager and browser.
  # main calls both on this same module object, at call time.
  shown   = []
  visited = []
  realShow = shell.showItemInFolder
  realSave = Report.save
  realDraft = Report.draft
  realOpen = shell.openExternal
  shell.showItemInFolder = (file) -> shown.push file
  shell.openExternal     = (url) -> visited.push url; Promise.resolve()
  throw new Error 'could not stand in for shell' unless shell.showItemInFolder isnt realShow and shell.openExternal isnt realOpen

  KEYS = [['F8', {}], ['F10', {}], ['\\', {ctrlKey: true}], ['e', {ctrlKey: true}], ['.', {ctrlKey: true}]]
  # Each key dispatched at `target`; the window's listeners preventDefault
  # whatever they act on.
  taken = (target) -> js """
    const target = #{target}
    return #{JSON.stringify KEYS}.filter(([key, mods]) => {
      const down = new KeyboardEvent('keydown', {key, ...mods, bubbles: true, cancelable: true})
      target.dispatchEvent(down)
      return down.defaultPrevented
    }).map(([key]) => key)
  """
  solo = -> js "return document.getElementById('main').classList.contains('solo')"
  wasSolo = await solo()

  reports = path.join paths.data, 'reports'
  await fsp.rm reports, recursive: yes, force: yes
  unhooked = {}
  unhooked[name] = value for name, value of process.env when not name.startsWith 'GIT_'
  checkout = fs.existsSync path.join paths.root, '.git'
  gitStatus = ->
    return '' unless checkout
    execFileSync 'git', ['--no-optional-locks', 'status', '--porcelain', '--untracked-files=normal'],
      {cwd: paths.root, env: unhooked, encoding: 'utf8'}
  statusBefore = gitStatus()

  step = (id) -> js "return !document.getElementById('#{id}').hidden"
  press = (id) -> js "await document.getElementById('#{id}').onclick(); return true"

  try
    await click 'feedback'
    opened = await waitFor "return document.getElementById('report').open && document.activeElement.id === 'reportWords'"
    blank  = await js "return document.getElementById('reportWords').value === '' && !document.getElementById('reportSketch').checked"
    check 'the button opens the report, the text box focused and empty, the sketch not ticked',
      opened and blank and await step('reportAsk')

    # V1's review: these used to act behind an open About, and here a player
    # types in a text box. The dialog closed, the same keys must still work.
    inDialog = await taken "document.getElementById('reportWords')"
    soloIn   = await solo()
    await js "document.querySelector('#reportAsk form button.ghost').click(); return true"
    closed   = await waitFor "return !document.getElementById('report').open"
    outside  = await taken 'document.body'
    await taken 'document.body' if (await solo()) isnt wasSolo
    check 'with a dialog open, F8, F10, Ctrl-\\, Ctrl-E and Ctrl-. stand down, and work again once it closes',
      inDialog.length is 0 and soloIn is wasSolo and closed and outside.length is KEYS.length and (await solo()) is wasSolo,
      "taken in the dialog #{JSON.stringify inDialog}, editor hidden #{wasSolo} -> #{soloIn}; taken after #{JSON.stringify outside}"

    # Opened the way a mouse opens it: pointerdown, then the button takes
    # focus, then the click. Closed, the dialog would hand focus back to the
    # button, where Space opens it again.
    await js """
      document.getElementById('promptLine').focus()
      const button = document.getElementById('feedback')
      button.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true}))
      button.focus()
      button.click()
      return true
    """
    await waitFor "return document.getElementById('report').open"
    await js "document.querySelector('#reportAsk form button.ghost').click(); return true"
    back = await waitFor "return !document.getElementById('report').open && document.activeElement.id === 'promptLine'", 1000
    check 'closing the report puts focus back where it was before the button was clicked',
      back, await js "return document.activeElement.id || document.activeElement.tagName"

    # Unticked: no sketch.
    words = "It froze when #{me.user} pressed space on #{me.host}"
    await click 'feedback'
    await js "document.getElementById('reportWords').value = #{JSON.stringify words}; return true"
    await press 'reportDraft'
    plain = await js "return document.getElementById('reportText').value"
    sections = ['-- About', '-- What happened', 'It froze when <user> pressed space on <host>', '-- The last', '<host> for <user>']
    missing  = (section for section in sections when not plain.includes section)
    check 'the draft has About, the player\'s words and the console, redacted',
      (await step 'reportCheck') and missing.length is 0 and plain.includes(about),
      "missing #{JSON.stringify missing}: #{JSON.stringify plain[..600]}"
    check 'without the tick the sketch is left out',
      not plain.includes(MARK) and plain.includes('-- The sketch was not included'), JSON.stringify plain[-200..]

    # What is saved is what was shown, the player's edits included.
    edited = plain + 'and the suite added this line\n'
    await js "document.getElementById('reportText').value = #{JSON.stringify edited}; return true"
    await press 'reportSave'
    first   = shown[0]
    written = first? and await fsp.readFile first, 'utf8'
    told    = await js "return document.getElementById('reportSaved').textContent"
    check 'Save writes exactly the edited text to reports/ in the data folder, and shows the file',
      shown.length is 1 and path.dirname(first) is reports and written is edited and await step('reportDone'),
      "shown #{JSON.stringify shown}, same text #{written is edited}"
    check 'and says to open an issue at the issues page and attach the file',
      told.includes(Report.ISSUES) and told.includes(first) and /attach/.test(told), JSON.stringify told

    await press 'reportIssues'
    check 'Open the issues page opens it', visited.length is 1 and visited[0] is Report.ISSUES, JSON.stringify visited
    await click 'reportClose'

    # Ticked: the sketch, redacted like the rest.
    await click 'feedback'
    await js "document.getElementById('reportSketch').checked = true; return true"
    await press 'reportDraft'
    ticked = await js "return document.getElementById('reportText').value"
    check 'ticked, the sketch is in it, redacted too',
      ticked.includes('-- The sketch, scratch.coffee') and ticked.includes(MARK) and ticked.includes('# kept in ~ by <user>'),
      JSON.stringify ticked[-200..]

    # A save that fails, clicked twice before it can: main calls Report.save
    # on this same module object, at call time.
    retouched = ticked + 'and the suite touched this one too\n'
    await js "document.getElementById('reportText').value = #{JSON.stringify retouched}; return true"
    saves = 0
    Report.save = -> saves += 1; Promise.reject new Error 'the suite refused this save'
    await js "const save = document.getElementById('reportSave'); save.click(); save.click(); return true"
    refused = await waitFor "return document.getElementById('reportRefused')?.hidden === false && !document.getElementById('reportSave').disabled"
    Report.save = realSave
    said = await js "return document.getElementById('reportRefused')?.textContent ?? '(no such element)'"
    still = await js "return document.getElementById('reportText').value"
    check 'a save that fails says why and stays on the text, the edits kept, to try again',
      refused and (await step 'reportCheck') and still is retouched and said.includes('the suite refused this save'),
      "step check #{await step 'reportCheck'}, text kept #{still is retouched}, said #{JSON.stringify said}"
    check 'Save waits for the save in flight: two clicks, one save', saves is 1, "#{saves} saves"
    await press 'reportSave'
    second = shown[1]
    await click 'reportClose'
    await waitFor "return !document.getElementById('report').open"

    # A press dragged off the button is no click. Opened after it from the
    # keyboard, the report must leave focus on the button when it closes,
    # not send it to where that press began.
    await js """
      document.getElementById('promptLine').focus()
      const button = document.getElementById('feedback')
      button.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true}))
      document.body.dispatchEvent(new PointerEvent('pointerup', {bubbles: true}))
      button.focus()
      button.click()
      return true
    """
    await waitFor "return document.getElementById('report').open"
    # Read in a `close` listener added after the app's: the dialog puts focus
    # back on the button itself first, and the app's listener moves it after,
    # so a poll could catch the moment between.
    await js """
      window.suiteClosedOn = null
      document.getElementById('report').addEventListener('close', () => {
        window.suiteClosedOn = document.activeElement.id || document.activeElement.tagName
      }, {once: true})
      document.querySelector('#reportAsk form button.ghost').click()
      return true
    """
    closedOn = await waitFor "return window.suiteClosedOn"
    check 'a press dragged off the button is forgotten: opened from the keyboard after it, closing leaves focus on the button',
      closedOn is 'feedback', closedOn

    drafts = 0
    Report.draft = (args...) -> drafts += 1; realDraft args...
    await click 'feedback'
    await js "const next = document.getElementById('reportDraft'); next.click(); next.click(); return true"
    await waitFor "return !document.getElementById('reportCheck').hidden"
    await js "return true"
    Report.draft = realDraft
    check 'Next waits for the draft in flight: two clicks, one draft', drafts is 1, "#{drafts} drafts"

    # Cancelled while its save is out, then opened again: the save landing
    # late must not jump the new report to its last step.
    release = null
    Report.save = (folder) -> new Promise (resolve) -> release = -> resolve path.join folder, 'late.txt'
    await js "document.getElementById('reportSave').click(); return true"
    deadline = Date.now() + 3000
    await new Promise((resolve) -> setTimeout resolve, 20) until release? or Date.now() > deadline
    await js "document.querySelector('#reportCheck form button.ghost').click(); return true"
    await click 'feedback'
    release?()
    landed = await waitFor "return [...document.getElementById('console').children].some((line) => line.textContent.includes('late.txt'))"
    check 'a save that lands after a cancel says so in the console, and leaves the reopened report where it is',
      release? and landed and (await step 'reportAsk') and not await step('reportDone'),
      "asked #{release?}, said #{landed}, ask step #{await step 'reportAsk'}"
  finally
    Report.save            = realSave
    Report.draft           = realDraft
    shell.showItemInFolder = realShow
    shell.openExternal     = realOpen
    await js "document.getElementById('report').close(); return true"

  texts = []
  texts.push await fsp.readFile file, 'utf8' for file in [first, second] when file
  found = (name for name in [me.user, me.host, me.home] when texts.some (text) -> text.toLowerCase().includes name.toLowerCase())
  check 'the user name, host name and home folder appear nowhere in either file',
    texts.length is 2 and found.length is 0, "#{texts.length} files; found #{JSON.stringify found}"

  saved = (await fsp.readdir reports).sort()
  check 'nothing is written outside the data folder: the two reports and only them, the checkout untouched',
    saved.length is 2 and (path.join(reports, name) for name in saved).join() is [first, second].sort().join() and
      gitStatus() is statusBefore,
    "#{JSON.stringify saved}; checkout changed: #{gitStatus() isnt statusBefore}"

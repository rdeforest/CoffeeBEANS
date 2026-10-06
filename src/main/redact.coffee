# Takes out of a report whatever would identify the player or their machine.
# Robert's bar, 2026-10-05: safe to post on a large billboard in a big city.
# Gone: the home folder (anyone's, however spelled) and the user name, the
# host name, IP and MAC addresses, e-mail addresses, and anything shaped
# like a token or key. Kept,
# because they are how a report gets diagnosed: the version, the OS and its
# release, the app's own messages, line:col positions, sketch names.
#
# Code, not a model: a table of patterns, applied in order, each with a check
# in the suite's `report` part that feeds it a realistic line. The player
# sees the result and can edit it before anything is saved, so the patterns
# lean towards taking too much rather than too little.

os   = require 'os'
path = require 'path'

escape = (text) -> text.replace /[.*+?^${}()|[\]\\]/g, '\\$&'

# A Windows path also reaches a report with forward slashes (a file URL) and
# with its backslashes doubled (anything JSON-encoded on the way).
spellings = (folder) ->
  [...new Set [folder, folder.replaceAll('\\', '/'), folder.replaceAll('\\', '\\\\')]]

# A name or a host: whole, never the middle of a longer word, so a user
# called `alice` leaves `malice` alone. Case-insensitive, as Windows and
# macOS paths are, and as host names are everywhere. A name shorter than
# SHORT is a word too often -- user `pi` in `Math.pi`, host `ab` -- so it
# goes only where it is a whole folder in a path, between two separators.
# The orchestrator's call in the V2 review, 2026-10-06, for Robert to
# overrule.
SHORT = 3

whole = (alternatives) ->
  long   = (name for name in alternatives when name.length >= SHORT).map escape
  short  = (name for name in alternatives when name.length <  SHORT).map escape
  either = [
    ("(?<![\\p{L}\\p{N}_])(?:#{long.join '|'})(?![\\p{L}\\p{N}_])" if long.length)
    ("(?<=[\\\\/])(?:#{short.join '|'})(?=[\\\\/])"               if short.length)
  ].filter Boolean
  new RegExp either.join('|'), 'giu'

# Folders end where a path segment ends: /home/al must not eat the front of
# /home/alice.
folder = (where) ->
  new RegExp "(?:#{spellings(where).map(escape).join '|'})(?![\\p{L}\\p{N}_-])", 'giu'

# Anyone's home folder, not only this account's: the same folder reached by
# another spelling -- Windows's 8.3 `ROBERT~1`, a file URL's `Robert%20Smith`
# or `jos%C3%A9`, a symlink's other path -- and another account's. A
# separator is a slash, a backslash, either doubled by JSON, or one
# percent-encoded; the name runs to the next separator.
SEPARATOR   = '(?:\\\\\\\\|[\\\\/]|%2F|%5C)'
HOME_SHAPED = new RegExp "(?:[A-Z](?::|%3A))?#{SEPARATOR}(?:Users|home)#{SEPARATOR}(?:[^\\\\/\\s'\"<>%:;,()[\\]{}]|%(?!2F|5C)[0-9A-F]{2})+", 'gi'

IPV4_OCTET = '(?:25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)'

# The shape is easy; telling an address from CoffeeScript's `Face::add` or a
# clock's 12:34:56 is the work, so candidates are checked by hand: exactly
# one `::` with at most seven groups, or none and exactly eight, and a digit
# somewhere -- prototype access between two hex-looking words has none.
ipv6 = (candidate) ->
  address = candidate.split('%')[0]
  halves  = address.split '::'
  groups  = (half.split ':' for half in halves when half).flat()
  /\d/.test(address) and halves.length <= 2 and
    groups.every((group) -> /^[0-9a-f]{1,4}$/i.test group) and
    (if halves.length is 2 then groups.length <= 7 else groups.length is 8)

# A name that says what its value is: apiKey, GITHUB_TOKEN, db-password,
# access_token in a query string. The words, not a substring, so `bypass`,
# `compass` and `author` are not taken for secrets. Not `pass` or `cookie`
# on their own: a sketch's render pass and a game's cookie are neither.
SECRET_WORDS = ['password', 'passwd', 'pwd', 'passphrase', 'secret', 'token', 'credential', 'credentials', 'auth']
SECRET_PAIRS = /(?:api|access|private|secret|client)key/

secretName = (name) ->
  words = name.replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase().split /[\s_-]+/
  words.some((word) -> word in SECRET_WORDS) or SECRET_PAIRS.test words.join ''

# Random enough to be a key: letters and digits both. A long identifier or a
# row of `x`s in a sketch has no digits; a long number has no letters.
randomish = (run) -> (run.match(/\d/g) ? []).length >= 2 and (run.match(/[a-z]/gi) ? []).length >= 2

# Base64, as an AWS secret key or a private key's body pasted without its
# BEGIN line: both cases and two digits. A path in the same alphabet --
# `sketches/level2/boss3` -- is written in lower case.
base64ish = (run) -> /[A-Z]/.test(run) and /[a-z]/.test(run) and randomish run

# Where a value is the last thing on its line, `PASSWORD = hunter2`, it is
# being stated, not computed.
endsLine = (text, at) -> /^[\s;,]*$/.test text[at..].split('\n')[0]

SECRET = '<secret>'

# One spelling of each accented letter, so `josé` composed matches `josé`
# decomposed: macOS hands out either. The redactor composes the text the
# same way.
composed = (who) ->
  out = {}
  out[key] = value?.normalize 'NFC' for key, value of who
  out

# In order. Folders before the user name, since a home folder holds it; keys
# and addresses before the bare names, since an e-mail address may hold one.
patterns = (who) ->
  {home, user, host, data, app} = composed who
  # Innermost first: the data folder sits inside the home folder, and in a
  # test run inside the app's; the app's sits inside home in a checkout.
  folders = ([where, put] for [where, put] in [[data, '<data>'], [app, '<app>'], [home, '~']] when where)
  hosts = [...new Set [host, host?.split('.')[0]]].filter Boolean

  [
    {name: 'private key', find: /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, put: SECRET}
    (for [where, put] in folders
      {name: "folder #{put}", find: folder(where), put: put})...
    {name: 'home-shaped folder', find: HOME_SHAPED, put: '~'}
    {name: 'password in a URL', find: /(?<=\/\/)[^\s\/@:]+:[^\s\/@]+(?=@)/g, put: SECRET}
    {name: 'JSON web token', find: /\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]*/g, put: SECRET}
    # GitHub, GitLab, OpenAI and Anthropic, Slack, AWS, Google.
    {
      name: 'known key prefix'
      find: /(?<![\w-])(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,}|glpat-[\w-]{20,}|sk-[\w-]{16,}|xox[abprs]-[\w-]{10,}|AKIA[0-9A-Z]{16}|AIza[\w-]{30,})(?![\w-])/g
      put: SECRET
    }
    # The scheme stays: `Bearer` or `Basic` says what kind of login failed.
    {
      name: 'authorization header'
      find: /(\bAuthorization["']?\s*[:=]\s*["']?(?:(?:Bearer|Basic|Token|Digest)\s+)?)[^\s"',;]+/gi
      put:  "$1#{SECRET}"
    }
    {name: 'bearer token', find: /(?<=\bBearer\s+)[\w.~+\/-]{8,}=*/g, put: SECRET}
    # The value goes and the name stays, so the report still says which
    # setting it was. A quoted value always goes, and so does a random one.
    # Otherwise an unquoted one goes when it is written straight after the
    # name -- `PASSWORD=hunter2`, a query string's `token=`, a header's
    # `X-Api-Key: abc` -- or ends its line, `PASSWORD = hunter2`; but not
    # from code that computes it, `secret = random 100` in a guessing game,
    # nor a call like `token = nextToken()`.
    {
      name: 'secret assignment'
      find: /([A-Za-z_][\w-]*)(["']?\s*(?::|=(?![=>]))\s*)("[^"\n]*"|'[^'\n]*'|[^\s"'`,;&#()[\]{}]+(?:\([^\s()]*\))?)/g
      put:  (match, name, between, value, offset, text) ->
        quoted = value[0] in ['"', "'"]
        head   = value.split('(')[0]
        called = value.includes '('
        tight  = /^["']?[:=]/.test between
        stated = quoted or randomish(head) or (not called and (tight or endsLine text, offset + match.length))
        if secretName(name) and stated then "#{name}#{between}#{SECRET}" else match
    }
    # With no `=` at all: .netrc's `login bob password s3cr3t!x`, or a
    # player's `password hunter2`. Prose has these words too, so only a
    # value that ends the line or looks random.
    {
      name: 'secret after its name'
      find: new RegExp "(?<![\\w-])(#{SECRET_WORDS.join '|'})([ \t]+)([^\\s\"'`,;&]+)", 'gi'
      put:  (match, name, between, value, offset, text) ->
        if randomish(value) or endsLine(text, offset + match.length) then "#{name}#{between}#{SECRET}" else match
    }
    {name: 'e-mail address', find: /[\p{L}\p{N}._%+-]+@[\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)*\.\p{L}{2,}(?![\p{L}\p{N}-])/gu, put: '<email>'}
    # Colons, dashes, or Cisco's three dotted groups.
    {
      name: 'MAC address'
      find: /(?<![\w:-])[0-9A-Fa-f]{2}([:-])[0-9A-Fa-f]{2}(?:\1[0-9A-Fa-f]{2}){4}(?![\w:-])|(?<![\w.])[0-9A-Fa-f]{4}(?:\.[0-9A-Fa-f]{4}){2}(?!\w|\.[0-9A-Fa-f])/g
      put:  '<mac>'
    }
    # Twelve hex digits alone are as often a short git commit id, so only
    # where something says it is a MAC: `ether`, ioreg's `IOMACAddress`, a
    # JSON `"mac":`.
    {
      name: 'MAC address after its name'
      find: /((?:\b|IO)(?:mac(?:[ _-]?address)?|ether|hwaddr|lladdr|bssid)\b[\s"'=:<]*)[0-9A-Fa-f]{12}(?!\w)/gi
      put:  "$1<mac>"
    }
    # Not after a letter or a dot, and not before a further dotted number: a
    # version's 1.2.3.4 is caught (a report loses nothing by it), but
    # Chromium's 140.0.7339.41 is not, and nor is a line:col.
    {name: 'IPv4 address', find: new RegExp("(?<![\\w.])(?:#{IPV4_OCTET}\\.){3}#{IPV4_OCTET}(?!\\w|\\.\\d)", 'g'), put: '<ip>'}
    {
      name: 'IPv6 address'
      find: /(?<![\w:.])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?:%[\w.-]+)?(?![\w:])/g
      put:  (match) -> if ipv6 match then '<ip>' else match
    }
    {
      name: 'base64 run'
      find: /(?<![\w+\/-])[A-Za-z0-9+\/]{32,}={0,2}(?![\w+\/=-])/g
      put:  (match) -> if base64ish match then SECRET else match
    }
    {
      name: 'long random string'
      find: /(?<![\w+-])[A-Za-z0-9_+-]{32,}=*/g
      put:  (match) -> if randomish match then SECRET else match
    }
    ({name: 'host name', find: whole(hosts), put: '<host>', word: yes} if hosts.length)
    ({name: 'user name', find: whole([user]), put: '<user>', word: yes} if user)
  ].filter Boolean

# Who is running this, asked of the OS each time a report is drafted, with
# the folders main knows (the data folder, the app's own). os.userInfo
# throws where the account has no entry in the password database (a
# container run under an arbitrary uid); the home folder's name is the
# nearest thing it has to a user name then.
userName = (home) ->
  try
    os.userInfo().username
  catch
    path.basename home

identity = (folders) ->
  home = os.homedir()
  {home, user: userName(home), host: os.hostname(), folders...}

# `words: no` leaves the user and host names alone: About's lines are the
# app's own, and a host called `linux` or a user called `node` must not turn
# them into `<host> 6.16` or `<user> 24.20.0` (orchestrator, V2 review,
# 2026-10-06).
redactor = (who, {words = yes} = {}) ->
  rules = (rule for rule in patterns(who) when words or not rule.word)
  (text) -> rules.reduce ((text, {find, put}) -> text.replace find, put), text.normalize 'NFC'

module.exports = {redactor, patterns, identity}

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

# Each accented letter both ways, so `josé` composed matches `josé`
# decomposed: macOS hands out either. The names are spelled both ways rather
# than the text composed: composing it would turn a Greek question mark into
# `;` and a Kelvin sign into `K`, which may be the very bug being reported.
accents = (name) -> [name.normalize('NFC'), name.normalize('NFD')]

# A Windows path also reaches a report with forward slashes (a file URL) and
# with its backslashes doubled (anything JSON-encoded on the way).
spellings = (folder) ->
  [...new Set accents(folder).flatMap (form) -> [form, form.replaceAll('\\', '/'), form.replaceAll('\\', '\\\\')]]

# A name or a host: whole, never the middle of a longer word, so a user
# called `alice` leaves `malice` alone. Case-insensitive, as Windows and
# macOS paths are, and as host names are everywhere. A name shorter than
# SHORT is a word too often -- user `pi` in `Math.pi`, host `ab` -- so it
# goes only where it is a whole folder in a path, between two separators.
# The orchestrator's call in the V2 review, 2026-10-06, for Robert to
# overrule.
SHORT = 3

whole = (names) ->
  alternatives = [...new Set names.flatMap accents]
  long   = (name for name in alternatives when name.length >= SHORT).map escape
  short  = (name for name in alternatives when name.length <  SHORT).map escape
  either = [
    ("(?<![\\p{L}\\p{M}\\p{N}_])(?:#{long.join '|'})(?![\\p{L}\\p{M}\\p{N}_])" if long.length)
    ("(?<=[\\\\/])(?:#{short.join '|'})(?=[\\\\/])"                            if short.length)
  ].filter Boolean
  new RegExp either.join('|'), 'giu'

# Folders end where a path segment ends: /home/al must not eat the front of
# /home/alice.
folder = (where) ->
  new RegExp "(?:#{spellings(where).map(escape).join '|'})(?![\\p{L}\\p{M}\\p{N}_-])", 'giu'

# Anyone's home folder, not only this account's: the same folder reached by
# another spelling -- Windows's 8.3 `ROBERT~1`, a file URL's `Robert%20Smith`
# or `jos%C3%A9`, a symlink's other path -- and another account's. A
# separator is a slash, a backslash, either doubled by JSON, or one
# percent-encoded; the name runs to the next separator, through single
# spaces only when one follows (`/Users/Mike Smith/Library`), so prose after
# a bare /home/bob is left alone.
SEPARATOR = '(?:\\\\\\\\|[\\\\/]|%2F|%5C)'
NAME_PART = "(?:[^\\\\/\\s'\"<>%:;,()[\\]{}]|%(?!2F|5C)[0-9A-F]{2})+"
NAME      = "#{NAME_PART}(?:(?: #{NAME_PART})+(?=#{SEPARATOR}))?"
# A web address's path is the site's, not the player's: /home/ and /users/42/
# there are how a load failure says what it was loading.
NOT_IN_URL = "(?<!\\bhttps?://[^\\s'\"<>`]*)"

HOME_SHAPED = new RegExp "#{NOT_IN_URL}(?:[A-Z](?::|%3A))?#{SEPARATOR}(?:Users|home)#{SEPARATOR}#{NAME}", 'gi'
# A drive udisks mounted for its owner: /media/<user> on Debian and Ubuntu,
# /run/media/<user> on Fedora and Arch. The mount point stays, since where a
# sketch was loaded from can be the bug.
MOUNTED = new RegExp "#{NOT_IN_URL}((?:#{SEPARATOR}run)?#{SEPARATOR}media#{SEPARATOR})#{NAME}", 'gi'
# The shell's way to another account's home, `~bob/games`. Only before a
# path, so `~str.indexOf` and `~x/2` are left to be code.
TILDE_HOME = new RegExp "#{NOT_IN_URL}(?<![\\w~])~[A-Za-z_][\\w.-]*(?=[\\\\/](?![\\d\\s(]))", 'g'

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
# access_token in a query string, and the same glued in capitals,
# PGPASSWORD and SESSIONTOKEN. The words, or the name's end, not a
# substring, so `bypass`, `compass` and `author` are not taken for secrets.
# Not `pass` or `cookie` on their own: a sketch's render pass and a game's
# cookie are neither.
SECRET_WORDS = ['password', 'passwd', 'pwd', 'passphrase', 'secret', 'token', 'credential', 'credentials', 'auth']
SECRET_PAIRS = /(?:api|access|private|secret|client)key/

secretName = (name) ->
  words  = name.replace(/([a-z0-9])([A-Z])/g, '$1 $2').toLowerCase().split /[\s_-]+/
  joined = words.join ''
  words.some((word) -> word in SECRET_WORDS) or SECRET_PAIRS.test(joined) or
    SECRET_WORDS.some (word) -> joined.endsWith word

count = (text, pattern) -> (text.match(pattern) ? []).length

# Random enough to be a key: letters and digits both. A long identifier or a
# row of `x`s in a sketch has no digits; a long number has no letters.
randomish = (run) -> count(run, /\d/g) >= 2 and count(run, /[a-z]/gi) >= 2

# Random letters in both cases are about half capitals; an identifier or a
# path is mostly lower case, or all capitals. With two digits that is not
# needed: a run with both cases and two digits was never a word.
mixed = (run) ->
  capitals = count(run, /[A-Z]/g) / Math.max 1, count(run, /[a-z]/gi)
  /[A-Z]/.test(run) and /[a-z]/.test(run) and (count(run, /\d/g) >= 2 or 0.25 <= capitals <= 0.75)

# A path in the base64 alphabet: every segment a word, CamelCase allowed,
# then perhaps a number -- `sketches/Level2/Boss3/ArenaFinal`. A key's
# pieces between its slashes are not words.
SEGMENT = /^[A-Za-z][a-z]*(?:[A-Z][a-z]*)*[0-9]*(?:\.[a-z]+)?$/
pathLike = (run) ->
  run.includes('/') and run.split('/').every (segment) ->
    segment is '' or (segment.length <= 24 and SEGMENT.test segment)

# Base64, as an AWS secret key or a private key's body pasted without its
# BEGIN line. Measured by a Claude reviewer of V2 on 100,000 random keys
# each (2026-10-06): 0.018% of 40-character AWS-shaped keys survive this,
# none of 44-character base64 or of base64url.
base64ish = (run) -> mixed(run) and not pathLike run

# Where a value is the last thing on its line, `PASSWORD = hunter2`, it is
# being stated, not computed.
endsLine = (text, at) -> /^[\s;,]*$/.test text[at..].split('\n')[0]

SECRET = '<secret>'

# In order. Folders before the user name, since a home folder holds it; keys
# and addresses before the bare names, since an e-mail address may hold one.
patterns = ({home, user, host, data, app}) ->
  # Innermost first: the data folder sits inside the home folder, and in a
  # test run inside the app's; the app's sits inside home in a checkout.
  folders = ([where, put] for [where, put] in [[data, '<data>'], [app, '<app>'], [home, '~']] when where)
  hosts = [...new Set [host, host?.split('.')[0]]].filter Boolean

  [
    {name: 'private key', find: /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, put: SECRET}
    (for [where, put] in folders
      {name: "folder #{put}", find: folder(where), put: put})...
    # \\server\share names a machine and, often, whose folder it is:
    # \\fs\home$\frank, \\server\Users\erin. Not \\?\C:\, which is a long
    # local path.
    {name: 'network share', find: /(?<![\w\\])\\\\\w[^\\\s'"<>]*\\(?:(?:Users|home\$?)\\)?[^\\\s'"<>]+/gi, put: '\\\\<share>'}
    {name: 'home-shaped folder', find: HOME_SHAPED, put: '~'}
    {name: 'mounted drive', find: MOUNTED, put: '$1<user>'}
    {name: 'home by account name', find: TILDE_HOME, put: '~'}
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
    # A session cookie is a login. The names stay, to say which cookie.
    {
      name: 'cookie'
      find: /(\b(?:Set-)?Cookie["']?[ \t]*:[ \t]*)([^\n]+)/gi
      put:  (match, head, pairs) -> head + pairs.replace /(=)[^;\s]+/g, "$1#{SECRET}"
    }
    # YAML's block scalar, `secret: |` with the value indented below it.
    # Before `secret assignment`, which would take the `|` for the value.
    {
      name: 'secret block'
      find: /^([ \t]*)([A-Za-z_][\w-]*)(["']?[ \t]*:[ \t]*[|>][1-9+-]{0,2}[ \t]*)((?:(?:\n[ \t]*(?=\n))*\n\1[ \t]+\S[^\n]*)+)/gm
      put:  (match, indent, name, header, block) ->
        return match unless secretName name
        inner = block.match(/\n([ \t]*)\S/)[1]
        "#{indent}#{name}#{header}\n#{inner}#{SECRET}"
    }
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
    # \p{M}: an accent left decomposed is part of its letter.
    {name: 'e-mail address', find: /[\p{L}\p{M}\p{N}._%+-]+@[\p{L}\p{M}\p{N}-]+(?:\.[\p{L}\p{M}\p{N}-]+)*\.\p{L}{2,}(?![\p{L}\p{M}\p{N}-])/gu, put: '<email>'}
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
    # A private key's body is wrapped at 64 (or 70, or 76) and its last line
    # can be any length, too short for `base64 run`. A short line of the
    # alphabet straight after a full one is that last line. Before `base64
    # run`, which would hide the full line this looks back at.
    {
      name: 'base64 last line'
      find: /(?<=^([A-Za-z0-9+\/]{60,})\r?\n)[A-Za-z0-9+\/]{1,31}={0,2}(?=\r?$)/gm
      put:  (match, full) -> if base64ish full then SECRET else match
    }
    {
      name: 'base64 run'
      find: /(?<![\w+\/-])[A-Za-z0-9+\/]{32,}={0,2}(?![\w+\/=-])/g
      put:  (match) -> if base64ish match then SECRET else match
    }
    # Hex digests and base64url keys. No `/` here, so no path to mistake.
    {
      name: 'long random string'
      find: /(?<![\w+-])[A-Za-z0-9_+-]{32,}=*/g
      put:  (match) -> if randomish(match) or mixed(match) then SECRET else match
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
  (text) -> rules.reduce ((text, {find, put}) -> text.replace find, put), text

module.exports = {redactor, patterns, identity}

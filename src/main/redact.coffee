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
# /home/alice, nor /home/bob the front of /home/bob.smith. A dot that ends a
# sentence still ends the folder. A web address's path is left alone, as
# the home-shaped rules leave it (IN_URL, below); for a player whose home is
# /home/alice, `https://example.com/home/alice/x.png` became
# `https://example.com~/x.png` (the integration review, 2026-10-06). The
# user name is still taken out of an address by its own rule.
folder = (where) ->
  new RegExp "#{IN_URL}(?:#{spellings(where).map(escape).join '|'})(?![\\p{L}\\p{M}\\p{N}_-]|\\.[\\p{L}\\p{N}])", 'giu'

# Anyone's home folder, not only this account's: the same folder reached by
# another spelling -- Windows's 8.3 `ROBERT~1`, a file URL's `Robert%20Smith`
# or `jos%C3%A9`, a symlink's other path -- and another account's. A
# separator is a slash, a backslash, either doubled by JSON, a slash JSON
# escaped (`\/`), or one percent-encoded. An apostrophe inside a name is
# part of it: O'Brien.
SEPARATOR = '(?:\\\\\\\\|\\\\/|[\\\\/]|%2F|%5C)'
NAME_PART = "(?:[^\\\\/\\s'\"<>%:;,()[\\]{}]|%(?!2F|5C)[0-9A-F]{2}|'(?=[A-Za-z]))+"
# The name runs to the next separator, and through single spaces only where
# something says it goes on: a separator after it (`/Users/Mike
# Smith/Library`), or the quote the path opened with, closing it
# (`'C:\Users\Mike Smith'`). So prose after a bare /home/bob is left alone,
# and so is the rest of `/home/bob doesn't exist, try 'x'`. Group 2 is the
# opening quote; the closing one is checked to be a quote too, since a
# group that never matched matches the empty string.
QUOTE_OPENS  = "(?:(?<=(['\"`]))|)"
QUOTE_CLOSES = "\\2(?<=['\"`])(?![A-Za-z])"
NAME = "#{NAME_PART}(?:(?: #{NAME_PART})+(?=#{SEPARATOR}|#{QUOTE_CLOSES}))?"
# A web address's path is the site's, not the player's: /home/ and /users/42/
# there are how a load failure says what it was loading. Its query and
# fragment are not exempt, since a local path is often passed in one. The
# address is matched and put back rather than looked behind for: a
# lookbehind that ran back over the line made every position cost the
# line's length, and one 100k-character line took seconds in main (V2's
# third review, 2026-10-06). So the rules that use it put back group 1 when
# set.
# JSON's escaped `https:\/\/` is an address too.
IN_URL = "(\\bhttps?:\\\\?/\\\\?/[^\\s'\"<>`?#]*)|"
# A home or media folder anywhere but inside the player's own folders,
# which are already `<data>`, `<app>` or `~` by now: `~/game/media/sounds`
# and `<data>/sketches/home/menu.coffee` keep their names. Anywhere else
# counts, since a path can start under any root -- Git Bash's
# `/c/Users/Robert Smith`, WSL's `/mnt/c/Users`, `/Volumes/Backup/Users`,
# `/net/nas/home/lena`, a compiler's `-I/home/bob/include`, a shell's
# `>/home/bob/log`. 34ce7fc looked only at the one character before, and
# let all of those through. The cost, a known over-redaction chosen on the
# orchestrator's instruction (V2's fourth fixer, 2026-10-06): a relative
# `sketches/media/boom.wav` or `y = x/media/2` is taken too, as at bc1ee71.
# The lookbehind runs only where a home or media folder starts, and is
# bounded, so a long line still costs its length, not its length squared.
OWN_ROOT = "(?<!(?:<data>|<app>|~)(?:[\\\\/]{1,2}[^\\\\/\\s'\"<>:,;]{1,255}){1,16})"

# Silverblue's /var/home/<user> is reached through its /var. A drive letter
# only where a word does not run into it: `path:/home/bob` keeps its `h:`.
HOME_HEAD   = "(?:(?<!\\w)[A-Z](?::|%3A))?(?:#{SEPARATOR}var)?#{SEPARATOR}(?:Users|home)#{SEPARATOR}"
HOME_SHAPED = new RegExp "#{IN_URL}(?=#{HOME_HEAD})#{OWN_ROOT}#{QUOTE_OPENS}#{HOME_HEAD}#{NAME}", 'gi'
# A drive udisks mounted for its owner: /media/<user> on Debian and Ubuntu,
# /run/media/<user> (or /var/run/media/<user>) on Fedora and Arch. The
# mount point stays, since where a sketch was loaded from can be the bug.
MOUNT_HEAD = "(?:#{SEPARATOR}(?:var#{SEPARATOR})?run)?#{SEPARATOR}media#{SEPARATOR}"
MOUNTED    = new RegExp "#{IN_URL}(?=#{MOUNT_HEAD})#{OWN_ROOT}#{QUOTE_OPENS}(#{MOUNT_HEAD})#{NAME}", 'gi'
# The shell's way to another account's home, `~bob/games`. Only before a
# path, so `~str.indexOf` and `~x/2` are left to be code.
TILDE_HOME = new RegExp "#{IN_URL}(?<![\\w~])~[A-Za-z_][\\w.-]*(?=[\\\\/](?![\\d\\s(]))", 'g'

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
# being stated, not computed. Looked for from `at` and no further than the
# line's end: splitting off the rest of the text cost every `x = 1` in a
# long sketch the sketch's length, and 400KB of them 36s (V2's fourth
# review, 2026-10-06).
LINE_END = /(?:[^\S\n]|[;,])*(?:\n|$)/y
endsLine = (text, at) ->
  LINE_END.lastIndex = at
  LINE_END.test text

# Space within a line: a non-breaking or ideographic space as well as a
# space or a tab, or `password:\u00a0hunter2` would keep its value.
INLINE = '[^\\S\\r\\n\\u2028\\u2029]'

SECRET = '<secret>'

# In order. Folders before the user name, since a home folder holds it; keys
# and addresses before the bare names, since an e-mail address may hold one.
patterns = ({home, user, host, data, app}) ->
  # Innermost first: the data folder sits inside the home folder, and in a
  # test run inside the app's; the app's sits inside home in a checkout.
  folders = ([where, put] for [where, put] in [[data, '<data>'], [app, '<app>'], [home, '~']] when where)
  hosts = [...new Set [host, host?.split('.')[0]]].filter Boolean

  [
    # Not across another BEGIN: one with no END would otherwise search to the
    # end of the text from every BEGIN after it.
    {name: 'private key', find: /-----BEGIN [A-Z ]*PRIVATE KEY-----(?:(?!-----BEGIN )[\s\S])*?-----END [A-Z ]*PRIVATE KEY-----/g, put: SECRET}
    (for [where, put] in folders
      {name: "folder #{put}", find: folder(where), put: do (put) -> (match, url) -> url ? put})...
    # \\server\share names a machine and, often, whose folder it is:
    # \\fs\home$\frank, \\server\Users\erin. Not \\?\C:\, which is a long
    # local path. Group 1 is one backslash, or two where JSON doubled them.
    {
      name: 'network share'
      find: /(?<![\w\\])(\\\\?)\1\w[^\\\s'"<>]*\1(?:(?:Users|home\$?)\1)?[^\\\s'"<>]+/gi
      put:  '$1$1<share>'
    }
    {name: 'home-shaped folder', find: HOME_SHAPED, put: (match, url) -> url ? '~'}
    {name: 'mounted drive', find: MOUNTED, put: (match, url, quote, mount) -> url ? "#{mount}<user>"}
    {name: 'home by account name', find: TILDE_HOME, put: (match, url) -> url ? '~'}
    {name: 'password in a URL', find: /(?<=\/\/)[^\s\/@:]+:[^\s\/@]+(?=@)/g, put: SECRET}
    {name: 'JSON web token', find: /\beyJ[\w-]{8,}\.[\w-]{8,}\.[\w-]*/g, put: SECRET}
    # GitHub, GitLab, OpenAI and Anthropic, Slack, AWS, Google, Stripe,
    # Hugging Face.
    {
      name: 'known key prefix'
      find: /(?<![\w-])(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_\w{20,}|glpat-[\w-]{20,}|sk-[\w-]{16,}|xox[abprs]-[\w-]{10,}|AKIA[0-9A-Z]{16}|AIza[\w-]{30,}|[sr]k_(?:live|test)_[A-Za-z0-9]{20,}|hf_[A-Za-z]{30,})(?![\w-])/g
      put: SECRET
    }
    # The scheme stays: `Bearer` or `Basic` says what kind of login failed.
    {
      name: 'authorization header'
      find: /(\bAuthorization["']?\s*[:=]\s*["']?(?:(?:Bearer|Basic|Token|Digest)\s+)?)[^\s"',;]+/gi
      put:  "$1#{SECRET}"
    }
    # Matched forward from `Bearer`: a lookbehind for it ran back over every
    # space before each position, and 100k blank lines took five seconds.
    {name: 'bearer token', find: /(\bBearer\s+)[\w.~+\/-]{8,}=*/g, put: "$1#{SECRET}"}
    # A session cookie is a login. The names stay, to say which cookie.
    {
      name: 'cookie'
      find: /(\b(?:Set-)?Cookie["']?[ \t]*:[ \t]*)([^\n]+)/gi
      put:  (match, head, pairs) -> head + pairs.replace /(=)[^;\s]+/g, "$1#{SECRET}"
    }
    # YAML's block scalar, `secret: |` with the value indented below it.
    # Before `secret assignment`: that takes the `|` for the value, which
    # leaves the lines below with no header for this to find. It still takes
    # the `|` afterwards.
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
    # nor a call like `token = nextToken()`. Across a line end only to a
    # quoted value, `{"password":\n"hunter2"}`, and never to one that is
    # itself a name: `config.yml:` once took the next line's `password:` for
    # its value and hid it, and `db:` would take `"password":` the same way.
    # The name is bounded so that a long run of letters costs its length,
    # not its length squared.
    {
      name: 'secret assignment'
      find: new RegExp "([A-Za-z_][\\w-]{0,63})([\"']?#{INLINE}*(?::|=(?![=>]))(?:\\s*(?=[\"'])|#{INLINE}*))" +
        "(\"[^\"\\n]*\"(?!#{INLINE}*:)|'[^'\\n]*'(?!#{INLINE}*:)|[^\\s\"'`,;&#()[\\]{}]+(?:\\([^\\s()]*\\))?)", 'g'
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
      find: new RegExp "(?<![\\w-])(#{SECRET_WORDS.join '|'})(#{INLINE}+)([^\\s\"'`,;&]+)", 'gi'
      put:  (match, name, between, value, offset, text) ->
        if randomish(value) or endsLine(text, offset + match.length) then "#{name}#{between}#{SECRET}" else match
    }
    # \p{M}: an accent left decomposed is part of its letter. `%40` is an
    # `@` in a web address. Started only where a run of the local part
    # starts: a match could not start later in the run without starting at
    # its front, and trying each position cost 100,000 letters 6.5s under
    # Node 26 (none under Electron 44's V8; V2's third fixer, 2026-10-06).
    {name: 'e-mail address', find: /(?<![\p{L}\p{M}\p{N}._%+-])[\p{L}\p{M}\p{N}._%+-]+(?:@|%40)[\p{L}\p{M}\p{N}-]+(?:\.[\p{L}\p{M}\p{N}-]+)*\.\p{L}{2,}(?![\p{L}\p{M}\p{N}-])/gu, put: '<email>'}
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
    # Other machines on the network, by the names Bonjour and Avahi give
    # them: `bobs-macbook.local`. Only hyphenated, where a name is a host's
    # and not a word.
    {name: 'mDNS host name', find: /(?<![\w.-])[A-Za-z0-9]+(?:-[A-Za-z0-9]+)+\.local(?![\w-]|\.\w)/gi, put: '<host>'}
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

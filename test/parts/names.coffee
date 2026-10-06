# Sketch names on a disk that folds case. Robert decided on 2026-10-05 that
# on macOS and Windows names differing only in case are one sketch, and that
# Edit > Warn About Name Case, on by default, says when the name asked for and
# the name on disk differ.
#
# This Linux disk keeps cases apart, so here the suite has main behave as if
# it folded (`folding.forced`, the way `faults` stands in for Windows refusing
# a rename) -- main then finds foo.coffee for Foo, which is what such a disk
# does. On the Windows and macOS CI runners the disk folds for real, the
# override stays off, and the same checks run against the real thing.

fsp      = require 'fs/promises'
path     = require 'path'
{Menu}   = require 'electron'
Settings = require '../../src/main/settings'

module.exports = (t) ->
  {js, check, setDoc, consoleText, clearConsole, quiet, untilDoc, waitFor, paths} = t
  {folding, sketches} = paths

  sketch    = 'names-foo'
  file      = path.join sketches, "#{sketch}.coffee"
  original  = "print 'FOO'\n"
  folder    = path.join sketches, 'names-sub'
  probeFile = path.join sketches, 'Names-Probe.txt'
  warnItem  = -> Menu.getApplicationMenu().getMenuItemById 'warnCase'
  # Every spelling of the sketch in its folder, as the disk lists it.
  spellings = (dir = sketches, leaf = "#{sketch}.coffee") ->
    (entry for entry in await fsp.readdir dir when entry.toLowerCase() is leaf)

  # /e at the prompt, then until the editor holds a sketch by either
  # spelling: today's code opened a new, empty `Names-Foo`.
  edit = (asked, meant = asked) ->
    await js "Editor.command(#{JSON.stringify "/e #{asked}"}); return true"
    await waitFor "return (Editor.name() || '').toLowerCase() === #{JSON.stringify meant.toLowerCase()}", 10000
    # selectSketch says its notice after asking main for the setting; this
    # asks main too, so its answer comes back behind that one.
    await js "await beans.warnCase(); return true"
    await quiet()

  # What the app came up with, before this part touched anything.
  stored = Settings.read path.join paths.data, 'settings.json'
  check 'a fresh install has Edit > Warn About Name Case ticked',
    warnItem()?.checked is true and not stored.warnCase?, JSON.stringify {checked: warnItem()?.checked, stored}

  # The probe asks the folder's name in its parent; this asks a file inside
  # the folder, the other way round.
  await fsp.writeFile probeFile, '', 'utf8'
  twin = await fsp.stat(path.join sketches, 'names-probe.txt').then (-> yes), (-> no)
  await fsp.rm probeFile
  check 'main knows whether the sketches folder folds case',
    folding.probed is twin, "probed #{folding.probed} disk #{twin}"

  # The probe swaps the case of ASCII letters only. A disk folding by a
  # one-for-one table (NTFS's) finds STRAßE.COFFEE for straße.coffee, never
  # STRASSE.COFFEE, JavaScript's full-mapping swap -- under which such a disk
  # probed as one that does not fold. Here a hard link spelled the one-for-one
  # way stands in for that disk; on a disk that folds, the link is refused as
  # already there, and the disk itself answers.
  probeDir = path.join paths.data, 'names-probe'
  await fsp.rm probeDir, recursive: yes, force: yes
  await fsp.mkdir probeDir
  try
    await fsp.writeFile path.join(probeDir, 'straße.coffee'), '', 'utf8'
    await fsp.link(path.join(probeDir, 'straße.coffee'), path.join(probeDir, 'STRAßE.COFFEE')).catch (error) ->
      throw error unless error.code is 'EEXIST'
    unicode = paths.probeFolding probeDir
  finally
    await fsp.rm probeDir, recursive: yes, force: yes
  check 'the probe finds straße.coffee again as STRAßE.COFFEE, where the disk folds that way',
    unicode is true, "probed #{unicode}"

  remembered = await js "return localStorage.getItem('lastSketch')"
  try
    # A disk that keeps cases apart keeps names apart, as it always did.
    unless folding.probed
      await fsp.writeFile file, original, 'utf8'
      await edit 'Names-Foo'
      apart = {name: await js("return Editor.name()"), disk: await fsp.readFile(file, 'utf8'), spellings: await spellings()}
      await js "await Editor.load('scratch'); return true"
      await fsp.rm path.join(sketches, 'Names-Foo.coffee'), force: yes
      check 'where the disk keeps cases apart, /e Names-Foo is a new sketch beside names-foo',
        apart.name is 'Names-Foo' and apart.disk is original and apart.spellings.length is 2,
        JSON.stringify apart

    # Whatever the disk: `./names-foo` is names-foo. Before, `/e ./names-foo`
    # looked for `./names-foo` among the names, missed, and "created" it --
    # writing '' over names-foo.coffee. Then the editor held it as
    # `./names-foo`, which the watcher's news (of `names-foo`) never matched.
    # Nor is `./names-foo` a spelling of names-foo the case notice is about.
    await fsp.writeFile file, original, 'utf8'
    await clearConsole()
    await edit './names-foo', sketch
    dotted =
      name:  await js "return Editor.name()"
      title: await js "return document.title"
      disk:  await fsp.readFile file, 'utf8'
      said:  (await consoleText()).trim()
    check '/e ./names-foo opens names-foo as it is, under that name, with no word about its case',
      dotted.name is sketch and dotted.title is "#{sketch} — CoffeeBEANS" and dotted.disk is original and
        not dotted.said.includes('asked for'),
      JSON.stringify dotted
    await fsp.writeFile file, "print 'DOTTED'\n", 'utf8'
    reached = await untilDoc "print 'DOTTED'\n", 10000
    check 'and an outside write to names-foo.coffee reaches it',
      reached is "print 'DOTTED'\n", JSON.stringify reached

    # A new sketch is made only if the disk still has none: one that appeared
    # since sketch:find looked is opened, not emptied.
    await js "await Editor.load('scratch'); return true"
    await fsp.writeFile file, original, 'utf8'
    raced = await js "return await beans.create('#{sketch}')"
    check 'creating a sketch that is already there opens it and leaves it be',
      raced.name is sketch and raced.created is false and (await fsp.readFile file, 'utf8') is original,
      JSON.stringify {raced, disk: await fsp.readFile file, 'utf8'}

    folding.forced = not folding.probed
    await fsp.writeFile file, original, 'utf8'
    await clearConsole()

    # The bug that started it: "created" Names-Foo with '' -- over foo.coffee,
    # on a disk that folds.
    await edit 'Names-Foo'
    opened =
      name:      await js "return Editor.name()"
      doc:       await js "return Editor.all()"
      disk:      await fsp.readFile file, 'utf8'
      spellings: await spellings()
    check '/e Names-Foo opens names-foo.coffee as it is, and writes nothing',
      opened.name is sketch and opened.doc is original and opened.disk is original and
        JSON.stringify(opened.spellings) is JSON.stringify(["#{sketch}.coffee"]),
      JSON.stringify opened

    said  = await consoleText()
    title = await js "return document.title"
    times = said.split("opened #{sketch} -- you asked for Names-Foo").length - 1
    check 'it says once that the name asked for is spelled otherwise, and the title has the disk\'s spelling',
      times is 1 and not said.includes('created') and title is "#{sketch} — CoffeeBEANS",
      JSON.stringify {said: said.trim(), title}

    # The editor holds it under the disk's spelling, so the watcher's news of
    # it and the editor's saves are about the one file.
    await fsp.writeFile file, "print 'OUTSIDE'\n", 'utf8'
    outside = await untilDoc "print 'OUTSIDE'\n", 10000
    check 'an outside write to names-foo.coffee reaches the editor that asked for Names-Foo',
      outside is "print 'OUTSIDE'\n", JSON.stringify outside

    await setDoc "print 'EDITED'\n"
    await js "await Editor.save(); return true"
    saved = {disk: await fsp.readFile(file, 'utf8'), spellings: await spellings()}
    check 'and its saves land in names-foo.coffee',
      saved.disk is "print 'EDITED'\n" and saved.spellings.length is 1, JSON.stringify saved

    # Unticked, the same open says nothing, and the choice is saved.
    await js "await Editor.load('scratch'); return true"
    await clearConsole()
    warnItem().click()
    await edit 'NAMES-FOO'
    quietly =
      name:   await js "return Editor.name()"
      said:   (await consoleText()).trim()
      stored: Settings.read(path.join paths.data, 'settings.json').warnCase
    warnItem().click()
    check 'with Warn About Name Case unticked it opens names-foo without a word, and remembers that',
      quietly.name is sketch and not quietly.said.includes('asked for') and quietly.stored is false,
      JSON.stringify quietly

    # Saves under both spellings are saves of one file, so they queue as one:
    # apart, they raced for the one staging file and the disk kept whichever
    # finished last (see sketch:write).
    await js "await Editor.load('scratch'); return true"
    results = await js """
      const writes = [];
      for (let i = 0; i < 12; i++) writes.push(beans.write(i % 2 ? 'NAMES-FOO' : '#{sketch}', 'print ' + i + ' ' + 'x'.repeat(4000 - 300 * i) + '\\n'));
      return (await Promise.allSettled(writes)).map(r => r.status === 'fulfilled' ? 'ok' : r.reason.message);
    """
    failed = (r for r in results when r isnt 'ok')
    disk   = await fsp.readFile file, 'utf8'
    last   = "print 11 #{'x'.repeat 4000 - 300 * 11}\n"
    check 'overlapping saves under two spellings all land in one file, the last one asked for',
      failed.length is 0 and disk is last and (await spellings()).length is 1,
      "#{failed.length} failed #{JSON.stringify failed[0] ? ''} disk starts #{JSON.stringify disk[0...12]} #{JSON.stringify await spellings()}"

    # A folder's spelling too: a new sketch goes into the folder already there.
    await fsp.mkdir folder, recursive: yes
    await edit 'Names-Sub/new'
    made =
      name:     await js "return Editor.name()"
      inFolder: await spellings(folder, 'new.coffee')
      folders:  await spellings(sketches, 'names-sub')
    check '/e Names-Sub/new makes the sketch in names-sub/, not a second folder',
      made.name is 'names-sub/new' and made.inFolder.length is 1 and made.folders.length is 1,
      JSON.stringify made

    # Where the disk folds, the extension's case does not matter either: a
    # foo.COFFEE is foo, not a name `foo.COFFEE` whose file would be
    # foo.COFFEE.coffee. (Opening it needs a disk that really folds, which
    # only the macOS and Windows runners have.)
    upper = path.join sketches, 'names-ext.COFFEE'
    await fsp.writeFile upper, original, 'utf8'
    try
      ext =
        found: await js "return await beans.find('Names-Ext')"
        list:  (n for n in await js("return await beans.list()") when n.toLowerCase().startsWith 'names-ext')
    finally
      await fsp.rm upper, force: yes
    check 'names-ext.COFFEE is the sketch names-ext, found and listed',
      ext.found.name is 'names-ext' and JSON.stringify(ext.list) is '["names-ext"]',
      JSON.stringify ext

    # The boot: a name typed into the URL, and the one remembered from last
    # time, each found under any spelling.
    await fsp.writeFile file, original, 'utf8'
    booted = await t.freshPage """
      if (typeof Editor === 'undefined' || !Editor.name()) return false
      const said = document.getElementById('console').textContent
      return said.includes('you asked for') && {name: Editor.name(), title: document.title, said}
    """, 8000, '?sketch=Names-Foo'
    check '?sketch=Names-Foo opens names-foo and says so',
      booted?.name is sketch and booted.title.startsWith(sketch) and booted.said.includes("opened #{sketch} -- you asked for Names-Foo"),
      JSON.stringify booted

    await js "localStorage.setItem('lastSketch', 'NAMES-FOO'); return true"
    reopened = await t.freshPage """
      return typeof Editor !== 'undefined' && Editor.name() && {name: Editor.name()}
    """
    check 'a remembered NAMES-FOO reopens names-foo rather than the first sketch',
      reopened?.name is sketch, JSON.stringify reopened

    # A name main refuses: before, the boot stopped at the refusal with no
    # sketch open, and whatever was typed next was never saved.
    refused = await t.freshPage """
      if (typeof Editor === 'undefined' || !Editor.name()) return false
      return {name: Editor.name(), said: document.getElementById('console').textContent}
    """, 8000, '?sketch=../names-outside'
    check '?sketch=../names-outside says it is outside and opens the first sketch',
      refused?.name and refused.said.includes('outside sketches/') and refused.said.includes("opening #{refused.name}"),
      JSON.stringify refused
  finally
    folding.forced = no
    await js "const was = #{JSON.stringify remembered}; was === null ? localStorage.removeItem('lastSketch') : localStorage.setItem('lastSketch', was); return true"
    warnItem().click() unless warnItem().checked
    await js "await Editor.load('scratch'); return true"
    await fsp.rm file, force: yes
    await fsp.rm folder, recursive: yes, force: yes

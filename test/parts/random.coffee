# Seeded randomness: one mulberry32 stream behind rnd, random and Math.random,
# reseeded by a fresh worker and by randomize(), and by nothing else.

module.exports = (t) ->
  {wait, check, setDoc, clearConsole, click, settled} = t

  # Each run in its own worker, so a value carried between two of these has
  # crossed a restart, which is the case currentSeed exists for.
  fresh = (source) ->
    await setDoc source
    await wait 400
    await clearConsole()
    await click 'runFresh'
    (await settled()).trim()

  # The reference algorithm (Tommy Ettinger's mulberry32), run by a Claude
  # agent on 2026-10-05 in plain node and as C; both gave these first three
  # outputs for seed 42, as 32-bit integers.
  known = '2581720956 1925393290 3661312704'
  text  = await fresh "randomize 42\nprint (rnd() * 4294967296 for i in [1..3]).join ' '\n"
  check 'randomize 42 gives mulberry32\'s known answer', text is known, JSON.stringify text

  draw  = "randomize 7\nprint (rnd() for i in [1..5]).join ','\n"
  one   = await fresh draw
  two   = await fresh draw
  check 'the same seed gives the same sequence in a new worker',
    one is two and one.split(',').length is 5, "#{JSON.stringify one} vs #{JSON.stringify two}"

  text = await fresh """
    randomize 5
    rnd() for i in [1..10]
    saved = rnd.currentSeed
    ahead = (rnd() for i in [1..5]).join ','
    randomize saved
    again = (rnd() for i in [1..5]).join ','
    print "number=\#{typeof saved is 'number'} resumed=\#{ahead is again}"
    print "seed=\#{saved}"
    print "ahead=\#{ahead}"
  """
  check 'currentSeed handed to randomize carries on exactly',
    text.includes('number=true resumed=true'), JSON.stringify text

  # and across a restart, the "pick up where I left off" case
  saved = /seed=(\d+)/.exec(text)?[1]
  ahead = /ahead=(\S+)/.exec(text)?[1]
  later = await fresh "randomize #{saved}\nprint (rnd() for i in [1..5]).join ','\n"
  check 'currentSeed carries on exactly in a new worker',
    saved? and later is ahead, "#{JSON.stringify later} vs #{JSON.stringify ahead}"

  text = await fresh """
    randomize 9
    a = [rnd(), random(), Math.random()]
    randomize 9
    b = [Math.random(), rnd(), random()]
    print "same=\#{random is Math.random} follow=\#{a.join() is b.join()}"
  """
  check 'random is Math.random, and both follow the seed',
    text is 'same=true follow=true', JSON.stringify text

  # Several resolutions between draws, since trying screen settings partway
  # through a sketch is the ordinary case NOTES.md names.
  text = await fresh """
    randomize 3
    plain = (rnd() for i in [1..6])
    randomize 3
    mixed = []
    for i in [1..6]
      screen 160 + i, 100
      mixed.push rnd()
    print "kept=\#{plain.join() is mixed.join()}"
  """
  check 'screen leaves the random stream alone', text is 'kept=true', JSON.stringify text

  probe = "print \"\#{rnd.currentSeed} \#{rnd()}\"\n"
  first  = await fresh probe
  second = await fresh probe
  [seedA] = first.split ' '
  [seedB] = second.split ' '
  check 'two fresh workers start from different seeds',
    /^\d+$/.test(seedA) and /^\d+$/.test(seedB) and first isnt second,
    "#{JSON.stringify first} vs #{JSON.stringify second}"

  text = await fresh "randomize 0.5\n"
  check 'randomize refuses a fraction instead of truncating it',
    text.includes('whole number'), JSON.stringify text

  # `randomize save.seed` with the field missing must fail, not quietly
  # reseed; only a bare randomize() is fresh.
  text = await fresh """
    randomize 11
    a = rnd()
    randomize()
    b = rnd()
    print "reseeded=\#{a isnt b}"
    randomize undefined
  """
  check 'randomize undefined is refused while randomize() reseeds',
    text.includes('reseeded=true') and text.includes('whole number, got undefined'),
    JSON.stringify text

  text = await fresh "randomize '5'\n"
  check 'randomize shows a string seed as a string',
    text.includes('got "5"'), JSON.stringify text

  text = await fresh """
    randomize 4294967295
    big = (rnd() for i in [1..5]).join ','
    randomize -1
    print "seed=\#{rnd.currentSeed} same=\#{big is (rnd() for i in [1..5]).join ','}"
  """
  check 'a negative seed wraps to its 32-bit twin',
    text is 'seed=4294967295 same=true', JSON.stringify text

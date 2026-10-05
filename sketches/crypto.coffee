if 'undefined' is typeof print
  print = console.log

intercept = """
    c43594a60dd4dbf985a4b320750e6181bb60d27c264a725a05e523e2b3949d0d52dc6cd5c9aceb434ad720ee50041dae9003
  """

intercept2 = """
    fe15ab919554b7b1110c5f2e3c24fa7e204ded1a339e1af91cf686a66717827ffb301c52bea06659b07b97770f06
  """

hexToInt = (hexStr) ->
  hexStr = hexStr.split('').filter((c) -> c in "0123456789abcdefABCDEF").join ''
  ( while hexStr
      octetStr = hexStr[..1]
      hexStr   = hexStr[2..]
      parseInt octetStr, 16
  )

intToHex = (ints) ->
  ( for c in ints
      (c.toString 16).padStart 2, '0'
  ).join ''

strToInt = (s) ->
  s .split ''
    .map (c) -> c.charCodeAt 0

intToStr = (ints) ->
  ints.map (i) -> String.fromCharCode i
      .join ''

cypherText = hexToInt intercept2

nextToGen = (nextFn, selector = (i) -> i) -> (z) ->
  loop
    yield selector z = nextFn z

makeRnd1 = (state, times = 16807, mod = 2**31 - 1) ->
  state = (state * times) % mod

makeRnd2 = (state, times = 1103515245, plus = 12345, mod = 2**31) ->
  state = parseInt ((BigInt(state) * BigInt(times) + BigInt(plus)) % BigInt(mod)).toString()

makeRnd = nextToGen makeRnd2, (z) -> (z >> 16) & 0xFF

encode =
decode = (cypherText, seed) ->
  myRnd = makeRnd seed
  cypherText.map (n) -> n ^ myRnd.next().value

validity = (s) ->
  if matched = s.match /^[0-9 A-Z.,?;:_()*&^%$#@!+-]*/
    matched[0].length
  else
    0

bruteForceSeed = (cypherText, begin, end) ->
  candidates = []

  for seed in [begin .. end]
    clearText = intToStr decode cypherText, seed

    if 3 < score = validity clearText
      candidates.push {seed, score, clearText, ok: clearText[..score - 1]}

  candidates.sort (a, b) -> a.score - b.score

  return candidates

print intToStr decode (hexToInt intercept2), 1989
#results = (bruteForceSeed cypherText, 1, 9999)[-10..]
#print results.length
#results[-10..].forEach ({ok}) -> print ok

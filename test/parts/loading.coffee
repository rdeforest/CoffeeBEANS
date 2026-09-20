# Images off the disk and off the network, and the cache underneath.

fsp     = require 'fs/promises'
path    = require 'path'

module.exports = (t) ->
  {wait, check, setDoc, evalAll, consoleText, clearConsole, paths, settled} = t
  # 30. load: real bytes, real decode, correct channel order, cached to disk
  assets = path.join paths.data, 'assets'
  await fsp.mkdir assets, recursive: yes
  await fsp.copyFile path.join(paths.root, 'test', 'fixtures', 'swatch.png'),
                     path.join assets, 'swatch.png'

  loading = """
screen 320, 200
cls()
swatch = load 'assets/swatch.png'
print 'size=' + swatch.width + 'x' + swatch.height
print 'red='   + (drawTo(swatch, -> pget 0, 0) is COLORS.red)
print 'green=' + (drawTo(swatch, -> pget 1, 0) is COLORS.lime)
print 'blue='  + (drawTo(swatch, -> pget 0, 1) is COLORS.blue)
print 'clear=' + (drawTo(swatch, -> pget 1, 1) is 0)

# transparency survives the trip: over must skip the clear pixel
cls COLORS.yellow
put swatch, 10, 10
print 'keptUnder=' + (pget(11, 11) is COLORS.yellow)
print 'drewOver='  + (pget(10, 10) is COLORS.red)

try
  load 'assets/definitely-missing.png'
  print 'missing=no error'
catch error
  print 'missing=' + (error.message.length > 0)
"""
  await setDoc loading
  await wait 500
  await clearConsole()
  await evalAll()
  text3  = await settled()
  wanted = ['size=2x2', 'red=true', 'green=true', 'blue=true', 'clear=true',
            'keptUnder=true', 'drewOver=true', 'missing=true']
  absent = (want for want in wanted when not text3.includes want)
  check 'load decodes an image with the right channel order', absent.length is 0,
    if absent.length then "missing #{absent.join ', '} -- got #{JSON.stringify text3.trim()}" else 'all eight'

  # 31. a remote image is cached, so the second run needs no network
  cachedFiles = await fsp.readdir assets
  check 'assets folder is where downloads land', cachedFiles.includes('swatch.png'),
    cachedFiles.join ', '

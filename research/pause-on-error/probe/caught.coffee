# Way (a)'s missing half, prototyped offline (Claude, 2026-10-05): with
# pauseOnExceptions 'all' V8 stops at every throw and its own `uncaught` flag
# is false for all of them -- worker-boot.js catches everything -- so the
# debugger would have to decide for itself whether the sketch will catch it.
#
# The rule: walk the paused stack from the top; a sketch frame whose position
# lies inside the `try` part of a try/catch the author wrote catches it.
# Positions come from the run's source map, whose sourcesContent carries the
# CoffeeScript, so no new plumbing is needed to get the source.
#
#   coffee research/pause-on-error/probe/caught.coffee     runs the cases

CoffeeScript = require 'coffeescript'

# [first, last] positions of every try body that has a catch, as
# [line, column] pairs, zero-based like the source map.
tryBodies = (source) ->
  bodies = []
  CoffeeScript.nodes(source).traverseChildren yes, (node) ->
    return unless node.constructor.name is 'Try' and node.catch
    at = node.attempt.locationData
    bodies.push [[at.first_line, at.first_column], [at.last_line, at.last_column]]
  bodies

before = ([l1, c1], [l2, c2]) -> l1 < l2 or (l1 is l2 and c1 <= c2)

# `stack` is innermost first: {source, line, column} for an author's frame,
# {ours: yes} for anything else. Ours never catches -- the runtime has only
# try/finally (grep, 2026-10-05) -- except the prompt, which is its own case.
willCatch = (stack) ->
  for frame in stack when not frame.ours
    return yes for [from, to] in tryBodies(frame.source) when before(from, [frame.line, frame.column]) and before([frame.line, frame.column], to)
  no

module.exports = {willCatch, tryBodies}

return unless require.main is module

source = """
got = 0
try
  null.x
catch e
  got = 1
risky = -> null.y
try risky() catch then got = 2
try
  ok = 1
catch e
  null.z
"""
cases = [
  ['throw inside a try body',                [{source, line: 2, column: 2}], yes]
  ['throw in a function, called from a try', [{source, line: 5, column: 11}, {source, line: 6, column: 4}], yes]
  ['throw inside a catch clause',            [{source, line: 10, column: 2}], no]
  ['throw at top level, no try',             [{source, line: 0, column: 0}], no]
  ['runtime frame on top, sketch try below', [{ours: yes}, {source, line: 2, column: 2}], yes]
]
for [name, stack, expected] in cases
  got = willCatch stack
  console.log "#{if got is expected then 'PASS' else 'FAIL'}  #{name}"

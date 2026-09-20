# BASIC had STOP: halt here, let me look, then carry on. This is that.
#
# It compiles to a `debugger` statement, which does nothing whatsoever unless
# something is watching. So a sketch with breakpoints left in it runs at full
# speed when nobody is debugging it, and there is no mode to remember to turn
# off -- which is the whole reason to spell it this way rather than keep a list
# of line numbers somewhere and try to hold them still while the buffer moves.
#
# A getter, like buffer.swap and keys.poll, so it reads as a bare word the way
# STOP did rather than as a call:
#
#   addAngle = (a, b) ->
#     breakpoint
#     a + b
#
# It stops *inside* here, one frame below the line you wrote, because that is
# where the statement is. A debugger that knows about us steps out once so you
# land on your own line; one that does not (DevTools) shows you this file and
# one click on "step out" does the same.
#
# Its own module, deliberately outside the beans-runtime/ family the others
# take. A debugger skips `debugger` statements inside a script it has been told
# to ignore, and the entire point of naming that family is so a debugger can
# ignore it. Put this file in there too and the command quietly stops working,
# which is about the worst failure a breakpoint can have.

Object.defineProperty globalThis, 'breakpoint', get: -> debugger

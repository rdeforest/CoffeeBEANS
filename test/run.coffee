# `npm test`. Node rather than a shell one-liner, so the same command works
# from cmd.exe and PowerShell: `rm -rf` and `VAR=x cmd` are POSIX only.
# Anything else set in the environment (BEANS_TESTS, BEANS_SHOW...) passes
# through to the app untouched.

{spawn} = require 'child_process'
fs      = require 'fs'
path    = require 'path'

root = path.resolve __dirname, '..'
data = path.join root, 'test_tmp'

# A run starts from an empty data folder, and a full green run removes it
# again; anything else leaves it for troubleshooting (the suite says so).
# The removal waits for Electron to exit: on Windows the app's own files in
# it are still open until then, and removing it from inside failed with EBUSY.
fs.rmSync data, recursive: yes, force: yes

env  = {process.env..., BEANS_TEST: '1', BEANS_DATA_HOME: 'test_tmp'}
full = not (process.env.BEANS_TESTS ? '').split(',').some (name) -> name.trim()

spawn require('electron'), ['.'], {cwd: root, env, stdio: 'inherit'}
  .on 'error', (error) ->
    console.error "could not start electron: #{error.message}"
    process.exit 1
  .on 'exit', (code, signal) ->
    console.error "electron killed by #{signal}" if signal
    if code is 0 and full
      fs.rmSync data, recursive: yes, force: yes
      console.log "removed #{data}"
    process.exit code ? 1

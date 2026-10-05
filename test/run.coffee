# `npm test`. Node rather than a shell one-liner, so the same command works
# from cmd.exe and PowerShell: `rm -rf` and `VAR=x cmd` are POSIX only.
# Anything else set in the environment (BEANS_TESTS, BEANS_SHOW...) passes
# through to the app untouched.

{spawn} = require 'child_process'
fs      = require 'fs'
path    = require 'path'

root = path.resolve __dirname, '..'

# A run starts from an empty data folder; the suite removes it again after a
# full green run, and leaves it for troubleshooting otherwise.
fs.rmSync path.join(root, 'test_tmp'), recursive: yes, force: yes

env = {process.env..., BEANS_TEST: '1', BEANS_DATA_HOME: 'test_tmp'}

spawn require('electron'), ['.'], {cwd: root, env, stdio: 'inherit'}
  .on 'exit', (code, signal) ->
    console.error "electron killed by #{signal}" if signal
    process.exit code ? 1

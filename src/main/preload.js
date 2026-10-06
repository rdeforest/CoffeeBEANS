const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('beans', {
  read:  (name)       => ipcRenderer.invoke('sketch:read', name),
  write: (name, text) => ipcRenderer.invoke('sketch:write', name, text),
  // Blocks until main has the sketch on disk; only for a page going away.
  flush: (name, text) => ipcRenderer.sendSync('sketch:flush', name, text),
  list:  ()           => ipcRenderer.invoke('sketch:list'),
  find:  (name)       => ipcRenderer.invoke('sketch:find', name),
  create: (name)      => ipcRenderer.invoke('sketch:create', name),
  pick:  ()           => ipcRenderer.invoke('sketch:pick'),
  paths: ()           => ipcRenderer.invoke('beans:paths'),
  image: (url)        => ipcRenderer.invoke('image:load', url),
  onOpen: (handler) => ipcRenderer.on('sketch:open', () => handler()),
  // Edit > Vim Keys: asked once at mount, then told whenever it is clicked.
  vim:   ()        => ipcRenderer.invoke('settings:vim'),
  onVim: (handler) => ipcRenderer.on('settings:vim', (_event, on) => handler(on)),
  // Edit > Undo and Redo, which the page sends to whichever history has focus.
  onHistory: (handler) => ipcRenderer.on('edit:history', (_event, verb) => handler(verb)),
  // And when that is a text field's, main takes the page's native step.
  nativeHistory: (verb) => ipcRenderer.invoke('edit:native', verb),
  // Help > About. The text is main's: it knows git's answer and the OS.
  about:   ()        => ipcRenderer.invoke('app:about'),
  onAbout: (handler) => ipcRenderer.on('app:about', () => handler()),
  // Through main, which writes whether or not the page has focus; Chromium's
  // navigator.clipboard refuses a page without it, and the suite's never has.
  copy:    (text)    => ipcRenderer.invoke('clipboard:write', text),
  // Edit > Warn About Name Case: asked whenever it matters.
  warnCase: ()     => ipcRenderer.invoke('settings:warnCase'),
  // Line stepping, in the app's words. See src/main/debugger.coffee.
  debug: {
    arm:     (want)         => ipcRenderer.invoke('debug:arm', want),
    pause:   ()             => ipcRenderer.invoke('debug:pause'),
    step:    ()             => ipcRenderer.invoke('debug:step'),
    resume:  (skip)         => ipcRenderer.invoke('debug:resume', skip),
    evaluate: (pause, source) => ipcRenderer.invoke('debug:eval', pause, source),
    members: (pause, id)    => ipcRenderer.invoke('debug:members', pause, id),
    getter:  (pause, owner, name) => ipcRenderer.invoke('debug:getter', pause, owner, name),
    onEvent: (handler) =>
      ipcRenderer.on('debug:event', (_event, payload) => handler(payload)),
  },
  onChanged: (handler) =>
    ipcRenderer.on('sketch:changed', (_event, payload) => handler(payload)),
})

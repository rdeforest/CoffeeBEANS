const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('beans', {
  read:  (name)       => ipcRenderer.invoke('sketch:read', name),
  write: (name, text) => ipcRenderer.invoke('sketch:write', name, text),
  list:  ()           => ipcRenderer.invoke('sketch:list'),
  pick:  ()           => ipcRenderer.invoke('sketch:pick'),
  paths: ()           => ipcRenderer.invoke('beans:paths'),
  image: (url)        => ipcRenderer.invoke('image:load', url),
  onOpen: (handler) => ipcRenderer.on('sketch:open', () => handler()),
  // Line stepping, in the app's words. See src/main/debugger.coffee.
  debug: {
    arm:     (want)         => ipcRenderer.invoke('debug:arm', want),
    pause:   ()             => ipcRenderer.invoke('debug:pause'),
    step:    ()             => ipcRenderer.invoke('debug:step'),
    resume:  (skip)         => ipcRenderer.invoke('debug:resume', skip),
    evaluate: (source)      => ipcRenderer.invoke('debug:eval', source),
    members: (pause, id)    => ipcRenderer.invoke('debug:members', pause, id),
    getter:  (pause, owner, name) => ipcRenderer.invoke('debug:getter', pause, owner, name),
    onEvent: (handler) =>
      ipcRenderer.on('debug:event', (_event, payload) => handler(payload)),
  },
  onChanged: (handler) =>
    ipcRenderer.on('sketch:changed', (_event, payload) => handler(payload)),
})

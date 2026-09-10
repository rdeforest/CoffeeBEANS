const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('beans', {
  read:  (name)       => ipcRenderer.invoke('sketch:read', name),
  write: (name, text) => ipcRenderer.invoke('sketch:write', name, text),
  list:  ()           => ipcRenderer.invoke('sketch:list'),
  paths: ()           => ipcRenderer.invoke('beans:paths'),
  onChanged: (handler) =>
    ipcRenderer.on('sketch:changed', (_event, payload) => handler(payload)),
})

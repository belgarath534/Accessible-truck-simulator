// The small bridge between the game page and the app.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('truckSim', {
  screenReaderActive: () => ipcRenderer.sendSync('screen-reader-active'),
  quit: () => ipcRenderer.send('quit'),
});

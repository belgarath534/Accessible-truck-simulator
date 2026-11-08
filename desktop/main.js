// Electron main process: one window that runs the game from the src folder.
import { app, BrowserWindow, ipcMain, net, protocol, Menu } from 'electron';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, 'src');

// Sound starts without a click first (it's a game).
app.commandLine.appendSwitch('autoplay-policy', 'no-user-gesture-required');

// The game is served from app://game/, a secure origin, so the audio worklet and modules load normally.
protocol.registerSchemesAsPrivileged([
  { scheme: 'app', privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true } },
]);

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 800,
    minWidth: 800,
    minHeight: 600,
    title: 'Accessible Truck Simulator',
    backgroundColor: '#12161c',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(here, 'preload.cjs'),
      contextIsolation: true,
      sandbox: true,
    },
  });
  win.loadURL('app://game/index.html');
}

app.whenReady().then(() => {
  Menu.setApplicationMenu(null);
  protocol.handle('app', (request) => {
    const { pathname } = new URL(request.url);
    const file = path.normalize(path.join(root, decodeURIComponent(pathname)));
    if (!file.startsWith(root)) return new Response('Not found', { status: 404 });
    return net.fetch(pathToFileURL(file).toString());
  });
  // True while Windows reports a screen reader (NVDA, JAWS, Narrator) is running.
  ipcMain.on('screen-reader-active', (e) => {
    e.returnValue = app.isAccessibilitySupportEnabled();
  });
  ipcMain.on('quit', () => app.quit());
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

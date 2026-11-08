// Copies the game's recordings from the iPhone app folder, so both versions share one set of sounds.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '..', '..');
const copies = [
  [path.join(repo, 'App', 'Sounds'), path.join(here, '..', 'src', 'sounds'), ['.wav']],
  [path.join(repo, 'App', 'Music'), path.join(here, '..', 'src', 'music'), ['.m4a']],
];
for (const [from, to, exts] of copies) {
  fs.mkdirSync(to, { recursive: true });
  for (const name of fs.readdirSync(from)) {
    if (!exts.includes(path.extname(name))) continue;
    fs.copyFileSync(path.join(from, name), path.join(to, name));
  }
  console.log(`Copied ${from} -> ${to}`);
}

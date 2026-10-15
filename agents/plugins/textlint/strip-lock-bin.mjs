// package-lock.json から各パッケージの bin を取り除き、npm ci に node_modules/.bin の symlink を作らせない。
// Claude Desktop は symlink を含む plugin を SSH 先へコピーせず、その plugin をセッションごと無効にするため。
// .npmrc の bin-links=false では代わりにならない。Claude Code は package.json と lockfile だけを一時ディレクトリへ移して npm ci するため。
import { readFile, writeFile } from "node:fs/promises";

const LOCKFILE = new URL("package-lock.json", import.meta.url);

const lock = JSON.parse(await readFile(LOCKFILE, "utf8"));
for (const pkg of Object.values(lock.packages ?? {})) delete pkg.bin;
await writeFile(LOCKFILE, `${JSON.stringify(lock, null, 2)}\n`);

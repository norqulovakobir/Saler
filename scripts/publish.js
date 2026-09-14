// Monorepo'dagi bitta papkani (bot yoki mini_app) o'zining GitHub deploy repo'siga push qiladi.
// Maxfiy va lokal fayllar (.env, env.json, node_modules, data/, tools/, loglar) repo'ga kirmaydi.
//
// Ishlatish (ildizda):
//   npm run publish:bot
//   npm run publish:mini_app
//   node scripts/publish.js <papka> <repo-url> [branch]
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');

const [folder, repo, branch = 'main'] = process.argv.slice(2);
if (!folder || !repo) {
  console.error('Ishlatish: node scripts/publish.js <papka> <repo-url> [branch]');
  process.exit(1);
}
const ROOT = path.resolve(__dirname, '..');
const SRC = path.join(ROOT, folder);
if (!fs.existsSync(SRC)) {
  console.error(`Papka topilmadi: ${SRC}`);
  process.exit(1);
}
const SKIP = new Set(['node_modules', 'data', 'tools', '.env', 'env.json', '.git', 'build', '.dart_tool']);

const out = fs.mkdtempSync(path.join(os.tmpdir(), `saler-${folder}-`));
const run = (cmd) => execSync(cmd, { cwd: out, stdio: 'inherit' });
const git = (cmd) => run(`git -c user.name="Behruz" -c user.email="tajimurodovbehruz@gmail.com" ${cmd}`);

fs.cpSync(SRC, out, { recursive: true, filter: (src) => !SKIP.has(path.basename(src)) && !src.endsWith('.log') });

let sha = '';
try { sha = execSync('git rev-parse --short HEAD', { cwd: ROOT }).toString().trim(); } catch {}
const msg = `Deploy ${folder}${sha ? ` (monorepo ${sha})` : ''}`;

run('git init -q');
run(`git checkout -q -b ${branch}`);
run('git add -A');
git(`commit -q -m "${msg}"`);
// Remote'da tarix bo'lsa uni saqlab, ustiga yangi holatni yozamiz
try {
  run(`git fetch -q ${repo} ${branch}`);
  git(`merge -q -s ours --allow-unrelated-histories FETCH_HEAD -m "${msg}"`);
} catch {
  console.log("Remote'da tarix yo'q — birinchi push");
}
run(`git push ${repo} ${branch}:${branch}`);
console.log(`\nPush qilindi: ${folder} -> ${repo} (${branch})`);
fs.rmSync(out, { recursive: true, force: true });

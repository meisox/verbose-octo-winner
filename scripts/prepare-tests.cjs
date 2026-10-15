// Stage the real sources for Lune. Only import paths and Roblox globals change.
// Compression needs the engine and is deliberately unavailable in this runner.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
const refIndex = args.indexOf('--ref');
const ref = refIndex < 0 ? undefined : args[refIndex + 1];
const dest = path.join(root, 'tests', ref ? '.baseline' : '.generated');
function files(dir) {
  return fs.readdirSync(path.join(root, dir), {withFileTypes:true}).flatMap(e =>
    e.isDirectory() ? files(`${dir}/${e.name}`) : [`${dir}/${e.name}`]);
}
const sources = ref
  ? cp.execFileSync('git', ['ls-tree', '-r', '--name-only', ref, 'src'], {cwd:root, encoding:'utf8'}).trim().split('\n')
  : files('src');
function staged(file) { return file.replace(/\/init\.luau$/, '/index.luau'); }
for (const file of sources.filter(f => f.endsWith('.luau'))) {
  let source = ref
    ? cp.execFileSync('git', ['show', `${ref}:${file}`], {cwd:root, encoding:'utf8'})
    : fs.readFileSync(path.join(root,file),'utf8');
  source = source.replace(/require\("([^"\n]+)"\)/g, (_, spec) => {
    if (!spec.startsWith('.') && !spec.startsWith('@self/')) throw new Error(`Unexpected import ${spec}`);
    // Roblox resolves ordinary paths from the requiring ModuleScript's parent.
    // Rojo init files become their directory's ModuleScript, so @self is used
    // for children and ./ for siblings. Preserve the original baseline's paths.
    const base = !ref && file.endsWith('/init.luau') && !spec.startsWith('@self/')
      ? path.posix.dirname(path.posix.dirname(file)) : path.posix.dirname(file);
    let target = path.posix.normalize(path.posix.join(base, spec.replace(/^@self\//, './'))) + '.luau';
    if (!sources.includes(target) && sources.includes(target.replace(/\.luau$/, '/init.luau'))) target = target.replace(/\.luau$/, '/init.luau');
    let relative = path.posix.relative(path.posix.dirname(staged(file)), staged(target)).replace(/\.luau$/, '');
    if (!relative.startsWith('.')) relative = './' + relative;
    return `require(${JSON.stringify(relative)})`;
  });
  if (file.startsWith('src/Roblox/')) {
    source = '--!strict\nlocal r = require("@lune/roblox")\nlocal Vector2, Vector3, CFrame, Color3, UDim, UDim2 = r.Vector2, r.Vector3, r.CFrame, r.Color3, r.UDim, r.UDim2\n' + source;
  }
  if (file === 'src/Compressed.luau') {
    source = 'local game = { GetService = function() error("Compression tests require Roblox Studio") end }\nlocal Enum = {}\n' + source;
    // Original eager module initialization prevents loading any codec in Lune.
    source = source.replace(/local EncodingService = game:GetService\("EncodingService"\)/, 'local EncodingService = {}');
    source = source.replace(/Enum\.CompressionAlgorithm\.Zstd/g, '"Zstd"');
  }
  const output = path.join(dest, staged(file));
  fs.mkdirSync(path.dirname(output), {recursive:true});
  fs.writeFileSync(output, source);
}
console.log(`Staged ${sources.length} sources from ${ref ?? 'working tree'} in ${path.relative(root,dest)}`);

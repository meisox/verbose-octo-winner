// Emits a bounded source group for the Studio MCP test runner. No game files
// are read or changed; the runner mounts these as detached ModuleScripts.
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const group=process.argv[2];
const dir=group==='root'?'src':group==='tests'?'tests':`src/${group}`;
const files=fs.readdirSync(path.join(root,dir),{withFileTypes:true})
  .filter(e=>e.isFile()&&e.name.endsWith('.luau'))
  .map(e=>({path:`${dir}/${e.name}`,source:fs.readFileSync(path.join(root,dir,e.name),'utf8')}));
process.stdout.write(JSON.stringify(files));

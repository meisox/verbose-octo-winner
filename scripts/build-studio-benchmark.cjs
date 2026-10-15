const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..'),target=path.join(root,'build/StudioBenchmark.luau');
if(process.argv[2]==='--part'){process.stdout.write(JSON.stringify(fs.readFileSync(target,'utf8').slice(Number(process.argv[3])*60000,(Number(process.argv[3])+1)*60000)));process.exit(0);}
function git(args){return cp.execFileSync('git',args,{cwd:root,encoding:'utf8'});}
function collect(dir){return fs.readdirSync(path.join(root,dir),{withFileTypes:true}).flatMap(e=>e.isDirectory()?collect(`${dir}/${e.name}`):[{path:`${dir}/${e.name}`,source:fs.readFileSync(path.join(root,dir,e.name),'utf8')}]);}
const current=collect('src').filter(f=>f.path.endsWith('.luau'));
const baseline=git(['ls-tree','-r','--name-only','0327edf','src']).trim().split('\n').filter(p=>p.endsWith('.luau')).map(p=>({path:p,source:git(['show',`0327edf:${p}`])}));
const hash=crypto.createHash('sha256').update(JSON.stringify(current)).digest('hex');
function literal(s){let eq='';while(s.includes(']'+eq+']'))eq+='=';return '['+eq+'['+s+']'+eq+']';}
let code=`local container=Instance.new("Folder")\nlocal nodes={}\nlocal function node(path,class)\n if nodes[path] then return nodes[path] end\n local parent,name=string.match(path,"^(.*)/([^/]+)$")\n if not name then parent,name="",path end\n local object=Instance.new(class or "Folder");object.Name=name\n object.Parent=if parent=="" then container else node(parent)\n nodes[path]=object;return object\nend\n`;
code+='node("old","ModuleScript");node("new","ModuleScript")\n';
for(const [group,files] of [['old',baseline],['new',current]]){
 for(const init of [true,false])for(const f of files.filter(f=>f.path.endsWith('/init.luau')===init)){
  let s=f.source;
  // Repair only original Roblox string-import paths so the intended baseline loads.
  if(group==='old'&&f.path==='src/init.luau')s=s.replace('@self/Dynamic/init','@self/Dynamic');
  if(group==='old'&&f.path==='src/Dynamic/init.luau')s=s.replace('require("../Types")','require("./Types")').replaceAll(/require\("\.\/([^"/]+)"\)/g,(m,name)=>name==='Types'?m:`require("@self/${name}")`);
  const relative=init?f.path.slice(4,-10).replace(/\/$/,''):f.path.slice(4,-5);
  code+=`node(${literal(group+(relative?'/'+relative:''))},"ModuleScript").Source=${literal(s)}\n`;
 }
}
code+=`node("benchmark","ModuleScript").Source=${literal(fs.readFileSync(path.join(root,'benchmarks/studio.luau'),'utf8'))}\n`;
code+=`local result\nlocal ok,problem=xpcall(function()\n result=require(nodes.benchmark)(require(nodes.old),require(nodes.new))\nend,debug.traceback)\ncontainer:Destroy()\nif not ok then error(problem) end\nresult.sourceHash=${JSON.stringify(hash)};result.baseline=${JSON.stringify(git(['rev-parse','0327edf']).trim())}\nreturn result\n`;
fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,code);
console.log(JSON.stringify({sourceHash:hash,characters:code.length,parts:Math.ceil(code.length/60000)}));

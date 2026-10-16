// Build a self-contained engine test runner. All modules are detached from the
// DataModel and destroyed after execution, including on a test failure.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');
const target=path.join(root,'build','StudioTests.luau');
if(process.argv[2]==='--part'){
  const index=Number(process.argv[3]);
  if(!Number.isSafeInteger(index)||index<0)throw new Error('Invalid part');
  process.stdout.write(JSON.stringify(fs.readFileSync(target,'utf8').slice(index*60000,(index+1)*60000)));
  process.exit(0);
}
function collect(directory){return fs.readdirSync(path.join(root,directory),{withFileTypes:true}).flatMap(e=>e.isDirectory()?collect(`${directory}/${e.name}`):e.name.endsWith('.luau')?[{path:`${directory}/${e.name}`,source:fs.readFileSync(path.join(root,directory,e.name),'utf8')}]:[]);}
const files=collect('src').concat(fs.readdirSync(path.join(root,'tests')).filter(n=>n.endsWith('.luau')).map(n=>({path:`tests/${n}`,source:fs.readFileSync(path.join(root,'tests',n),'utf8')})));
const hash=crypto.createHash('sha256').update(JSON.stringify(files)).digest('hex');
function literal(source){let eq='';while(source.includes(']'+eq+']'))eq+='=';return '['+eq+'['+source+']'+eq+']';}
let code=`local root=Instance.new("ModuleScript")
root.Name="SerdesValidation"
local nodes={[""]=root}
local function node(path,class)
 if nodes[path] then return nodes[path] end
 local parent,name=string.match(path,"^(.*)/([^/]+)$")
 if not name then parent,name="",path end
 local object=Instance.new(class or "Folder")
 object.Name=name;object.Parent=node(parent);nodes[path]=object
 return object
end
`;
for(const f of files.filter(f=>f.path.startsWith('src/')&&f.path.endsWith('/init.luau')))code+=`node(${literal(f.path.slice(4,-10).replace(/\/$/,''))},"ModuleScript").Source=${literal(f.source)}\n`;
for(const f of files.filter(f=>f.path.startsWith('src/')&&!f.path.endsWith('/init.luau')))code+=`node(${literal(f.path.slice(4,-5))},"ModuleScript").Source=${literal(f.source)}\n`;
for(const f of files.filter(f=>f.path.startsWith('tests/'))){
 const source='return function()\n'+f.source.replace(/require\("\.\/\.generated\/src\/index"\)/,'require(script.Parent)')+'\nreturn true\nend\n';
 code+=`node(${literal('Test_'+f.path.slice(6,-5))},"ModuleScript").Source=${literal(source)}\n`;
}
code+=`local result={sourceHash=${JSON.stringify(hash)},version=version(),tests={}}
local logStart=#game:GetService("LogService"):GetLogHistory()
local ok,problem=xpcall(function()
`;
for(const f of files.filter(f=>f.path.startsWith('tests/'))){const name=JSON.stringify('Test_'+f.path.slice(6,-5));code+=`result.tests[${name}]=require(nodes[${name}])()\n`;}
code+=`end,debug.traceback)
root:Destroy()
result.ok=ok;result.problem=if ok then nil else tostring(problem)
local logs=game:GetService("LogService"):GetLogHistory()
result.log={};for i=logStart+1,#logs do table.insert(result.log,logs[i].message) end
return result
`;
fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,code);
console.log(JSON.stringify({path:path.relative(root,target),sourceHash:hash,characters:code.length,parts:Math.ceil(code.length/60000)}));

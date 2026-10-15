const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const root=path.resolve(__dirname,'..');
function run(command,args){const r=cp.spawnSync(command,args,{cwd:root,stdio:'inherit'});if(r.error)throw r.error;if(r.status!==0)process.exit(r.status??1);}
async function main(){
  fs.mkdirSync(path.join(root,'build'),{recursive:true});
  const definitions=process.env.ROBLOX_TYPES||path.join(root,'build/globalTypes.d.luau');
  if(!fs.existsSync(definitions)){
    // Pin the engine definitions independently of installed editor state.
    const revision='8e8a4e745c814ee8d3dd1cea8980901cb27a6970';
    const response=await fetch(`https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/${revision}/scripts/globalTypes.d.luau`);
    if(!response.ok)throw new Error(`Unable to download Roblox definitions: ${response.status}`);
    fs.writeFileSync(definitions,await response.text());
  }
  run('rojo',['sourcemap','default.project.json','--output','build/sourcemap.json']);
  run(process.env.LUAU_LSP||'luau-lsp',['analyze','--flag:LuauSolverV2=True','--platform=roblox',`--definitions=${definitions}`,'--sourcemap=build/sourcemap.json','src','tests/types/public.luau']);
  const file='tests/types/public-negative.luau';
  const negative=cp.spawnSync(process.env.LUAU_LSP||'luau-lsp',['analyze','--flag:LuauSolverV2=True','--platform=roblox',`--definitions=${definitions}`,'--sourcemap=build/sourcemap.json',file],{cwd:root,encoding:'utf8'});
  if(negative.error)throw negative.error;
  const output=negative.stdout+negative.stderr;
  const expected=fs.readFileSync(path.join(root,file),'utf8').split('\n').flatMap((s,i)=>s.includes('-- EXPECT_ERROR')?[i+1]:[]);
  const errors=[...output.matchAll(/public-negative\.luau\((\d+),\d+\): TypeError:/g)].map(m=>Number(m[1]));
  if(negative.status===0||expected.some(n=>!errors.includes(n))||errors.some(n=>!expected.includes(n))||output.split('TypeError:').length-1!==errors.length){console.error(output);throw new Error('Public API rejection tests did not fail on exactly the expected lines');}
  console.log(`Public API types: valid usage accepted; ${expected.length} invalid uses rejected`);
}
main().catch(e=>{console.error(e.message);process.exitCode=1});

const cp=require('node:child_process'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
function run(command,args){const r=cp.spawnSync(command,args,{cwd:root,stdio:'inherit'});if(r.error)throw r.error;if(r.status!==0)process.exit(r.status??1);}
run(process.execPath,['scripts/prepare-tests.cjs']);
run('luau-analyze',['tests/types/positive.luau']);
let rejected=0;
for(const file of ['negative','schema-indexers']) {
  const negative=cp.spawnSync('luau-analyze',[`tests/types/${file}.luau`],{cwd:root,encoding:'utf8'});
  if(negative.error)throw negative.error;
  const output=negative.stdout+negative.stderr;
  const lines=fs.readFileSync(path.join(root,`tests/types/${file}.luau`),'utf8').split('\n');
  const expected=lines.map((s,i)=>s.includes('-- EXPECT_ERROR')?i+1:null).filter(Boolean);
  const errors=[...output.matchAll(/\.luau\((\d+),\d+\): TypeError:/g)].map(m=>Number(m[1]));
  if(negative.status===0||expected.length!==errors.length||expected.some(n=>!errors.includes(n))||output.split('TypeError:').length-1!==expected.length){console.error(output);throw new Error('Type rejection suite did not fail exactly as expected');}
  rejected+=expected.length;
}
console.log(`Type tests: valid schema accepted; ${rejected} invalid uses rejected`);
for(const suite of ['regressions','packing','delta','struct','quantization','dynamic','compression','roblox','public'])run('lune',['run',`tests/${suite}.luau`]);

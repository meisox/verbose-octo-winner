const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process'),crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');
function run(command,args){const r=cp.spawnSync(command,args,{cwd:root,encoding:'utf8'});if(r.error)throw r.error;if(r.status!==0)throw new Error(r.stdout+r.stderr);return r.stdout;}
process.stdout.write(run(process.execPath,['scripts/prepare-tests.cjs']));
process.stdout.write(run(process.execPath,['scripts/prepare-tests.cjs','--ref','0327edf']));
const digest=crypto.createHash('sha256');
function hashSources(dir){for(const name of fs.readdirSync(path.join(root,dir)).sort()){const relative=`${dir}/${name}`;if(fs.statSync(path.join(root,relative)).isDirectory())hashSources(relative);else{digest.update(relative);digest.update(fs.readFileSync(path.join(root,relative)));}}}
hashSources('src');
const report={baseline:run('git',['rev-parse','0327edf']).trim(),sourceHash:digest.digest('hex'),platform:process.platform,createdAt:new Date().toISOString(),runs:[]};
for(const native of [true,false])for(const suite of ['compare','dynamic']){
  const args=['-O2',...(native?['--codegen']:[]),`benchmarks/${suite}.luau`];
  const csv=run('luau',args);report.runs.push({suite,native,command:['luau',...args].join(' '),csv});
  console.log(`Finished ${suite} (${native?'native':'interpreted'})`);
}
const output=path.join(root,'benchmarks/results/latest.json');fs.mkdirSync(path.dirname(output),{recursive:true});fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');
console.log(path.relative(root,output));

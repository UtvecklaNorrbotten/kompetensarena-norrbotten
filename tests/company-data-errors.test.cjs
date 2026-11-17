// Synthetic database failures. No server credentials or production data.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const ts=require('typescript');
const zod=require('zod');

async function responseFor(error,action='scope',client=null) {
  const logs=[];
  const source=fs.readFileSync('src/lib/company-data.server.ts','utf8')
    .replace("(await import('@/integrations/supabase/client.server')).supabaseAdmin",'globalThis.syntheticClient');
  const built=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
  assert.equal((built.diagnostics??[]).length,0);
  const exports={};
  const context={exports,Response,URL,TextEncoder,console:{error:(...v)=>logs.push(v)},
    syntheticClient:client??{rpc:async()=>({data:[],error})},
    require:(name)=>{
      if(name==='zod')return zod;
      if(name==='./etl-auth.server')return {authorize:async()=>null,createRateLimiter:()=>()=>false,json:(body,status)=>new Response(JSON.stringify(body),{status})};
      throw new Error('Unexpected synthetic dependency');
    }};
  vm.runInNewContext(built.outputText,context);
  const response=await exports.handleCompanyData(new Request('https://synthetic.example/api/public/jobs/company-data?action='+action));
  return {response,body:await response.json(),logs};
}

test('database timeouts and serialization/lock failures permit client retry',async()=>{
  for(const code of ['57014','55P03','40001','40P01','53300','08006']){
    const {response,body,logs}=await responseFor({code,message:'synthetic-secret'});
    assert.equal(response.status,503);
    assert.equal(body.error_code,code);
    assert.equal(response.headers.get('cache-control'),'no-store');
    assert.ok(!JSON.stringify({body,logs}).includes('synthetic-secret'));
  }
});

test('validation errors remain terminal and unsafe database text is hidden',async()=>{
  for(const [code,expected] of [['P0001','P0001'],['unsafe synthetic-secret','unknown']]){
    const {response,body,logs}=await responseFor({code,message:'synthetic-secret'});
    assert.equal(response.status,422);
    assert.equal(body.error_code,expected);
    assert.ok(!JSON.stringify({body,logs}).includes('synthetic-secret'));
  }
});

test('successful database response is preserved',async()=>{
  const {response,body}=await responseFor(null);
  assert.equal(response.status,200);
  assert.deepEqual(body,[]);
});

test('comparison sample uses AB filter, excludes pending/stale reports and omits names',async()=>{
  const rows={afr_syncs:{source_date:'synthetic-source'},afr_je_current:[{je_id:'a'},{je_id:'b'},{je_id:'c'},{je_id:'d'},{je_id:'e'}],
    company_account_candidates:[{je_id:'a',status:'imported',package_sha256:'same',period_end:'2025-12-31'},
      {je_id:'c',status:'quarantined'},{je_id:'d',status:'pending'},{je_id:'e',status:'imported',package_sha256:'stale'}],
    company_accounts_latest:[{je_id:'a',account_id:1},{je_id:'e',account_id:2}],
    company_accounts:[{id:1,package_sha256:'same',document_sha256:'doc'},{id:2,package_sha256:'old'}]};
  let pages=0;const filters=[];
  const client={rpc:async(name,params)=>{
    assert.equal(name,'company_data_scope');assert.equal(params.p_limit,100);
    return {data:pages++===0?['a','b','c','d','e'].map(je_id=>({je_id,org_nr:'0000000000'})):[],error:null};
  },from:(table)=>{
    const chain={then:(resolve)=>Promise.resolve({data:rows[table],error:null}).then(resolve)};
    for(const method of ['select','eq','order','limit','single','in'])chain[method]=(...args)=>{filters.push([table,method,...args]);return chain;};
    return chain;
  }};
  const {response,body}=await responseFor(null,'api-sample',client);
  assert.equal(response.status,200);
  assert.deepEqual(body.samples.map(r=>r.bulk_status),['imported','absent','quarantined']);
  assert.ok(filters.some(f=>f[0]==='afr_je_current'&&f[1]==='eq'&&f[2]==='jurform'&&f[3]==='49'));
  for(const row of body.samples)assert.deepEqual(Object.keys(row).sort(),['bulk_status','document_sha256','org_nr','package_sha256','period_end']);
});

test('quarantine inventory validates cursor and refuses non-AB identities',async()=>{
  const {response}=await responseFor(null,'quarantine-audit&after=invalid');
  assert.equal(response.status,400);
  let identitiesRead=false;const filters=[];
  const client={from:(table)=>{
    if(table==='afr_je_ident')identitiesRead=true;
    const data=table==='company_account_candidates'?[{je_id:'a',package_sha256:'hash'}]:[];
    const chain={then:(resolve)=>Promise.resolve({data,error:null}).then(resolve)};
    for(const method of ['select','eq','order','limit','in'])chain[method]=(...args)=>{filters.push([table,method,...args]);return chain;};
    return chain;
  }};
  const refused=await responseFor(null,'quarantine-audit',client);
  assert.equal(refused.response.status,422);
  assert.equal(identitiesRead,false);
  assert.ok(filters.some(f=>f[0]==='afr_je_current'&&f[1]==='in'&&f[2]==='jurform'&&JSON.stringify(f[3])==='["41","42","49"]'));
});

test('supplement queues reject unknown modes and invalid cursors',async()=>{
  for(const action of ['supplement-queue&mode=unknown','supplement-queue&mode=api&after=bad']){
    const {response}=await responseFor(null,action);
    assert.equal(response.status,400);
  }
  const {response}=await responseFor(null,'supplement-queue&mode=bulk');
  assert.equal(response.status,200);
});

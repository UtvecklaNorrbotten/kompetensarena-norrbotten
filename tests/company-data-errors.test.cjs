// Synthetic database failures. No server credentials or production data.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const ts=require('typescript');
const zod=require('zod');

async function responseFor(error) {
  const logs=[];
  const source=fs.readFileSync('src/lib/company-data.server.ts','utf8')
    .replace("(await import('@/integrations/supabase/client.server')).supabaseAdmin",'globalThis.syntheticClient');
  const built=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022},reportDiagnostics:true});
  assert.equal((built.diagnostics??[]).length,0);
  const exports={};
  const context={exports,Response,URL,TextEncoder,console:{error:(...v)=>logs.push(v)},
    syntheticClient:{rpc:async()=>({data:[],error})},
    require:(name)=>{
      if(name==='zod')return zod;
      if(name==='./etl-auth.server')return {authorize:async()=>null,createRateLimiter:()=>()=>false,json:(body,status)=>new Response(JSON.stringify(body),{status})};
      throw new Error('Unexpected synthetic dependency');
    }};
  vm.runInNewContext(built.outputText,context);
  const response=await exports.handleCompanyData(new Request('https://synthetic.example/api/public/jobs/company-data?action=scope'));
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

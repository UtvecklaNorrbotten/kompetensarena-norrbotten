/** Protected ETL API. No public views or direct client access to company data. */
import { z } from 'zod';
import type { SupabaseClient } from '@supabase/supabase-js';
import { authorize, createRateLimiter, json as etlJson } from './etl-auth.server';

function json(body:unknown,status:number):Response {
  const response=etlJson(body,status);
  response.headers.set('cache-control','no-store');
  return response;
}

const rate = createRateLimiter(600);
const sha = z.string().regex(/^[0-9a-f]{64}$/);
const uuid = z.string().uuid();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const key = z.string().regex(/^arsredovisningar\/\d{4}\/\d{2}_\d+\.zip$/);
const member = z.string().regex(/^\d{10}_\d{4}-\d{2}-\d{2}\.zip$/);
const archive = z.object({key,etag:z.string().min(1).max(200),size:z.number().int().positive(),modified:z.string().datetime(),
  scope_hash:sha,members:z.number().int().nonnegative(),downloaded_bytes:z.number().int().nonnegative()}).strict();
const metric = z.string().regex(/^-?\d+(\.\d+)?$/).max(100).nullable();
const metrics = z.object({net_sales:metric,operating_profit:metric,profit_for_year:metric,equity:metric,total_assets:metric,average_employees:metric}).strict();
const document = z.object({document_id:z.string().min(1).max(300),source_reference:z.string().url().max(1000),archive_key:key,
  member_name:member,archive_etag:z.string().max(200),package_sha256:sha,document_sha256:sha,storage_path:z.string().regex(/^accounts\/[0-9a-f]{64}\.zip$/),
  parser_version:z.string().max(100),period_start:day,period_end:day,currency:z.string().regex(/^[A-Z]{3}$/),unit:z.literal('currency_units'),
  report_type:z.string().max(2000),scope:z.literal('company'),metrics,provenance:z.record(z.unknown()),issues:z.array(z.string().max(300)).max(100)}).strict();
const allocation = z.object({cfar_nr:z.string().regex(/^\d+$/),structure_history_id:z.number().int().positive(),midpoint:metric,
  weight:metric,estimated_net_sales:metric,flags:z.array(z.string().max(100)),is_estimate:z.literal(true),rule_version:z.literal('afr-midpoint-1')}).strict();
const postSchema = z.discriminatedUnion('action',[
  z.object({action:z.literal('profile-hashes'),entity:z.enum(['je','ae']),keys:z.array(z.string().max(40)).max(1000)}).strict(),
  z.object({action:z.literal('profiles'),sync_id:uuid,entity:z.enum(['je','ae']),records:z.array(z.object({key:z.string().max(40),
    profile_canonical:z.string().max(20000),contact_canonical:z.string().max(5000),profile_hash:sha,contact_hash:sha}).strict()).max(1000)}).strict(),
  z.object({action:z.literal('profiles-complete'),sync_id:uuid,details:z.record(z.unknown())}).strict(),
  z.object({action:z.literal('catalog'),archive,candidates:z.array(z.object({je_id:uuid,period_end:day,member_name:member}).strict()).max(10000)}).strict(),
  z.object({action:z.literal('upload'),sha256:sha}).strict(),
  z.object({action:z.literal('account'),je_id:uuid,document,allocations:z.array(allocation).max(20000),structure:z.record(z.unknown())}).strict(),
  z.object({action:z.literal('prepare'),parser_version:z.string().max(100)}).strict(),
  z.object({action:z.literal('quarantine'),je_id:uuid,archive_etag:z.string().max(200),reason:z.string().regex(/^[a-z0-9_]+$/).max(100),package_sha256:sha,parser_version:z.string().max(100)}).strict(),
  z.object({action:z.literal('log'),source_id:z.enum(['scb-afr-profiles','bolagsverket-annual-accounts']),
    status:z.enum(['succeeded','failed','no_change','waiting']),period:z.string().max(100),details:z.record(z.unknown()),error:z.string().max(1000).optional()}).strict(),
]);

async function db():Promise<SupabaseClient> {
  return (await import('@/integrations/supabase/client.server')).supabaseAdmin as unknown as SupabaseClient;
}
function checked<T>(result:{data:T;error:unknown}):T {
  if(result.error) throw new Error('Database operation failed');
  return result.data;
}

export async function handleCompanyData(request:Request):Promise<Response> {
  const denied=await authorize(request); if(denied) { denied.headers.set('cache-control','no-store'); return denied; }
  if(rate()) return json({error:'Too many requests'},429);
  try {
    const client=await db();
    if(request.method==='GET') {
      const url=new URL(request.url); const action=url.searchParams.get('action');
      if(action==='state') {
        const sync=checked(await client.from('afr_syncs').select('id,status,source_date,fetched_at,je_source_count,ae_source_count')
          .eq('status','succeeded').order('source_date',{ascending:false}).order('created_at',{ascending:false}).limit(1).maybeSingle());
        const releases=checked(await client.from('afr_profile_releases').select('sync_id,source_date').order('completed_at',{ascending:false}).limit(1).maybeSingle());
        return json({sync,profiles:releases},200);
      }
      if(action==='scope') {
        const after=url.searchParams.get('after'); if(after&&!uuid.safeParse(after).success) return json({error:'Invalid cursor'},400);
        return json(checked(await client.rpc('company_data_scope',{p_after:after,p_limit:1000})),200);
      }
      if(action==='archives') {
        // Fewer than 2,000 bulk objects currently; paginate nevertheless.
        const after=url.searchParams.get('after')??'';
        return json(checked(await client.from('company_account_archives').select('archive_key,etag,scope_hash').gt('archive_key',after).order('archive_key').limit(1000)),200);
      }
      if(action==='candidates') {
        const after=url.searchParams.get('after'); if(after&&!uuid.safeParse(after).success) return json({error:'Invalid cursor'},400);
        let query=client.from('company_account_candidates').select('*').eq('status','pending').order('je_id').limit(100);
        if(after) query=query.gt('je_id',after);
        const rows=checked(await query)??[];
        const identities=rows.length?(checked(await client.from('afr_je_ident').select('je_id,org_nr').in('je_id',rows.map(r=>r.je_id)))??[]):[];
        const orgs=new Map(identities.map(r=>[r.je_id,r.org_nr]));
        return json(rows.map(r=>({...r,org_nr:orgs.get(r.je_id)})),200);
      }
      if(action==='structure') {
        const id=url.searchParams.get('je_id'),end=url.searchParams.get('period_end');
        if(!uuid.safeParse(id).success||!day.safeParse(end).success) return json({error:'Invalid structure request'},400);
        return json(checked(await client.rpc('company_account_structure',{p_je_id:id,p_period_end:end})),200);
      }
      if(action==='package') {
        const id=url.searchParams.get('je_id');if(!uuid.safeParse(id).success)return json({error:'Invalid identity'},400);
        const row=checked(await client.from('company_account_candidates').select('package_sha256').eq('je_id',id).single());
        if(!row?.package_sha256)return json({error:'No package'},404);
        return json(checked(await client.storage.from('company-source-documents').createSignedUrl(`accounts/${row.package_sha256}.zip`,300)),200);
      }
      if(action==='coverage') return json(checked(await client.rpc('company_data_coverage')),200);
      return json({error:'Unknown action'},400);
    }
    if(request.method!=='POST') return json({error:'Method not allowed'},405);
    const raw=await request.text(); if(new TextEncoder().encode(raw).length>5_800_000) return json({error:'Payload too large'},413);
    const parsed=postSchema.safeParse(JSON.parse(raw)); if(!parsed.success) return json({error:'Invalid payload',issues:parsed.error.issues.map(i=>({path:i.path,message:i.message})).slice(0,10)},400);
    const p=parsed.data;
    if(p.action==='profile-hashes') {
      return json(checked(await client.rpc('afr_profile_hashes',{p_entity:p.entity,p_keys:p.keys})),200);
    }
    if(p.action==='profiles') return json(checked(await client.rpc('afr_profile_store',{p_sync_id:p.sync_id,p_entity:p.entity,p_records:p.records})),200);
    if(p.action==='profiles-complete') {
      const sync=checked(await client.from('afr_syncs').select('*').eq('id',p.sync_id).eq('status','succeeded').single());
      if(p.details['je_observed']!==sync.je_source_count||p.details['ae_observed']!==sync.ae_source_count||p.details['source_date']!==sync.source_date||p.details['has_more_false']!==true)
        return json({error:'Profile traversal proof mismatch'},409);
      checked(await client.from('afr_profile_releases').upsert({sync_id:p.sync_id,source_date:sync.source_date,details:p.details},{onConflict:'sync_id'}));
      return json({ok:true},200);
    }
    if(p.action==='catalog') return json(checked(await client.rpc('company_account_catalog',{p_archive:p.archive,p_candidates:p.candidates})),200);
    if(p.action==='upload') {
      const path=`accounts/${p.sha256}.zip`;
      const existing=await client.storage.from('company-source-documents').info(path);
      if(!existing.error) return json({exists:true,path},200);
      const data=checked(await client.storage.from('company-source-documents').createSignedUploadUrl(path));
      return json({path,signed_url:data!.signedUrl},200);
    }
    if(p.action==='account') {
      const bytes=checked(await client.storage.from('company-source-documents').download(p.document.storage_path));
      const {createHash}=await import('node:crypto');
      if(!bytes||bytes.size>40_000_000||createHash('sha256').update(new Uint8Array(await bytes.arrayBuffer())).digest('hex')!==p.document.package_sha256)
        return json({error:'Archived source checksum mismatch'},409);
      return json(checked(await client.rpc('company_account_store',{p_je_id:p.je_id,p_document:p.document,p_allocations:p.allocations,p_structure:p.structure})),200);
    }
    if(p.action==='prepare') return json(checked(await client.rpc('company_accounts_prepare',{p_parser_version:p.parser_version})),200);
    if(p.action==='quarantine') {
      checked(await client.from('company_account_candidates').update({status:'quarantined',error_code:p.reason,package_sha256:p.package_sha256,checked_parser_version:p.parser_version,checked_at:new Date().toISOString()})
        .eq('je_id',p.je_id).eq('archive_etag',p.archive_etag));
      return json({ok:true},200);
    }
    if(p.action==='log') {
      const now=new Date().toISOString(); const succeeded=p.status==='succeeded'||p.status==='no_change';
      checked(await client.from('data_source_runs').insert({source:p.source_id,source_id:p.source_id,
        status:p.status==='waiting'?'started':p.status,started_at:now,finished_at:now,source_period:p.period,details:p.details,error_message:p.error??null}));
      checked(await client.from('data_source_state').upsert({source_id:p.source_id,last_checked_at:now,last_status:p.status,
        latest_available_period:p.period,...(succeeded?{latest_successful_period:p.period,last_successful_at:now}:{}),
        details:p.details,last_error:p.error??null,updated_at:now},{onConflict:'source_id'}));
      return json({ok:true},200);
    }
    return json({error:'Unknown action'},400);
  } catch(error) {
    // Do not log raw records, contact values, upload tokens, or source documents.
    console.error('[company-data]',error instanceof Error?error.name:'Error');
    return json({error:'Company data operation failed'},422);
  }
}

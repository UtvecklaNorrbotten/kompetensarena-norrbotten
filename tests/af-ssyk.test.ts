import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {afSsykCategory} from '../src/lib/af-ssyk.ts';
import {demandSeries,sumDemand,type DemandModel} from '../src/lib/labour-demand.ts';
// Synthetic boundary cases: military, unknown and multiple AF fields for one SSYK.
assert.equal(afSsykCategory('9999','four'),'other:unknown');
assert.equal(afSsykCategory('0110','nine'),'other:military');
assert.equal(afSsykCategory('unknown','four'),'other:unknown');
const model:DemandModel={totals:[],fields:[],groups:[['2025-01','A','2221','Ja',2],['2025-01','B','2221','Nej',3],['2025-01','A','9999','Nej',7]]};
const s={field:'',group:'four:2-3',metric:'remaining' as const,duration:'source' as const};
assert.equal(demandSeries(model,s)[0]!.value,5);
assert.equal(demandSeries(model,{...s,field:'A'})[0]!.value,2);
assert.equal(demandSeries(model,{...s,group:'four:9'})[0]!.value,null);
assert.equal(demandSeries({...model,groups:[['2025-01','A','2221','Nej','<5']]},s)[0]!.value,'<5');
// Every geography and month: both complete partitions must reconcile to original KVAR rows.
let checks=0;
for(const file of readdirSync(new URL('../public/data/demand/',import.meta.url))){
 const encoded=JSON.parse(readFileSync(new URL('../public/data/demand/'+file,import.meta.url),'utf8'));
 const m:DemandModel=JSON.parse(gunzipSync(Buffer.from(encoded.gzip,'base64')).toString());
 const raw=new Map<string,any[]>();const partitions={four:new Map<string,Map<string,any[]>>(),nine:new Map<string,Map<string,any[]>>()};
 for(const [p,,code,,v] of m.groups??[]){raw.set(p,[...(raw.get(p)??[]),v]);for(const level of ['four','nine'] as const){if(!partitions[level].has(p))partitions[level].set(p,new Map());const b=partitions[level].get(p)!;const c=afSsykCategory(code,level);b.set(c,[...(b.get(c)??[]),v]);}}
 for(const [p,values] of raw)for(const level of ['four','nine'] as const){assert.equal(sumDemand([...partitions[level].get(p)!.values()].map(sumDemand)),sumDemand(values),file+' '+p+' '+level);checks++;}
}
console.log('Verified AF SSYK partitions:',checks);

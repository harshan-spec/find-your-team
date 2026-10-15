import{readFileSync,readdirSync,existsSync}from'node:fs';
import assert from'node:assert/strict';
import{randomUUID,randomBytes}from'node:crypto';
process.loadEnvFile('.env.local');
let passed=0;
function check(name,fn){fn();passed++;console.log('PASS '+name)}
const files=readdirSync('dist').filter(f=>f.endsWith('.html'));
for(const file of files){const html=readFileSync('dist/'+file,'utf8');check(file+' metadata and usable content',()=>{assert.match(html,/<html lang="en">/);assert.match(html,/<title>[^<]+/);assert.match(html,/<meta name="description"/);assert.match(html,/<h1>/);assert.match(html,/<meta name="google-adsense-account" content="ca-pub-2851684575995607"/);assert.doesNotMatch(html,/adsbygoogle|lorem ipsum/i)});for(const match of html.matchAll(/(?:href|src)="(\/[^"?#]*)/g)){check(file+' local asset '+match[1],()=>assert.ok(existsSync('dist'+(match[1]==='/'?'/index.html':match[1]))))}}
check('sitemap and robots',()=>{assert.ok(existsSync('dist/robots.txt'));assert.match(readFileSync('dist/sitemap.xml','utf8'),/findyourteam-ten.vercel.app/)});
const url=process.env.VITE_SUPABASE_URL,key=process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
async function request(path,body,method=body?'POST':'GET'){const r=await fetch(url+'/rest/v1/'+path,{method,headers:{apikey:key,'Content-Type':'application/json',Prefer:'return=representation'},...(body?{body:JSON.stringify(body)}:{})});return{status:r.status,data:await r.text()}}
let r=await request('team_posts?select=id,status&limit=1');check('anonymous browsing succeeds',()=>assert.equal(r.status,200));
const id=randomUUID(),secret=randomBytes(32).toString('hex');const payload={title:'Verification fixture — automatically removed',event_name:'Private quality assurance',type:'Hackathon',description:'Temporary automated verification of recruitment publishing, filtering and owner authorization. Removed immediately after the check.',skills:['Testing'],year:'2nd year',department:'CSE',gender:'Both / everyone',mode:'Online',location:'Online',college:'Quality assurance',seats:2,deadline:'2099-10-15',event_url:'https://example.com/event',name:'Verification',email:'qa@example.com'};
const rpc=(action,data=payload,token=secret)=>request('rpc/team_write',{p_id:id,p_key:token,p_data:data,p_action:action});
try{
r=await request('team_posts',{id,...payload});check('direct anonymous insert denied',()=>assert.ok(r.status>=400));
r=await rpc('create');check('capability post creation succeeds',()=>assert.equal(r.status,200,r.data));
r=await request('team_posts?id=eq.'+id);check('created post readable; no management key exposed',()=>{assert.equal(r.status,200);assert.equal(JSON.parse(r.data)[0].id,id);assert.doesNotMatch(r.data,/key_hash|management_key/)});
r=await rpc('edit',{...payload,title:'Unauthorized change'},randomBytes(32).toString('hex'));check('wrong key cannot edit',()=>assert.ok(r.status>=400));
r=await request('team_posts?id=eq.'+id,{title:'Unauthorized direct update'},'PATCH');check('direct anonymous update denied',()=>assert.ok(r.status>=400));
r=await rpc('edit',{...payload,event_url:'javascript:alert(1)'});check('unsafe event link rejected by database',()=>assert.ok(r.status>=400));
r=await rpc('edit',{...payload,seats:0});check('invalid open spots rejected by database',()=>assert.ok(r.status>=400));
r=await rpc('edit',{...payload,deadline:'2000-01-01'});check('past deadline rejected by database',()=>assert.ok(r.status>=400));
r=await rpc('edit',{...payload,title:'Verified updated opportunity'});check('correct key can edit',()=>assert.equal(r.status,200,r.data));
r=await rpc('close',{});check('owner can mark team filled',()=>assert.equal(r.status,200,r.data));
r=await request('team_posts?id=eq.'+id+'&status=eq.open');check('filled team excluded by open filter',()=>assert.deepEqual(JSON.parse(r.data),[]));
r=await rpc('reopen',{});check('owner can reopen',()=>assert.equal(r.status,200,r.data));
r=await request('rpc/team_report',{p_post:id,p_reason:'Automated verification report, fixture will be removed.'});check('private report submission succeeds',()=>assert.equal(r.status,204,r.data));
r=await request('reports');check('moderation reports are not publicly readable',()=>assert.ok(r.status>=400));
r=await rpc('delete',{},randomBytes(32).toString('hex'));check('wrong key cannot delete',()=>assert.ok(r.status>=400));
}finally{r=await rpc('delete',{});check('fixture removed using owner capability',()=>assert.equal(r.status,200,r.data));r=await request('team_posts?id=eq.'+id);check('deleted fixture is absent',()=>assert.deepEqual(JSON.parse(r.data),[]));}
console.log(`${passed} checks passed.`);

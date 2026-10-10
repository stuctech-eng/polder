const { Client } = require("pg");
let pool; const cfg = global.__cfg = global.__cfg || { uploads: [] };
async function db(){ if(!pool){ pool=new Client({host:process.env.PGHOST||"/home/pgtest",port:+(process.env.PGPORT||55432),database:process.env.TESTDB||"s3",user:process.env.PGUSER||"pgtest"}); await pool.connect(); } return pool; }
async function runAs(role, sub, sql, params){
  const c = await db();
  await c.query("begin");
  try{
    await c.query(`set local role ${role}`);
    await c.query("select set_config('request.jwt.claims',$1,true), set_config('request.jwt.claim.sub',$2,true)",[JSON.stringify({role, sub}), sub||""]);
    const r = await c.query(sql, params); await c.query("commit"); return {rows:r.rows, rowCount:r.rowCount};
  }catch(e){ await c.query("rollback"); return {error:{message:e.message, code:e.code}}; }
}
const REL = {
  receipts: { open_tabs:{one:true,fk:"open_tab_id"}, receipt_lines:{fk:"receipt_id"}, approvals:{fk:"receipt_id"} },
  open_tabs: { companies:{one:true,fk:"company_id"}, departments:{one:true,fk:"department_id"}, cost_centers:{one:true,fk:"cost_center_id"}, projects:{one:true,fk:"project_id"} },
  daily_closings: { users:{one:true,fk:"closed_by"} },
};
function splitTop(s){ const out=[]; let d=0,cur=""; for(const ch of s){ if(ch==="(")d++; if(ch===")")d--; if(ch===","&&d===0){out.push(cur.trim());cur="";} else cur+=ch; } if(cur.trim())out.push(cur.trim()); return out; }
function builder(role, sub, table){
  const q={op:"select",cols:"*",conds:[],ret:false,head:false,order:null};
  const b={
    select(cols,opt){ if(q.op==="select"){q.cols=cols||"*"; q.head=!!opt?.head;} else {q.ret=true; q.cols=cols||"*";} return b; },
    insert(d){ q.op="insert"; q.data=d; return b; }, update(d){ q.op="update"; q.data=d; return b; }, delete(){ q.op="delete"; return b; },
    eq(c,v){ q.conds.push((P)=>{P.push(v);return `"${c}"=$${P.length}`}); return b; },
    in(c,arr){ q.conds.push((P)=>{P.push(arr);return `"${c}" = any($${P.length})`}); return b; },
    gte(c,v){ q.conds.push((P)=>{P.push(v);return `"${c}">=$${P.length}`}); return b; },
    lte(c,v){ q.conds.push((P)=>{P.push(v);return `"${c}"<=$${P.length}`}); return b; },
    not(c,op,v){ q.conds.push((P)=>{ if(op==="is") return `"${c}" is not null`; P.push(v); return `"${c}"<>$${P.length}`; }); return b; },
    order(c,o){ q.order=`"${c}" ${o&&o.ascending===false?"desc":"asc"}`; return b; },
    limit(n){ q.limit=+n; return b; },
    maybeSingle(){ q.single="maybe"; return b; }, single(){ q.single="one"; return b; },
    then(res,rej){ return exec().then(res,rej); },
  };
  async function exec(){
    // cfg.writeFault = "<tabel>": elke insert/update/delete op die tabel geeft een fout (zichtbaarheid van schrijffouten)
    if(cfg.writeFault===table && q.op!=="select") return {data:null,error:{message:"boom"},count:null};
    if(cfg.fault && cfg.fault.table===table && q.op==="select"){ if(cfg.fault.mode==="throw") throw new Error("boom"); return {data:null,error:{message:"boom"},count:null}; }
    const P=[]; const w=q.conds.map(f=>f(P)).join(" and ");
    const toks=splitTop(q.cols); const embeds=[]; const base=[];
    for(const t of toks){ const m=t.match(/^(\w+)\((.*)\)$/s); if(m&&REL[table]&&REL[table][m[1]]) embeds.push([m[1],m[2]]); else base.push(t); }
    const cols = (embeds.length||!base.length)?"*":base.join(",");
    let sql;
    if(q.op==="select") sql = q.head? `select count(*)::int as n from public.${table}${w?" where "+w:""}` : `select ${cols} from public.${table}${w?" where "+w:""}${q.order?" order by "+q.order:""}${q.limit?" limit "+q.limit:""}`;
    if(q.op==="insert"){ const rows=Array.isArray(q.data)?q.data:[q.data]; const ks=Object.keys(rows[0]);
      const vals=rows.map(r=>"("+ks.map(k=>{P.push(typeof r[k]==="object"&&r[k]!==null?JSON.stringify(r[k]):r[k]);return "$"+P.length}).join(",")+")").join(",");
      sql=`insert into public.${table} (${ks.map(k=>`"${k}"`).join(",")}) values ${vals}${q.ret?" returning "+(base.length?base.join(","):"*"):""}`; }
    if(q.op==="update"){ const ks=Object.keys(q.data); const base0=P.length; const set=ks.map((k,i)=>`"${k}"=$${base0+i+1}`).join(","); ks.forEach(k=>P.push(q.data[k]));
      sql=`update public.${table} set ${set} where ${w}${q.ret?" returning "+(base.length?base.join(","):"*"):""}`; }
    if(q.op==="delete") sql=`delete from public.${table} where ${w}${q.ret?" returning *":""}`;
    // update: de where-parameters komen eerst in P; params van set staan erna -> herbouw volgorde
    const r=await runAs(role,sub,sql,P);
    if(r.error) return {data:null,error:r.error,count:null};
    if(q.op==="select"&&q.head) return {data:null,error:null,count:r.rows[0].n};
    let rows=r.rows;
    if(q.op==="select"&&embeds.length){
      for(const row of rows){
        for(const [name,sub2] of embeds){
          const rel=REL[table][name]; const subCols=sub2.trim()||"*";
          if(rel.one){ if(row[rel.fk]==null){row[name]=null;continue;}
            const rr=await runAs(role,sub,`select ${subCols} from public.${name} where id=$1`,[row[rel.fk]]); row[name]=rr.rows[0]??null; }
          else { const rr=await runAs(role,sub,`select ${subCols} from public.${name} where ${rel.fk}=$1`,[row.id]); row[name]=rr.rows; }
        }
      }
    }
    let data=rows; if(q.single==="maybe") data=data[0]??null; else if(q.single==="one"){ if(data.length!==1) return {data:null,error:{message:"JSON object requested, multiple (or no) rows returned"}}; data=data[0]; }
    if((q.op==="insert"||q.op==="update")&&!q.ret) data=null;
    return {data,error:null};
  }
  return b;
}
function createClient(url,key,opts){ cfg.clients=(cfg.clients||[]).concat([{key,opts}]);
  const role = key==="service"?"service_role":"authenticated"; const sub = key.startsWith("user:")?key.slice(5):null;
  return { from:t=>builder(role,sub,t),
    // rpc: roept public.<fn>() aan als deze gebruiker; cfg.rpcFault = "<fn>" geeft een fout terug (fail-closed-test)
    // met argumenten: rpc(fn, { p_a: 1, p_b: 2 }) -> select public.fn(p_a => $1, p_b => $2)
    rpc: async (fn,args)=>{ if(cfg.rpcFault===fn) return {data:null,error:{message:"boom"}};
      const ks=Object.keys(args||{}); const named=ks.map((k,i)=>`${k} => $${i+1}`).join(", ");
      const r=await runAs(role,sub,`select public.${fn}(${named}) as v`,ks.map(k=>args[k])); return r.error?{data:null,error:r.error}:{data:r.rows[0].v,error:null}; },
    auth:{ getUser: async ()=>({ data:{ user: sub?{id:sub}:null }, error:null }),
      // verifyOtp: token_hash "geldig-<type>" is geldig voor dat type, al het andere is ongeldig/verlopen (zoals Supabase)
      // resetPasswordForEmail: legt de aanvraag vast; cfg.resetFault = "<melding>" geeft een fout zoals Supabase (bijv. wachttijd)
      resetPasswordForEmail: async (email, o)=>{ cfg.resets=(cfg.resets||[]).concat([{email, redirectTo:o&&o.redirectTo, key, flowType:opts&&opts.auth&&opts.auth.flowType}]);
        return cfg.resetFault?{data:null,error:{message:cfg.resetFault}}:{data:{},error:null}; },
      verifyOtp: async ({type, token_hash})=>{ cfg.verifyCalls=(cfg.verifyCalls||[]).concat([{type,token_hash}]);
        return token_hash===`geldig-${type}` ? {data:{user:{id:"u"},session:{}},error:null} : {data:{user:null,session:null},error:{message:"Email link is invalid or has expired",code:"otp_expired"}}; },
      // admin-API (alleen met de service-sleutel); schrijft rechtstreeks in auth.users zoals Supabase Auth dat doet
      admin: role!=="service_role" ? undefined : {
        getUserById: async (id)=>{ const c=await db(); const r=await c.query("select id, email, created_at from auth.users where id=$1",[id]);
          return r.rows[0]?{data:{user:r.rows[0]},error:null}:{data:{user:null},error:{message:"User not found"}}; },
        inviteUserByEmail: async (email)=>{ const c=await db(); const e=await c.query("select 1 from auth.users where email=$1",[email]);
          if(e.rowCount) return {data:null,error:{message:"A user with this email address has already been registered",code:"email_exists"}};
          const r=await c.query("insert into auth.users (instance_id,id,aud,role,email,created_at,updated_at) values ('00000000-0000-0000-0000-000000000000',gen_random_uuid(),'authenticated','authenticated',$1,now(),now()) returning id, email, created_at",[email]);
          cfg.invites=(cfg.invites||[]).concat(email); return {data:{user:r.rows[0]},error:null}; },
        deleteUser: async (id)=>{ const c=await db(); await c.query("delete from auth.users where id=$1",[id]); return {error:null}; },
      } },
    storage:{ from:(bucket)=>({ upload: async (path,bytes,opt)=>{ cfg.uploads.push({bucket,path,opt}); return {error:null}; } }) } };
}
module.exports={createClient, cfg, end:async()=>pool&&pool.end()};

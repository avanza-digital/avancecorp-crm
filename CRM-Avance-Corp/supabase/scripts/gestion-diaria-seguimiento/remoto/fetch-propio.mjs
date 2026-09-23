// Solo red propia del banco autorizado; no altera respuestas ni relojes.
import assert from 'node:assert/strict';
const original=globalThis.fetch;
globalThis.fetch=(input,opciones={})=>{
 const u=new URL(input instanceof Request?input.url:input);
 assert.equal(u.origin,'https://zviwoyvtccqhhdfqdang.supabase.co');
 assert.ok(!u.username&&!u.password);
 return original(input,{...opciones,redirect:'error'});
};

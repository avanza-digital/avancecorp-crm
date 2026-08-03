# supabase/functions/ — Edge Functions del CRM

Fuentes versionadas actualmente:

- `crm-agenda-ics` — feed público por bearer token; `verify_jwt=false` porque
  Google Calendar no envía JWT. La función valida el token mediante una RPC
  service-role-only y responde 404 uniforme cuando no autoriza.
- `crm-importar-leads` — ingreso por lotes desde la hoja comercial. Su copia
  operativa histórica vive también en
  `../../_supabase_functions/functions/crm-importar-leads/index.ts`; ambas deben
  permanecer byte a byte idénticas (`cmp -s`) hasta retirar ese espejo.
- `crm-tipo-cambio` — consulta del tipo de cambio usado por el CRM.

Regla dura: **toda función desplegada del CRM tiene su fuente versionada aquí**
(prohibido el drift tipo `intake-lead`/`diagnostico-push`). `service_role` jamás
sale de las Functions. Cuando exista un espejo legado, el gate debe comprobar
igualdad exacta antes del despliegue.

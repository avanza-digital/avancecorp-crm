# supabase/functions/ — Edge Functions del CRM

Fuentes versionadas actualmente:

- `crm-agenda-ics` — feed público por bearer token; `verify_jwt=false` porque
  Google Calendar no envía JWT. La función valida el token mediante una RPC
  service-role-only y responde 404 uniforme cuando no autoriza.
- `crm-importar-leads` — ingreso por lotes desde la hoja comercial. Su copia
  operativa histórica vive también en
  `../../../_supabase_functions/functions/crm-importar-leads/`. Mientras ese
  espejo exista, `index.ts` y `destinos.ts` deben permanecer byte a byte
  idénticos (`cmp -s`) en ambas ubicaciones.
- `crm-tipo-cambio` — consulta del tipo de cambio usado por el CRM.
- `crm-usuarios` — alta de candidatos CRM y envío de recuperación. Se despliega
  con `verify_jwt=true`: valida la sesión humana antes de usar Auth Admin y
  limita cada acción a Gerencia CRM activa. El navegador nunca puede enviar
  rol, estado, supervisor ni contraseña. `CRM_ALLOWED_ORIGINS` admite una lista
  CSV adicional de orígenes HTTPS (o HTTP solo para `localhost`/`127.0.0.1`);
  los orígenes productivos del CRM permanecen siempre permitidos y `*` se
  rechaza. `CRM_PASSWORD_RESET_REDIRECT_URL` configura el destino de la
  recuperación; ningún secreto ni `service_role` se devuelve o registra.

Regla dura: **toda función desplegada del CRM tiene su fuente versionada aquí**
(prohibido el drift tipo `intake-lead`/`diagnostico-push`). `service_role` jamás
sale de las Functions. Cuando exista un espejo legado, el gate debe comprobar
igualdad exacta antes del despliegue.

# supabase/functions/ — Edge Functions del CRM

Fuentes versionadas actualmente:

- `crm-agenda-ics` — feed público por bearer token; `verify_jwt=false` porque
  Google Calendar no envía JWT. La función valida el token mediante una RPC
  service-role-only y responde 404 uniforme cuando no autoriza.
- `crm-importar-leads` — ingreso por lotes desde la hoja comercial. Su copia
  operativa histórica vive también en
  `../../../_supabase_functions/functions/crm-importar-leads/`. Mientras ese
  espejo exista, `index.ts`, `destinos.ts` y `resultado-importacion.ts` deben
  permanecer byte a byte idénticos (`cmp -s`) en ambas ubicaciones.
- `crm-llamadas-ingesta` — recibe de la macro del celular corporativo el aviso de cada
  llamada y su latido de salud (plan «Llamadas desde el celular», F3-b; **en rama, sin
  desplegar**). `verify_jwt=false` porque la macro no tiene JWT: el control es la clave
  del celular en la cabecera `x-celular-credencial` (nunca en la URL), validada contra su
  sha256 por dos RPC solo de `service_role` (`crm.ingerir_llamada_celular_servicio` y
  `crm.registrar_salud_celular_servicio`). Contrato de `20261005143843`: la Edge solo revisa
  el transporte (405, 415, 401 por clave sin forma, 413 por más de 4 KB) y todo lo demás llega
  a la base, también el JSON mal formado (gasta cupo); la base devuelve `{resultado, mensaje}`
  y la Edge responde 202/200 (aceptado), 400 (inválido, con el mensaje), 401 uniforme, 429 con
  `Retry-After` o 503. Sin 409. La misma respuesta para una llamada guardada, repetida o
  ignorada. Sin espejo legado. Pruebas:
  `npm run test:llamadas-ingesta` y `npm run test:llamadas-ingesta:mutantes` (Deno 2.x).
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

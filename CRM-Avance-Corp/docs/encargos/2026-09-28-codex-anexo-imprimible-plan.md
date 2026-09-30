ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia (fragmento citado de este encargo), TEST GAPS, REGRESSION RISKS,
RECOMMENDED NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia; marca como hipótesis lo no
demostrado. Omite secciones vacías.

# Encargo: REFUTAR el PLAN v3 «anexo de cronograma IMPRIMIBLE, documento aparte del contrato» — LEVEL 3

Contexto: ya refutaste el plan v2 (casilla al crear + columna + plantilla v10). Miguel lo descartó:
«todo sigue igual, solo que el añadido es que el analista ahora puede imprimir este anexo». El contrato
PDF no cambia. Todavía no hay SQL ni código nuevo escrito (salvo un borrador del anexo pegado al contrato
en la edge, que el plan REVIERTE).

Intenta tumbar: la autorización de la función nueva (¿fuga entre carteras, roles, anon, lector global,
contrato en eliminación, contrato sin PDF, contrato con varias revisiones?), la entrega binaria por la
edge (CORS, `functions.invoke` y `Content-Type`, tamaño, cabeceras), el determinismo prometido, la ausencia
de sellado/bitácora del anexo (¿riesgo legal u operativo real?), la reutilización de helpers de la plantilla
v9 sin alterar sus bytes, el orden de publicación, y lo que el plan NO cubre. Si crees que el anexo debería
guardarse y sellarse como el contrato, argumenta con evidencia y costo.

# Plan técnico v3: anexo de cronograma IMPRIMIBLE, documento aparte del contrato

Fecha: 2026-09-28. PRIMARY: Claude. Nivel: LEVEL 3 (función nueva con autorización + acción nueva en la
edge que entrega datos del contrato sellado). Sustituye al plan v2 (casilla + columna + plantilla v10),
descartado por Miguel: «todo sigue igual, solo que el añadido es que el analista ahora puede imprimir
este anexo».

## Objetivo
El contrato PDF NO cambia (sigue en `contrato-aep-17-v9`, mismos bytes). El analista, desde la ficha
del contrato, pulsa «Imprimir anexo de cronograma» y obtiene un PDF aparte (modelo «Propuesta de Anexo
para contrato de AEP») con los datos CONGELADOS del contrato sellado. No se guarda ni se sella: se
genera a demanda y es determinista (mismo snapshot ⇒ mismos bytes).

## Hechos en los que se apoya (verificados 28/09)
- El snapshot sellado vive en `private.contrato_pdfs.snapshot` (copiado desde el job en `finalizar`,
  comparado en `estado_base`), con `contrato` (13 claves: incluye modalidad y tipoInteres), `titular`,
  `analista`, `cotitulares`, `cronograma[]` (numeroCuota, fechaProgramada, montoProgramado, tipo) y
  `cuentaPago`. Solo `contrato_pdf_reclamar` (service_role) devuelve hoy un snapshot, y es el del JOB.
- Contrato, cronograma y titulares quedan congelados por trigger en cuanto existe un job o PDF.
- Autorización de lectura del PDF: `private.puede_leer_contrato_pdf_como(contrato_id, actor_id)`
  (cartera del cliente P04 o, con D2, quien cerró la venta y su cadena mientras el cliente siga activo).
  `crm.contrato_pdf_estado_fn(uuid)` (authenticated) la aplica con `auth.uid()`.
- La edge `crm-contrato-pdf-v2` acepta cuerpo exacto `{action, contratoId}` con `action ∈ {ensure,
  status, delete, delete-audited}`, sesión Bearer, JSON ≤ 2 KB; usa `actor.rpc` (como el usuario) y
  `deps.rpcAdmin` (service_role, con `p_actor_id`). Firma URLs de 300 s tras verificar hash y bytes.
- La firma impresa de Avance Corp y el fondo son assets de la edge, verificados por SHA-256; no existen
  en el front (la demo del front no tiene firma real). Por eso el anexo se dibuja en la edge.
- El front llama con `functions.invoke('crm-contrato-pdf-v2', {action, contratoId})`; supabase-js
  convierte la respuesta según `Content-Type` (`application/json` → json, `application/octet-stream` →
  Blob; otros tipos → texto).
- No hay espejo de esta edge en `_supabase_functions/functions/` (no aplica la regla byte a byte).

## Diseño

### D1. Servidor: una función de lectura del snapshot sellado
`crm.contrato_pdf_snapshot_sellado(p_contrato_id uuid, p_actor_id uuid) returns jsonb`
- security definer, `set search_path = ''`, `revoke all`, `grant execute to service_role` (patrón de
  `contrato_pdf_reclamar`). Comentario `COMMENT ON`.
- Exige `p_actor_id` no nulo y `private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id)`; si no,
  `insufficient_privilege` «Contrato no encontrado o fuera de tu cartera» (mismo mensaje que el resto,
  sin filtrar existencia).
- Si el contrato está en eliminación → 55000 (como el resto).
- Lee `private.contrato_pdfs` (la revisión más alta) y devuelve `{contrato_id, revision, template_version,
  snapshot, generado_en}`. Sin PDF sellado → `P0002` con hint `ANEXO_SIN_PDF_SELLADO` (el front lo traduce
  a «Primero genera el contrato PDF»).
- Solo lectura: sin escrituras, sin bitácora nueva (la descarga del contrato tampoco la tiene). No toca
  `public`, ni firmas existentes, ni huellas F7/venta cruzada (no se modifica ninguna función viva).
- Registrador `scripts/registrar-<ts>.sql`; reversa = `drop function`.
- Migración `AAAAMMDDHHMMSS_crm_contrato_pdf_snapshot_sellado.sql` con preflight (función inexistente,
  `puede_leer_contrato_pdf_como` presente con la firma esperada) y postflight (prosecdef, search_path,
  ACL exacta `{postgres=X/postgres,service_role=X/postgres}`, comentario).

### D2. Edge: acción `anexo`
- `handler.ts`: `action` admite `anexo`. Flujo: sesión Bearer → `deps.rpcAdmin('contrato_pdf_snapshot_sellado',
  {p_contrato_id, p_actor_id})` → `validarSnapshotContratoV2(snapshot)` (el mismo validador estricto) →
  `renderizarAnexoPdfV1(snapshot, generado_en)` → respuesta `200` `Content-Type: application/octet-stream`,
  cabeceras `Content-Disposition: inline; filename="Anexo-<numero>-<NOMBRE>.pdf"`, `X-Document-Sha256`,
  `X-Anexo-Template: anexo-cronograma-v1`, `Cache-Control: private, no-store`. Errores en JSON con código
  (`ANEXO_SIN_PDF_SELLADO` 409, permisos 403, snapshot inválido 502).
- Determinismo: `info.CreationDate/ModDate` fijadas con `generado_en` del PDF sellado ⇒ mismos bytes en
  cada impresión; `X-Document-Sha256` lo acredita.
- `renderer.ts`: `renderizarAnexoPdfV1` reutiliza PdfPrinter, fuentes, `verificarRecursos()` e imágenes.
- Plantilla nueva `anexo-v1.ts` (`ANEXO_TEMPLATE_VERSION = "anexo-cronograma-v1"`): `AnexoPdfDatos` y
  `construirAnexoPdf(datos, assets)`. Reutiliza helpers de `template-v2.ts` SOLO exportándolos (`fechaPartes`,
  `montoVisible`, `etiquetaDocumento`, `documentoDe`, `parrafo`, `tituloClausula`, `bloqueFirmas`, `TIPOGRAFIA`,
  fondo/cabecera/pie): exportar no cambia los bytes del contrato. Se REVIERTE en `template-v2.ts` lo que hoy
  hay sin commit (anexo pegado siempre, `cronograma`/`modalidad`/`tipoInteres` en `ContratoPdfDatos`) y en
  `renderer.ts` (`datosDocumento`): el contrato vuelve a ser byte-idéntico a la v9 y los 8 tests que fallan
  vuelven a pasar sin tocarlos.
- Contenido del anexo (decisiones por defecto, corregibles sobre la muestra): datos del contrato (número,
  inicio, vencimiento, contribución, modalidad, analista); parciales = filas `tipo = 'cuota'` (# / fecha /
  participación); liquidación final: fila «Restitución de la contribución» con fecha = `fechaVencimiento` y
  monto = capital, precedida, si existe fila `devolucion` (compuesto), de «Participación en utilidades» con su
  fecha y monto; compuesto: tabla de parciales con la fila «No se programan liquidaciones parciales» y
  modalidad «Única, al vencimiento del contrato»; textos de naturaleza y prevalencia; cierre «en la misma fecha
  de celebración»; bloque de firmas con co-titulares. Cabecera con el número de contrato, pie «n / total».
- Tests Deno: goldens del anexo (simple mensual, compuesto, mancomunado; hash y tamaño), snapshot sin fila
  `retorno` (no debe ocurrir; se acepta con capital/vencimiento), 60 cuotas (paginación con cabecera repetida),
  handler `anexo`: sin sesión 401, cuerpo inválido 400, `P0002` → 409 `ANEXO_SIN_PDF_SELLADO`, permisos → 403,
  snapshot inválido → 502, ok → octet-stream con sha256 y nombre. `_render-muestra.ts --anexo` genera la muestra
  del anexo con el snapshot ficticio (flags `--modalidad`, `--compuesto`, `--anios`, `--cotitulares`).
- Verificación previa al deploy: contrastar los módulos vivos con el árbol por la API de gestión (no con
  `functions download`, que transpila).

### D3. Front
- `contrato-pdf-archivo.ts`: `imprimirAnexoCronograma(contratoId)` → `functions.invoke(..., {action:'anexo',
  contratoId})` → Blob → verifica `X-Document-Sha256` contra el blob → `window.open(URL.createObjectURL(blob))`
  (pestaña nueva; desde ahí imprime o guarda). Errores: `ANEXO_SIN_PDF_SELLADO` → toast «Primero genera el
  contrato PDF»; 403 → «Contrato fuera de tu cartera».
- `contrato-detalle.tsx`: botón «Imprimir anexo de cronograma» junto a «Ver/Descargar contrato PDF», misma
  regla de visibilidad (régimen nuevo o con PDF), estado de carga y toast. Sin cambios en `crm-api.ts` ni en
  los tipos generados (`database.types.ts` sí cambia por la función nueva: `npm run gen:types`).
- Modo demo (solo desarrollo): el botón no se muestra (evita una tercera plantilla en el front). Diferido.
- Pruebas: Vitest del componente (botón visible/oculto, llamada, toasts) y del cliente (blob + sha256); e2e en
  Docker con el mock de la edge devolviendo un PDF pequeño; revisor-a11y sobre el botón.

### D4. Publicación (con el `!` de Miguel; sin ventana de 409 porque la versión del contrato no cambia)
1. Migración `db query --linked --file` + registrador (la función sola no hace nada visible).
2. Edge `npx supabase@2.114.0 functions deploy crm-contrato-pdf-v2 --project-ref … --use-api` DESDE
   `CRM-Avance-Corp/` (ventana muerta; la acción nueva no afecta a `ensure/status/delete`; los 9 módulos vivos
   contrastados antes).
3. Front `/release-crm` con preflight.
4. Verificación en prod, sin escrituras: función con ACL exacta; estado de un contrato sellado sigue OK; Miguel
   imprime el anexo de un contrato real (es solo lectura) y compara con la muestra.
5. Mismo día: commit en `main` antes de construir, push `avancecorp main`, PR de integración, vault, memoria.

## Decisiones tomadas por defecto (Miguel corrige sobre la muestra)
- Fecha de liquidación final = vencimiento; compuesto = dos filas finales sin parciales.
- Solo contratos con PDF sellado (régimen nuevo, desde el 19/08). Los del régimen anterior no tienen
  snapshot congelado; si Miguel los quiere, sería otro paso (leer tablas no congeladas).
- No se guarda ni se sella: determinista sobre datos congelados. Si algún día hace falta acta de impresión,
  se añade bitácora (quién/cuándo) sin cambiar el documento.
- Solo en el CRM; el portal admin (que también llama `ensure/delete`) no recibe el botón.
- Montos fijos en «Participación» frente a la cláusula 3.9: abogado; el anexo ya se cubre con «Naturaleza»
  y «Prevalencia».

## Qué NO cambia
El contrato PDF (v9, mismos bytes), su snapshot, sus tablas y triggers, las RPC de alta/corrección, las huellas
F7 y de venta cruzada, el cronograma, el portal del cliente, los PDF sellados.

## Riesgos conocidos
- Un contrato corregido tiene varias revisiones: el anexo usa la revisión más alta sellada (la vigente).
- Si el sellado está en curso (job pendiente), el anexo responde `ANEXO_SIN_PDF_SELLADO`; el front ya ofrece
  «Ver contrato PDF» que lo sella.
- La respuesta binaria por `functions.invoke` depende del `Content-Type` (`application/octet-stream` → Blob).
  Se prueba en e2e y en el humo de producción.

## EVIDENCIA TRANSCRITA (cuerpos VIVOS según la última migración que los define)

### private.contrato_pdfs — 20260818014534:319-345 (más job_id y revision añadidas después)
```sql
create table if not exists private.contrato_pdfs (
  id uuid primary key default gen_random_uuid(),
  contrato_id uuid not null references public.contratos(id) on delete restrict,
  job_id uuid,
  storage_bucket text not null default 'contratos-generados',
  storage_path text not null,
  nombre_archivo text not null,
  sha256 text not null,
  bytes bigint not null,
  template_version text not null,
  snapshot jsonb not null,
  generado_por uuid not null references public.perfiles(id) on delete restrict,
  generado_en timestamptz not null default statement_timestamp(),
  constraint contrato_pdfs_unico_por_contrato unique (contrato_id),
  constraint contrato_pdfs_ruta_unica unique (storage_bucket, storage_path)
);

alter table private.contrato_pdfs
  add column if not exists job_id uuid;

alter table private.contrato_pdfs
  drop constraint if exists contrato_pdfs_ruta_fija,
  drop constraint if exists contrato_pdfs_template_version_check,
  drop constraint if exists contrato_pdfs_storage_bucket_check,
  drop constraint if exists contrato_pdfs_nombre_archivo_check,
  drop constraint if exists contrato_pdfs_sha256_check,
  drop constraint if exists contrato_pdfs_bytes_check;
```

### private.puede_leer_contrato_pdf_como — viva (archivo 20260818014534; la regla D2 la amplió en 20260924042729)
```sql
create or replace function private.puede_leer_contrato_pdf_como(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
  v_resultado boolean;
begin
  if p_actor_id is null then return false; end if;
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  v_resultado := private.puede_leer_contrato_pdf(p_contrato_id);
  perform set_config(
    'request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true
  );
  return v_resultado;
exception when others then
  perform set_config(
    'request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true
  );
  raise;
end;
$function$;
revoke all on function private.puede_leer_contrato_pdf_como(uuid,uuid)
  from public, anon, authenticated, service_role;

-- La fila padre es el mutex contractual. Los writers de hijos la bloquean en
-- sus triggers; la reserva la bloquea antes de fotografiar, pero nunca bloquea
-- filas hijas. Así no se mantiene ningún lock durante render/Storage.
create or replace function private.bloquear_fila_contrato_pdf(
  p_contrato_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform 1
  from public.contratos c
  where c.id = p_contrato_id
  for update;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
end;
$function$;
```

### crm.contrato_pdf_estado_fn(uuid) — authenticated; patrón de autorización con auth.uid()
```sql
create or replace function crm.contrato_pdf_estado_fn(
  p_contrato_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not private.puede_leer_contrato_pdf(p_contrato_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;
  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;
revoke all on function crm.contrato_pdf_estado_fn(uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_archivo_fn(uuid)
  from public, anon, authenticated, service_role;
revoke all on function crm.contrato_pdf_snapshot_v2(uuid)
  from public, anon, authenticated, service_role;

grant execute on function crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)
  to authenticated;
grant execute on function crm.contrato_pdf_estado_fn(uuid)
  to authenticated;
grant execute on function crm.contrato_pdf_archivo_fn(uuid)
  to authenticated;
grant execute on function crm.contrato_pdf_reservar(uuid,uuid)
  to service_role;
grant execute on function crm.contrato_pdf_reclamar(uuid,uuid,integer)
  to service_role;
grant execute on function crm.contrato_pdf_marcar_subido(uuid,uuid,uuid,text,bigint)
  to service_role;
grant execute on function crm.contrato_pdf_marcar_error(uuid,uuid,uuid,text)
  to service_role;
grant execute on function crm.contrato_pdf_finalizar(uuid,uuid,uuid)
  to service_role;

do $cerrar_registro_v1$
begin
  if to_regprocedure(
    'crm.registrar_contrato_pdf(uuid,text,text,text,bigint,text,jsonb,uuid)'
  ) is not null then
    execute 'revoke all on function '
      || 'crm.registrar_contrato_pdf(uuid,text,text,text,bigint,text,jsonb,uuid) '
      || 'from public, anon, authenticated, service_role';
  end if;
end;
$cerrar_registro_v1$;

comment on table private.contrato_pdf_jobs is
  'Reserva durable v2; snapshot y ruta server-side inmutables, con lease corto para I/O externo.';
comment on table private.contrato_pdfs is
  'Ledger inmutable compatible con archivos v1 y jobs server-side v2.';
comment on function crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) is
  'Alta CRM atómica de contrato, cronograma, cuenta de pago y reserva documental v2.';
comment on function crm.contrato_pdf_reclamar(uuid,uuid,integer) is
  'Entrega un lease corto y el snapshot congelado a un worker service_role.';

do $postflight$
begin
  if not (
    (select c.relrowsecurity and c.relforcerowsecurity
     from pg_catalog.pg_class c
     where c.oid = 'private.contrato_pdf_jobs'::regclass)
    and
    (select c.relrowsecurity and c.relforcerowsecurity
     from pg_catalog.pg_class c
     where c.oid = 'private.contrato_pdfs'::regclass)
  ) then
    raise exception 'Las tablas PDF privadas no tienen RLS forzada';
  end if;

  if has_table_privilege('anon', 'private.contrato_pdf_jobs', 'SELECT')
     or has_table_privilege('authenticated', 'private.contrato_pdf_jobs', 'SELECT')
     or has_table_privilege('service_role', 'private.contrato_pdf_jobs', 'SELECT')
     or has_table_privilege('anon', 'private.contrato_pdfs', 'SELECT')
     or has_table_privilege('authenticated', 'private.contrato_pdfs', 'SELECT')
     or has_table_privilege('service_role', 'private.contrato_pdfs', 'SELECT') then
    raise exception 'Existe acceso directo indebido a tablas PDF privadas';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = 'storage.objects'::regclass
      and not t.tgisinternal
      and t.tgname = 'contrato_pdf_objeto_inmutable'
  ) then
    raise exception 'El PDF v2 no debe alterar storage.objects con triggers';
  end if;
end;
$postflight$;
```

### private.contrato_pdf_snapshot_v2_base — viva, 20260818014534:534-680 (forma del snapshot)
```sql
create or replace function private.contrato_pdf_snapshot_v2_base(
  p_contrato_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_contrato public.contratos%rowtype;
  v_cliente public.perfiles%rowtype;
  v_analista public.perfiles%rowtype;
  v_cotitulares jsonb;
  v_cronograma jsonb;
  v_cuenta jsonb;
begin
  select * into strict v_contrato
  from public.contratos c
  where c.id = p_contrato_id;

  select * into strict v_cliente
  from public.perfiles p
  where p.id = v_contrato.cliente_id
    and p.rol = 'cliente';

  if v_contrato.creado_por is null then
    raise exception 'El contrato no identifica al analista que lo creó'
      using errcode = '23514';
  end if;

  select * into strict v_analista
  from public.perfiles p
  where p.id = v_contrato.creado_por;

  if nullif(btrim(v_contrato.numero_contrato), '') is null
     or nullif(btrim(v_cliente.nombre_completo), '') is null
     or nullif(btrim(v_cliente.tipo_documento), '') is null
     or nullif(btrim(v_cliente.dni), '') is null
     or nullif(btrim(v_cliente.domicilio), '') is null
     or nullif(btrim(v_cliente.correo), '') is null
     or nullif(btrim(v_analista.nombre_completo), '') is null
     or nullif(btrim(v_analista.dni), '') is null
     or nullif(btrim(v_analista.telefono), '') is null
     or nullif(btrim(v_analista.correo), '') is null then
    raise exception
      'Faltan datos legales obligatorios del titular o del analista'
      using errcode = '23514';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'orden', t.orden,
        'nombreCompleto', t.nombre_completo,
        'tipoDocumento', upper(t.tipo_documento),
        'documento', t.documento
      ) order by t.orden, t.id
    ),
    '[]'::jsonb
  ) into v_cotitulares
  from public.contrato_titulares t
  where t.contrato_id = p_contrato_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', cp.id,
        'numeroCuota', cp.numero_cuota,
        'fechaProgramada', cp.fecha_programada::text,
        'montoProgramado', cp.monto_programado,
        'tipo', cp.tipo
      ) order by cp.numero_cuota, cp.id
    ),
    '[]'::jsonb
  ) into v_cronograma
  from public.cronograma_pagos cp
  where cp.contrato_id = p_contrato_id;

  if jsonb_array_length(v_cronograma) = 0 then
    raise exception 'El contrato no tiene cronograma contractual'
      using errcode = '23514';
  end if;

  select jsonb_build_object(
    'cuentaId', cb.id,
    'moneda', cb.moneda,
    'banco', cb.banco,
    'tipoCuenta', cb.tipo_cuenta,
    'numeroCuenta', cb.numero_cuenta,
    'cci', cb.cci,
    'titularDistinto', cb.titular_distinto,
    'beneficiarioNombre', cb.beneficiario_nombre,
    'beneficiarioDocumento', cb.beneficiario_dni,
    'origen', cb.origen
  ) into v_cuenta
  from crm.contrato_cuentas_pago ccp
  join crm.cuentas_bancarias cb on cb.id = ccp.cuenta_bancaria_id
  where ccp.contrato_id = p_contrato_id;

  if v_cuenta is null then
    raise exception 'El contrato no tiene una cuenta de pago contractual'
      using errcode = '23514';
  end if;

  return jsonb_build_object(
    'snapshotVersion', 2,
    'contrato', jsonb_build_object(
      'id', v_contrato.id,
      'numero', v_contrato.numero_contrato,
      'clienteId', v_contrato.cliente_id,
      'capital', v_contrato.capital,
      'moneda', v_contrato.moneda,
      'porcentaje', v_contrato.tasa_anual,
      'modalidad', v_contrato.modalidad,
      'tipoInteres', v_contrato.tipo_interes,
      'categoria', v_contrato.categoria,
      'fechaInicio', v_contrato.fecha_inicio::text,
      'fechaVencimiento', v_contrato.fecha_vencimiento::text,
      'productoCondicionId', v_contrato.producto_condicion_id,
      'creadoPor', v_contrato.creado_por
    ),
    'titular', jsonb_build_object(
      'id', v_cliente.id,
      'nombreCompleto', v_cliente.nombre_completo,
      'tipoDocumento', upper(v_cliente.tipo_documento),
      'documento', v_cliente.dni,
      'domicilio', v_cliente.domicilio,
      'correo', v_cliente.correo
    ),
    'analista', jsonb_build_object(
      'id', v_analista.id,
      'nombreCompleto', v_analista.nombre_completo,
      'documento', v_analista.dni,
      'celular', v_analista.telefono,
      'correo', v_analista.correo
    ),
    'cotitulares', v_cotitulares,
    'cronograma', v_cronograma,
    'cuentaPago', v_cuenta
  );
exception when no_data_found then
  raise exception 'Contrato, titular o analista inexistente'
    using errcode = 'P0002';
end;
$function$;
```

### private.crear_job_contrato_pdf_base — viva, 20260924042729:984-1057 (para ver qué se guarda en el job)
```sql
CREATE OR REPLACE FUNCTION private.crear_job_contrato_pdf_base(p_contrato_id uuid, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_job_id uuid;
  v_snapshot jsonb;
  v_nombre text;
  v_revision integer;
begin
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  perform private.bloquear_fila_contrato_pdf(p_contrato_id);

  if private.contrato_en_eliminacion(p_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  if exists (
    select 1 from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id
  ) or exists (
    select 1 from private.contrato_pdf_jobs j
    where j.contrato_id = p_contrato_id
  ) then
    return private.contrato_pdf_estado_base(p_contrato_id);
  end if;

  if private.contrato_documental_regimen(p_contrato_id) = 'anterior' then
    return private.contrato_pdf_estado_base(p_contrato_id);
  end if;

  -- Un trabajo NUEVO es parte del alta del contrato: la lectura (D2) no basta.
  if not private.puede_crear_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  v_job_id := gen_random_uuid();
  v_revision := 1;
  v_snapshot := private.contrato_pdf_snapshot_v2_base(p_contrato_id);
  v_nombre := private.nombre_archivo_contrato_pdf(p_contrato_id);
  if v_nombre is null then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;

  insert into private.contrato_pdf_jobs (
    id, contrato_id, revision, estado, storage_path, nombre_archivo,
    template_version, snapshot, solicitado_por
  ) values (
    v_job_id,
    p_contrato_id,
    v_revision,
    'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    v_nombre,
    'contrato-aep-17-v9',
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;
```

### Edge handler.ts:586-626 — validación del cuerpo y acciones admitidas
```ts
        origenes,
        {
          error: grande ? "Solicitud demasiado grande" : "JSON inválido",
          codigo: grande ? "SOLICITUD_GRANDE" : "JSON_INVALIDO",
        },
        grande ? 413 : 400,
      );
    }
    if (
      !esObjeto(cuerpo) || !clavesExactas(cuerpo, ["action", "contratoId"]) ||
      (cuerpo.action !== "ensure" && cuerpo.action !== "status" &&
        cuerpo.action !== "delete" && cuerpo.action !== "delete-audited") ||
      !uuidCanonico(cuerpo.contratoId)
    ) {
      return json(
        origin,
        origenes,
        { error: "Solicitud inválida", codigo: "SOLICITUD_INVALIDA" },
        400,
      );
    }

    const token = bearer(req);
    if (!token) {
      return json(origin, origenes, {
        error: "Sesión inválida",
        codigo: "SESION",
      }, 401);
    }
    const actor = deps.crearActor(token);
    const sesion = await actor.verificarSesion();
    if (!sesion || !uuidCanonico(sesion.id)) {
      return json(origin, origenes, {
        error: "Sesión inválida",
        codigo: "SESION",
      }, 401);
    }
    const contratoId = cuerpo.contratoId;

    if (cuerpo.action === "delete" || cuerpo.action === "delete-audited") {
      // La copia de datos y el borrado son una sola transacción. Los objetos
```

### Edge handler.ts:686-730 — cómo firma la URL del PDF sellado (verifica hash y bytes)
```ts
          { error: "Metadata PDF incoherente", codigo: "INTEGRIDAD_METADATA" },
          409,
        );
      }
      if (!yaVerificado) {
        const descarga = await deps.storage.descargar(archivo.storage_path);
        if (descarga.error || !descarga.data) {
          return json(
            origin,
            origenes,
            {
              error: "PDF no disponible temporalmente",
              codigo: "STORAGE_DESCARGA",
            },
            503,
          );
        }
        const fp = await pdfValido(descarga.data)
          ? await fingerprint(descarga.data)
          : null;
        if (
          !fp || fp.sha256 !== archivo.sha256 ||
          fp.bytes !== archivo.bytes
        ) {
          return json(
            origin,
            origenes,
            {
              error: "Integridad del PDF bloqueada",
              codigo: "INTEGRIDAD_OBJETO",
            },
            409,
          );
        }
      }
      const firma = await deps.storage.firmar(archivo.storage_path, 300, req);
      if (firma.error || !firma.url) {
        return json(
          origin,
          origenes,
          { error: "No se pudo firmar la descarga", codigo: "STORAGE_FIRMA" },
          503,
        );
      }
      return json(origin, origenes, {
```

### Edge handler.ts:200-213 — versionJobLegible
```ts
    if (codigo <= 0x1f || (codigo >= 0x7f && codigo <= 0x9f)) return true;
  }
  return false;
}

function versionJobLegible(valor: unknown): valor is string {
  return valor === "contrato-aep-17-v2" ||
    valor === "contrato-aep-17-v5" ||
    valor === "contrato-aep-17-v6" ||
    valor === "contrato-aep-17-v7" ||
    valor === "contrato-aep-17-v8" ||
    valor === CONTRATO_PDF_TEMPLATE_VERSION;
}

```

### Edge renderer.ts — validador estricto del snapshot (209-232) y datosDocumento (436-475; el plan revierte los añadidos)
```ts

export function validarSnapshotContratoV2(valor: unknown): SnapshotContratoV2 {
  if (
    !esObjeto(valor) ||
    !clavesExactas(valor, [
      "snapshotVersion",
      "contrato",
      "titular",
      "analista",
      "cotitulares",
      "cronograma",
      "cuentaPago",
    ]) || valor.snapshotVersion !== 2
  ) fallo("raíz");

  const contrato = valor.contrato;
  if (
    !esObjeto(contrato) ||
    !clavesExactas(contrato, [
      "id",
      "numero",
      "clienteId",
      "capital",
      "moneda",
  return {
    contrato: {
      numero: snapshot.contrato.numero,
      capital: snapshot.contrato.capital,
      moneda: snapshot.contrato.moneda,
      porcentaje: snapshot.contrato.porcentaje,
      modalidad: snapshot.contrato.modalidad,
      tipoInteres: snapshot.contrato.tipoInteres,
      fechaInicio: snapshot.contrato.fechaInicio,
      fechaVencimiento: snapshot.contrato.fechaVencimiento,
    },
    titular: {
      nombreCompleto: snapshot.titular.nombreCompleto,
      tipoDocumento: snapshot.titular.tipoDocumento,
      documento: snapshot.titular.documento,
      domicilio: snapshot.titular.domicilio,
      correo: snapshot.titular.correo,
    },
    analista: {
      nombreCompleto: snapshot.analista.nombreCompleto,
      documento: snapshot.analista.documento,
      celular: snapshot.analista.celular,
      correo: snapshot.analista.correo,
    },
    cotitulares: snapshot.cotitulares.map((cotitular) => ({
      nombreCompleto: cotitular.nombreCompleto,
      tipoDocumento: cotitular.tipoDocumento,
      documento: cotitular.documento,
    })),
    cronograma: snapshot.cronograma.map((cuota) => ({
      numeroCuota: cuota.numeroCuota,
      fechaProgramada: cuota.fechaProgramada,
      montoProgramado: cuota.montoProgramado,
      tipo: cuota.tipo,
    })),
  };
}

function fuente(nombre: string): Buffer {
  const base64 = (robotoVfs as unknown as Record<string, string>)[nombre];
```

### Edge template-v2.ts — borrador del anexo pegado al contrato (el plan lo mueve a anexo-v1.ts y lo quita del contrato)
```ts
function anexoCronograma(
  datos: ContratoPdfDatos,
  documento: string,
  cotitulares: Cotitular[],
): Content[] {
  const { contrato, titular, analista } = datos;
  const parciales = datos.cronograma.filter((cuota) => cuota.tipo !== "retorno");
  const retorno = datos.cronograma.find((cuota) => cuota.tipo === "retorno");
  const fechaFinal = retorno?.fechaProgramada ?? contrato.fechaVencimiento;
  const montoFinal = retorno?.montoProgramado ?? contrato.capital;

  const filasDatos: CeldaAnexo[][] = [
    [{ text: "Número de contrato" }, { text: contrato.numero, bold: true }],
    [{ text: "Fecha de inicio" }, {
      text: fechaLarga(contrato.fechaInicio),
      bold: true,
    }],
    [{ text: "Fecha de vencimiento" }, {
      text: fechaLarga(contrato.fechaVencimiento),
      bold: true,
    }],
    [{ text: "Monto de la contribución" }, {
      text: montoVisible(contrato.capital, contrato.moneda),
    // … (cuerpo del anexo: tablas y párrafos, 200 líneas) …
1084:    ...anexoCronograma(datos, documento, cotitulares),
```

### Front app/src/lib/contrato-pdf-archivo.ts:225-275 — cómo llama el front a la edge
```ts
  }
}

export function etiquetaEstadoContratoPdf(estado: EstadoContratoPdf): string {
  return mensajeEstado(estado)
}

async function invocarEdge(
  action: 'ensure' | 'status',
  contratoId: string): Promise<EdgeRespuesta> {
  exigirContratoIdCanonico(contratoId)
  const { data, error } = await clienteSupabase().functions.invoke(CONTRATO_PDF_EDGE, {
    body: { action, contratoId },
  })
  if (error) {
    let mensaje = error.message || 'No se pudo acceder al archivo contractual privado.'
    if (error instanceof FunctionsHttpError) {
      try {
        const cuerpo = (await error.context.clone().json()) as unknown
        const durable = v.safeParse(EdgeRespuestaSchema, cuerpo)
        if (durable.success && durable.output.pdf.contrato_id === contratoId) {
          return durable.output
        }
        if (
          cuerpo != null &&
          typeof cuerpo === 'object' &&
          'error' in cuerpo &&
          typeof cuerpo.error === 'string' &&
          cuerpo.error.trim()
        ) {
          mensaje = cuerpo.error
        }
      } catch {
        // La respuesta HTTP puede no ser JSON; conservamos el diagnóstico SDK.
      }
    }
    throw new Error(mensaje)
  }
  const resultado = v.safeParse(EdgeRespuestaSchema, data)
  if (!resultado.success) {
    throw new Error('La respuesta del archivo contractual no tiene el formato esperado.')
  }
  if (resultado.output.pdf.contrato_id !== contratoId) {
    throw new Error('El servidor respondió con el estado de otro contrato.')
  }
  return resultado.output
}

function estadoPublico(pdf: PdfEstadoWire): EstadoContratoPdfServidor {
  return {
    contratoId: pdf.contrato_id,
```

## .ai/REVIEW_PROTOCOL.md (transcrito)
# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.

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

# Encargo: REFUTAR el PLAN «anexo de cronograma OPCIONAL en el contrato PDF (plantilla v10)» — LEVEL 3

Todavía no hay SQL escrito. Miguel (dueño) vio las muestras del anexo y aprobó su aspecto; ahora pide
que el analista ELIJA por contrato si el PDF lleva anexo, y que la solución sea consistente y escalable.
Tu trabajo es intentar TUMBAR el diseño antes de que se escriba: dónde se guarda la elección, cómo viaja,
cómo se congela con el documento, qué pasa en corrección / F4 / reserva perezosa / reestampado de reservas
pendientes / eliminación / reversa, y qué anclas (huellas F7, postflights de venta cruzada, oráculos) se
romperían. Si prefieres la Opción B (columna en public) a la A (tabla en private), argumenta con evidencia.
Señala también lo que el plan NO cubre.

# Plan técnico: anexo de cronograma OPCIONAL en el contrato PDF (plantilla v10)

Fecha: 2026-09-28. PRIMARY: Claude. Nivel de riesgo: LEVEL 3 (migración, datos documentales, tabla nueva).

## Objetivo

Que el analista, al crear un contrato, elija si el PDF lleva un ANEXO con el cronograma de
liquidaciones parciales (modelo «Propuesta de Anexo para contrato de AEP», septiembre 2026).
La elección queda congelada con el documento: misma versión de plantilla + mismo snapshot ⇒
mismos bytes. Los PDF ya sellados no cambian.

## Hechos del sistema en los que se apoya (verificados 28/09)

- El PDF real lo genera solo la edge `crm-contrato-pdf-v2`; todos los caminos (alta, renovación,
  upgrade, corrección, F4 inversiones, cartera, portal admin) terminan en su acción `ensure`.
- El snapshot lo arma `private.contrato_pdf_snapshot_v2_base(uuid)` desde las tablas y se congela
  en `private.contrato_pdf_jobs.snapshot` al RESERVAR (`private.crear_job_contrato_pdf_base`).
  `contrato_pdf_reclamar` devuelve el snapshot guardado; `finalizar` lo copia a `contrato_pdfs` y
  exige que coincida. Ya lleva `contrato.modalidad`, `contrato.tipoInteres` y `cronograma[]`.
- Una CORRECCIÓN (`crm.actualizar_contrato_con_cuenta_pdf_v3` → `crm.actualizar_contrato_con_cuenta`
  → `public.actualizar_contrato`, ventana 5 h) abre el congelamiento y crea una REVISIÓN nueva con el
  snapshot RECALCULADO desde las tablas (`private.crear_revision_contrato_pdf_base`).
- «Ver PDF» de un contrato sin documento (p. ej. creado desde el portal admin) reserva sin que el
  analista elija nada (`contrato_pdf_reservar` → `crear_job`).
- `p_contrato` (jsonb) NO tiene lista blanca de claves: `clave_idempotencia`, `contrato_origen_id`,
  `titulares`, `analista_cierre_id` ya viajan dentro. F4 pasa `datos->'contrato'` tal cual a
  `crm.crear_contrato_con_cuenta_pdf_v2`; la lista cerrada de F4 es solo del nivel superior de `datos`.
- Huella de idempotencia del alta = md5((p_contrato - 'clave_idempotencia') | p_cronograma | p_cuenta).
- El renderer exige claves EXACTAS en el snapshot (raíz y `contrato`) y `snapshotVersion === 2`.
- Un solo formulario en el front (`ContratoNuevo`) sirve alta, renovación, upgrade, demo y F4.
- La plantilla v9 vive en `handler.ts` (constante + lista de versiones legibles), en los CHECK y
  default de las dos tablas y como literal en `crear_job` y `crear_revision`. `handler.test.ts:274` y
  `banco-pdf-v9/oraculo.sh:50` usan «v10» como versión inventada.

## Diseño

### D1. Transporte: clave dentro de `p_contrato`
- Clave `anexo_cronograma: true`, emitida por el front SOLO cuando el analista la marca (como
  `titulares`/`analista_cierre_id`). Ausente ⇒ false.
- No cambia la firma de ninguna RPC (las firmas de `pdf_v2` y `crear_contrato_con_cuenta` están
  ancladas por el censo F7 y los postflights de venta cruzada).
- F4 la lleva sola dentro de `datos.contrato`; `BorradorCondicionesSchema` y `ResumenRevision` la
  conservan y la muestran. Al emitirla solo cuando es true, `mismoContenidoInversion` no fuerza
  correcciones falsas en solicitudes preparadas antes del cambio.
- La huella de idempotencia la cubre sin tocar nada.

### D2. Persistencia: tabla lateral en `private` (recomendada) o columna en `public.contratos`
Opción A (recomendada): `private.contrato_opciones_documentales`
- `contrato_id uuid primary key references public.contratos(id) on delete cascade`,
  `con_anexo_cronograma boolean not null default false`, `creado_en`, `actualizado_en`, `creado_por`.
  RLS on, deny-by-default, `revoke all`, sin policy DELETE; solo la tocan funciones `private`/`crm`
  security definer. `COMMENT ON` completo.
- Trigger de congelamiento `proteger_opciones_documentales` (espejo de `proteger_titulares_documentales`):
  con `contrato_documental_congelado(contrato_id)` y sin `mutacion_documental_autorizada` ni
  `crm.contrato_pdf_revision_autorizada`, rechaza UPDATE/DELETE (55000). El borrado en cascada
  durante la eliminación auditada pasa por `mutacion_documental_autorizada`.
- Escritura: `crm.crear_contrato_con_cuenta_pdf_v2` inserta la fila (upsert por contrato_id) DESPUÉS
  de `crm.crear_contrato_con_cuenta` y ANTES de `crear_job`, leyendo `p_contrato->>'anexo_cronograma'`
  (`coalesce(...::boolean,false)`), y la quita de `p_contrato`? NO: se deja dentro (la huella la incluye
  y `public.crear_contrato` la ignora). Contratos creados por el portal admin: sin fila ⇒ false.
- Corrección (si Miguel lo aprueba): `crm.actualizar_contrato_con_cuenta_pdf_v3` upsert-ea la fila
  con la misma clave dentro de la ventana autorizada (`crm.contrato_pdf_revision_autorizada` ya está
  puesta), antes de `crear_revision`. Si no se aprueba, la corrección conserva la elección original.
- Por qué no `public`: la regla del proyecto es no tocar `public` sin OK; las opciones documentales
  son del CRM, no del portal; y deja casa a futuras opciones (otros anexos) sin volver a `public`.
Opción B: columna `public.contratos.con_anexo_cronograma boolean not null default false`
- Menos piezas (una columna, una línea en la lista congelada de `proteger_contrato_documental`,
  `public.crear_contrato` y `public.actualizar_contrato` leen la clave), pero toca tabla y dos
  funciones de `public` (OK explícito de Miguel) y obliga a regenerar `database.types.ts`.
- Ojo Opción B: `public.actualizar_contrato` hoy hace `update ... set modalidad = p_contrato->>'modalidad'`
  con lista fija; la columna nueva quedaría fuera del UPDATE (bien, si no se puede corregir) o dentro.

### D3. Snapshot: clave nueva de primer nivel `opciones`
- `private.contrato_pdf_snapshot_v2_base` añade `'opciones', jsonb_build_object('anexoCronograma',
  coalesce(o.con_anexo_cronograma,false))` con `left join private.contrato_opciones_documentales o`.
  `snapshotVersion` sigue en 2 (el oráculo `test-contrato-pdf-v2.sql:845` lo exige).
- Se conserva intacto el bloque «Faltan datos legales obligatorios» (lo buscan postflights antiguos).
- Renderer: `opciones` OPCIONAL en la raíz (claves exactas + una opcional); ausente ⇒ `{anexoCronograma:false}`.
  Motivo: las reservas pendientes sin bytes que la migración pasa de v9 a v10 conservan su snapshot
  SIN la clave (patrón v9: «sin tocar su snapshot») ⇒ salen sin anexo, como se reservaron.
- `datosDocumento` pasa `opciones.anexoCronograma` a la plantilla.

### D4. Plantilla v10 (una sola versión, dos variantes decididas por el snapshot)
- `template-v2.ts`: `...(datos.opciones?.anexoCronograma ? anexoCronograma(...) : [])`. Sin la opción, el
  PDF es idéntico a la v9 píxel a píxel y en texto (comparador `comparar-texto.py`: 22 233 caracteres).
- `ContratoPdfDatos.cronograma` y `contrato.modalidad/tipoInteres` requeridos (ya en el árbol);
  `opciones?: { anexoCronograma: boolean }`.
- Reglas del anexo: parciales = filas del cronograma con `tipo !== 'retorno'`; liquidación final = fila
  `retorno` (fecha y monto) o, si Miguel decide, `fechaVencimiento` + capital. Compuesto: una fila
  «devolucion» al vencimiento y modalidad «Única, al vencimiento del contrato».
- `handler.ts`: `CONTRATO_PDF_TEMPLATE_VERSION = contrato-aep-17-v10`; `versionJobLegible` añade v9.
- Tests: golden v10 SIN anexo (bytes = golden v9, mismo tamaño 218 672) y golden v10 CON anexo; tests de
  plantilla con fixtures con `cronograma`; `handler.test.ts` y `oraculo.sh` pasan la «versión
  inventada» a v11; `_render-muestra.ts --anexo`.

### D5. Migración `AAAAMMDDHHMMSS_crm_contrato_pdf_plantilla_v10_anexo_cronograma.sql`
Espejo de la v9 (begin/commit explícitos, candados antes de contar, preflight de reservas en vuelo,
conjunto EXACTO de funciones, OID/ACL/prosecdef/search_path medidos antes y después), más:
1. Tabla `private.contrato_opciones_documentales` + RLS + revoke + trigger + comentarios.
2. `private.contrato_pdf_snapshot_v2_base`: cuerpo vivo (pg_get_functiondef) + `left join` + clave `opciones`.
3. `crm.crear_contrato_con_cuenta_pdf_v2` (y `actualizar_..._v3` si aplica): cuerpo vivo + upsert de la fila.
   Se re-declaran las huellas que los anclen (postflight de venta cruzada 20260924042729 guarda la de
   `pdf_v2` y `crear_job`; `scripts/venta-cruzada/reversa-fase3.sql` exige las mismas ⇒ actualizar
   ese script o documentar que ya no aplica).
4. CHECKs de `contrato_pdf_jobs` y `contrato_pdfs` (+v10), default v10, reestampar reservas pendientes
   sin bytes v9→v10 (trigger de inmutabilidad apagado POR NOMBRE dentro de la transacción), literal
   v9→v10 en `crear_job` y `crear_revision` (una ocurrencia cada uno).
5. Postflight: default v10, 0 funciones con v9, 2 con v10, trigger de vuelta, sellados intactos.
6. Registrador `scripts/registrar-<ts>.sql` (md5 del archivo) y reversa `scripts/rollback-pdf-v10.sql`
   + edge de reversa (constante v9 que siga LEYENDO v10). La tabla y la clave `opciones` son aditivas:
   la reversa las deja (la edge v9 de reversa debe tolerar `opciones` en el snapshot).
7. Banco Docker `supabase/scripts/banco-pdf-v10/`: alta con y sin clave (snapshot y PDF), F4 con la
   clave dentro de `datos.contrato`, corrección conserva/cambia, reserva perezosa de contrato del portal
   ⇒ false, reserva pendiente v9 reestampada ⇒ sin anexo, sellado v9 intacto y descargable, eliminación
   auditada borra la fila, mutantes (clave ausente vs false, tipo 'retorno' mal filtrado, huella cambiada).

### D6. Front
- `CrearContratoInput.anexo_cronograma?: true`; `prepararPayloadContrato` la emite solo si true.
- `ContratoNuevo`: casilla «Incluir en el contrato el anexo con el cronograma de liquidaciones» (estado,
  inicialización desde `borrador`/`borradorLocal`, efecto del borrador F4). `BorradorCondicionesSchema`
  añade la clave opcional. `ResumenRevision` la muestra. `contrato-corregir.tsx` si se aprueba D2-corrección.
- Gemela demo `app/src/lib/contrato-pdf.ts`: añade `cronograma`, `modalidad`, `tipoInteres`, `opciones` y
  el mismo anexo; `contrato-nuevo.tsx` y `demo-clientes.ts` pasan el cronograma. (Deuda aparte: la gemela
  ya diverge en texto legal; propuesta futura: que el demo importe la plantilla de la edge.)
- e2e: los mocks hacen eco de `p_contrato` (`_helpers.ts:2304-2448`, `tasas-bajas.spec.ts`,
  `contrato-crear.spec.ts`, `f5-cartera.spec.ts`, `acceso-avance-ux.spec.ts`) ⇒ correr esos specs en
  Docker. Vitest: `crm-api-clientes-msw.test.ts`, `inversion-solicitud.test.ts`, `contrato-nuevo.test.tsx`.
- Los `strictObject` de `contrato-pdf-archivo.ts` no se tocan: la edge no añade claves a su respuesta.

### D7. Publicación (ventana muerta, con el `!` de Miguel, en este orden)
1. Front `/release-crm` (la clave la ignora el servidor viejo: un contrato creado en el hueco con la
   casilla marcada saldría SIN anexo; hueco de minutos, se avisa).
2. Edge `npx supabase@2.114.0 functions deploy crm-contrato-pdf-v2 --project-ref … --use-api` DESDE
   `CRM-Avance-Corp/` (contrastar 9 módulos vivos por la API de gestión antes).
3. Migración `db query --linked --file` y registrador. Entre 2 y 3: 409 reintentable en renders nuevos.
4. Verificación en prod (solo lectura): default v10, CHECKs, 0 funciones con v9, sellado v9 descarga,
   alta nueva con casilla ⇒ PDF con anexo; sin casilla ⇒ idéntico a v9; corrección conserva la elección.
5. Mismo día: commit en `main`, push `avancecorp main`, nota del vault, memoria.

## Decisiones pendientes de Miguel
1. Persistencia: Opción A (tabla en `private`, recomendada) u Opción B (columna en `public`, con su OK).
2. Casilla marcada por defecto o desmarcada.
3. ¿Se puede cambiar el anexo dentro de la ventana de corrección de 5 h?
4. Fecha de la liquidación final en el anexo: fila retorno (vencimiento + 7 días naturales) o vencimiento.
5. Compuesto: ¿anexo igual (una fila al vencimiento) o sin anexo?
6. Montos fijos en «Participación» frente a la cláusula 3.9 («sin constituir pagos fijos»): abogado.

## Qué NO cambia
PDF sellados (v1..v9); contratos del régimen anterior al 19/08; el cuerpo del contrato (ni una palabra);
el cálculo del cronograma; el portal del cliente; las firmas de las RPC.

## EVIDENCIA TRANSCRITA (cuerpos VIVOS según la última migración que los define)

### private.contrato_pdf_snapshot_v2_base — viva, 20260818014534:534-680
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

### private.crear_job_contrato_pdf_base — viva, 20260924042729:984-1057
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

### private.crear_revision_contrato_pdf_base — cuerpo 20260901184132:151-210 (literal ya en v9 por sustitución de texto)
```sql
create or replace function private.crear_revision_contrato_pdf_base(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_job_id uuid := gen_random_uuid();
  v_revision integer;
  v_snapshot jsonb;
  v_nombre text;
begin
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);
  if private.contrato_en_eliminacion(p_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  if not private.puede_leer_contrato_pdf_como(p_contrato_id, p_actor_id) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  if private.contrato_documental_regimen(p_contrato_id) = 'anterior' then
    return private.contrato_pdf_estado_base(p_contrato_id);
  end if;

  select greatest(
    coalesce((select max(j.revision) from private.contrato_pdf_jobs j
              where j.contrato_id = p_contrato_id), 0),
    coalesce((select max(p.revision) from private.contrato_pdfs p
              where p.contrato_id = p_contrato_id), 0)
  ) + 1 into v_revision;

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
    'contrato-aep-17-v7',
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;
```

### private.proteger_contrato_documental — viva, 20260818200741:560-600
```sql
create or replace function private.proteger_contrato_documental()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_contrato_id uuid := old.id;
  v_cambio_documental boolean := true;
begin
  if private.contrato_en_eliminacion(v_contrato_id)
     and not private.mutacion_documental_autorizada(v_contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;

  if tg_op = 'UPDATE' then
    v_cambio_documental := row(
      new.id, new.cliente_id, new.numero_contrato, new.capital, new.moneda,
      new.tasa_anual, new.modalidad, new.tipo_interes, new.fecha_inicio,
      new.fecha_vencimiento, new.categoria, new.producto_condicion_id,
      new.creado_por
    ) is distinct from row(
      old.id, old.cliente_id, old.numero_contrato, old.capital, old.moneda,
      old.tasa_anual, old.modalidad, old.tipo_interes, old.fecha_inicio,
      old.fecha_vencimiento, old.categoria, old.producto_condicion_id,
      old.creado_por
    );
  end if;

  if v_cambio_documental
     and private.contrato_documental_congelado(v_contrato_id)
     and not private.mutacion_documental_autorizada(v_contrato_id) then
    raise exception 'Los términos del contrato están congelados por su PDF legal'
      using errcode = '55000';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;
```

### public.crear_contrato (portal) — viva 20260908211349, tramo del INSERT (3455-3500)
```sql
  end if;

  if v_numero is null then
    v_numero := private.siguiente_numero_contrato(v_anio);
  end if;
  if exists (select 1 from public.contratos c where c.numero_contrato = v_numero) then
    raise exception 'El N de contrato % ya existe', v_numero;
  end if;

  insert into public.contratos (
    cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
    tipo_interes, fecha_inicio, fecha_vencimiento, notas_internas,
    categoria, estado, creado_por, analista_cierre_id
  ) values (
    v_cliente_id, v_numero, v_capital, v_moneda,
    (p_contrato->>'tasa_anual')::numeric, p_contrato->>'modalidad',
    coalesce(nullif(p_contrato->>'tipo_interes', ''), 'simple'),
    (p_contrato->>'fecha_inicio')::date,
    (p_contrato->>'fecha_vencimiento')::date,
    nullif(btrim(coalesce(p_contrato->>'notas_internas', '')), ''),
    v_categoria, 'activo', v_uid, v_analista_cierre
  ) returning id, fecha_cierre_comercial into v_contrato_id, v_fecha_operacion;

  if p_cronograma is null or jsonb_typeof(p_cronograma) <> 'array'
     or jsonb_array_length(p_cronograma) = 0 then
    raise exception 'El cronograma no puede estar vacío';
  end if;
  for v_cuota in select value from jsonb_array_elements(p_cronograma)
  loop
    insert into public.cronograma_pagos (
      contrato_id, numero_cuota, fecha_programada, monto_programado, estado, tipo
    ) values (
      v_contrato_id, (v_cuota->>'numero_cuota')::integer,
      (v_cuota->>'fecha_programada')::date,
      (v_cuota->>'monto_programado')::numeric, 'pendiente',
      coalesce(nullif(v_cuota->>'tipo', ''), 'cuota')
    );
  end loop;
  if p_contrato ? 'titulares' then
    perform public._sync_contrato_titulares(v_contrato_id, p_contrato->'titulares');
  end if;

  if v_categoria in ('renovacion', 'upgrade') then
    v_periodo := date_trunc('month', v_fecha_operacion)::date;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.operaciones_cartera'),
```

### public.actualizar_contrato (corrección) — viva 20260821222348, tramo del UPDATE
```sql
      'El contrato esta cerrado (%): no se pueden editar sus terminos',
      v_row.estado;
  end if;

  if (p_contrato->>'capital')::numeric < 100
     or (p_contrato->>'capital')::numeric > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000';
  end if;
  if (p_contrato->>'tasa_anual')::numeric <= 0
     or (p_contrato->>'tasa_anual')::numeric > 50 then
    raise exception 'La tasa anual debe estar entre 0 y 50%%';
  end if;

  if (p_contrato->>'categoria') is not null
     and (p_contrato->>'categoria') not in (
       'nuevo', 'renovacion', 'upgrade'
     ) then
    raise exception 'Categoria invalida';
  end if;

  v_numero := nullif(btrim(p_contrato->>'numero_contrato'), '');
  if v_numero is not null
     and v_numero is distinct from v_row.numero_contrato then
    if exists (
      select 1
      from public.contratos c
      where c.numero_contrato = v_numero
        and c.id <> p_id
    ) then
      raise exception
        'El N de contrato % ya existe en otro contrato',
        v_numero;
    end if;
  end if;

  update public.contratos
     set numero_contrato = coalesce(v_numero, numero_contrato),
         capital = (p_contrato->>'capital')::numeric,
         moneda = coalesce(nullif(p_contrato->>'moneda', ''), moneda),
         tasa_anual = (p_contrato->>'tasa_anual')::numeric,
         modalidad = p_contrato->>'modalidad',
         tipo_interes = coalesce(
           nullif(p_contrato->>'tipo_interes', ''),
           tipo_interes
         ),
         fecha_inicio = (p_contrato->>'fecha_inicio')::date,
         fecha_vencimiento = (p_contrato->>'fecha_vencimiento')::date,
         notas_internas = nullif(
           btrim(coalesce(p_contrato->>'notas_internas', '')),
           ''
         ),
         categoria = coalesce(
           nullif(p_contrato->>'categoria', ''),
           categoria
         )
   where id = p_id;

  if p_cronograma is not null
     and jsonb_array_length(p_cronograma) > 0 then
    if not exists (
      select 1
      from public.cronograma_pagos cp
      where cp.contrato_id = p_id
        and (cp.estado = 'pagado' or cp.monto_pagado is not null)
    ) then
      delete from public.cronograma_pagos cp
```

### Migración v9 20260915005752 (líneas 33-210): patrón de candados, preflights y reestampado que la v10 copiará
```sql
begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';
set local search_path = pg_catalog, pg_temp;

-- CANDADOS ANTES DE MIRAR (revisión de Codex, P1). Bajo READ COMMITTED, contar
-- reservas y luego pedir el candado deja una rendija: otra sesión puede reclamar
-- un job v8 entre el conteo y el ACCESS EXCLUSIVE del primer ALTER, y ese job se
-- salta el UPDATE y el postcheck. Se toman los candados PRIMERO, en el mismo
-- orden en que los ALTER los volverán a pedir (jobs → pdfs), para no invertir el
-- orden con ninguna otra operación. Con `lock_timeout` a 10 s esto falla cerrado
-- si la tabla está ocupada, en vez de esperar indefinidamente.
--
-- El advisory serializa dos pasadas de esta misma migración: `create or replace`
-- toma AccessExclusive sobre la función, pero entre LEER `pg_get_functiondef` y
-- EJECUTAR el replace hay una rendija que solo se cierra si nadie más despliega
-- funciones a la vez. Riesgo aceptado y declarado: en este proyecto las
-- migraciones se aplican de una en una.
select pg_catalog.pg_advisory_xact_lock(hashtext('crm.contrato_pdf.plantilla'));
lock table private.contrato_pdf_jobs in access exclusive mode;
lock table private.contrato_pdfs in access exclusive mode;

-- Preflight 1 · Ninguna migración del CRM toca `public` sin OK explícito. Si el
-- literal viviera en una función fuera de `private`, esto se detiene y la
-- nombra, en vez de reescribir en silencio algo del portal. Se mira
-- `pg_get_functiondef` y no `prosrc` porque un cuerpo SQL estándar
-- (BEGIN ATOMIC) no vive en `prosrc`, y sería invisible para una guarda ingenua.
do $block$
declare
  v_intrusas text;
begin
  select string_agg(n.nspname || '.' || p.proname, ', ' order by n.nspname, p.proname)
  into v_intrusas
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname not in ('pg_catalog', 'information_schema')
    and n.nspname <> 'private'
    and p.prokind in ('f', 'p')
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v8') > 0;

  if v_intrusas is not null then
    raise exception
      'PREFLIGHT v9: el literal v8 vive fuera de private (%); requiere decision explicita',
      v_intrusas;
  end if;
end;
$block$;

-- Preflight 2 · Reservas v8 EN VUELO. El UPDATE de más abajo no las toca (bien:
-- tienen lease vivo), pero con la edge ya en v9 quedarían varadas: al reclamar,
-- la edge marca PLANTILLA_NO_SOPORTADA y el job cae en error_reintentable
-- todavía en v8, cuando esta migración ya terminó. Se exige la ventana muerta.
do $block$
declare
  v_en_vuelo integer;
  v_vencidas integer;
begin
  select count(*)::integer,
         count(*) filter (where j.lease_expira_en <= now())::integer
  into v_en_vuelo, v_vencidas
  from private.contrato_pdf_jobs j
  where j.template_version = 'contrato-aep-17-v8'
    and j.estado in ('procesando', 'subido_verificado');

  -- Una con lease VIVO se resuelve sola al vencer o al terminar su trabajo. Una
  -- con lease VENCIDO no se mueve hasta que alguien la vuelva a reclamar: esperar
  -- no la arregla, hay que provocar el reclamo o resolverla a mano. Se distinguen
  -- porque el mensaje no debe prometer una recuperación por tiempo que no existe.
  if v_en_vuelo <> 0 then
    raise exception
      'PREFLIGHT v9: % reservas v8 en vuelo (% con lease ya vencido). Las de lease vivo se resuelven al vencer; las vencidas NO se mueven solas: hay que reclamarlas o resolverlas antes de repetir',
      v_en_vuelo, v_vencidas;
  end if;
end;
$block$;

alter table private.contrato_pdf_jobs
  drop constraint if exists contrato_pdf_jobs_template_valido;

alter table private.contrato_pdf_jobs
  alter column template_version set default 'contrato-aep-17-v9',
  add constraint contrato_pdf_jobs_template_valido check (
    template_version in (
      'contrato-aep-17-v2',
      'contrato-aep-17-v3',
      'contrato-aep-17-v4',
      'contrato-aep-17-v5',
      'contrato-aep-17-v6',
      'contrato-aep-17-v7',
      'contrato-aep-17-v8',
      'contrato-aep-17-v9'
    )
  );

alter table private.contrato_pdfs
  drop constraint if exists contrato_pdfs_version_ruta_valida;

alter table private.contrato_pdfs
  add constraint contrato_pdfs_version_ruta_valida check (
    (
      template_version = 'contrato-aep-17-v1'
      and job_id is null
      and storage_path = contrato_id::text || '/contrato.pdf'
    )
    or (
      template_version in (
        'contrato-aep-17-v2',
        'contrato-aep-17-v3',
        'contrato-aep-17-v4',
        'contrato-aep-17-v5',
        'contrato-aep-17-v6',
        'contrato-aep-17-v7',
        'contrato-aep-17-v8',
        'contrato-aep-17-v9'
      )
      and job_id is not null
      and storage_path =
        contrato_id::text || '/v2/' || job_id::text || '/contrato.pdf'
    )
  );

-- Los únicos UPDATE permitidos son reservas que todavía no representan bytes.
-- El trigger de inmutabilidad se apaga POR SU NOMBRE (nunca DISABLE TRIGGER
-- USER/ALL) y solo dentro de esta transacción: si algo falla, el rollback
-- deshace también el apagado.
alter table private.contrato_pdf_jobs
  disable trigger contrato_pdf_jobs_transiciones_validas;

update private.contrato_pdf_jobs
set template_version = 'contrato-aep-17-v9',
    actualizado_en = statement_timestamp()
where template_version = 'contrato-aep-17-v8'
  and estado in ('pendiente', 'error_reintentable')
  and lease_token is null
  and lease_expira_en is null
  and sha256 is null
  and bytes is null
  and subido_en is null;

alter table private.contrato_pdf_jobs
  enable trigger contrato_pdf_jobs_transiciones_validas;

-- Aviso (no aborta) con lo que se deja a propósito en v8: reservas que ya
-- representan bytes (error_reintentable con sha256/bytes) y sellados. Las
-- primeras, con la edge en v9, rebotan en PLANTILLA_NO_SOPORTADA al reclamarse
-- y solo salen del bucle por una corrección (revisión nueva). Hallazgo del
-- auditor del 14/09: que el operador lo vea en el log, aunque hoy sean cero.
do $aviso$
declare
  v_con_bytes integer;
  v_sellados integer;
begin
  select count(*)::integer into v_con_bytes
  from private.contrato_pdf_jobs j
  where j.template_version = 'contrato-aep-17-v8'
    and j.estado = 'error_reintentable';
  select count(*)::integer into v_sellados
  from private.contrato_pdf_jobs j
  where j.template_version = 'contrato-aep-17-v8'
    and j.estado = 'sellado';
  raise notice
    'v9: quedan en v8 a propósito % reservas error_reintentable con bytes y % jobs sellados',
    v_con_bytes, v_sellados;
end
$aviso$;

-- Sustitución del literal de versión en el cuerpo vivo de las funciones que lo
-- estampan, con el conjunto esperado declarado y los atributos medidos antes y
-- después. `strpos` en vez de LIKE: en LIKE el guion bajo es comodín.
do $block$
declare
  v_esperado constant text[] := array[
    'crear_job_contrato_pdf_base(p_contrato_id uuid, p_actor_id uuid)',
    'crear_revision_contrato_pdf_base(p_contrato_id uuid, p_actor_id uuid)'
  ];
  v_encontrado text[];
  v_oids oid[];
```

### Front app/src/data/crm-api.ts:2960-3010 — prepararPayloadContrato y crearContrato (transporte de claves dentro de p_contrato)
```ts
// «protege» DESPUÉS de una escritura irreversible: el contrato ya existe en el
// servidor, el front dice «error» y el analista lo crea otra vez.
//   · 19/08: el bundle exigía plantilla v3 y producción emitía v5 → todo alta
//     moría con «El servidor no confirmó completamente el contrato».
//   · 05/09: el esquema exigía la reserva `pendiente` y los contratos firmados
//     antes del 19/08 (régimen documental ANTERIOR: el servidor no emite
//     documento) vuelven con `sin_reserva` y `job_id = null` → 33 altas del
//     régimen anterior desde el 21/08 pasaron por el error falso, y el 05/09 un
//     analista cambió el número y creó el mismo contrato dos veces
//     (2026-01-000025 y 2026-01-000253, 61 s de diferencia).
// La fuente de verdad del documento es la edge (`contrato-pdf-archivo`), que se
// vuelve a consultar al archivar y en el detalle: esta copia solo pinta el primer
// estado, así que degradarla no esconde nada.
const ContratoConfirmadoSchema = v.object({
  id: v.pipe(v.string(), v.uuid()),
  numero_contrato: v.pipe(v.string(), v.minLength(1)),
  cuenta_bancaria_id: v.optional(v.unknown()),
  pdf: v.optional(v.unknown()),
  idempotente: v.optional(v.unknown()),
})
const CuentaBancariaIdSchema = v.pipe(v.string(), v.uuid())
// La forma que emite `private.contrato_pdf_estado_base` en TODAS sus ramas:
// reserva `pendiente`, `sin_reserva`, sellado… `looseObject` porque la rama de
// integridad añade `ok`/`codigo`, y porque una clave nueva del servidor no puede
// volver a convertir un alta en error.
const PdfAltaSchema = v.looseObject({
  contrato_id: v.pipe(v.string(), v.uuid()),
  job_id: v.nullable(v.pipe(v.string(), v.uuid())),
  estado: v.picklist(ESTADOS_CONTRATO_PDF),
  reintentable: v.boolean(),
})

/** Mismo contenido económico en el alta publicada y en la revisión F4. */
export function prepararPayloadContrato(input: CrearContratoInput): Record<string, unknown> {
  const p_contrato: Record<string, unknown> = {
    cliente_id: input.cliente_id,
    capital: input.capital,
    moneda: input.moneda,
    tasa_anual: input.tasa_anual,
    modalidad: input.modalidad,
    tipo_interes: input.tipo_interes,
    categoria: input.categoria,
    fecha_inicio: input.fecha_inicio,
    fecha_vencimiento: input.fecha_vencimiento,
    numero_contrato: input.numero_contrato?.trim() || null,
    notas_internas: input.notas_internas?.trim() || null,
  }
  if (input.categoria === 'renovacion') {
    p_contrato.contrato_origen_id = input.contrato_origen_id ?? null
    p_contrato.capital_renovado = input.capital_renovado ?? null
    p_contrato.capital_adicional = input.capital_adicional ?? 0
```

### Edge renderer.ts — validador de claves exactas (209-232) y datosDocumento (436-475, árbol de trabajo con cronograma ya pasado)
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

### Edge template-v2.ts — anexo en el árbol de trabajo (hoy SIEMPRE; el plan lo condiciona a opciones.anexoCronograma)
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

### Edge handler.ts:200-213 — versionJobLegible (lista de versiones que la edge sabe leer)
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

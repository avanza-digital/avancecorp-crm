-- El documento contractual solo existe para lo firmado del 2026-08-19 en adelante.
--
-- POR QUE. Miguel lo fijo el 2026-08-20: «el sistema me da un PDF que se usa como
-- unico contrato, pero los clientes anteriores a esto (19-08) ya tienen otro tipo
-- de contrato». La frontera la manda la FECHA DE FIRMA (`contratos.fecha_inicio`),
-- no la fecha en que el contrato se carga al sistema. Una operacion de febrero que
-- se registra hoy es del regimen ANTERIOR: ya tiene su contrato, y el sistema no
-- debe fabricarle otro.
--
-- QUE ESTABA PASANDO (medido en produccion el 2026-08-20, no supuesto):
--   · De los 31 contratos cargados desde el 18-ago, 26 se firmaron ANTES del 19 y
--     a 21 de ellos YA se les emitio documento nuevo. El mas viejo: 17 de febrero.
--   · El mecanismo no era el alta: es el boton «Ver contrato PDF» del detalle. Si
--     el contrato no tiene documento, ese boton NO muestra — FABRICA uno nuevo
--     (front → edge `ensure` → `crm.contrato_pdf_reservar`). Cualquiera que abriera
--     un contrato viejo acuñaba un contrato en el formato nuevo, fechado meses
--     atras y con el domicilio de HOY (el de notificaciones, clausula 14.ª).
--   · Efecto colateral del mismo agujero: como el documento exige el domicilio, la
--     carga del historial —que es el 97 % del trabajo real del equipo: 214 contratos
--     en 30 dias, solo 6 firmados del 19-ago en adelante— chocaba contra un muro
--     que ese contrato no necesitaba.
--
-- QUE HACE ESTA MIGRACION. `private.contrato_documental_regimen` como **fuente
-- unica** de la frontera (misma forma que `crm.normalizar_domicilio_legal` en el
-- bloque 1: una sola puerta, un solo liston) y las CUATRO funciones que pueden
-- acuñar o mover un documento la consultan:
--   1. `private.crear_job_contrato_pdf_base`      — alta y boton «Ver PDF»
--   2. `private.crear_revision_contrato_pdf_base` — correccion de contrato/numero
--   3. `crm.contrato_pdf_reclamar`                — la entrega del turno a la edge
--   4. `private.contrato_pdf_estado_base`         — lo que ve la pantalla
--
-- LO QUE NO TOCA, POR DECISION DE MIGUEL: los 21 documentos ya emitidos para
-- operaciones antiguas **se quedan como estan**. Siguen sellados, siguen
-- descargables. Esta migracion impide que nazcan mas, no borra los que hay.
--
-- LOS DOS TRABAJOS A MEDIAS. Los contratos 2026-01-000319 y 2026-01-000602
-- (RAMIREZ CARDENAS TONNY, firmados el 26-mar y el 18-may) tienen un trabajo en
-- `pendiente` desde el 19-ago con CERO intentos: nadie los reclamo nunca y nadie
-- los reclamara. No se borra ni se muta una sola fila: con la regla nueva quedan
-- INERTES (nadie puede reclamarlos) e INVISIBLES (el estado responde
-- `sin_reserva`), que es la verdad — ese contrato no lleva documento nuevo.
--
-- ORDEN DE DESPLIEGUE — LA EDGE VA PRIMERO. `parseEstado` de
-- `crm-contrato-pdf-v2` EXIGE hoy `reintentable === true` cuando el estado es
-- `sin_reserva`; devolver `false` sin actualizarla antes hace que la edge
-- descarte la respuesta entera (502) y la pantalla del contrato se rompa. La edge
-- tolerante viaja en este mismo commit y se despliega ANTES que esta migracion.
--
-- No crea, altera ni borra ningun objeto de `public`.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';

do $preflight$
begin
  if to_regprocedure('private.crear_job_contrato_pdf_base(uuid, uuid)') is null then
    raise exception 'PREFLIGHT: falta private.crear_job_contrato_pdf_base(uuid, uuid)';
  end if;
  if to_regprocedure('private.crear_revision_contrato_pdf_base(uuid, uuid)') is null then
    raise exception 'PREFLIGHT: falta private.crear_revision_contrato_pdf_base(uuid, uuid)';
  end if;
  if to_regprocedure('private.contrato_pdf_estado_base(uuid)') is null then
    raise exception 'PREFLIGHT: falta private.contrato_pdf_estado_base(uuid)';
  end if;
  if to_regprocedure('crm.contrato_pdf_reclamar(uuid, uuid, integer)') is null then
    raise exception 'PREFLIGHT: falta crm.contrato_pdf_reclamar(uuid, uuid, integer)';
  end if;
  -- La frontera se apoya en una columna NOT NULL: si `fecha_inicio` admitiera
  -- nulos, un contrato sin fecha caeria en 'anterior' por comparacion nula y se
  -- quedaria mudo para siempre sin que nadie lo notase.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'contratos'
      and column_name = 'fecha_inicio' and is_nullable = 'NO'
  ) then
    raise exception 'PREFLIGHT: public.contratos.fecha_inicio dejo de ser NOT NULL';
  end if;
end;
$preflight$;

-- ── La fuente unica de la frontera ───────────────────────────────────────────
-- Devuelve 'nuevo', 'anterior' o NULL (contrato inexistente). El NULL importa:
-- quien la llama NO debe tratarlo como 'anterior', sino dejar que su propio
-- camino de «contrato no encontrado» levante el error de siempre.
--
-- ⚠️ SON DOS FECHAS, Y LA SEGUNDA NO SOBRA. `fecha_inicio` es el inicio del
-- PLAZO, que no siempre coincide con la firma: medido en produccion el
-- 2026-08-20, los contratos 2026-01-000891 y 2026-01-000892 (REATEGUI PEREZ
-- PEDRO IVAN, S/ 170.000 y S/ 250.000) se cargaron el 1 de JULIO con
-- `fecha_inicio` = 2027-07-01. Con la fecha de plazo sola caerian en el regimen
-- NUEVO y el sistema les ofreceria emitir un contrato en el formato nuevo a dos
-- operaciones firmadas en julio, cuando este documento ni existia. El suelo de
-- `creado_en` lo impide sin contradecir la regla de Miguel: una operacion
-- registrada ANTES del 19-ago no pudo firmarse el 19-ago o despues. En hora de
-- Lima, que es donde se firma.
create or replace function private.contrato_documental_regimen(p_contrato_id uuid)
returns text
language sql
stable
security definer
set search_path to ''
as $$
  select case
    when c.fecha_inicio >= date '2026-08-19'
         and (c.creado_en at time zone 'America/Lima')::date >= date '2026-08-19'
      then 'nuevo'
    else 'anterior'
  end
  from public.contratos c
  where c.id = p_contrato_id
$$;

comment on function private.contrato_documental_regimen(uuid) is
  'Regimen documental de un contrato por FECHA DE FIRMA: firmado el 2026-08-19 o '
  'despues => ''nuevo'' (el sistema emite el PDF, que es el unico contrato); antes '
  '=> ''anterior'' (el cliente ya tiene su contrato en el formato previo y el '
  'sistema no le emite ninguno). NULL si el contrato no existe. Fuente unica: '
  'ninguna otra funcion repite esta fecha.';

revoke all on function private.contrato_documental_regimen(uuid) from public;

-- ── 1. El alta y el boton «Ver PDF»: no acuñan documento para lo antiguo ─────
create or replace function private.crear_job_contrato_pdf_base(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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

  -- LA FRONTERA. Va DESPUES del permiso (no se filtra la existencia de un
  -- contrato ajeno) y ANTES de la fotografia contractual: es justo el snapshot
  -- quien exige los nueve datos —domicilio incluido—, asi que salir aqui es lo
  -- que libera la carga del historial de un requisito que ese contrato no tiene.
  if private.contrato_documental_regimen(p_contrato_id) = 'anterior' then
    return private.contrato_pdf_estado_base(p_contrato_id);
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
    'contrato-aep-17-v5',
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;

-- Mismos privilegios que ya tenía viva (`postgres=X/postgres`). `create or
-- replace` los conserva; se repiten porque un ACL que solo vive en la memoria
-- de otra migración es un ACL que nadie puede auditar aquí.
revoke all on function private.crear_job_contrato_pdf_base(uuid, uuid)
  from public, anon, authenticated, service_role;

-- ── 2. Las correcciones: tampoco acuñan documento para lo antiguo ────────────
-- Incluye a los 21 ya emitidos: corregir uno de ellos NO genera una revision
-- nueva. Es coherente con «se quedan como estan» — y con que ese papel no es el
-- contrato de esa operacion, asi que refrescarlo no arregla nada y si acuñaria
-- un documento mas.
create or replace function private.crear_revision_contrato_pdf_base(
  p_contrato_id uuid,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
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
    snapshot, solicitado_por
  ) values (
    v_job_id,
    p_contrato_id,
    v_revision,
    'pendiente',
    p_contrato_id::text || '/v2/' || v_job_id::text || '/contrato.pdf',
    v_nombre,
    v_snapshot,
    p_actor_id
  );

  return private.contrato_pdf_estado_base(p_contrato_id);
end;
$function$;

revoke all on function private.crear_revision_contrato_pdf_base(uuid, uuid)
  from public, anon, authenticated, service_role;

-- ── 3. La entrega del turno: nadie trabaja un documento del regimen anterior ─
-- La guarda va DESPUES del bloque de integridad y del corte por
-- 'sellado'/'integridad_bloqueada': para los 21 ya emitidos todo sigue igual
-- (incluido el autodiagnostico de ledger incoherente). Solo muerde en
-- 'pendiente' / 'error_reintentable' / lease caducado, que es exactamente donde
-- viven los dos trabajos huerfanos del 19-ago.
create or replace function crm.contrato_pdf_reclamar(
  p_contrato_id uuid,
  p_actor_id uuid,
  p_lease_segundos integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_job private.contrato_pdf_jobs%rowtype;
  v_token uuid;
  v_adquirido boolean := false;
  v_estado_siguiente text;
  v_respuesta jsonb;
begin
  if p_lease_segundos is null
     or p_lease_segundos not between 30 and 300 then
    raise exception 'El lease debe durar entre 30 y 300 segundos'
      using errcode = '22023';
  end if;

  select * into v_job
  from private.contrato_pdf_jobs j
  where j.contrato_id = p_contrato_id
  order by j.revision desc
  limit 1;
  if not found then
    raise exception 'El contrato no tiene una reserva PDF v2'
      using errcode = 'P0002';
  end if;

  perform private.bloquear_fila_contrato_pdf(v_job.contrato_id);
  if private.contrato_en_eliminacion(v_job.contrato_id) then
    raise exception 'El contrato está en proceso de eliminación'
      using errcode = '55000';
  end if;
  select * into strict v_job
  from private.contrato_pdf_jobs j
  where j.id = v_job.id
  for update;

  if not private.puede_leer_contrato_pdf_como(
    v_job.contrato_id, p_actor_id
  ) then
    raise insufficient_privilege using
      message = 'Contrato no encontrado o fuera de tu cartera';
  end if;

  v_respuesta := private.contrato_pdf_estado_base(v_job.contrato_id);
  if (v_respuesta->>'estado') = 'integridad_bloqueada'
     and v_job.estado <> 'integridad_bloqueada' then
    update private.contrato_pdf_jobs
       set estado = 'integridad_bloqueada',
           lease_token = null,
           lease_expira_en = null,
           sellado_en = null,
           ultimo_error = 'LEDGER_INCOHERENTE',
           actualizado_en = statement_timestamp()
     where id = v_job.id;
    return private.contrato_pdf_estado_base(v_job.contrato_id)
      || jsonb_build_object('adquirido', false);
  end if;

  if v_job.estado in ('sellado', 'integridad_bloqueada') then
    return v_respuesta || jsonb_build_object('adquirido', false);
  end if;

  if private.contrato_documental_regimen(v_job.contrato_id) = 'anterior' then
    return v_respuesta || jsonb_build_object('adquirido', false);
  end if;

  if v_job.estado in ('pendiente', 'error_reintentable') then
    v_adquirido := true;
    v_estado_siguiente := case
      when v_job.sha256 is null then 'procesando'
      else 'subido_verificado'
    end;
  elsif v_job.estado in ('procesando', 'subido_verificado')
        and v_job.lease_expira_en <= statement_timestamp() then
    v_adquirido := true;
    v_estado_siguiente := v_job.estado;
  end if;

  if not v_adquirido then
    return v_respuesta || jsonb_build_object('adquirido', false);
  end if;

  v_token := gen_random_uuid();
  update private.contrato_pdf_jobs
     set estado = v_estado_siguiente,
         lease_token = v_token,
         lease_expira_en = statement_timestamp()
           + make_interval(secs => p_lease_segundos),
         intentos = intentos + 1,
         ultimo_error = null,
         actualizado_en = statement_timestamp()
   where id = v_job.id;

  select * into strict v_job
  from private.contrato_pdf_jobs j
  where j.id = v_job.id;

  return private.contrato_pdf_estado_base(v_job.contrato_id)
    || jsonb_build_object(
      'adquirido', true,
      'lease_token', v_token,
      'snapshot', v_job.snapshot,
      'renderizado_en', v_job.creado_en
    );
end;
$function$;

-- ── 4. Lo que ve la pantalla: la verdad, no una promesa ──────────────────────
-- Un contrato del regimen anterior SIN archivo responde `sin_reserva` con
-- `reintentable=false`, tenga o no un trabajo a medias. Los 21 que si tienen
-- archivo siguen respondiendo `sellado` con su documento descargable.
create or replace function private.contrato_pdf_estado_base(p_contrato_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_job private.contrato_pdf_jobs%rowtype;
  v_archivo jsonb;
  v_reintentable boolean;
  v_ledger_coherente boolean := false;
  v_integridad boolean := false;
  v_regimen_anterior boolean;
begin
  -- Se resuelve ANTES del `select into`: una asignacion no toca `found`, pero
  -- colocarla entre el SELECT y su `if not found` es pedirle explicaciones a la
  -- proxima persona que lea esto.
  v_regimen_anterior :=
    private.contrato_documental_regimen(p_contrato_id) = 'anterior';

  select * into v_job
  from private.contrato_pdf_jobs j
  where j.contrato_id = p_contrato_id
  order by j.revision desc
  limit 1;

  v_archivo := private.contrato_pdf_archivo_base(p_contrato_id);

  if not found then
    if v_archivo is not null then
      return jsonb_build_object(
        'contrato_id', p_contrato_id,
        'job_id', null,
        'estado', 'sellado',
        'storage_bucket', v_archivo->'storage_bucket',
        'storage_path', v_archivo->'storage_path',
        'nombre_archivo', v_archivo->'nombre_archivo',
        'template_version', v_archivo->'template_version',
        'intentos', 0,
        'lease_expira_en', null,
        'reintentable', false,
        'sha256', v_archivo->'sha256',
        'bytes', v_archivo->'bytes',
        'archivo', v_archivo
      );
    end if;
    return jsonb_build_object(
      'contrato_id', p_contrato_id,
      'job_id', null,
      'estado', 'sin_reserva',
      'storage_bucket', 'contratos-generados',
      'storage_path', null,
      'nombre_archivo', null,
      'template_version', null,
      'intentos', 0,
      'lease_expira_en', null,
      'reintentable', not v_regimen_anterior,
      'sha256', null,
      'bytes', null,
      'archivo', null
    );
  end if;

  -- Hay trabajo pero el contrato es del regimen anterior y no llego a archivo:
  -- ese trabajo no lo va a tomar nadie (`crm.contrato_pdf_reclamar` lo frena),
  -- asi que la pantalla no debe anunciar un documento en camino.
  if v_regimen_anterior and v_archivo is null then
    return jsonb_build_object(
      'contrato_id', p_contrato_id,
      'job_id', null,
      'estado', 'sin_reserva',
      'storage_bucket', 'contratos-generados',
      'storage_path', null,
      'nombre_archivo', null,
      'template_version', null,
      'intentos', 0,
      'lease_expira_en', null,
      'reintentable', false,
      'sha256', null,
      'bytes', null,
      'archivo', null
    );
  end if;

  if v_job.estado = 'integridad_bloqueada' then
    v_integridad := true;
  elsif v_job.estado = 'sellado' and v_archivo is null then
    v_integridad := true;
    v_job.estado := 'integridad_bloqueada';
  elsif v_archivo is not null then
    select exists (
      select 1
      from private.contrato_pdfs p
      where p.job_id = v_job.id
        and p.contrato_id = v_job.contrato_id
        and p.revision = v_job.revision
        and p.storage_bucket = v_job.storage_bucket
        and p.storage_path = v_job.storage_path
        and p.nombre_archivo = v_job.nombre_archivo
        and p.sha256 = v_job.sha256
        and p.bytes = v_job.bytes
        and p.template_version = v_job.template_version
        and p.snapshot = v_job.snapshot
        and p.generado_por = v_job.solicitado_por
    ) into v_ledger_coherente;

    if v_job.estado <> 'sellado' or not v_ledger_coherente then
      v_integridad := true;
      v_job.estado := 'integridad_bloqueada';
    end if;
  end if;

  v_reintentable := v_job.estado in ('pendiente', 'error_reintentable')
    or (
      v_job.estado in ('procesando', 'subido_verificado')
      and coalesce(v_job.lease_expira_en, '-infinity'::timestamptz) <= now()
    );
  return jsonb_build_object(
    'contrato_id', v_job.contrato_id,
    'job_id', v_job.id,
    'estado', v_job.estado,
    'storage_bucket', v_job.storage_bucket,
    'storage_path', v_job.storage_path,
    'nombre_archivo', v_job.nombre_archivo,
    'template_version', v_job.template_version,
    'intentos', v_job.intentos,
    'lease_expira_en', v_job.lease_expira_en,
    'reintentable', case
      when v_archivo is not null or v_integridad then false
      else v_reintentable
    end,
    'sha256', coalesce(v_archivo->'sha256', to_jsonb(v_job.sha256)),
    'bytes', coalesce(v_archivo->'bytes', to_jsonb(v_job.bytes)),
    'archivo', v_archivo
  ) || case
    when v_integridad then jsonb_build_object(
      'ok', false,
      'codigo', 'PDF_INTEGRIDAD_BLOQUEADA'
    )
    else '{}'::jsonb
  end;
end;
$function$;

-- ── POSTFLIGHT 1 · la frontera existe y clasifica con datos REALES ───────────
-- Sobre una base VACIA (el oraculo local, un banco recien creado) no hay nada
-- que medir: entonces GRITA en vez de aprobar, y no aborta. Contra produccion
-- tiene que decir OK; si dice SIN DATOS, algo va mal y hay que parar. El bloque
-- 1 enseño que una sonda que pasa en verde sin nada que contar no prueba nada.
do $postflight$
declare
  v_nuevos int;
  v_anteriores int;
  v_mal int;
begin
  if to_regprocedure('private.contrato_documental_regimen(uuid)') is null then
    raise exception 'POSTFLIGHT 1: no quedo private.contrato_documental_regimen(uuid)';
  end if;

  select
    count(*) filter (where private.contrato_documental_regimen(c.id) = 'nuevo'),
    count(*) filter (where private.contrato_documental_regimen(c.id) = 'anterior'),
    count(*) filter (where private.contrato_documental_regimen(c.id) is null)
  into v_nuevos, v_anteriores, v_mal
  from public.contratos c;

  if v_mal > 0 then
    raise exception 'POSTFLIGHT 1: % contratos sin regimen (fecha_inicio nula?)', v_mal;
  end if;
  if v_nuevos + v_anteriores = 0 then
    raise warning 'POSTFLIGHT 1 SIN DATOS · no hay contratos que clasificar. '
      'Contra produccion esto NO puede salir: si aparece, PARA.';
  elsif v_anteriores = 0 then
    raise warning 'POSTFLIGHT 1 SIN DATOS · CERO contratos del regimen anterior '
      '(nuevos=%). Contra produccion es imposible: hay historial cargado. PARA.',
      v_nuevos;
  else
    raise notice 'POSTFLIGHT 1 OK · regimen nuevo=% · anterior=%', v_nuevos, v_anteriores;
  end if;
end;
$postflight$;

-- ── POSTFLIGHT 2 · el estado dice la verdad y lo ya emitido sigue intacto ────
do $postflight$
declare
  v_antiguos int;
  v_prometidos int;
  v_ya_emitidos int;
  v_rotos int;
begin
  select count(*) into v_antiguos
  from public.contratos c
  where private.contrato_documental_regimen(c.id) = 'anterior';

  -- Ningun contrato del regimen anterior sin archivo puede seguir anunciando
  -- documento en camino ni ofrecerse como reintentable.
  select count(*) into v_prometidos
  from public.contratos c
  where private.contrato_documental_regimen(c.id) = 'anterior'
    and not exists (
      select 1 from private.contrato_pdfs p where p.contrato_id = c.id
    )
    and (
      (private.contrato_pdf_estado_base(c.id)->>'estado') <> 'sin_reserva'
      or (private.contrato_pdf_estado_base(c.id)->>'reintentable')::boolean
    );
  if v_prometidos > 0 then
    raise exception 'POSTFLIGHT 2: % contratos antiguos siguen prometiendo documento', v_prometidos;
  end if;

  -- Y los ya emitidos siguen intactos y descargables: esta migracion no borra.
  select
    count(*),
    count(*) filter (
      where (private.contrato_pdf_estado_base(c.id)->>'estado') <> 'sellado'
    )
  into v_ya_emitidos, v_rotos
  from public.contratos c
  where private.contrato_documental_regimen(c.id) = 'anterior'
    and exists (select 1 from private.contrato_pdfs p where p.contrato_id = c.id);
  if v_rotos > 0 then
    raise exception 'POSTFLIGHT 2: % documentos antiguos ya emitidos dejaron de responder sellado', v_rotos;
  end if;

  if v_antiguos = 0 then
    raise warning 'POSTFLIGHT 2 SIN DATOS · no hay contratos del regimen anterior '
      'que medir. Contra produccion esto NO puede salir: si aparece, PARA.';
  else
    raise notice 'POSTFLIGHT 2 OK · antiguos=% · de ellos ya emitidos e intactos=%',
      v_antiguos, v_ya_emitidos;
  end if;
end;
$postflight$;

-- ── POSTFLIGHT 3 · las cuatro puertas consultan la fuente unica ──────────────
do $postflight$
declare
  v_falta text[] := '{}';
  v_fn text;
begin
  foreach v_fn in array array[
    'private.crear_job_contrato_pdf_base',
    'private.crear_revision_contrato_pdf_base',
    'private.contrato_pdf_estado_base',
    'crm.contrato_pdf_reclamar'
  ] loop
    if not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname || '.' || p.proname = v_fn
        -- Se busca la LLAMADA cualificada, no el nombre suelto: una mencion en
        -- un comentario aprobaria la sonda sin que nadie consulte nada. Misma
        -- familia de trampa que «en LIKE el guion bajo es comodin» (14-ago).
        and strpos(p.prosrc, 'private.contrato_documental_regimen(') > 0
    ) then
      v_falta := v_falta || v_fn::text;
    end if;
  end loop;
  if cardinality(v_falta) > 0 then
    raise exception 'POSTFLIGHT 3: no consultan la fuente unica: %',
      array_to_string(v_falta, ' | ');
  end if;

  -- `search_path` vacio deja en proconfig el literal CON COMILLAS: la sonda
  -- ingenua ('search_path=' = any(proconfig)) es SIEMPRE falsa. Bloque 1, 19-ago.
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname = 'contrato_documental_regimen'
      and p.proconfig @> array['search_path=""']
  ) then
    raise exception 'POSTFLIGHT 3: contrato_documental_regimen sin search_path blindado';
  end if;
  raise notice 'POSTFLIGHT 3 OK · las cuatro puertas consultan la fuente unica';
end;
$postflight$;

commit;

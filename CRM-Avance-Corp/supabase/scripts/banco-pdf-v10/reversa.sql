-- Reversa v10 -> v9. Ejecutar SOLO con autorización de producción.
-- Antes: detener emisiones y resolver TODOS los trabajos en vuelo/con bytes.
-- Desplegar la Edge de reversa: renderer v9/anexo v1 con firma antigua, pero
-- lector compatible con TODOS los PDF v1..v10. El artefacto v9 original no sirve.
-- Ver LEEME.md del banco-pdf-v10 para construir/verificar ese artefacto.
-- Este SQL conserva los CHECK ampliados a v10, todos los PDF ya emitidos y los
-- snapshots; solo devuelve a v9 las reservas v10 todavía sin bytes.
-- No es idempotente y no elimina historial de migraciones ni de emisiones.

begin;

set local lock_timeout = '10s';
set local statement_timeout = '120s';
set local search_path = pg_catalog, pg_temp;

-- CANDADOS ANTES DE MIRAR (revisión de Codex, P1). Bajo READ COMMITTED, contar
-- reservas y luego pedir el candado deja una rendija: otra sesión puede reclamar
-- un job v10 entre el conteo y el ACCESS EXCLUSIVE del primer ALTER, y ese job se
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
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v10') > 0;

  if v_intrusas is not null then
    raise exception
      'REVERSA v10: el literal v10 vive fuera de private (%); requiere decision explicita',
      v_intrusas;
  end if;
end;
$block$;

-- Bloquea trabajo pendiente que el nuevo renderer no podría terminar. También
-- bloquea leases vencidos y reintentos con bytes: esperar no los recupera.
-- No modifica sellados ni integridad_bloqueada; estos últimos necesitan la
-- revisión auditada existente, nunca reescribir sus bytes o snapshot.
do $preflight$
declare
  v_pendientes integer;
begin
  if not exists (
    select 1 from pg_catalog.pg_trigger
    where tgrelid = 'private.contrato_pdf_jobs'::regclass
      and tgname = 'contrato_pdf_jobs_transiciones_validas'
      and not tgisinternal and tgenabled = 'O'
  ) then
    raise exception 'REVERSA v10: el trigger de inmutabilidad no esta habilitado en origen';
  end if;

  select count(*)::integer into v_pendientes
  from private.contrato_pdf_jobs j
  where j.estado in ('pendiente', 'error_reintentable', 'procesando', 'subido_verificado')
    and not (
      j.template_version = 'contrato-aep-17-v10'
      and j.estado in ('pendiente', 'error_reintentable')
      and j.lease_token is null and j.lease_expira_en is null
      and j.sha256 is null and j.bytes is null and j.subido_en is null
    );
  if v_pendientes <> 0 then
    raise exception
      'REVERSA v10: % reservas incompatibles, en vuelo o con bytes. Resolver con la Edge anterior antes del cambio, incluso si el lease vencio', v_pendientes;
  end if;
end;
$preflight$;

alter table private.contrato_pdf_jobs
  alter column template_version set default 'contrato-aep-17-v9';

-- Los únicos UPDATE permitidos son reservas que todavía no representan bytes.
-- El trigger de inmutabilidad se apaga POR SU NOMBRE (nunca DISABLE TRIGGER
-- USER/ALL) y solo dentro de esta transacción: si algo falla, el rollback
-- deshace también el apagado.
alter table private.contrato_pdf_jobs
  disable trigger contrato_pdf_jobs_transiciones_validas;

update private.contrato_pdf_jobs
set template_version = 'contrato-aep-17-v9',
    actualizado_en = statement_timestamp()
where template_version = 'contrato-aep-17-v10'
  and estado in ('pendiente', 'error_reintentable')
  and lease_token is null
  and lease_expira_en is null
  and sha256 is null
  and bytes is null
  and subido_en is null;

alter table private.contrato_pdf_jobs
  enable trigger contrato_pdf_jobs_transiciones_validas;

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
  v_antes jsonb;
  v_despues jsonb;
  v_oid oid;
  v_def text;
  v_ocurrencias integer;
  v_reescritas integer := 0;
begin
  select coalesce(
           array_agg(
             p.proname || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')'
             order by p.proname
           ),
           array[]::text[]
         ),
         coalesce(array_agg(p.oid order by p.proname), array[]::oid[])
  into v_encontrado, v_oids
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.prokind in ('f', 'p')
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v10') > 0;

  -- El mundo se declara, no se supone: si mañana una tercera función de
  -- `private` estampara la versión, se reescribiría sin revisión y sin su
  -- `revoke` correspondiente.
  if v_encontrado <> v_esperado then
    raise exception
      'REVERSA v10: las funciones que estampan la v10 son % y se esperaban %',
      v_encontrado, v_esperado;
  end if;

  select jsonb_object_agg(
           p.oid::text,
           jsonb_build_object(
             'duenio', pg_catalog.pg_get_userbyid(p.proowner),
             'acl', coalesce(p.proacl::text, '<default>'),
             'secdef', p.prosecdef,
             'config', coalesce(array_to_string(p.proconfig, '|'), '<null>'),
             'volatilidad', p.provolatile,
             'lenguaje', l.lanname,
             'retorno', pg_catalog.format_type(p.prorettype, null)
           )
         )
  into v_antes
  from pg_catalog.pg_proc p
  join pg_catalog.pg_language l on l.oid = p.prolang
  where p.oid = any (v_oids);

  foreach v_oid in array v_oids loop
    v_def := pg_catalog.pg_get_functiondef(v_oid);

    v_ocurrencias := (
      length(v_def) - length(replace(v_def, 'contrato-aep-17-v10', ''))
    ) / length('contrato-aep-17-v10');

    if v_ocurrencias <> 1 then
      raise exception
        'REVERSA v10: % tiene % ocurrencias del literal v10, se esperaba 1',
        v_oid::regprocedure, v_ocurrencias;
    end if;

    execute replace(v_def, 'contrato-aep-17-v10', 'contrato-aep-17-v9');

    -- Lo que quedó vivo tiene que ser exactamente lo que quisimos escribir.
    if pg_catalog.pg_get_functiondef(v_oid)
       is distinct from replace(v_def, 'contrato-aep-17-v10', 'contrato-aep-17-v9') then
      raise exception
        'REVERSA v10: el cuerpo vivo de % no coincide con el que se escribio',
        v_oid::regprocedure;
    end if;

    v_reescritas := v_reescritas + 1;
  end loop;

  if v_reescritas <> array_length(v_esperado, 1) then
    raise exception
      'REVERSA v10: se reescribieron % funciones y se esperaban %',
      v_reescritas, array_length(v_esperado, 1);
  end if;

  -- Se buscan por OID: `create or replace` conserva el OID de pg_proc, y con él
  -- propietario, ACL y comentarios. Si alguna hubiera sido recreada (OID nuevo),
  -- esta lectura devolvería menos filas y la comparación fallaría.
  select jsonb_object_agg(
           p.oid::text,
           jsonb_build_object(
             'duenio', pg_catalog.pg_get_userbyid(p.proowner),
             'acl', coalesce(p.proacl::text, '<default>'),
             'secdef', p.prosecdef,
             'config', coalesce(array_to_string(p.proconfig, '|'), '<null>'),
             'volatilidad', p.provolatile,
             'lenguaje', l.lanname,
             'retorno', pg_catalog.format_type(p.prorettype, null)
           )
         )
  into v_despues
  from pg_catalog.pg_proc p
  join pg_catalog.pg_language l on l.oid = p.prolang
  where p.oid = any (v_oids);

  if v_despues is distinct from v_antes then
    raise exception
      'REVERSA v10: la reescritura cambio atributos de las funciones. antes=% despues=%',
      v_antes, v_despues;
  end if;

  raise notice 'v9: % funciones reescritas, atributos y OID intactos', v_reescritas;
end;
$block$;

-- Defensa en profundidad, no reparación: `create or replace` conserva la ACL,
-- así que estos revokes son no-ops mientras el cierre original siga en pie
-- (la base ya los revocó en 20260818014534). Se dejan porque su coste es cero y
-- acreditan la intención; el bloque de arriba es quien PRUEBA que la ACL no
-- cambió.
revoke all on function private.crear_job_contrato_pdf_base(uuid, uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.crear_revision_contrato_pdf_base(uuid, uuid)
  from public, anon, authenticated, service_role;

do $block$
declare
  v_default text;
  v_restantes integer;
  v_en_vuelo integer;
  v_funciones_v10 integer;
  v_funciones_v9 integer;
begin
  select pg_catalog.pg_get_expr(d.adbin, d.adrelid)
  into v_default
  from pg_catalog.pg_attrdef d
  join pg_catalog.pg_attribute a
    on a.attrelid = d.adrelid and a.attnum = d.adnum
  where d.adrelid = 'private.contrato_pdf_jobs'::regclass
    and a.attname = 'template_version';

  if v_default is null or strpos(v_default, 'contrato-aep-17-v9') = 0 then
    raise exception
      'REVERSA v10: el default de template_version es %', coalesce(v_default, '<null>');
  end if;

  -- El trigger que esta migración apagó tiene que haber vuelto, y en origen
  -- ('O'): `enable trigger` FIJA ese valor, no restaura el anterior.
  if not exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = 'private.contrato_pdf_jobs'::regclass
      and t.tgname = 'contrato_pdf_jobs_transiciones_validas'
      and not t.tgisinternal
      and t.tgenabled = 'O'
  ) then
    raise exception
      'REVERSA v10: contrato_pdf_jobs_transiciones_validas no quedo habilitado en origen';
  end if;

  -- Mismo predicado, palabra por palabra, que el UPDATE de arriba.
  select count(*)::integer
  into v_restantes
  from private.contrato_pdf_jobs j
  where j.template_version = 'contrato-aep-17-v10'
    and j.estado in ('pendiente', 'error_reintentable')
    and j.lease_token is null
    and j.lease_expira_en is null
    and j.sha256 is null
    and j.bytes is null
    and j.subido_en is null;

  if v_restantes <> 0 then
    raise exception
      'REVERSA v10: quedan % reservas v10 sin bytes', v_restantes;
  end if;

  -- Con los candados tomados al principio nadie pudo colar una reserva nueva
  -- durante la migración; esto lo acredita en vez de suponerlo.
  select count(*)::integer
  into v_en_vuelo
  from private.contrato_pdf_jobs j
  where j.template_version = 'contrato-aep-17-v10'
    and j.estado in ('procesando', 'subido_verificado');

  if v_en_vuelo <> 0 then
    raise exception
      'REVERSA v10: aparecieron % reservas v10 en vuelo durante la migracion', v_en_vuelo;
  end if;

  select count(*)::integer into v_funciones_v10
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname not in ('pg_catalog', 'information_schema')
    and p.prokind in ('f', 'p')
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v10') > 0;

  select count(*)::integer into v_funciones_v9
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.prokind in ('f', 'p')
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v9') > 0;

  if v_funciones_v10 <> 0 then
    raise exception
      'REVERSA v10: % funciones siguen estampando la v10', v_funciones_v10;
  end if;
  if v_funciones_v9 <> 2 then
    raise exception
      'REVERSA v10: estampan la v9 % funciones y se esperaban 2', v_funciones_v9;
  end if;

  raise notice 'CONTRATO_PDF_V10_ROLLBACK_OK';
end;
$block$;

commit;

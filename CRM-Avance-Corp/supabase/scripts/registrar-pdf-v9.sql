-- REGISTRO en supabase_migrations.schema_migrations de la PLANTILLA v9 del PDF (20260915005752).
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración.
-- Idempotente. Se niega si el mundo no quedó como la migración promete (default en v9, las dos
-- funciones estampando la v9, cero funciones con la v8 en cualquier esquema, trigger de
-- inmutabilidad habilitado en origen) o si la versión ya está registrada con otro contenido.
-- md5 del archivo 26534a4a1cfa9a7bb111504c4c7a8515.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm.contrato_pdf.plantilla'));
do $chk$
declare
  v_default text;
  v_v8 integer;
  v_v9 integer;
begin
  select pg_catalog.pg_get_expr(d.adbin, d.adrelid) into v_default
  from pg_catalog.pg_attrdef d
  join pg_catalog.pg_attribute a on a.attrelid = d.adrelid and a.attnum = d.adnum
  where d.adrelid = 'private.contrato_pdf_jobs'::regclass and a.attname = 'template_version';
  if v_default is null or strpos(v_default, 'contrato-aep-17-v9') = 0 then
    raise exception 'REGISTRO v9: el default de template_version es %', coalesce(v_default, '<null>');
  end if;

  select count(*)::integer into v_v8
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname not in ('pg_catalog','information_schema') and p.prokind in ('f','p')
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v8') > 0;
  if v_v8 <> 0 then
    raise exception 'REGISTRO v9: % funciones siguen estampando la v8', v_v8;
  end if;

  select count(*)::integer into v_v9
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.prokind in ('f','p')
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v9') > 0;
  if v_v9 <> 2 then
    raise exception 'REGISTRO v9: estampan la v9 % funciones y se esperaban 2', v_v9;
  end if;

  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'private.contrato_pdf_jobs'::regclass
      and t.tgname = 'contrato_pdf_jobs_transiciones_validas'
      and not t.tgisinternal and t.tgenabled = 'O') then
    raise exception 'REGISTRO v9: el trigger de transiciones no está habilitado en origen';
  end if;

  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20260915005752'
               and coalesce(md5(statements[1]), '') <> '26534a4a1cfa9a7bb111504c4c7a8515') then
    raise exception 'REGISTRO v9: la versión 20260915005752 ya está registrada con otro contenido';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260915005752', 'crm_contrato_pdf_plantilla_v9_cotitulares', array[$m$-- Plantilla v9: el contrato con cuenta mancomunada nombra a los co-titulares en
-- la comparecencia («quienes actúan de manera conjunta y a quienes se les
-- denominará EL ASOCIADO») y los hace firmar al final, rotulados EL ASOCIADO,
-- debajo del titular principal (decisión de Miguel, 14/09/2026; anula la de
-- julio de no imprimirlos). De cada co-titular van solo nombre y documento, que
-- ya viajan en el snapshot desde la v2: esta migración NO toca el snapshot ni
-- ninguna tabla de datos. Un contrato SIN co-titulares sale idéntico a la v8,
-- píxel a píxel (misma letra, mismas cláusulas, mismo membrete).
--
-- Los PDFs ya sellados (v1..v8) NO se tocan ni se regeneran: siguen
-- descargándose byte a byte como se firmaron. Esta migración solo declara la
-- v9, la pone como versión de las reservas nuevas y convierte a v9 las reservas
-- que todavía no representan bytes. No crea revisiones.
--
-- TRANSACCIÓN EXPLÍCITA (auditoría 08/09, P0): el carril productivo
-- `db query --linked --file` no auto-envuelve, y este archivo apaga el trigger
-- de inmutabilidad y rehace dos CHECK. Sin `begin`/`commit`, un fallo del
-- UPDATE dejaría `contrato_pdf_jobs_transiciones_validas` apagado de forma
-- indefinida y silenciosa, los CHECK podrían quedar caídos, y los `set local`
-- de abajo serían un no-op (WARNING: SET LOCAL can only be used in transaction
-- blocks). El begin/commit es lo que hace que el ACCESS EXCLUSIVE de los ALTER
-- se sostenga hasta el final y que todo revierta junto.
--
-- Las funciones que estampan la versión se reescriben a partir de su CUERPO
-- VIVO (pg_get_functiondef), sustituyendo únicamente el literal de versión: una
-- función viva no se reteclea. Desde la v8 ninguna migración del árbol volvió a
-- definir esos cuerpos (20260908211349 solo los llama), pero la regla se
-- mantiene por si otra sesión los tocó fuera del árbol. Se exige el conjunto
-- EXACTO de funciones esperado, una sola ocurrencia del literal en cada una, y
-- que propietario, ACL, SECURITY DEFINER, search_path, volatilidad y OID
-- sobrevivan a la reescritura.

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
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v8') > 0;

  -- El mundo se declara, no se supone: si mañana una tercera función de
  -- `private` estampara la versión, se reescribiría sin revisión y sin su
  -- `revoke` correspondiente.
  if v_encontrado <> v_esperado then
    raise exception
      'PREFLIGHT v9: las funciones que estampan la v8 son % y se esperaban %',
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
      length(v_def) - length(replace(v_def, 'contrato-aep-17-v8', ''))
    ) / length('contrato-aep-17-v8');

    if v_ocurrencias <> 1 then
      raise exception
        'PREFLIGHT v9: %.% tiene % ocurrencias del literal v8, se esperaba 1',
        v_oid::regprocedure, '', v_ocurrencias;
    end if;

    execute replace(v_def, 'contrato-aep-17-v8', 'contrato-aep-17-v9');

    -- Lo que quedó vivo tiene que ser exactamente lo que quisimos escribir.
    if pg_catalog.pg_get_functiondef(v_oid)
       is distinct from replace(v_def, 'contrato-aep-17-v8', 'contrato-aep-17-v9') then
      raise exception
        'POSTCHECK v9: el cuerpo vivo de % no coincide con el que se escribio',
        v_oid::regprocedure;
    end if;

    v_reescritas := v_reescritas + 1;
  end loop;

  if v_reescritas <> array_length(v_esperado, 1) then
    raise exception
      'PREFLIGHT v9: se reescribieron % funciones y se esperaban %',
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
      'POSTCHECK v9: la reescritura cambio atributos de las funciones. antes=% despues=%',
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
  v_funciones_v8 integer;
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
      'POSTCHECK v9: el default de template_version es %', coalesce(v_default, '<null>');
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
      'POSTCHECK v9: contrato_pdf_jobs_transiciones_validas no quedo habilitado en origen';
  end if;

  -- Mismo predicado, palabra por palabra, que el UPDATE de arriba.
  select count(*)::integer
  into v_restantes
  from private.contrato_pdf_jobs j
  where j.template_version = 'contrato-aep-17-v8'
    and j.estado in ('pendiente', 'error_reintentable')
    and j.lease_token is null
    and j.lease_expira_en is null
    and j.sha256 is null
    and j.bytes is null
    and j.subido_en is null;

  if v_restantes <> 0 then
    raise exception
      'POSTCHECK v9: quedan % reservas v8 sin bytes', v_restantes;
  end if;

  -- Con los candados tomados al principio nadie pudo colar una reserva nueva
  -- durante la migración; esto lo acredita en vez de suponerlo.
  select count(*)::integer
  into v_en_vuelo
  from private.contrato_pdf_jobs j
  where j.template_version = 'contrato-aep-17-v8'
    and j.estado in ('procesando', 'subido_verificado');

  if v_en_vuelo <> 0 then
    raise exception
      'POSTCHECK v9: aparecieron % reservas v8 en vuelo durante la migracion', v_en_vuelo;
  end if;

  select count(*)::integer into v_funciones_v8
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname not in ('pg_catalog', 'information_schema')
    and p.prokind in ('f', 'p')
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v8') > 0;

  select count(*)::integer into v_funciones_v9
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.prokind in ('f', 'p')
    and strpos(pg_catalog.pg_get_functiondef(p.oid), 'contrato-aep-17-v9') > 0;

  if v_funciones_v8 <> 0 then
    raise exception
      'POSTCHECK v9: % funciones siguen estampando la v8', v_funciones_v8;
  end if;
  if v_funciones_v9 <> 2 then
    raise exception
      'POSTCHECK v9: estampan la v9 % funciones y se esperaban 2', v_funciones_v9;
  end if;

  raise notice 'CONTRATO_PDF_V9_MIGRATION_OK';
end;
$block$;

commit;
$m$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20260915005752' and md5(statements[1]) = '26534a4a1cfa9a7bb111504c4c7a8515') then
    raise exception 'REGISTRO v9: la versión no quedó registrada con el contenido esperado';
  end if;
  raise notice 'REGISTRO CONTRATO PDF v9 OK (20260915005752, md5 26534a4a…)';
end
$post$;
commit;

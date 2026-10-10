-- REGISTRO en supabase_migrations.schema_migrations de 20261010150451_crm_jerarquia_relleno_carmen_jorge.
-- Correr DESPUÉS de aplicar la migración, por la misma vía. Idempotente; se niega si los dos eventos del relleno no
-- están exactos o si la versión ya está registrada con otro nombre u otro texto. Si algo corta entre la migración y
-- este registro: la migración repetida dice «ya aplicado» y este registro se puede correr otra vez.
-- Generado por generar.py: md5 del texto de la migración 00fb0e49cba90b54cd242b2878dc6554.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_jerarquia_relleno_carmen_jorge'));
do $chk$
begin
  -- Los dos eventos EXACTOS (mismos campos que comprueba la migración al repetirse), no solo dos con su idempotencia.
  if (select count(*) from crm.usuario_eventos ue
      where ue.actor_id = 'f6d2941b-2e93-4c81-9a27-0c5e786b104d' and ue.accion = 'jerarquia_actualizada'
        and ue.detalle ->> 'via' = 'relleno'
        and ue.detalle ->> 'supervisor_anterior' = 'ebb19751-5976-4446-91ec-03382247d8b8'
        and ue.detalle ->> 'supervisor_nuevo' = 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'
        and ue.creado_en = '2026-08-29 17:56:38.8714+00'
        and (ue.objetivo_id, ue.idempotencia) in (('0eeb8c64-25e4-418b-b5d5-e07b06758b5e'::uuid, 'df2577aa-0315-43ad-8d28-cc1fce382b61'::uuid), ('cc8b660a-49e9-49b2-a939-c12b5078911b'::uuid, '8ea032ed-da1e-48f1-b75c-52f6afaaf3e5'::uuid))) <> 2 then
    raise exception 'REGISTRO: faltan los dos eventos del relleno; aplica primero 20261010150451';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261010150451' and coalesce(name, '') <> 'crm_jerarquia_relleno_carmen_jorge') then
    raise exception 'REGISTRO: la versión 20261010150451 ya está registrada con otro nombre';
  end if;
  -- Un registro con OTRO texto no se pisa en silencio (el insert de abajo no hace nada si la versión existe).
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261010150451' and (cardinality(statements) is distinct from 1
               or md5(statements[1]) is distinct from '00fb0e49cba90b54cd242b2878dc6554')) then
    raise exception 'REGISTRO: la versión 20261010150451 ya está registrada con OTRO texto; revisar a mano';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261010150451', 'crm_jerarquia_relleno_carmen_jorge', array[$migracion_20261010150451$-- Facturación FASE 5: relleno de jerarquía de Carmen Jaramillo y Jorge Marzano (aprobado por Miguel el 10/10/2026).
-- QUÉ: anota los DOS eventos `jerarquia_actualizada` que el bloque $normalizar_directorio$ de 20260828210351 no dejó al
-- mover a estos dos supervisores de CARLOS VALLES a ADMINISTRADOR AVANCE CORP. Hora, antes y después salen de
-- public.audit_log (29/08/2026 12:56:38 Lima, sin autor): no se inventa nada. Autor «sistema» (fase 2), via 'relleno'.
-- EFECTO (medido en producción el 10/10 09:51 con supabase/scripts/jerarquia-relleno/medir-relleno.sql y aprobado):
-- solo Facturación lee estos eventos. Las 9 ventas de Jorge desde el 29/08 pasan de supervisor CARLOS VALLES a
-- ADMINISTRADOR AVANCE CORP: septiembre 4 × S/ 1,271,900 + 1 × US$ 27,000; octubre 3 × S/ 213,600 + 1 × US$ 20,000.
-- Carmen, nada. Los totales de la empresa, agosto (sellado) y lo que ve cada supervisor no cambian.
-- Sin cambios de esquema, funciones ni permisos. Una base sin estas personas ni su rastro (banco, local) no recibe nada.
-- ORÁCULO en la misma transacción: Facturación entera antes y después del insert; se niega si cambia algo distinto de lo
-- aprobado. Las ventas de los dos fechadas desde el 10/10 (posteriores a la medición) también pasan a Administrador.
-- CONCURRENCIA (Codex r1, P2): crm.equipo y crm.usuario_eventos se bloquean ANTES de fijar la instantánea, así que
-- ningún cambio de jerarquía ni evento entra entre la validación y el commit. Una venta que se confirme en esos
-- ~300 ms no se bloquea: sigue la misma regla (si es de ellos desde el 29/08, va con Administrador, que es lo correcto).
-- REVERSA: supabase/scripts/jerarquia-relleno/reversa.sql (borra los dos eventos por su idempotencia fija).
begin;
set transaction isolation level repeatable read;
set local lock_timeout = '10s';
set local statement_timeout = '120s';
-- Antes de la primera lectura: en REPEATABLE READ la instantánea se fija en la primera consulta, ya con los candados.
lock table crm.equipo in share mode;
lock table crm.usuario_eventos in share row exclusive mode;
-- INICIO TRANSACCION
do $migracion$
declare
  v_sistema uuid := 'f6d2941b-2e93-4c81-9a27-0c5e786b104d';
  v_antes uuid;
  v_despues uuid;
  v_ts timestamptz;
  v_corte date;
  v_dia_cambio date;
  v_n integer;
  v_movidas integer;
  v_nuevas integer;
  v_cambio text;
  v_inicio timestamptz := clock_timestamp();
begin
-- INICIO CONSTANTES
  -- Producción (medido el 10/10/2026): cada persona, su fila de public.audit_log y la idempotencia fija de su evento.
  create temporary table relleno_eventos (
    perfil_id uuid primary key, audit_id uuid not null unique, idempotencia uuid not null unique
  ) on commit drop;
  insert into pg_temp.relleno_eventos values
    ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', '9808d0f3-5746-4373-9db7-ff8a7d692586', 'df2577aa-0315-43ad-8d28-cc1fce382b61'),  -- JORGE MARZANO
    ('cc8b660a-49e9-49b2-a939-c12b5078911b', '13d8b650-cccd-4e5d-9dad-4295bcd88da2', '8ea032ed-da1e-48f1-b75c-52f6afaaf3e5');  -- CARMEN JARAMILLO
  v_antes := 'ebb19751-5976-4446-91ec-03382247d8b8';    -- CARLOS VALLES
  v_despues := 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';  -- ADMINISTRADOR AVANCE CORP
  v_ts := '2026-08-29 17:56:38.8714+00';
  v_corte := '2026-10-10';  -- día de la medición: lo fechado desde ese día (Lima) no estaba en el cambio aprobado
  -- El cambio APROBADO por analista, mes y moneda (ventas fechadas antes del corte).
  create temporary table relleno_aprobado (
    analista_id uuid, mes date, moneda text, operaciones bigint not null, capital numeric not null,
    primary key (analista_id, mes, moneda)
  ) on commit drop;
  insert into pg_temp.relleno_aprobado values
    ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', '2026-09-01', 'PEN', 4, 1271900),
    ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', '2026-09-01', 'USD', 1, 27000),
    ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', '2026-10-01', 'PEN', 3, 213600),
    ('0eeb8c64-25e4-418b-b5d5-e07b06758b5e', '2026-10-01', 'USD', 1, 20000);
-- FIN CONSTANTES
  v_dia_cambio := (v_ts at time zone 'America/Lima')::date;

  -- 0. Una base sin estas personas ni su rastro (banco, local) no recibe nada.
  if not exists (select 1 from crm.equipo e
                 where e.perfil_id in (select r.perfil_id from pg_temp.relleno_eventos r)
                    or e.perfil_id in (v_antes, v_despues))
     and not exists (select 1 from public.audit_log al
                     where al.id in (select r.audit_id from pg_temp.relleno_eventos r)) then
    raise notice 'Relleno de jerarquía: esta base no tiene a estas personas ni su rastro; nada que hacer';
    return;
  end if;

  -- 1. ¿Ya aplicada? Los dos eventos exactos: nada que hacer. Uno solo o distinto: estado a medias, se niega.
  select count(*) into v_n from crm.usuario_eventos ue
  where ue.actor_id = v_sistema and ue.accion = 'jerarquia_actualizada'
    and ue.idempotencia in (select r.idempotencia from pg_temp.relleno_eventos r);
  if v_n > 0 then
    if v_n = 2 and (select count(*) from crm.usuario_eventos ue
                    join pg_temp.relleno_eventos r
                      on r.idempotencia = ue.idempotencia and r.perfil_id = ue.objetivo_id
                    where ue.actor_id = v_sistema and ue.accion = 'jerarquia_actualizada'
                      and ue.creado_en = v_ts
                      and ue.detalle ->> 'supervisor_anterior' = v_antes::text
                      and ue.detalle ->> 'supervisor_nuevo' = v_despues::text
                      and ue.detalle ->> 'via' = 'relleno') = 2 then
      raise notice 'Relleno de jerarquía ya aplicado: los dos eventos están y coinciden';
      return;
    end if;
    raise exception 'PREFLIGHT: relleno a medias o distinto (% eventos con su idempotencia); revisar a mano', v_n;
  end if;

  -- 2. PREFLIGHT. La lógica de Facturación es la que se midió y aprobó.
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p
      where p.oid = to_regprocedure('private.facturacion_operaciones(timestamptz,timestamptz)'))
       is distinct from '5d63cb537b0b286ad47feb7f5b26d161'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p
         where p.oid = to_regprocedure('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'))
       is distinct from '2ed07da302e9a1b881a4962724234dd7' then
    raise exception 'PREFLIGHT: Facturación cambió desde la medición aprobada (huellas); volver a medir';
  end if;
  if private.actor_sistema_eventos() is distinct from v_sistema then
    raise exception 'PREFLIGHT: el autor «sistema» no es el de la fase 2';
  end if;
  -- El rastro: cada fila de auditoría dice exactamente este cambio, a esta hora.
  select count(*) into v_n
  from pg_temp.relleno_eventos r
  join public.audit_log al on al.id = r.audit_id
  where al.tabla = 'crm.equipo' and al.operacion = 'UPDATE' and al.fila_id = r.perfil_id::text
    and al.ts = v_ts
    and al.data_antes ->> 'supervisor_id' = v_antes::text
    and al.data_despues ->> 'supervisor_id' = v_despues::text;
  if v_n <> 2 then
    raise exception 'PREFLIGHT: el rastro de auditoría no es el medido (% de 2 filas coinciden)', v_n;
  end if;
  -- Hoy: los dos siguen con ADMINISTRADOR, su último evento dice CARLOS VALLES y ninguno es posterior al cambio.
  select count(*) into v_n
  from pg_temp.relleno_eventos r
  join crm.equipo e on e.perfil_id = r.perfil_id
  where e.supervisor_id = v_despues
    and (select ue.detalle ->> 'supervisor_nuevo'
         from crm.usuario_eventos ue
         where ue.accion = 'jerarquia_actualizada' and ue.objetivo_id = r.perfil_id
         order by ue.creado_en desc, ue.id desc limit 1) = v_antes::text
    and not exists (select 1 from crm.usuario_eventos ue
                    where ue.accion = 'jerarquia_actualizada' and ue.objetivo_id = r.perfil_id
                      and ue.creado_en >= v_ts);
  if v_n <> 2 then
    raise exception 'PREFLIGHT: la jerarquía de hoy ya no es la medida (% de 2 coinciden); volver a medir', v_n;
  end if;

  -- 3. ORÁCULO, foto ANTES (REPEATABLE READ: misma instantánea que la foto DESPUÉS, salvo este insert).
  create temporary table relleno_antes on commit drop as
    select o.operacion_id, o.dia, o.tipo, o.moneda, o.monto, o.analista_id, o.supervisor_id,
           row_number() over (partition by o.operacion_id, o.dia, o.tipo, o.moneda, o.monto, o.analista_id) as rn
    from private.facturacion_operaciones('-infinity'::timestamptz, 'infinity'::timestamptz) o;

  -- 4. El relleno: un evento por persona, con la hora y el antes/después de la auditoría.
  insert into crm.usuario_eventos(actor_id, objetivo_id, accion, detalle, idempotencia, creado_en)
  select v_sistema, r.perfil_id, 'jerarquia_actualizada',
         jsonb_build_object(
           'supervisor_anterior', v_antes, 'supervisor_nuevo', v_despues, 'via', 'relleno',
           'evidencia', jsonb_build_object('audit_log_id', r.audit_id,
                                           'origen', '20260828210351 $normalizar_directorio$'),
           'aprobado', 'Miguel, 10/10/2026 (fase 5 de Facturación)'),
         r.idempotencia, v_ts
  from pg_temp.relleno_eventos r;

  -- 5. ORÁCULO, foto DESPUÉS y comparación operación por operación. El supervisor de una operación depende solo de
  -- su analista y su día, así que dentro de una clave repetida todas las filas son iguales y el emparejamiento por
  -- posición es exacto.
  create temporary table relleno_despues on commit drop as
    select o.operacion_id, o.dia, o.tipo, o.moneda, o.monto, o.analista_id, o.supervisor_id,
           row_number() over (partition by o.operacion_id, o.dia, o.tipo, o.moneda, o.monto, o.analista_id) as rn
    from private.facturacion_operaciones('-infinity'::timestamptz, 'infinity'::timestamptz) o;
  create temporary table relleno_par on commit drop as
    select a.dia, a.moneda, a.monto, a.analista_id, a.supervisor_id as de, d.supervisor_id as a_sup
    from pg_temp.relleno_antes a
    join pg_temp.relleno_despues d
      on d.operacion_id is not distinct from a.operacion_id and d.dia is not distinct from a.dia
     and d.tipo is not distinct from a.tipo and d.moneda is not distinct from a.moneda
     and d.monto is not distinct from a.monto and d.analista_id is not distinct from a.analista_id
     and d.rn = a.rn;
  if (select count(*) from pg_temp.relleno_antes) <> (select count(*) from pg_temp.relleno_despues)
     or (select count(*) from pg_temp.relleno_par) <> (select count(*) from pg_temp.relleno_antes) then
    raise exception 'ORÁCULO: las operaciones no casan (antes %, después %, emparejadas %)',
      (select count(*) from pg_temp.relleno_antes), (select count(*) from pg_temp.relleno_despues),
      (select count(*) from pg_temp.relleno_par);
  end if;
  -- Solo cambian ventas de estas dos personas desde el día del cambio, y de CARLOS VALLES a ADMINISTRADOR.
  select count(*) into v_n from pg_temp.relleno_par p
  where p.de is distinct from p.a_sup
    and (p.analista_id in (select r.perfil_id from pg_temp.relleno_eventos r)
         and p.dia >= v_dia_cambio and p.de = v_antes and p.a_sup = v_despues) is not true;
  if v_n > 0 then
    raise exception 'ORÁCULO: % operaciones cambian de supervisor fuera de lo aprobado', v_n;
  end if;
  -- Y TODAS las suyas desde ese día quedan con ADMINISTRADOR.
  select count(*) into v_n from pg_temp.relleno_par p
  where p.analista_id in (select r.perfil_id from pg_temp.relleno_eventos r)
    and p.dia >= v_dia_cambio and p.a_sup is distinct from v_despues;
  if v_n > 0 then
    raise exception 'ORÁCULO: % operaciones de los dos desde el cambio no quedan con ADMINISTRADOR', v_n;
  end if;
  -- El cambio aprobado, exacto, para lo fechado antes del corte.
  select coalesce(string_agg(format('%s %s %s: %s × %s', x.analista_id, to_char(x.mes, 'YYYY-MM'), x.moneda,
                                    x.operaciones, x.capital), '; ' order by x.analista_id, x.mes, x.moneda), 'ninguno')
  into v_cambio
  from (select p.analista_id, date_trunc('month', p.dia)::date as mes, p.moneda,
               count(*) as operaciones, sum(p.monto) as capital
        from pg_temp.relleno_par p
        where p.de is distinct from p.a_sup and p.dia < v_corte
        group by 1, 2, 3) x;
  if exists ((select p.analista_id, date_trunc('month', p.dia)::date, p.moneda, count(*), sum(p.monto)
              from pg_temp.relleno_par p
              where p.de is distinct from p.a_sup and p.dia < v_corte
              group by 1, 2, 3)
             except all
             (select a.analista_id, a.mes, a.moneda, a.operaciones, a.capital from pg_temp.relleno_aprobado a))
     or exists ((select a.analista_id, a.mes, a.moneda, a.operaciones, a.capital from pg_temp.relleno_aprobado a)
                except all
                (select p.analista_id, date_trunc('month', p.dia)::date, p.moneda, count(*), sum(p.monto)
                 from pg_temp.relleno_par p
                 where p.de is distinct from p.a_sup and p.dia < v_corte
                 group by 1, 2, 3)) then
    raise exception 'ORÁCULO: el cambio no es el aprobado. Medido ahora: %', v_cambio;
  end if;
  select count(*) filter (where p.dia >= v_corte), count(*) into v_nuevas, v_movidas
  from pg_temp.relleno_par p where p.de is distinct from p.a_sup;

  v_cambio := format('%s operaciones de %s pasan de supervisor (aprobado: %s; nuevas desde el %s: %s); %s ms',
                     v_movidas, (select count(*) from pg_temp.relleno_antes), v_cambio, v_corte, v_nuevas,
                     round(extract(epoch from clock_timestamp() - v_inicio) * 1000));
  if current_setting('crm.relleno_jerarquia_ensayo', true) = 'on' then
    raise exception 'ENSAYO RELLENO PASS: % — SE DESHACE TODO', v_cambio;
  end if;
  raise notice 'Relleno de jerarquía aplicado: %', v_cambio;
end
$migracion$;
commit;
$migracion_20261010150451$])
on conflict (version) do nothing;
select version, name, md5(statements[1]) as md5_texto from supabase_migrations.schema_migrations where version = '20261010150451';
commit;

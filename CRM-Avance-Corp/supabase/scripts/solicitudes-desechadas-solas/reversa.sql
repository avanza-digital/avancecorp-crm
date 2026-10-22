-- REVERSA de 20261022171000_crm_solicitudes_desechadas_solas.sql (bloque 2.15: D-58, D-59, D-63, D-66).
--
-- FALLA CERRADA. Antes de revertir exige que las dos puertas re-emitidas (`crm.crear_contrato_con_cuenta_pdf_v2` y
-- `crm.solicitud_inversion_fn`) tengan EXACTAMENTE la definición que dejó la migración (md5 de `prosrc` y de
-- `pg_get_functiondef`), su dueño, su ACL efectiva y el comentario que les puso; que las cuatro piezas (`private.solicitud_desechar`,
-- `private.solicitudes_desechar_por_contrato`, `private.solicitudes_desechar_ciclo`, `private.solicitud_cancelacion_vista`) tengan
-- EXACTAMENTE la definición y la ficha que dejó la migración (ronda 4; Codex r1, P2-5), que la tabla de corridas, las dos columnas
-- y sus CHECK tengan la forma exacta y el job su configuración; y que NINGUNA otra función ni vista nombre a las piezas ni lea la
-- tabla de corridas o las columnas nuevas (PL/pgSQL no registra esa dependencia: borrarlas rompería en silencio a quien las use).
-- Se niega si la migración no está aplicada o si alguien cambió algo después (p. ej. `ALTER FUNCTION … SET statement_timeout`,
-- una columna añadida a la tabla, un lector directo, el job cambiado): en esos casos NO se revierte nada y se revisa a mano.
-- (Ensayado con `armar-ensayo.mjs --reversa-con-set`, `--reversa-deriva` y, con cancelaciones y corridas reales, `--reversa-poblada`.)
--
-- QUÉ RESTAURA: el cuerpo anterior de las dos puertas, byte a byte (`md5(prosrc)` vuelve a 505598d6… y 0427b888…; las
-- definiciones a d0b33d8f… y 1c5867ea…) y sus comentarios anteriores; desprograma el job `crm-solicitudes-desechar`; borra las
-- cuatro piezas, la tabla `crm.solicitudes_desechadas_corridas` y las dos columnas (con sus CHECK). El postflight exige esas huellas,
-- la ficha de cada puerta idéntica a la previa (dueño, ACL, atributos), nada de lo nuevo presente y la FOTO de los
-- `private.assert_*()` sin argumentos y sin los `*_mutantes` idéntica a la de antes de revertir.
--
-- QUÉ CONSERVA: firma, dueño, `security definer`, `search_path` y ACL de las dos puertas (`create or replace` no los toca).
--
-- NO DESHACE DATOS: las solicitudes que el CRM canceló solo SIGUEN canceladas (son estado de negocio; nunca se «des-cancela»); al
-- borrar las columnas se pierde el motivo en la fila, pero queda en `public.audit_log` (el auditor guardó el antes y el después) y
-- las corridas quedan auditadas ahí mismo. Tras revertir, la app nueva sigue funcionando: las claves son opcionales.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $preflight$
declare
  v_alta constant text := 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)';
  v_consulta constant text := 'crm.solicitud_inversion_fn(uuid)';
  v_ficha text;
  v_foto text := '';
  v text;
  r record;
begin
  if to_regprocedure(v_alta) is null or to_regprocedure(v_consulta) is null then
    raise exception 'REVERSA solicitudes_desechadas_solas: falta una de las dos puertas; nada que revertir';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = v_alta::regprocedure) is distinct from '6ecd78e32f1b39dff4ee9827dc00c459'
     or (select md5(p.prosrc) from pg_proc p where p.oid = v_consulta::regprocedure) is distinct from 'ca715d075ca160afdff0257f190616dd' then
    raise exception 'REVERSA solicitudes_desechadas_solas: el cuerpo de una puerta no es el que dejó la migración (no está aplicada o cambió después): revisar antes de revertir';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_alta::regprocedure) is distinct from '9c2ff20faaf5a11190167c4621144676'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_consulta::regprocedure) is distinct from '1ad5589b98a7c60f76a886fe95a9c0cc' then
    raise exception 'REVERSA solicitudes_desechadas_solas: una puerta no tiene exactamente la definición que dejó la migración (un atributo cambió después sin tocar el cuerpo, p. ej. un SET statement_timeout): la reversa falla cerrada; revisar a mano antes de revertir';
  end if;
  for r in
    select * from (values
      (v_alta, 'postgres|true|v|u|search_path=""|authenticated:EXECUTE:false,postgres:EXECUTE:false',
       'Alta CRM atómica de contrato, cronograma, cuenta de pago y reserva documental v2. Bloque 2.15 (D-58, D-59): tras el alta, las solicitudes de inversión PREPARADAS de Avance que llevan el mismo número de contrato y no son la que lo creó se cancelan solas, con el motivo a la vista de su asesor (private.solicitudes_desechar_por_contrato); el rechazo de un disparador al cancelar no tumba el alta (subtransacción por solicitud).'),
      (v_consulta, 'postgres|true|v|u|search_path="";lock_timeout=5s|authenticated:EXECUTE:false,postgres:EXECUTE:false',
       'Consulta una solicitud de inversión. Autoriza con la solicitud como llave: en venta cruzada, su analista y su cadena; en cartera, la regla de siempre. Bloque 2.15: añade cancelacion_motivo, cancelacion_detalle y cancelacion_texto (nulos si el CRM no la canceló solo).')
    ) as h(firma, ficha, comentario)
  loop
    select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || p.proparallel::text
             || '|' || coalesce(array_to_string(p.proconfig, ';'), '-')
             || '|' || coalesce((select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text)
                                   from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a), '-')
      into v_ficha
      from pg_proc p where p.oid = to_regprocedure(r.firma);
    if v_ficha is distinct from r.ficha or obj_description(to_regprocedure(r.firma), 'pg_proc') is distinct from r.comentario then
      raise exception 'REVERSA solicitudes_desechadas_solas: el dueño, la ACL o el comentario de % no son los que dejó la migración: revisar antes de revertir', r.firma;
    end if;
  end loop;
  if to_regprocedure('private.solicitud_desechar(uuid,text,jsonb)') is null
     or to_regprocedure('private.solicitudes_desechar_por_contrato(uuid)') is null
     or to_regprocedure('private.solicitudes_desechar_ciclo(timestamp with time zone,integer,integer)') is null
     or to_regprocedure('private.solicitud_cancelacion_vista(uuid)') is null
     or to_regclass('crm.solicitudes_desechadas_corridas') is null
     or (select count(*) from pg_attribute a where a.attrelid = 'crm.inversion_solicitudes'::regclass and not a.attisdropped
          and a.attname in ('cancelacion_motivo', 'cancelacion_detalle')) <> 2 then
    raise exception 'REVERSA solicitudes_desechadas_solas: falta una pieza, la tabla de corridas o una de las dos columnas: la migración no está aplicada entera; revisar a mano';
  end if;
  -- Las cuatro piezas, EXACTAMENTE como las dejó la migración (ronda 4; Codex r1, P2-5): definición (md5 de pg_get_functiondef,
  -- que incluye SET, volatilidad, DEFINER…) y ficha (dueño, ACL, configuración). Si alguien las cambió después, se revisa a mano.
  for r in
    select * from (values
      ('private.solicitud_desechar(uuid,text,jsonb)', 'ae6326c1db6e18bafac11fc1bf02b36c', 'postgres|false|v|u|search_path=""|postgres:EXECUTE:false'),
      ('private.solicitudes_desechar_por_contrato(uuid)', '705f430f6875e5b0784fa37f21c97a92', 'postgres|false|v|u|search_path=""|postgres:EXECUTE:false'),
      ('private.solicitudes_desechar_ciclo(timestamp with time zone,integer,integer)', '42a2a6dac13f9f3f5f1f71e39bab8b4d', 'postgres|false|v|u|search_path="";lock_timeout=10s|postgres:EXECUTE:false'),
      ('private.solicitud_cancelacion_vista(uuid)', 'a4f98925760983763c45b854631e903a', 'postgres|false|s|u|search_path=""|postgres:EXECUTE:false')
    ) as h(firma, def, ficha)
  loop
    if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = to_regprocedure(r.firma)) is distinct from r.def then
      raise exception 'REVERSA solicitudes_desechadas_solas: la pieza % no tiene exactamente la definición que dejó la migración (cambió después, p. ej. un SET o el cuerpo): la reversa falla cerrada; revisar a mano antes de revertir', r.firma;
    end if;
    select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || p.proparallel::text
             || '|' || coalesce(array_to_string(p.proconfig, ';'), '-')
             || '|' || coalesce((select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text)
                                   from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a), '-')
      into v_ficha
      from pg_proc p where p.oid = to_regprocedure(r.firma);
    if v_ficha is distinct from r.ficha then
      raise exception 'REVERSA solicitudes_desechadas_solas: la ficha de la pieza % no es la que dejó la migración (medida «%»): revisar antes de revertir', r.firma, v_ficha;
    end if;
  end loop;
  -- La tabla de corridas con su FICHA COMPLETA (ronda 5; Codex r2, P2): dueño, RLS, ACL, columnas con tipo/nulabilidad/default,
  -- TODAS las restricciones, índices, disparadores (y si están habilitados), políticas, comentario de la tabla y de sus columnas.
  -- Medida en el VERDE del ensayo con la misma expresión; cualquier diferencia ⇒ la reversa se niega sin tocar nada.
  if (select 'dueno=' || c.relowner::regrole::text || '|rls=' || c.relrowsecurity::text || '/' || c.relforcerowsecurity::text || '|acl=' || coalesce(c.relacl::text, '-')
         || '|cols=' || coalesce((select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-'), ',' order by a.attnum)
                                    from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
                                   where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped), '-')
         || '|cons=' || coalesce((select string_agg(x.conname || ':' || pg_get_constraintdef(x.oid), ';' order by x.conname) from pg_constraint x where x.conrelid = c.oid), '-')
         || '|idx=' || coalesce((select string_agg(pg_get_indexdef(i.indexrelid), ';' order by i.indexrelid::regclass::text) from pg_index i where i.indrelid = c.oid), '-')
         || '|trg=' || coalesce((select string_agg(pg_get_triggerdef(t.oid) || '|' || t.tgenabled::text, ';' order by t.tgname) from pg_trigger t where t.tgrelid = c.oid and not t.tgisinternal), '-')
         || '|pol=' || coalesce((select string_agg(p.polname || ':' || p.polcmd::text || ':' || coalesce((select string_agg(rl.rolname, ',' order by rl.rolname) from pg_roles rl where rl.oid = any (p.polroles)), 'public')
                                                   || ':' || coalesce(pg_get_expr(p.polqual, p.polrelid), '-') || ':' || coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '-'), ';' order by p.polname)
                                    from pg_policy p where p.polrelid = c.oid), '-')
         || '|com=' || coalesce(obj_description(c.oid, 'pg_class'), '-')
         || '|colcom=' || coalesce((select string_agg(a.attname || ':' || coalesce(col_description(c.oid, a.attnum), '-'), ',' order by a.attnum)
                                      from pg_attribute a where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped), '-')
         from pg_class c where c.oid = 'crm.solicitudes_desechadas_corridas'::regclass)
     is distinct from $f$dueno=postgres|rls=true/false|acl={postgres=arwdDxtm/postgres}|cols=id:uuid:true:-,creado_en:timestamp with time zone:true:clock_timestamp(),corte:timestamp with time zone:true:-,dias:integer:true:-,limite:integer:true:-,canceladas_numero_usado:integer:true:-,canceladas_sin_movimiento:integer:true:-,omitidas:integer:true:-,rechazadas:integer:true:-,detalle:jsonb:true:-,duracion_ms:integer:true:-|cons=solicitudes_desechadas_corridas_canceladas_numero_usado_check:CHECK ((canceladas_numero_usado >= 0));solicitudes_desechadas_corridas_canceladas_sin_movimiento_check:CHECK ((canceladas_sin_movimiento >= 0));solicitudes_desechadas_corridas_detalle_check:CHECK ((jsonb_typeof(detalle) = 'array'::text));solicitudes_desechadas_corridas_dias_check:CHECK ((dias >= 1));solicitudes_desechadas_corridas_duracion_ms_check:CHECK ((duracion_ms >= 0));solicitudes_desechadas_corridas_limite_check:CHECK ((limite >= 1));solicitudes_desechadas_corridas_omitidas_check:CHECK ((omitidas >= 0));solicitudes_desechadas_corridas_pkey:PRIMARY KEY (id);solicitudes_desechadas_corridas_rechazadas_check:CHECK ((rechazadas >= 0));solicitudes_desechadas_corridas_tiempos_finitos:CHECK ((isfinite(creado_en) AND isfinite(corte)))|idx=CREATE UNIQUE INDEX solicitudes_desechadas_corridas_pkey ON crm.solicitudes_desechadas_corridas USING btree (id)|trg=CREATE TRIGGER trg_audit_solicitudes_desechadas_corridas AFTER INSERT OR DELETE OR UPDATE ON crm.solicitudes_desechadas_corridas FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm()|O|pol=-|com=Rastro de cada corrida de private.solicitudes_desechar_ciclo (bloque 2.15: el CRM cancela solo las solicitudes de inversión que ya no corresponden; D-58, D-59, D-63): cuántas canceló por número de contrato ya usado y por 30 días sin movimiento, cuántas omitió (guardas o fila ocupada) y cuántas rechazó un disparador, con el detalle por solicitud. Append-only; sin grants para la API; sin columna de empresa (CRM de una sola empresa, excepción documentada).|colcom=id:Identificador de la corrida; viaja en cancelacion_detalle.corrida_id de cada solicitud cancelada.,creado_en:Cuándo terminó la corrida.,corte:Instante de corte con el que se evaluó «sin movimiento» (p_corte).,dias:Días sin movimiento exigidos (30, D-63).,limite:Presupuesto de cancelaciones por corrida (200), compartido por las dos pasadas; las omitidas y rechazadas no lo consumen.,canceladas_numero_usado:Canceladas por número de contrato ya usado por otro contrato (pasada 1).,canceladas_sin_movimiento:Canceladas por 30 días sin confirmarse ni corregirse (pasada 2).,omitidas:Candidatas que no se tocaron: una guarda bajo el candado o fila ocupada por otra sesión.,rechazadas:Candidatas cuya cancelación rechazó un disparador de la tabla (quedaron como estaban).,detalle:Lista: por solicitud candidata, su id, el motivo evaluado y el resultado (cancelada | omitida: … | rechazada: …).,duracion_ms:Duración de la corrida en milisegundos.$f$ then
    raise exception 'REVERSA solicitudes_desechadas_solas: la tabla crm.solicitudes_desechadas_corridas no tiene la ficha que dejó la migración (restricción, valor por defecto, índice, disparador, política, dueño, RLS, ACL o comentario cambiados después): revisar a mano antes de revertir';
  end if;
  -- Las dos columnas nuevas de crm.inversion_solicitudes: tipo, nulabilidad, valor por defecto y comentario; y sus dos CHECK.
  if (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '-') || ':' || coalesce(col_description(a.attrelid, a.attnum), '-'), ',' order by a.attname)
        from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
       where a.attrelid = 'crm.inversion_solicitudes'::regclass and a.attnum > 0 and not a.attisdropped and a.attname in ('cancelacion_motivo', 'cancelacion_detalle'))
     is distinct from $f$cancelacion_detalle:jsonb:false:-:Detalle de la cancelación automática (objeto): via (alta | tarea), contrato_id y numero_contrato (con cuál), corrida_id (la corrida de la tarea), dias y ultimo_movimiento (sin movimiento), corte, cancelada_en. NULL si no la canceló el CRM.,cancelacion_motivo:text:false:-:Por qué la canceló el CRM solo (bloque 2.15; D-58, D-59, D-63): numero_contrato_usado (el número de contrato de la solicitud ya lo usa otro contrato) o sin_movimiento (30 días sin confirmarse ni corregirse). NULL en las cancelaciones de la pantalla (crm.cancelar_solicitud_inversion_fn). Solo con estado = cancelada.$f$
     or (select string_agg(c.conname || ':' || pg_get_constraintdef(c.oid), ';' order by c.conname) from pg_constraint c
          where c.conrelid = 'crm.inversion_solicitudes'::regclass and c.conname like 'inversion_solicitud_cancelacion_%')
     is distinct from $c$inversion_solicitud_cancelacion_coherente:CHECK ((((cancelacion_motivo IS NULL) AND (cancelacion_detalle IS NULL)) OR ((estado = 'cancelada'::text) AND (cancelacion_motivo IS NOT NULL) AND (cancelacion_detalle IS NOT NULL) AND (jsonb_typeof(cancelacion_detalle) = 'object'::text))));inversion_solicitud_cancelacion_motivo_valido:CHECK (((cancelacion_motivo IS NULL) OR (cancelacion_motivo = ANY (ARRAY['numero_contrato_usado'::text, 'sin_movimiento'::text]))))$c$ then
    raise exception 'REVERSA solicitudes_desechadas_solas: las columnas cancelacion_motivo/cancelacion_detalle no tienen la ficha que dejó la migración (tipo, nulabilidad, valor por defecto, CHECK o comentario cambiados después): revisar a mano antes de revertir';
  end if;
  -- El job, con la configuración que dejó la migración (si hay reloj y el job existe).
  if to_regclass('cron.job') is not null
     and exists (select 1 from cron.job j where j.jobname = 'crm-solicitudes-desechar')
     and not exists (select 1 from cron.job j where j.jobname = 'crm-solicitudes-desechar'
                       and j.schedule = '17 7 * * *' and j.command = 'select private.solicitudes_desechar_ciclo()' and j.active) then
    raise exception 'REVERSA solicitudes_desechadas_solas: el job crm-solicitudes-desechar no tiene la configuración que dejó la migración (horario, comando o activo cambiados después): revisar a mano antes de revertir';
  end if;
  -- Nadie más nombra a las piezas NI lee la tabla de corridas o las columnas nuevas (función fuera de las dos puertas y las
  -- propias piezas, o vista). PL/pgSQL no registra esa dependencia: borrarlas rompería en silencio a quien las use.
  if exists (
       select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
          and p.oid not in (to_regprocedure(v_alta), to_regprocedure(v_consulta),
                            to_regprocedure('private.solicitud_desechar(uuid,text,jsonb)'),
                            to_regprocedure('private.solicitudes_desechar_por_contrato(uuid)'),
                            to_regprocedure('private.solicitudes_desechar_ciclo(timestamp with time zone,integer,integer)'),
                            to_regprocedure('private.solicitud_cancelacion_vista(uuid)'))
          and (coalesce(p.prosrc, '') || ' ' || coalesce(pg_get_function_sqlbody(p.oid), ''))
              ~ '\m(solicitud_desechar|solicitudes_desechar_por_contrato|solicitudes_desechar_ciclo|solicitud_cancelacion_vista|solicitudes_desechadas_corridas|cancelacion_motivo|cancelacion_detalle)\M')
     or exists (
       select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
        where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema') and n.nspname not like 'pg_temp%'
          and pg_get_viewdef(c.oid) ~ '\m(solicitud_desechar|solicitudes_desechar_por_contrato|solicitudes_desechar_ciclo|solicitud_cancelacion_vista|solicitudes_desechadas_corridas|cancelacion_motivo|cancelacion_detalle)\M') then
    raise exception 'REVERSA solicitudes_desechadas_solas: otra función o vista nombra a las piezas o lee la tabla de corridas o las columnas nuevas: borrarlas la rompería; revisar antes de revertir';
  end if;
  perform set_config('crm.c215_reversa_alta_previa',
    (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = v_alta::regprocedure), true);
  perform set_config('crm.c215_reversa_consulta_previa',
    (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = v_consulta::regprocedure), true);
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  perform set_config('crm.c215_reversa_trinquetes_previos', v_foto, true);
end
$preflight$;

-- ── 1 · Las dos puertas, byte a byte como antes ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta_pdf_v2(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_contrato jsonb := p_contrato;
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
  v_clave_texto text := nullif(btrim(coalesce(p_contrato->>'clave_idempotencia', '')), '');
  v_clave uuid;
  v_huella text;
  v_huella_previa text;
  -- Rentabilidad R4 (D2): el contrato que amplía un UPGRADE. Viaja dentro de p_contrato igual que
  -- clave_idempotencia (es del transporte, no del contrato) y NO se le quita: la cadena de abajo solo lo lee en la
  -- rama de renovación, así que recibe exactamente lo que recibía.
  v_origen_upgrade text := nullif(btrim(coalesce(p_contrato->>'contrato_origen_id', '')), '');
begin
  perform private.inversiones_escritura_bajo_candado(); -- F4: bandera antes de persona/cuenta/PDF
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;

  -- El origen declarado se publica en un GUC TRANSACCIONAL para que el candado del servidor
  -- (private.trg_contratos_observar_rentabilidad, al commit) sepa de qué contrato hereda la tasa este upgrade. Va con
  -- el cliente delante para que no pueda aplicarse al contrato de otro, y se REESCRIBE en cada alta (también vacío)
  -- para que un alta posterior de la misma transacción no herede la declaración de la anterior.
  perform set_config(
    'crm.rentabilidad_origen_upgrade',
    case when p_contrato->>'categoria' = 'upgrade' and v_origen_upgrade is not null
         then coalesce(p_contrato->>'cliente_id', '') || '|' || v_origen_upgrade else '' end,
    true);

  -- IDEMPOTENCIA DEL ALTA (05/09/2026). El front manda una clave (uuid) por intento de
  -- formulario, la MISMA en cada reintento. Si este actor ya registró un alta con esa
  -- clave, se devuelve el MISMO contrato en vez de crear otro. Viaja DENTRO de
  -- p_contrato para no cambiar la firma del RPC; es del transporte, no del contrato:
  -- se quita antes de bajar a la cadena, que recibe EXACTAMENTE lo que recibía.
  -- Sin clave, nada cambia (los clientes que no la mandan siguen igual).
  if v_clave_texto is not null then
    begin
      v_clave := v_clave_texto::uuid;
    exception when invalid_text_representation then
      raise exception 'La clave de idempotencia del alta no es válida'
        using errcode = '22023';
    end;
    -- Dos envíos simultáneos con la misma clave del mismo actor (doble clic, dos
    -- pestañas) se serializan aquí: el segundo espera y lee el alta del primero.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'crm.alta_contrato_idempotente|' || v_actor_id::text || '|' || v_clave::text, 0
      )
    );
    -- La huella de LO QUE SE PIDE (sin la clave): la misma clave solo vale para la
    -- misma solicitud. jsonb::text es canónico (claves ordenadas), así que dos
    -- envíos iguales dan la misma huella.
    v_huella := md5(
      (p_contrato - 'clave_idempotencia')::text || '|'
      || coalesce(p_cronograma::text, '') || '|'
      || coalesce(p_cuenta::text, '')
    );
    select a.respuesta, a.contrato_id, a.huella
      into v_resultado, v_contrato_id, v_huella_previa
    from private.contrato_altas_idempotentes a
    where a.actor_id = v_actor_id and a.clave = v_clave;
    if found then
      -- El replay pasa por la MISMA autorización que el alta (Codex 05/09): una
      -- membresía revocada o un contrato fuera de cartera no recuperan nada.
      if not (select private.puede_registrar_ventas()) then
        raise insufficient_privilege using
          message = 'Cliente no encontrado o fuera de tu cartera';
      end if;
      -- Lápida: el contrato de este intento fue eliminado después (FK SET NULL).
      -- Un reintento tardío NO recrea lo que Gerencia borró a propósito.
      if v_contrato_id is null then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end if;
      -- Misma fila que bloquea la puerta de eliminación: replay y borrado se
      -- serializan. Si el contrato desaparece mientras esperamos, es lápida.
      begin
        perform private.bloquear_fila_contrato_pdf(v_contrato_id);
      exception when sqlstate 'P0002' then
        raise exception 'El contrato de este intento fue eliminado después; vuelve a registrar el alta'
          using errcode = 'P0409', hint = 'ALTA_ELIMINADA';
      end;
      -- Eliminación PREPARADA y aún no finalizada (Gerencia pulsó «Eliminar» y la edge todavía
      -- no borró): no se devuelve como «alta recuperada» un contrato que está a punto de
      -- desaparecer. La misma pregunta y el mismo 55000 que hace el alta
      -- (private.crear_job_contrato_pdf_base); la fila ya está bloqueada, así que la
      -- respuesta es estable hasta que esta transacción termine.
      if private.contrato_en_eliminacion(v_contrato_id) then
        raise exception 'El contrato está en proceso de eliminación'
          using errcode = '55000';
      end if;
      if not private.puede_leer_contrato_pdf_como(v_contrato_id, v_actor_id) then
        raise insufficient_privilege using
          message = 'Contrato no encontrado o fuera de tu cartera';
      end if;
      -- Misma clave pero OTROS datos (el analista editó el formulario tras un
      -- intento que SÍ creó el contrato): no se devuelve el viejo como si fuera
      -- el nuevo ni se crea otro. Se le dice la verdad, con el número.
      if v_huella_previa is distinct from v_huella then
        raise exception 'Este intento ya creó el contrato % con otros datos; no se creó otro. Revísalo antes de registrar uno nuevo',
          coalesce(v_resultado->>'numero_contrato', v_contrato_id::text)
          using errcode = 'P0409',
                hint = 'ALTA_YA_CREADA_CON_OTROS_DATOS',
                detail = jsonb_build_object(
                  'contrato_id', v_contrato_id,
                  'numero_contrato', v_resultado->>'numero_contrato'
                )::text;
      end if;
      -- El MISMO contrato, con el estado documental de HOY (la reserva pudo avanzar
      -- desde el primer intento) y la marca de que es un alta ya registrada.
      return (v_resultado - 'pdf')
        || jsonb_build_object('pdf', private.contrato_pdf_estado_base(v_contrato_id))
        || jsonb_build_object('idempotente', true);
    end if;
    v_contrato := p_contrato - 'clave_idempotencia';
  end if;

  -- El contrato, cronograma, cuenta, vínculo, snapshot y job se confirman o
  -- revierten juntos porque toda la cadena corre en esta transacción RPC.
  v_resultado := crm.crear_contrato_con_cuenta(
    v_contrato,
    p_cronograma,
    p_cuenta
  );
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end;
  if v_contrato_id is null then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end if;

  -- Dar de alta un contrato exige su cartera (P04) o ser la confirmación en curso de SU
  -- venta cruzada, sea cual sea su régimen documental: un contrato de régimen «anterior»
  -- no crea PDF y no llega a la compuerta de private.crear_job_contrato_pdf_base
  -- (segunda auditoría de la Fase 3, P1).
  if not private.puede_crear_contrato_pdf_como(v_contrato_id, v_actor_id) then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  if private.inversiones_escritura_bajo_candado() then
    perform private.inversion_cotitulares_vincular(
      (select id from crm.inversiones where contrato_id=v_contrato_id),'alta');
  end if;
  v_resultado := v_resultado || jsonb_build_object('pdf', v_pdf);
  if v_clave is not null then
    -- Misma transacción que el alta: o quedan los dos, o ninguno.
    insert into private.contrato_altas_idempotentes (actor_id, clave, contrato_id, huella, respuesta)
    values (v_actor_id, v_clave, v_contrato_id, v_huella, v_resultado);
  end if;
  return v_resultado;
end;
$function$;
comment on function crm.crear_contrato_con_cuenta_pdf_v2(jsonb, jsonb, jsonb) is
  'Alta CRM atómica de contrato, cronograma, cuenta de pago y reserva documental v2.';
CREATE OR REPLACE FUNCTION crm.solicitud_inversion_fn(p_solicitud uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare v_persona uuid; v_ctx jsonb; v_datos jsonb;
begin
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  v_ctx:=private.inversion_persona_autorizada_para(v_persona,p_solicitud,null::uuid);
  select datos into v_datos from crm.inversion_solicitudes where id=p_solicitud for share;
  return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||jsonb_build_object('datos',v_datos);
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;
comment on function crm.solicitud_inversion_fn(uuid) is
  'Consulta una solicitud de inversión. Autoriza con la solicitud como llave: en venta cruzada, su analista y su cadena; en cartera, la regla de siempre.';

-- ── 2 · El reloj, las piezas, la tabla y las columnas ───────────────────────────────────────────────────────────────────────
do $reloj$
begin
  if to_regclass('cron.job') is not null and to_regprocedure('cron.unschedule(text)') is not null then
    if exists (select 1 from cron.job j where j.jobname = 'crm-solicitudes-desechar') then
      perform cron.unschedule('crm-solicitudes-desechar');
    end if;
  end if;
end;
$reloj$;
drop function private.solicitudes_desechar_ciclo(timestamptz, integer, integer);
drop function private.solicitudes_desechar_por_contrato(uuid);
drop function private.solicitud_desechar(uuid, text, jsonb);
drop function private.solicitud_cancelacion_vista(uuid);
drop table crm.solicitudes_desechadas_corridas;
alter table crm.inversion_solicitudes
  drop constraint inversion_solicitud_cancelacion_coherente,
  drop constraint inversion_solicitud_cancelacion_motivo_valido,
  drop column cancelacion_motivo,
  drop column cancelacion_detalle;

-- ── 3 · Postflight ──────────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_alta constant text := 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)';
  v_consulta constant text := 'crm.solicitud_inversion_fn(uuid)';
  v_foto text := '';
  v text;
  r record;
begin
  if (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_alta::regprocedure)
       is distinct from '505598d6fef7ea585a965f925a8eb9fb|d0b33d8fb1d27ef2da62105b7ccabd88'
     or (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_consulta::regprocedure)
       is distinct from '0427b888c4a0c4082831e42244c2e0e1|1c5867eaed3a1ea89b2b4626e2c9385e' then
    raise exception 'REVERSA solicitudes_desechadas_solas: una puerta no volvió a su cuerpo original';
  end if;
  if (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = v_alta::regprocedure) is distinct from current_setting('crm.c215_reversa_alta_previa', true)
     or (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = v_consulta::regprocedure) is distinct from current_setting('crm.c215_reversa_consulta_previa', true) then
    raise exception 'REVERSA solicitudes_desechadas_solas: cambió el dueño, la ACL o un atributo de una puerta al revertir';
  end if;
  if obj_description(v_alta::regprocedure, 'pg_proc') is distinct from 'Alta CRM atómica de contrato, cronograma, cuenta de pago y reserva documental v2.'
     or obj_description(v_consulta::regprocedure, 'pg_proc') is distinct from 'Consulta una solicitud de inversión. Autoriza con la solicitud como llave: en venta cruzada, su analista y su cadena; en cartera, la regla de siempre.' then
    raise exception 'REVERSA solicitudes_desechadas_solas: los comentarios no volvieron a los anteriores';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'private'::regnamespace
              and p.proname in ('solicitud_desechar', 'solicitudes_desechar_por_contrato', 'solicitudes_desechar_ciclo', 'solicitud_cancelacion_vista'))
     or to_regclass('crm.solicitudes_desechadas_corridas') is not null
     or exists (select 1 from pg_attribute a where a.attrelid = 'crm.inversion_solicitudes'::regclass and not a.attisdropped
                 and a.attname in ('cancelacion_motivo', 'cancelacion_detalle')) then
    raise exception 'REVERSA solicitudes_desechadas_solas: quedó una pieza, la tabla o una columna';
  end if;
  if to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job where jobname = 'crm-solicitudes-desechar') then
      raise exception 'REVERSA solicitudes_desechadas_solas: quedó el job';
    end if;
  end if;
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  if v_foto is distinct from current_setting('crm.c215_reversa_trinquetes_previos', true) then
    raise exception E'REVERSA solicitudes_desechadas_solas: algún private.assert_*() da otro resultado que antes de revertir.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('crm.c215_reversa_trinquetes_previos', true), v_foto;
  end if;
  raise notice 'REVERSA solicitudes_desechadas_solas OK: puertas 505598d6… y 0427b888… (comentarios anteriores), sin piezas, tabla, columnas ni job; trinquetes idénticos. Las cancelaciones hechas se conservan.';
end
$postflight$;
commit;

-- REGISTRO en supabase_migrations.schema_migrations de 20261004123611_crm_base_gestion_reservar_nota_veto.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Generado con banco/generar-registrador.py. statements = el archivo entero (md5 abd20c567aaa1291bb6ec9fb3155789f).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_base_gestion_reservar_nota_veto_registro'));
do $chk$
begin
  if (
    to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()') is not null
    and (select t.oid from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_no_contactar_solo_puerta') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261004123611 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261004123611' and (coalesce(name, '') <> 'crm_base_gestion_reservar_nota_veto' or statements is distinct from array[$mig$-- 20261004123611_crm_base_gestion_reservar_nota_veto.sql
--
-- Base para gestión del analista · B6c: la nota del veto queda reservada a sus puertas, e inmutable. Decisión de Miguel
-- (04/10/2026, `BASE PARA GESTION/F4-SUPERVISOR.md`, P2b del auditor-rls de B6b): B6b salió con el riesgo escrito y «justo
-- después una migración pequeña (B6c) reserva `metadata.evento='no_contactar'` para las puertas oficiales».
-- r1 (04/10): Codex r1 BLOCK (P2 interbloqueo al desplegar, P3 avisos) + auditor-rls PASS con P3 (inmutable, variantes,
-- interbloqueo, exenciones documentadas).
--
-- POR QUÉ. B6b (20261004045038) muestra a Supervisión y Gerencia la «marca vigente» del veto (cuándo, motivo, quién) leyendo
--   la ÚLTIMA nota de crm.actividades con metadata evento = no_contactar. Hoy esa nota se puede escribir desde la API:
--   la policy `actividades_insert` (20260807123000:85-115) deja insertar en un lead propio o del ámbito con cualquier
--   metadata, y `trg_01_gestion_lead_serializada` solo frena el seguimiento de una persona vetada para los tipos de
--   CONTACTO (20260904130000:1082-1088), no una 'nota'. Quien escribe en un lead podía «firmar» una marca falsa (o un
--   «levantar» que la ocultara) con él como autor. Medido en el banco: authenticated tiene INSERT y SELECT en
--   crm.actividades (sin UPDATE ni DELETE, ni grant ni policy): el único camino de la API es el INSERT.
--
-- QUÉ:
--   1. NUEVO sello `trg_00_actividades_no_contactar_solo_puerta` (BEFORE INSERT OR UPDATE OR DELETE ON crm.actividades,
--      por fila) con `private.trg_actividades_no_contactar_solo_puerta()`. Con una sesión que tenga usuario y sin la
--      válvula de transacción `crm.op_privilegiada = on` → 42501:
--        · INSERT de una fila cuyo evento es el del veto;
--        · UPDATE (de CUALQUIER columna) de una fila que es o pasa a ser nota del veto (auditor-rls r1, P3: inmutables);
--        · DELETE de una nota del veto.
--      «Evento del veto» = lower(btrim(metadata->>'evento')) = 'no_contactar' (auditor-rls r1, P3: también 'No_Contactar' o
--      ' no_contactar '; B6b solo lee la forma exacta, pero ninguna variante entra por la API).
--      Exentos: la válvula `crm.op_privilegiada = on` (la que ya ponen las tres puertas del veto) y las sesiones sin
--      usuario (`auth.uid()` nulo: migraciones, backfills, jobs internos y la clave de servicio SIN sub). Esa exención de
--      service_role sin sub es ACEPTADA, igual que en los sellos vecinos: la clave de servicio es del servidor.
--      Mismo molde que los dos sellos vecinos de crm.actividades — `trg_actividades_resultado_solo_nucleo`
--      (20260920005000:211-249, válvula crm.op_resultado_llamada) y `trg_actividades_base_gestion_solo_nucleo`
--      (20261002231436:126-148, válvula crm.op_base_gestion) — y de `trg_leads_no_contactar_solo_puerta`, que ya reserva
--      la columna leads.no_contactar a estas puertas con la misma válvula (20260903240000:208-231). Función PROPIA y no
--      una rama más en un vecino: cada sello va con SU válvula; el del resultado está sellado por huella en
--      `private.assert_gestion_diaria_resultado` (tocarlo rompe ese trinquete) y el de la base es de otra familia
--      (crm.op_base_gestion). La lista de lo reservado para el veto vive en UNA sola definición: esta función.
--      Sin bandera: la reserva vale siempre (con resolver_en_puertas apagada las puertas también escriben con la válvula).
--      NO acredita las notas del veto escritas ANTES de instalarse: una nota forjada antes de B6c sigue en el historial.
--   2. `crm.levantar_no_contactar(uuid, text)`: create or replace con el texto VIVO de B2 (20261002061500:55-245, md5
--      prosrc 05df49be…) y UN solo cambio: el `set_config('crm.op_privilegiada', 'off', true)` pasa de ANTES del insert
--      de su nota (20261002061500:233) a justo DESPUÉS (como marcar). Sin eso, el sello rechazaría su propia nota.
--      Firma, dueño, ACL y todo lo demás, byte a byte. Su comentario suma una frase B6c.
--   3. Comentario (solo texto; el cuerpo no se toca, md5 36af7e9c…) de `crm.obtener_base_gestion(uuid, boolean)`: la nota
--      ya está reservada (no acredita las anteriores) y queda escrito el residuo P3 del auditor-rls de B6b: la función no
--      lee la bandera resolver_en_puertas (encendida desde el 07/09/2026).
--
-- ESCRITORES de la nota (grep del repo y `pg_proc` del banco, 04/10): solo tres cuerpos construyen
--   jsonb_build_object('evento', 'no_contactar', …), y los tres escriben con la válvula puesta:
--   · crm.marcar_no_contactar — 20260910150039:976 (on), :1016 (insert), :1023 (off); md5 prosrc vivo 6cd5678e…. NO se toca
--     (sellada por huella en private.assert_gestion_diaria_resultado).
--   · crm.postventa_veto_fn — 20260910150039:488 (on), :511 (insert en todos los leads de la persona), :516 (restaura), con
--     el bloque exterior PT409 que le puso 20260910190000 (mismo orden); md5 prosrc vivo c67d516b…. NO se toca.
--   · crm.levantar_no_contactar — 20261002061500:213 (on), :233 (off), :235 (insert) → este es el que se corrige.
--   Ningún backfill, fusión, importador, seed ni el front escriben esa nota (el front inserta notas sin metadata,
--   app/src/lib/store.tsx:2736). El preflight exige que siga habiendo solo esos tres en la base.
--   Otras puertas que encienden crm.op_privilegiada y escriben en crm.actividades (conversión, cierres externos, fusión,
--   corrección de documento, enlace, reasignación de responsable, inversión revisada, abandono de conversión) construyen su
--   metadata en el servidor con claves fijas: ninguna deja al cliente poner evento = no_contactar bajo la válvula.
-- QUIÉN CAMBIA O BORRA actividades (para la inmutabilidad; `pg_proc` del banco, 04/10): solo cuatro funciones hacen UPDATE y
--   ninguna DELETE, y ninguna puede caer sobre una nota del veto:
--   · private.base_gestion_intento_core — UPDATE de la fila que ella misma acaba de insertar con id = p_operacion_id
--     (20261003162300:199; el replay sale antes);
--   · private.llamada_registrar / private.llamada_registrar_v4 — UPDATE de su propia actividad de llamada (id =
--     p_operacion_id recién creado por registrar_actividad_v2, o el actividad_id que devuelve cerrar_tarea_v2)
--     (20260921153654:264/315);
--   · crm.deshacer_resultado_llamada — UPDATE solo si la actividad es evento = resultado_llamada (20260920005000:654).
--   Acciones referenciales: el lead se borra en CASCADA (actividades_lead_id_fkey), pero un lead con dueño no se puede
--   borrar (lead_asignaciones_lead_id_fkey, ledger append-only; probado en el banco) y ninguna función borra crm.leads; el
--   autor pasa a NULL al borrar su perfil (actividades_creado_por_fkey SET NULL), pero crm.eliminar_usuario_fn solo borra
--   auth.users si private.usuario_tiene_historial es falso (cuenta TODA FK al perfil, también actividades.creado_por:
--   20260925180145) y crm.eliminar_cliente_fn exige auth.uid() nulo. Si algún día una sesión con usuario hiciera una de
--   esas acciones sobre una nota del veto sin la válvula, el sello la rechaza (42501): es la regla, no un efecto lateral.
--   El preflight exige que sigan siendo solo esas cuatro las que hacen UPDATE/DELETE de crm.actividades.
--
-- DESPLIEGUE (Codex r1, P2): `CREATE TRIGGER` deja SHARE ROW EXCLUSIVE sobre crm.actividades hasta el commit. Esta migración
--   NO hace DML: su postflight es SOLO de catálogo (md5, contrato, ACL, forma del trigger, comentarios, censo). La r0 insertaba
--   notas de prueba (que bloquean el lead por trg_01_gestion_lead_serializada) con ese candado puesto: una llamada
--   concurrente a marcar_no_contactar (bloquea el lead y luego inserta en actividades) cerraba un ciclo → 40P01 (reproducido
--   en el banco con dos sesiones). El trigger se crea al FINAL, para tener el candado el menor tiempo posible. La prueba de
--   comportamiento (la API no escribe la nota; nota normal, válvula y sin usuario sí) va aparte, DESPUÉS del commit:
--   `supabase/scripts/base-gestion/b6c-comprobar-tras-aplicar.sql` (termina siempre en ROLLBACK).
-- AISLAMIENTO: READ COMMITTED explícito, sin REPEATABLE READ (a diferencia de B6b): no hay foto de DATOS que comparar
--   con una lectura posterior (el censo es catálogo).
-- QUÉ NO CAMBIA: RLS, policies y grants de crm.actividades; marcar y postventa; el cuerpo de obtener_base_gestion; los
--   otros sellos. Para un usuario solo cambia que su INSERT de una nota con evento del veto falla con 42501.
-- PRECONDICIÓN: B6b aplicada (cuerpo y comentario de obtener_base_gestion), levantar en el texto de B2, marcar y
--   postventa con los cuerpos medidos (md5 en el preflight).
-- REVERSA: `supabase/scripts/base-gestion/reversa-b6c.sql` (borra el sello, reinstala levantar de B2 y el comentario de
--   B6b, exactos). Antes que la de B6b. No toca datos.
begin;
set transaction isolation level read committed;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    -- levantar: el texto vivo de B2 (md5 prosrc 05df49be…), DEFINER de postgres, search_path vacío, ACL exacta, una sola
    -- sobrecarga y el comentario de B2.
    (select md5(p.prosrc) = '05df49be43869cd8e5f75330fa592a84'
        and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]
        and p.proacl is not null and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
        and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '5325ff9e4d60af5816bc20aa899e4dd1'
       from pg_proc p where p.oid = to_regprocedure('crm.levantar_no_contactar(uuid,text)'))
    and (select count(*) = 1 from pg_proc p where p.proname = 'levantar_no_contactar' and p.pronamespace = 'crm'::regnamespace)
    -- marcar y postventa: los cuerpos medidos, que escriben su nota CON la válvula puesta.
    and (select md5(p.prosrc) = '6cd5678eed537dc880c5ce4447165d30' and p.prosecdef
       from pg_proc p where p.oid = to_regprocedure('crm.marcar_no_contactar(uuid,text)'))
    and (select md5(p.prosrc) = 'c67d516bcd37562a93af6a1a8b4629f7' and p.prosecdef
       from pg_proc p where p.oid = to_regprocedure('crm.postventa_veto_fn(uuid,uuid,boolean,text,uuid)'))
    -- Ningún OTRO cuerpo construye la nota (si apareciera uno, el sello podría romperlo: se revisa antes).
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema')
                       and p.prosrc ~* '''evento''\s*,\s*''no_contactar''|"evento"\s*:\s*"no_contactar"'
                       and p.oid not in (coalesce(to_regprocedure('crm.marcar_no_contactar(uuid,text)')::oid, 0),
                                         coalesce(to_regprocedure('crm.levantar_no_contactar(uuid,text)')::oid, 0),
                                         coalesce(to_regprocedure('crm.postventa_veto_fn(uuid,uuid,boolean,text,uuid)')::oid, 0)))
    -- Ninguna OTRA función cambia o borra actividades (la nota del veto pasa a ser inmutable: se revisa antes).
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema')
                       and p.prosrc ~* 'update\s+crm\.actividades|delete\s+from\s+crm\.actividades'
                       and p.oid not in (coalesce(to_regprocedure('crm.deshacer_resultado_llamada(uuid)')::oid, 0),
                                         coalesce(to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)')::oid, 0),
                                         coalesce(to_regprocedure('private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)')::oid, 0),
                                         coalesce(to_regprocedure('private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)')::oid, 0)))
    -- obtener_base_gestion: el cuerpo de B6b y su comentario EXACTO (solo cambia el comentario).
    and (select md5(p.prosrc) = '36af7e9cc4d6ec319b3d8004f3903473'
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '469119616ab78df3eba406c7622d3888'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
    -- El sello no existe todavía.
    and to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()') is null
    and not exists (select 1 from pg_trigger t
                     where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_no_contactar_solo_puerta')
    -- Nadie enciende la válvula por configuración de rol o de base (abriría la reserva a todo el mundo).
    and not exists (select 1 from pg_catalog.pg_db_role_setting s cross join lateral pg_catalog.unnest(s.setconfig) c(x)
                     where c.x ilike 'crm.op_privilegiada=%')
  ) is not true then
    raise exception 'PREFLIGHT B6c: levantar no es el texto de B2, marcar/postventa no son los medidos, hay otro escritor de la nota del veto u otra funcion que cambia actividades, obtener_base_gestion no es la de B6b, el sello ya existe o la valvula se enciende por configuracion';
  end if;
end;
$preflight$;

-- Foto del censo analítico: el postflight exige que no cambie.
create temp table _b6c_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- ── 1. levantar_no_contactar: su nota, ANTES de apagar la válvula (texto vivo de B2 con ese único cambio) ──
create or replace function crm.levantar_no_contactar(p_lead_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean;
  v_dni_suelto text;
  v_suelto boolean := false;  -- F2.b (b2)
  v_puente boolean := false;  -- F2.b [D-3]: la persona se resolvió por el PUENTE (lead histórico sin DNI ni enlace)
  v_leads  uuid[];            -- F2.b [D-3]: enlace vivo ∪ puente ∪ sueltos con su documento, más el propio lead
  v_docs   text[];            -- F2.b [D-3]: documentos vigentes de la persona, bloqueados ANTES que ella (tipo:documento)
  v_perfiles uuid[] := array[]::uuid[];  -- F2.b [D-3]: perfiles cliente de la persona (enlazado o con su documento): tareas de cliente
begin
  -- B2 · Base para gestión (D5, Miguel 02/10/2026): Gerencia o Supervisión. Supervisión solo dentro de su ámbito y
  -- solo si TODA la persona (sus leads) cae en su equipo; si no, lo pide a Gerencia. `v_rol is null` también rechaza.
  if v_uid is null or v_rol is null or v_rol not in ('supervisor', 'gerencia') then
    raise exception 'Solo Gerencia o Supervisión pueden levantar No contactar' using errcode = '42501';
  end if;
  if p_motivo is null or pg_catalog.btrim(p_motivo) = '' then
    raise exception 'Levantar No contactar exige un motivo' using errcode = '22023';
  end if;
  -- Ámbito ANTES de resolver la identidad o tomar candados (el espejo de la policy leads_select, sin la rama de gerencia).
  if v_rol = 'supervisor' and not exists (
       select 1 from crm.leads l
        where l.id = p_lead_id
          and l.activo
          and (l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
               or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  -- F2.b [D-17] (Codex, 3.ª ronda del bloque 4): la bandera se lee con READ COMMITTED y bajo el candado
  -- COMPARTIDO por bandera; el UPDATE de crm.multiempresa_flags toma el EXCLUSIVO en su trigger (D-5).
  -- Así una llamada que entró APAGADA termina apagada aunque espere por una fila, y una que entra después
  -- del encendido lo ve: sin esto, una llamada en vuelo podía escribir con la bandera cambiada a medias.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'), false);

  -- ORDEN: identidad PRIMERO, luego leads.
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_flag and v_inv is null then
    -- F2.b [D-3] (Codex #7): un lead que solo está en el PUENTE (histórico sin DNI ni enlace vivo) también es de su
    -- persona: se resuelve por el puente (canónica) antes de intentar el documento. El puente solo cambia bajo el lock
    -- de la persona (fusión), que se toma más abajo y se revalida tras bloquear el lead.
    select private.inversionista_canonica(il.inversionista_id) into v_inv
    from crm.inversionista_leads il
    where il.lead_id = p_lead_id
    order by (il.rol = 'canonico') desc, il.inversionista_id
    limit 1;
    v_puente := v_inv is not null;
  end if;
  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
    select l.dni into v_dni_suelto from crm.leads l where l.id = p_lead_id;
    perform private.identidad_bloquear_documento('DNI', v_dni_suelto);
    v_inv := private.inversionista_por_documento('DNI', v_dni_suelto);
    v_suelto := v_inv is not null;
  end if;
  if v_inv is not null then
    -- F2.b [D-3] (auditor M1): DOCUMENTO → PERSONA, el orden del nacimiento (b1), la puerta del DNI (D-13) y la fusión (b5):
    -- se bloquean los documentos vigentes de la persona (en orden de texto) ANTES de bloquearla, y se releen después;
    -- así la puerta del DNI (que solo bloquea documentos y a la persona NUEVA) no puede llevarse un suelto a otra persona
    -- mientras el veto se propaga. Si el juego de documentos cambió mientras se esperaba → 40001.
    v_docs := private.identidad_bloquear_documentos_de(array[v_inv]);
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- La relectura es una LECTURA PURA (Codex N3): no vuelve a tomar candados con la persona ya bloqueada (documento → persona).
    if (select coalesce(pg_catalog.array_agg(s.k order by s.k), '{}'::text[])
          from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
                  from crm.inversionista_identificadores d
                 where d.inversionista_id = v_inv and d.estado = 'vigente') s) is distinct from v_docs then
      raise exception 'Los documentos de la persona cambiaron mientras se marcaba; vuelve a intentarlo'
        using errcode = '40001';
    end if;
    -- F2.b [D-3] (Codex #12): el motivo no lleva NINGÚN documento de la persona (vigentes ni históricos; la regla documental
    -- de las puertas de b5, sin imponer aquí su largo mínimo: el motivo de marcar es opcional).
    if p_motivo is not null and exists (
         select 1 from crm.inversionista_identificadores d
          where d.inversionista_id = v_inv
            and pg_catalog.length(d.documento_normalizado) >= 6
            and pg_catalog.strpos(pg_catalog.upper(pg_catalog.regexp_replace(p_motivo, '[^A-Za-z0-9]', '', 'g')), d.documento_normalizado) > 0) then
      raise exception 'El motivo no debe contener el número de documento' using errcode = '22023';
    end if;
  end if;
  -- F2.b [D-3]: bajo los locks de documentos y persona, «sus leads» = enlace vivo ∪ puente ∪ sueltos con su documento
  -- verificado (private.leads_de_persona_veto) más el propio lead; y sus perfiles cliente (el enlazado a la identidad o
  -- el que lleva su documento exacto, como persona_vetada_perfil) para las tareas de cliente. Estable hasta el commit.
  if v_inv is not null then
    v_leads := array(select x from private.leads_de_persona_veto(v_inv) x union select p_lead_id order by 1);
    v_perfiles := array(
      select i.perfil_id from crm.inversionistas i where i.id = v_inv and i.perfil_id is not null
      union
      select p.id from public.perfiles p
       where p.rol = 'cliente'
         and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
         and (coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') || ':' || pg_catalog.upper(pg_catalog.regexp_replace(p.dni, '[^A-Za-z0-9]', '', 'g'))) = any(v_docs)
      order by 1);
  else
    v_leads := array[p_lead_id];
  end if;
  -- F2.b [D-3] (Codex #1): tareas → leads es el orden de b2 y de cerrar_tarea; derivar y repartir van al revés (lead →
  -- tareas por el trigger de sincronización). Como la fusión (b5, E3-9): los leads se toman SIN esperar; si otra sesión
  -- tiene uno, 40001 y el front reintenta. Solo con la bandera (con OFF no hay tareas bloqueadas: el propio lead se toma como hoy).
  if v_flag then
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
  end if;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;
  -- B2 (D5): bajo candado, el ámbito se revalida y se exige para TODOS los leads de la persona que se van a tocar.
  -- Las dos comprobaciones van con `is not true`: un lead sin vendedor cuyo supervisor no está en el ámbito da NULL
  -- (NULL in (...)) y un `not NULL` dejaría pasar (Codex B1+B2, P1). Fail-closed también ante NULL.
  if v_rol = 'supervisor' then
    if (v_lead.activo
        and (v_lead.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
             or (v_lead.vendedor_id is null and v_lead.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) is not true then
      raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
    end if;
    if exists (select 1 from crm.leads l
                where l.id = any(v_leads)
                  and (l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
                       or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))) is not true) then
      raise exception 'La persona tiene leads fuera de tu equipo: pídelo a Gerencia' using errcode = '42501';
    end if;
  end if;
  if v_flag and not v_suelto and not v_puente and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_puente
     and (v_lead.inversionista_id is not null
          or not exists (select 1 from crm.inversionista_leads il
                         where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) = v_inv)) then
    raise exception 'El puente del lead cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_suelto
     and (v_lead.inversionista_id is not null
          or private.inversionista_por_documento('DNI', v_lead.dni) is distinct from v_inv) then
    raise exception 'El documento del lead cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_inv is not null then
    update crm.inversionistas
       set no_contactar = false, no_contactar_en = null, no_contactar_por = null
     where id = v_inv and no_contactar = true;
    for v_lead in
      select * from crm.leads where id = any(v_leads) order by id for update  -- F2.b [D-3]: enlace ∪ puente ∪ sueltos
    loop
      if v_lead.no_contactar then
        update crm.leads set no_contactar = false where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;
    -- F2.b (b2): el propio lead suelto también.
    update crm.leads set no_contactar = false where id = p_lead_id and no_contactar = true;
    if found then v_n := v_n + 1; end if;
  else
    update crm.leads set no_contactar = false where id = p_lead_id and no_contactar = true;
    get diagnostics v_n = row_count;
  end if;

  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (p_lead_id, 'nota', 'Levantado No contactar por ' || case when v_rol = 'gerencia' then 'Gerencia' else 'Supervisión' end,
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'levantar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', pg_catalog.btrim(p_motivo), 'rol', v_rol),
          v_uid);
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$function$;
alter function crm.levantar_no_contactar(uuid, text) owner to postgres;
revoke all on function crm.levantar_no_contactar(uuid, text) from public, anon, authenticated, service_role;
grant execute on function crm.levantar_no_contactar(uuid, text) to authenticated;
comment on function crm.levantar_no_contactar(uuid, text) is
  'Levanta No contactar (Ley 29571) de la persona del lead y de todos sus leads. Gerencia en toda la operación; Supervisión (B2, D5 02/10/2026) solo si el lead y TODOS los leads de la persona están en su equipo (si no, 42501: pídelo a Gerencia). Motivo obligatorio; queda en el historial con el rol. DEFINER: compone la identidad y escribe bajo crm.op_privilegiada; search_path vacío, dueño postgres, EXECUTE solo authenticated. B6c (04/10/2026): escribe su nota (metadata evento = no_contactar, accion = levantar) ANTES de apagar crm.op_privilegiada, porque esa nota quedó reservada a las puertas del veto (private.trg_actividades_no_contactar_solo_puerta).';

-- ── 2. El comentario de la base (solo texto) ───────────────────────────────────────────────────────────────
comment on function crm.obtener_base_gestion(uuid, boolean) is 'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente (salvo p_incluir_vetados, ver B6b), con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico. B5 (03/10/2026): devuelve al final recibido_en = coalesce(tenencia_desde, creado_en), cuándo le llegó el lead a quien lo tiene: el MES por el que se organiza el analista. B6b (03/10/2026, F4): p_incluir_vetados (default false; null = false) suma los leads «No contactar» del ámbito, también los que están en descanso; solo Supervisión y Gerencia (otro rol → 42501). Los vetados van al final y nunca en «Llamar hoy» (rellamada_hoy = false). Columnas finales no_contactar, no_contactar_en, no_contactar_motivo y no_contactar_por (nombre del autor): de la nota del evento vigente del veto — si la persona del lead (enlace, puente o DNI, como en marcar/levantar) está vetada, la última nota del veto entre los leads de la persona (private.leads_de_persona_veto ∪ el propio lead); si no, la del propio lead — solo si es un «marcar» (también el de postventa, motivo en el detalle) y su lead es visible para quien llama; si no, NULL. Residuo: empate exacto de clock_timestamp, desempate por id. B6c (04/10/2026, decisión de Miguel): la nota del veto (metadata evento = no_contactar) solo la escriben sus puertas (marcar_no_contactar, levantar_no_contactar y postventa_veto_fn, bajo crm.op_privilegiada; trigger trg_00_actividades_no_contactar_solo_puerta en crm.actividades): desde la API ya no se puede firmar el motivo, el autor ni la fecha de la marca, y la nota ya escrita no se cambia ni se borra. No acredita las notas anteriores a B6c (04/10/2026). Residuo (auditor-rls B6b, P3): esta función no lee la bandera resolver_en_puertas (encendida desde el 07/09/2026) y resuelve siempre la persona como las puertas con la bandera encendida; si se apagara, las puertas actuarían solo sobre el lead y la marca de un lead cuya persona siga vetada podría salir NULL o venir de otro lead de la persona (nunca de uno fuera del ámbito de quien llama). Con false, el resultado es el de B5. Envoltorios DEFINER en la base: crm.base_gestion_resumen y crm.base_gestion_resumen_detalle (re-auditarlos si cambia leads_select).';

-- ── 3. El sello (al final: CREATE TRIGGER deja SHARE ROW EXCLUSIVE sobre crm.actividades hasta el commit) ──
create function private.trg_actividades_no_contactar_solo_puerta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_exento boolean := false;
  v_veto boolean := false;
begin
  -- B6c: la nota del veto (metadata evento = no_contactar) es la fuente de la marca que la base para gestión muestra a
  -- Supervisión y Gerencia (cuándo, motivo, quién). Solo la escriben sus puertas, bajo la válvula de transacción
  -- crm.op_privilegiada = on (marcar_no_contactar, levantar_no_contactar y postventa_veto_fn), y no se cambia ni se borra.
  if (select auth.uid()) is null then
    v_exento := true;  -- sin usuario (migraciones, backfills, service_role sin sub), como los otros sellos de crm.actividades
  elsif coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off') = 'on' then
    v_exento := true;  -- la válvula de las puertas del veto
  end if;
  if not v_exento then
    if tg_op <> 'DELETE' then
      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(new.metadata->>'evento', ''), E' \t\r\n')) = 'no_contactar';
    end if;
    if tg_op <> 'INSERT' and not v_veto then
      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(old.metadata->>'evento', ''), E' \t\r\n')) = 'no_contactar';
    end if;
    if v_veto then
      raise exception 'La nota de No contactar solo la escriben sus puertas (marcar, levantar o postventa); no se cambia ni se borra'
        using errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;
alter function private.trg_actividades_no_contactar_solo_puerta() owner to postgres;
revoke all on function private.trg_actividades_no_contactar_solo_puerta() from public, anon, authenticated, service_role;
comment on function private.trg_actividades_no_contactar_solo_puerta() is
  'Base para gestión (B6c, 04/10/2026): reserva en crm.actividades la nota del veto — evento lower(btrim(metadata->>''evento'')) = ''no_contactar'' — para sus puertas (crm.marcar_no_contactar, crm.levantar_no_contactar y crm.postventa_veto_fn, que escriben bajo la válvula de transacción crm.op_privilegiada = on) y la hace inmutable: con una sesión con usuario y sin la válvula, INSERT de una nota del veto, UPDATE de cualquier columna de una fila que es o pasa a ser nota del veto y DELETE de una nota del veto → 42501. Exentas las sesiones sin usuario (migraciones, backfills, jobs y la clave de servicio SIN sub: exención aceptada, como en los sellos vecinos). Evita que quien escribe en un lead firme u oculte la marca vigente (motivo, autor, fecha) que crm.obtener_base_gestion muestra a Supervisión y Gerencia. No acredita las notas escritas antes de su instalación. Acciones referenciales: el borrado en cascada de un lead o el SET NULL del autor sobre una nota del veto también pasan por aquí (hoy ningún camino con usuario las dispara: un lead con dueño no se borra y eliminar_usuario_fn solo borra usuarios sin historial). Mismo molde que trg_actividades_resultado_solo_nucleo y trg_actividades_base_gestion_solo_nucleo (cada sello con su válvula) y que trg_leads_no_contactar_solo_puerta (misma válvula, sobre leads.no_contactar). Vale siempre, sin mirar la bandera resolver_en_puertas. DEFINER como ellos: no lee tablas ni amplía ámbito; search_path vacío, dueño postgres, sin EXECUTE para la API.';
create trigger trg_00_actividades_no_contactar_solo_puerta
  before insert or update or delete on crm.actividades
  for each row execute function private.trg_actividades_no_contactar_solo_puerta();
comment on trigger trg_00_actividades_no_contactar_solo_puerta on crm.actividades is
  'Base para gestión (B6c): la nota del veto (evento no_contactar, sin distinguir mayúsculas ni espacios) solo la escriben sus puertas (válvula crm.op_privilegiada) o sesiones sin usuario, y no se cambia ni se borra; desde la API → 42501. Ver private.trg_actividades_no_contactar_solo_puerta.';

do $postflight$
begin
  -- SOLO catálogo (Codex r1, P2: nada de DML con el candado del CREATE TRIGGER puesto). Sello con el cuerpo ensayado, el
  -- contrato y la ACL exactos; trigger habilitado, BEFORE INSERT OR UPDATE OR DELETE, por fila, sin WHEN ni columnas.
  -- levantar con el cuerpo ensayado (y, como fragmento, la nota ANTES del apagado de la válvula). marcar, postventa y el
  -- cuerpo de la base, intactos. Censo igual a la foto; ninguna de las dos entra.
  if (
    (select md5(p.prosrc) = 'af83cbd67513122a325d2f159254bb3c'
        and p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole and p.prorettype = 'trigger'::regtype
        and p.proconfig = array['search_path=""']::text[] and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
        and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = 'f1fd306fb7afc8d405a778e14779a90a'
       from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()'))
    and (select count(*) = 1 from pg_trigger t
          where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_no_contactar_solo_puerta'
            and t.tgfoid = to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()')
            and t.tgenabled = 'O' and t.tgtype = 31 and t.tgqual is null and t.tgattr = ''::int2vector
            and pg_get_triggerdef(t.oid) like '%BEFORE INSERT OR DELETE OR UPDATE ON crm.actividades FOR EACH ROW%'
            and obj_description(t.oid, 'pg_trigger') like 'Base para gestión (B6c)%')
    and (select md5(p.prosrc) = '663780d27e3c7aa8d086f9a376ab3c4b'
            and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]
            and p.proacl is not null and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
            and pg_catalog.strpos(p.prosrc, 'insert into crm.actividades') > 0
            and pg_catalog.strpos(p.prosrc, 'insert into crm.actividades')
                < pg_catalog.strpos(p.prosrc, 'set_config(''crm.op_privilegiada'', ''off''')
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = 'e827b0475992abbe2136b434c4d439f6'
       from pg_proc p where p.oid = to_regprocedure('crm.levantar_no_contactar(uuid,text)'))
    and (select count(*) = 1 from pg_proc p where p.proname = 'levantar_no_contactar' and p.pronamespace = 'crm'::regnamespace)
    and (select md5(p.prosrc) = '6cd5678eed537dc880c5ce4447165d30' from pg_proc p where p.oid = to_regprocedure('crm.marcar_no_contactar(uuid,text)'))
    and (select md5(p.prosrc) = 'c67d516bcd37562a93af6a1a8b4629f7' from pg_proc p where p.oid = to_regprocedure('crm.postventa_veto_fn(uuid,uuid,boolean,text,uuid)'))
    and (select md5(p.prosrc) = '36af7e9cc4d6ec319b3d8004f3903473'
            and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '67f83881ece789fee1a37e0799123c18'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
    and not exists (select 1 from private.contadores_crudos_leads_citas() c
                     where c.objeto in (to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()')::text,
                                        to_regprocedure('crm.levantar_no_contactar(uuid,text)')::text))
    and not exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto not in (select a.objeto from pg_temp._b6c_censo_antes a))
    and (select count(*) from pg_temp._b6c_censo_antes) = (select count(*) from private.contadores_crudos_leads_citas())
  ) is not true then
    raise exception 'POSTFLIGHT B6c: el sello, su trigger, levantar o el comentario de la base no quedaron como se ensayaron, marcar/postventa cambiaron o el censo se movio';
  end if;
  -- Aviso honesto (Codex r1, P3): aquí solo se acredita el CATÁLOGO.
  raise notice 'B6c CATALOGO OK: sello (BEFORE INSERT OR UPDATE OR DELETE, habilitado, md5 y ACL), levantar (nota antes de apagar la valvula), comentarios y censo. COMPORTAMIENTO NO PROBADO en esta migracion: tras el commit, correr supabase/scripts/base-gestion/b6c-comprobar-tras-aplicar.sql';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261004123611 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261004123611', 'crm_base_gestion_reservar_nota_veto', array[$mig$-- 20261004123611_crm_base_gestion_reservar_nota_veto.sql
--
-- Base para gestión del analista · B6c: la nota del veto queda reservada a sus puertas, e inmutable. Decisión de Miguel
-- (04/10/2026, `BASE PARA GESTION/F4-SUPERVISOR.md`, P2b del auditor-rls de B6b): B6b salió con el riesgo escrito y «justo
-- después una migración pequeña (B6c) reserva `metadata.evento='no_contactar'` para las puertas oficiales».
-- r1 (04/10): Codex r1 BLOCK (P2 interbloqueo al desplegar, P3 avisos) + auditor-rls PASS con P3 (inmutable, variantes,
-- interbloqueo, exenciones documentadas).
--
-- POR QUÉ. B6b (20261004045038) muestra a Supervisión y Gerencia la «marca vigente» del veto (cuándo, motivo, quién) leyendo
--   la ÚLTIMA nota de crm.actividades con metadata evento = no_contactar. Hoy esa nota se puede escribir desde la API:
--   la policy `actividades_insert` (20260807123000:85-115) deja insertar en un lead propio o del ámbito con cualquier
--   metadata, y `trg_01_gestion_lead_serializada` solo frena el seguimiento de una persona vetada para los tipos de
--   CONTACTO (20260904130000:1082-1088), no una 'nota'. Quien escribe en un lead podía «firmar» una marca falsa (o un
--   «levantar» que la ocultara) con él como autor. Medido en el banco: authenticated tiene INSERT y SELECT en
--   crm.actividades (sin UPDATE ni DELETE, ni grant ni policy): el único camino de la API es el INSERT.
--
-- QUÉ:
--   1. NUEVO sello `trg_00_actividades_no_contactar_solo_puerta` (BEFORE INSERT OR UPDATE OR DELETE ON crm.actividades,
--      por fila) con `private.trg_actividades_no_contactar_solo_puerta()`. Con una sesión que tenga usuario y sin la
--      válvula de transacción `crm.op_privilegiada = on` → 42501:
--        · INSERT de una fila cuyo evento es el del veto;
--        · UPDATE (de CUALQUIER columna) de una fila que es o pasa a ser nota del veto (auditor-rls r1, P3: inmutables);
--        · DELETE de una nota del veto.
--      «Evento del veto» = lower(btrim(metadata->>'evento')) = 'no_contactar' (auditor-rls r1, P3: también 'No_Contactar' o
--      ' no_contactar '; B6b solo lee la forma exacta, pero ninguna variante entra por la API).
--      Exentos: la válvula `crm.op_privilegiada = on` (la que ya ponen las tres puertas del veto) y las sesiones sin
--      usuario (`auth.uid()` nulo: migraciones, backfills, jobs internos y la clave de servicio SIN sub). Esa exención de
--      service_role sin sub es ACEPTADA, igual que en los sellos vecinos: la clave de servicio es del servidor.
--      Mismo molde que los dos sellos vecinos de crm.actividades — `trg_actividades_resultado_solo_nucleo`
--      (20260920005000:211-249, válvula crm.op_resultado_llamada) y `trg_actividades_base_gestion_solo_nucleo`
--      (20261002231436:126-148, válvula crm.op_base_gestion) — y de `trg_leads_no_contactar_solo_puerta`, que ya reserva
--      la columna leads.no_contactar a estas puertas con la misma válvula (20260903240000:208-231). Función PROPIA y no
--      una rama más en un vecino: cada sello va con SU válvula; el del resultado está sellado por huella en
--      `private.assert_gestion_diaria_resultado` (tocarlo rompe ese trinquete) y el de la base es de otra familia
--      (crm.op_base_gestion). La lista de lo reservado para el veto vive en UNA sola definición: esta función.
--      Sin bandera: la reserva vale siempre (con resolver_en_puertas apagada las puertas también escriben con la válvula).
--      NO acredita las notas del veto escritas ANTES de instalarse: una nota forjada antes de B6c sigue en el historial.
--   2. `crm.levantar_no_contactar(uuid, text)`: create or replace con el texto VIVO de B2 (20261002061500:55-245, md5
--      prosrc 05df49be…) y UN solo cambio: el `set_config('crm.op_privilegiada', 'off', true)` pasa de ANTES del insert
--      de su nota (20261002061500:233) a justo DESPUÉS (como marcar). Sin eso, el sello rechazaría su propia nota.
--      Firma, dueño, ACL y todo lo demás, byte a byte. Su comentario suma una frase B6c.
--   3. Comentario (solo texto; el cuerpo no se toca, md5 36af7e9c…) de `crm.obtener_base_gestion(uuid, boolean)`: la nota
--      ya está reservada (no acredita las anteriores) y queda escrito el residuo P3 del auditor-rls de B6b: la función no
--      lee la bandera resolver_en_puertas (encendida desde el 07/09/2026).
--
-- ESCRITORES de la nota (grep del repo y `pg_proc` del banco, 04/10): solo tres cuerpos construyen
--   jsonb_build_object('evento', 'no_contactar', …), y los tres escriben con la válvula puesta:
--   · crm.marcar_no_contactar — 20260910150039:976 (on), :1016 (insert), :1023 (off); md5 prosrc vivo 6cd5678e…. NO se toca
--     (sellada por huella en private.assert_gestion_diaria_resultado).
--   · crm.postventa_veto_fn — 20260910150039:488 (on), :511 (insert en todos los leads de la persona), :516 (restaura), con
--     el bloque exterior PT409 que le puso 20260910190000 (mismo orden); md5 prosrc vivo c67d516b…. NO se toca.
--   · crm.levantar_no_contactar — 20261002061500:213 (on), :233 (off), :235 (insert) → este es el que se corrige.
--   Ningún backfill, fusión, importador, seed ni el front escriben esa nota (el front inserta notas sin metadata,
--   app/src/lib/store.tsx:2736). El preflight exige que siga habiendo solo esos tres en la base.
--   Otras puertas que encienden crm.op_privilegiada y escriben en crm.actividades (conversión, cierres externos, fusión,
--   corrección de documento, enlace, reasignación de responsable, inversión revisada, abandono de conversión) construyen su
--   metadata en el servidor con claves fijas: ninguna deja al cliente poner evento = no_contactar bajo la válvula.
-- QUIÉN CAMBIA O BORRA actividades (para la inmutabilidad; `pg_proc` del banco, 04/10): solo cuatro funciones hacen UPDATE y
--   ninguna DELETE, y ninguna puede caer sobre una nota del veto:
--   · private.base_gestion_intento_core — UPDATE de la fila que ella misma acaba de insertar con id = p_operacion_id
--     (20261003162300:199; el replay sale antes);
--   · private.llamada_registrar / private.llamada_registrar_v4 — UPDATE de su propia actividad de llamada (id =
--     p_operacion_id recién creado por registrar_actividad_v2, o el actividad_id que devuelve cerrar_tarea_v2)
--     (20260921153654:264/315);
--   · crm.deshacer_resultado_llamada — UPDATE solo si la actividad es evento = resultado_llamada (20260920005000:654).
--   Acciones referenciales: el lead se borra en CASCADA (actividades_lead_id_fkey), pero un lead con dueño no se puede
--   borrar (lead_asignaciones_lead_id_fkey, ledger append-only; probado en el banco) y ninguna función borra crm.leads; el
--   autor pasa a NULL al borrar su perfil (actividades_creado_por_fkey SET NULL), pero crm.eliminar_usuario_fn solo borra
--   auth.users si private.usuario_tiene_historial es falso (cuenta TODA FK al perfil, también actividades.creado_por:
--   20260925180145) y crm.eliminar_cliente_fn exige auth.uid() nulo. Si algún día una sesión con usuario hiciera una de
--   esas acciones sobre una nota del veto sin la válvula, el sello la rechaza (42501): es la regla, no un efecto lateral.
--   El preflight exige que sigan siendo solo esas cuatro las que hacen UPDATE/DELETE de crm.actividades.
--
-- DESPLIEGUE (Codex r1, P2): `CREATE TRIGGER` deja SHARE ROW EXCLUSIVE sobre crm.actividades hasta el commit. Esta migración
--   NO hace DML: su postflight es SOLO de catálogo (md5, contrato, ACL, forma del trigger, comentarios, censo). La r0 insertaba
--   notas de prueba (que bloquean el lead por trg_01_gestion_lead_serializada) con ese candado puesto: una llamada
--   concurrente a marcar_no_contactar (bloquea el lead y luego inserta en actividades) cerraba un ciclo → 40P01 (reproducido
--   en el banco con dos sesiones). El trigger se crea al FINAL, para tener el candado el menor tiempo posible. La prueba de
--   comportamiento (la API no escribe la nota; nota normal, válvula y sin usuario sí) va aparte, DESPUÉS del commit:
--   `supabase/scripts/base-gestion/b6c-comprobar-tras-aplicar.sql` (termina siempre en ROLLBACK).
-- AISLAMIENTO: READ COMMITTED explícito, sin REPEATABLE READ (a diferencia de B6b): no hay foto de DATOS que comparar
--   con una lectura posterior (el censo es catálogo).
-- QUÉ NO CAMBIA: RLS, policies y grants de crm.actividades; marcar y postventa; el cuerpo de obtener_base_gestion; los
--   otros sellos. Para un usuario solo cambia que su INSERT de una nota con evento del veto falla con 42501.
-- PRECONDICIÓN: B6b aplicada (cuerpo y comentario de obtener_base_gestion), levantar en el texto de B2, marcar y
--   postventa con los cuerpos medidos (md5 en el preflight).
-- REVERSA: `supabase/scripts/base-gestion/reversa-b6c.sql` (borra el sello, reinstala levantar de B2 y el comentario de
--   B6b, exactos). Antes que la de B6b. No toca datos.
begin;
set transaction isolation level read committed;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    -- levantar: el texto vivo de B2 (md5 prosrc 05df49be…), DEFINER de postgres, search_path vacío, ACL exacta, una sola
    -- sobrecarga y el comentario de B2.
    (select md5(p.prosrc) = '05df49be43869cd8e5f75330fa592a84'
        and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]
        and p.proacl is not null and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
        and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '5325ff9e4d60af5816bc20aa899e4dd1'
       from pg_proc p where p.oid = to_regprocedure('crm.levantar_no_contactar(uuid,text)'))
    and (select count(*) = 1 from pg_proc p where p.proname = 'levantar_no_contactar' and p.pronamespace = 'crm'::regnamespace)
    -- marcar y postventa: los cuerpos medidos, que escriben su nota CON la válvula puesta.
    and (select md5(p.prosrc) = '6cd5678eed537dc880c5ce4447165d30' and p.prosecdef
       from pg_proc p where p.oid = to_regprocedure('crm.marcar_no_contactar(uuid,text)'))
    and (select md5(p.prosrc) = 'c67d516bcd37562a93af6a1a8b4629f7' and p.prosecdef
       from pg_proc p where p.oid = to_regprocedure('crm.postventa_veto_fn(uuid,uuid,boolean,text,uuid)'))
    -- Ningún OTRO cuerpo construye la nota (si apareciera uno, el sello podría romperlo: se revisa antes).
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema')
                       and p.prosrc ~* '''evento''\s*,\s*''no_contactar''|"evento"\s*:\s*"no_contactar"'
                       and p.oid not in (coalesce(to_regprocedure('crm.marcar_no_contactar(uuid,text)')::oid, 0),
                                         coalesce(to_regprocedure('crm.levantar_no_contactar(uuid,text)')::oid, 0),
                                         coalesce(to_regprocedure('crm.postventa_veto_fn(uuid,uuid,boolean,text,uuid)')::oid, 0)))
    -- Ninguna OTRA función cambia o borra actividades (la nota del veto pasa a ser inmutable: se revisa antes).
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema')
                       and p.prosrc ~* 'update\s+crm\.actividades|delete\s+from\s+crm\.actividades'
                       and p.oid not in (coalesce(to_regprocedure('crm.deshacer_resultado_llamada(uuid)')::oid, 0),
                                         coalesce(to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)')::oid, 0),
                                         coalesce(to_regprocedure('private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)')::oid, 0),
                                         coalesce(to_regprocedure('private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)')::oid, 0)))
    -- obtener_base_gestion: el cuerpo de B6b y su comentario EXACTO (solo cambia el comentario).
    and (select md5(p.prosrc) = '36af7e9cc4d6ec319b3d8004f3903473'
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '469119616ab78df3eba406c7622d3888'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
    -- El sello no existe todavía.
    and to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()') is null
    and not exists (select 1 from pg_trigger t
                     where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_no_contactar_solo_puerta')
    -- Nadie enciende la válvula por configuración de rol o de base (abriría la reserva a todo el mundo).
    and not exists (select 1 from pg_catalog.pg_db_role_setting s cross join lateral pg_catalog.unnest(s.setconfig) c(x)
                     where c.x ilike 'crm.op_privilegiada=%')
  ) is not true then
    raise exception 'PREFLIGHT B6c: levantar no es el texto de B2, marcar/postventa no son los medidos, hay otro escritor de la nota del veto u otra funcion que cambia actividades, obtener_base_gestion no es la de B6b, el sello ya existe o la valvula se enciende por configuracion';
  end if;
end;
$preflight$;

-- Foto del censo analítico: el postflight exige que no cambie.
create temp table _b6c_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- ── 1. levantar_no_contactar: su nota, ANTES de apagar la válvula (texto vivo de B2 con ese único cambio) ──
create or replace function crm.levantar_no_contactar(p_lead_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean;
  v_dni_suelto text;
  v_suelto boolean := false;  -- F2.b (b2)
  v_puente boolean := false;  -- F2.b [D-3]: la persona se resolvió por el PUENTE (lead histórico sin DNI ni enlace)
  v_leads  uuid[];            -- F2.b [D-3]: enlace vivo ∪ puente ∪ sueltos con su documento, más el propio lead
  v_docs   text[];            -- F2.b [D-3]: documentos vigentes de la persona, bloqueados ANTES que ella (tipo:documento)
  v_perfiles uuid[] := array[]::uuid[];  -- F2.b [D-3]: perfiles cliente de la persona (enlazado o con su documento): tareas de cliente
begin
  -- B2 · Base para gestión (D5, Miguel 02/10/2026): Gerencia o Supervisión. Supervisión solo dentro de su ámbito y
  -- solo si TODA la persona (sus leads) cae en su equipo; si no, lo pide a Gerencia. `v_rol is null` también rechaza.
  if v_uid is null or v_rol is null or v_rol not in ('supervisor', 'gerencia') then
    raise exception 'Solo Gerencia o Supervisión pueden levantar No contactar' using errcode = '42501';
  end if;
  if p_motivo is null or pg_catalog.btrim(p_motivo) = '' then
    raise exception 'Levantar No contactar exige un motivo' using errcode = '22023';
  end if;
  -- Ámbito ANTES de resolver la identidad o tomar candados (el espejo de la policy leads_select, sin la rama de gerencia).
  if v_rol = 'supervisor' and not exists (
       select 1 from crm.leads l
        where l.id = p_lead_id
          and l.activo
          and (l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
               or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  -- F2.b [D-17] (Codex, 3.ª ronda del bloque 4): la bandera se lee con READ COMMITTED y bajo el candado
  -- COMPARTIDO por bandera; el UPDATE de crm.multiempresa_flags toma el EXCLUSIVO en su trigger (D-5).
  -- Así una llamada que entró APAGADA termina apagada aunque espere por una fila, y una que entra después
  -- del encendido lo ve: sin esto, una llamada en vuelo podía escribir con la bandera cambiada a medias.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'), false);

  -- ORDEN: identidad PRIMERO, luego leads.
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_flag and v_inv is null then
    -- F2.b [D-3] (Codex #7): un lead que solo está en el PUENTE (histórico sin DNI ni enlace vivo) también es de su
    -- persona: se resuelve por el puente (canónica) antes de intentar el documento. El puente solo cambia bajo el lock
    -- de la persona (fusión), que se toma más abajo y se revalida tras bloquear el lead.
    select private.inversionista_canonica(il.inversionista_id) into v_inv
    from crm.inversionista_leads il
    where il.lead_id = p_lead_id
    order by (il.rol = 'canonico') desc, il.inversionista_id
    limit 1;
    v_puente := v_inv is not null;
  end if;
  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
    select l.dni into v_dni_suelto from crm.leads l where l.id = p_lead_id;
    perform private.identidad_bloquear_documento('DNI', v_dni_suelto);
    v_inv := private.inversionista_por_documento('DNI', v_dni_suelto);
    v_suelto := v_inv is not null;
  end if;
  if v_inv is not null then
    -- F2.b [D-3] (auditor M1): DOCUMENTO → PERSONA, el orden del nacimiento (b1), la puerta del DNI (D-13) y la fusión (b5):
    -- se bloquean los documentos vigentes de la persona (en orden de texto) ANTES de bloquearla, y se releen después;
    -- así la puerta del DNI (que solo bloquea documentos y a la persona NUEVA) no puede llevarse un suelto a otra persona
    -- mientras el veto se propaga. Si el juego de documentos cambió mientras se esperaba → 40001.
    v_docs := private.identidad_bloquear_documentos_de(array[v_inv]);
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- La relectura es una LECTURA PURA (Codex N3): no vuelve a tomar candados con la persona ya bloqueada (documento → persona).
    if (select coalesce(pg_catalog.array_agg(s.k order by s.k), '{}'::text[])
          from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
                  from crm.inversionista_identificadores d
                 where d.inversionista_id = v_inv and d.estado = 'vigente') s) is distinct from v_docs then
      raise exception 'Los documentos de la persona cambiaron mientras se marcaba; vuelve a intentarlo'
        using errcode = '40001';
    end if;
    -- F2.b [D-3] (Codex #12): el motivo no lleva NINGÚN documento de la persona (vigentes ni históricos; la regla documental
    -- de las puertas de b5, sin imponer aquí su largo mínimo: el motivo de marcar es opcional).
    if p_motivo is not null and exists (
         select 1 from crm.inversionista_identificadores d
          where d.inversionista_id = v_inv
            and pg_catalog.length(d.documento_normalizado) >= 6
            and pg_catalog.strpos(pg_catalog.upper(pg_catalog.regexp_replace(p_motivo, '[^A-Za-z0-9]', '', 'g')), d.documento_normalizado) > 0) then
      raise exception 'El motivo no debe contener el número de documento' using errcode = '22023';
    end if;
  end if;
  -- F2.b [D-3]: bajo los locks de documentos y persona, «sus leads» = enlace vivo ∪ puente ∪ sueltos con su documento
  -- verificado (private.leads_de_persona_veto) más el propio lead; y sus perfiles cliente (el enlazado a la identidad o
  -- el que lleva su documento exacto, como persona_vetada_perfil) para las tareas de cliente. Estable hasta el commit.
  if v_inv is not null then
    v_leads := array(select x from private.leads_de_persona_veto(v_inv) x union select p_lead_id order by 1);
    v_perfiles := array(
      select i.perfil_id from crm.inversionistas i where i.id = v_inv and i.perfil_id is not null
      union
      select p.id from public.perfiles p
       where p.rol = 'cliente'
         and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
         and (coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') || ':' || pg_catalog.upper(pg_catalog.regexp_replace(p.dni, '[^A-Za-z0-9]', '', 'g'))) = any(v_docs)
      order by 1);
  else
    v_leads := array[p_lead_id];
  end if;
  -- F2.b [D-3] (Codex #1): tareas → leads es el orden de b2 y de cerrar_tarea; derivar y repartir van al revés (lead →
  -- tareas por el trigger de sincronización). Como la fusión (b5, E3-9): los leads se toman SIN esperar; si otra sesión
  -- tiene uno, 40001 y el front reintenta. Solo con la bandera (con OFF no hay tareas bloqueadas: el propio lead se toma como hoy).
  if v_flag then
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
  end if;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;
  -- B2 (D5): bajo candado, el ámbito se revalida y se exige para TODOS los leads de la persona que se van a tocar.
  -- Las dos comprobaciones van con `is not true`: un lead sin vendedor cuyo supervisor no está en el ámbito da NULL
  -- (NULL in (...)) y un `not NULL` dejaría pasar (Codex B1+B2, P1). Fail-closed también ante NULL.
  if v_rol = 'supervisor' then
    if (v_lead.activo
        and (v_lead.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
             or (v_lead.vendedor_id is null and v_lead.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) is not true then
      raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
    end if;
    if exists (select 1 from crm.leads l
                where l.id = any(v_leads)
                  and (l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
                       or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))) is not true) then
      raise exception 'La persona tiene leads fuera de tu equipo: pídelo a Gerencia' using errcode = '42501';
    end if;
  end if;
  if v_flag and not v_suelto and not v_puente and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_puente
     and (v_lead.inversionista_id is not null
          or not exists (select 1 from crm.inversionista_leads il
                         where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) = v_inv)) then
    raise exception 'El puente del lead cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_suelto
     and (v_lead.inversionista_id is not null
          or private.inversionista_por_documento('DNI', v_lead.dni) is distinct from v_inv) then
    raise exception 'El documento del lead cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_inv is not null then
    update crm.inversionistas
       set no_contactar = false, no_contactar_en = null, no_contactar_por = null
     where id = v_inv and no_contactar = true;
    for v_lead in
      select * from crm.leads where id = any(v_leads) order by id for update  -- F2.b [D-3]: enlace ∪ puente ∪ sueltos
    loop
      if v_lead.no_contactar then
        update crm.leads set no_contactar = false where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;
    -- F2.b (b2): el propio lead suelto también.
    update crm.leads set no_contactar = false where id = p_lead_id and no_contactar = true;
    if found then v_n := v_n + 1; end if;
  else
    update crm.leads set no_contactar = false where id = p_lead_id and no_contactar = true;
    get diagnostics v_n = row_count;
  end if;

  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (p_lead_id, 'nota', 'Levantado No contactar por ' || case when v_rol = 'gerencia' then 'Gerencia' else 'Supervisión' end,
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'levantar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', pg_catalog.btrim(p_motivo), 'rol', v_rol),
          v_uid);
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$function$;
alter function crm.levantar_no_contactar(uuid, text) owner to postgres;
revoke all on function crm.levantar_no_contactar(uuid, text) from public, anon, authenticated, service_role;
grant execute on function crm.levantar_no_contactar(uuid, text) to authenticated;
comment on function crm.levantar_no_contactar(uuid, text) is
  'Levanta No contactar (Ley 29571) de la persona del lead y de todos sus leads. Gerencia en toda la operación; Supervisión (B2, D5 02/10/2026) solo si el lead y TODOS los leads de la persona están en su equipo (si no, 42501: pídelo a Gerencia). Motivo obligatorio; queda en el historial con el rol. DEFINER: compone la identidad y escribe bajo crm.op_privilegiada; search_path vacío, dueño postgres, EXECUTE solo authenticated. B6c (04/10/2026): escribe su nota (metadata evento = no_contactar, accion = levantar) ANTES de apagar crm.op_privilegiada, porque esa nota quedó reservada a las puertas del veto (private.trg_actividades_no_contactar_solo_puerta).';

-- ── 2. El comentario de la base (solo texto) ───────────────────────────────────────────────────────────────
comment on function crm.obtener_base_gestion(uuid, boolean) is 'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente (salvo p_incluir_vetados, ver B6b), con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico. B5 (03/10/2026): devuelve al final recibido_en = coalesce(tenencia_desde, creado_en), cuándo le llegó el lead a quien lo tiene: el MES por el que se organiza el analista. B6b (03/10/2026, F4): p_incluir_vetados (default false; null = false) suma los leads «No contactar» del ámbito, también los que están en descanso; solo Supervisión y Gerencia (otro rol → 42501). Los vetados van al final y nunca en «Llamar hoy» (rellamada_hoy = false). Columnas finales no_contactar, no_contactar_en, no_contactar_motivo y no_contactar_por (nombre del autor): de la nota del evento vigente del veto — si la persona del lead (enlace, puente o DNI, como en marcar/levantar) está vetada, la última nota del veto entre los leads de la persona (private.leads_de_persona_veto ∪ el propio lead); si no, la del propio lead — solo si es un «marcar» (también el de postventa, motivo en el detalle) y su lead es visible para quien llama; si no, NULL. Residuo: empate exacto de clock_timestamp, desempate por id. B6c (04/10/2026, decisión de Miguel): la nota del veto (metadata evento = no_contactar) solo la escriben sus puertas (marcar_no_contactar, levantar_no_contactar y postventa_veto_fn, bajo crm.op_privilegiada; trigger trg_00_actividades_no_contactar_solo_puerta en crm.actividades): desde la API ya no se puede firmar el motivo, el autor ni la fecha de la marca, y la nota ya escrita no se cambia ni se borra. No acredita las notas anteriores a B6c (04/10/2026). Residuo (auditor-rls B6b, P3): esta función no lee la bandera resolver_en_puertas (encendida desde el 07/09/2026) y resuelve siempre la persona como las puertas con la bandera encendida; si se apagara, las puertas actuarían solo sobre el lead y la marca de un lead cuya persona siga vetada podría salir NULL o venir de otro lead de la persona (nunca de uno fuera del ámbito de quien llama). Con false, el resultado es el de B5. Envoltorios DEFINER en la base: crm.base_gestion_resumen y crm.base_gestion_resumen_detalle (re-auditarlos si cambia leads_select).';

-- ── 3. El sello (al final: CREATE TRIGGER deja SHARE ROW EXCLUSIVE sobre crm.actividades hasta el commit) ──
create function private.trg_actividades_no_contactar_solo_puerta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_exento boolean := false;
  v_veto boolean := false;
begin
  -- B6c: la nota del veto (metadata evento = no_contactar) es la fuente de la marca que la base para gestión muestra a
  -- Supervisión y Gerencia (cuándo, motivo, quién). Solo la escriben sus puertas, bajo la válvula de transacción
  -- crm.op_privilegiada = on (marcar_no_contactar, levantar_no_contactar y postventa_veto_fn), y no se cambia ni se borra.
  if (select auth.uid()) is null then
    v_exento := true;  -- sin usuario (migraciones, backfills, service_role sin sub), como los otros sellos de crm.actividades
  elsif coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off') = 'on' then
    v_exento := true;  -- la válvula de las puertas del veto
  end if;
  if not v_exento then
    if tg_op <> 'DELETE' then
      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(new.metadata->>'evento', ''), E' \t\r\n')) = 'no_contactar';
    end if;
    if tg_op <> 'INSERT' and not v_veto then
      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(old.metadata->>'evento', ''), E' \t\r\n')) = 'no_contactar';
    end if;
    if v_veto then
      raise exception 'La nota de No contactar solo la escriben sus puertas (marcar, levantar o postventa); no se cambia ni se borra'
        using errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;
alter function private.trg_actividades_no_contactar_solo_puerta() owner to postgres;
revoke all on function private.trg_actividades_no_contactar_solo_puerta() from public, anon, authenticated, service_role;
comment on function private.trg_actividades_no_contactar_solo_puerta() is
  'Base para gestión (B6c, 04/10/2026): reserva en crm.actividades la nota del veto — evento lower(btrim(metadata->>''evento'')) = ''no_contactar'' — para sus puertas (crm.marcar_no_contactar, crm.levantar_no_contactar y crm.postventa_veto_fn, que escriben bajo la válvula de transacción crm.op_privilegiada = on) y la hace inmutable: con una sesión con usuario y sin la válvula, INSERT de una nota del veto, UPDATE de cualquier columna de una fila que es o pasa a ser nota del veto y DELETE de una nota del veto → 42501. Exentas las sesiones sin usuario (migraciones, backfills, jobs y la clave de servicio SIN sub: exención aceptada, como en los sellos vecinos). Evita que quien escribe en un lead firme u oculte la marca vigente (motivo, autor, fecha) que crm.obtener_base_gestion muestra a Supervisión y Gerencia. No acredita las notas escritas antes de su instalación. Acciones referenciales: el borrado en cascada de un lead o el SET NULL del autor sobre una nota del veto también pasan por aquí (hoy ningún camino con usuario las dispara: un lead con dueño no se borra y eliminar_usuario_fn solo borra usuarios sin historial). Mismo molde que trg_actividades_resultado_solo_nucleo y trg_actividades_base_gestion_solo_nucleo (cada sello con su válvula) y que trg_leads_no_contactar_solo_puerta (misma válvula, sobre leads.no_contactar). Vale siempre, sin mirar la bandera resolver_en_puertas. DEFINER como ellos: no lee tablas ni amplía ámbito; search_path vacío, dueño postgres, sin EXECUTE para la API.';
create trigger trg_00_actividades_no_contactar_solo_puerta
  before insert or update or delete on crm.actividades
  for each row execute function private.trg_actividades_no_contactar_solo_puerta();
comment on trigger trg_00_actividades_no_contactar_solo_puerta on crm.actividades is
  'Base para gestión (B6c): la nota del veto (evento no_contactar, sin distinguir mayúsculas ni espacios) solo la escriben sus puertas (válvula crm.op_privilegiada) o sesiones sin usuario, y no se cambia ni se borra; desde la API → 42501. Ver private.trg_actividades_no_contactar_solo_puerta.';

do $postflight$
begin
  -- SOLO catálogo (Codex r1, P2: nada de DML con el candado del CREATE TRIGGER puesto). Sello con el cuerpo ensayado, el
  -- contrato y la ACL exactos; trigger habilitado, BEFORE INSERT OR UPDATE OR DELETE, por fila, sin WHEN ni columnas.
  -- levantar con el cuerpo ensayado (y, como fragmento, la nota ANTES del apagado de la válvula). marcar, postventa y el
  -- cuerpo de la base, intactos. Censo igual a la foto; ninguna de las dos entra.
  if (
    (select md5(p.prosrc) = 'af83cbd67513122a325d2f159254bb3c'
        and p.prosecdef and p.provolatile = 'v' and p.proowner = 'postgres'::regrole and p.prorettype = 'trigger'::regtype
        and p.proconfig = array['search_path=""']::text[] and p.proacl is not null and p.proacl::text = '{postgres=X/postgres}'
        and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = 'f1fd306fb7afc8d405a778e14779a90a'
       from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()'))
    and (select count(*) = 1 from pg_trigger t
          where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_no_contactar_solo_puerta'
            and t.tgfoid = to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()')
            and t.tgenabled = 'O' and t.tgtype = 31 and t.tgqual is null and t.tgattr = ''::int2vector
            and pg_get_triggerdef(t.oid) like '%BEFORE INSERT OR DELETE OR UPDATE ON crm.actividades FOR EACH ROW%'
            and obj_description(t.oid, 'pg_trigger') like 'Base para gestión (B6c)%')
    and (select md5(p.prosrc) = '663780d27e3c7aa8d086f9a376ab3c4b'
            and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]
            and p.proacl is not null and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
            and pg_catalog.strpos(p.prosrc, 'insert into crm.actividades') > 0
            and pg_catalog.strpos(p.prosrc, 'insert into crm.actividades')
                < pg_catalog.strpos(p.prosrc, 'set_config(''crm.op_privilegiada'', ''off''')
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = 'e827b0475992abbe2136b434c4d439f6'
       from pg_proc p where p.oid = to_regprocedure('crm.levantar_no_contactar(uuid,text)'))
    and (select count(*) = 1 from pg_proc p where p.proname = 'levantar_no_contactar' and p.pronamespace = 'crm'::regnamespace)
    and (select md5(p.prosrc) = '6cd5678eed537dc880c5ce4447165d30' from pg_proc p where p.oid = to_regprocedure('crm.marcar_no_contactar(uuid,text)'))
    and (select md5(p.prosrc) = 'c67d516bcd37562a93af6a1a8b4629f7' from pg_proc p where p.oid = to_regprocedure('crm.postventa_veto_fn(uuid,uuid,boolean,text,uuid)'))
    and (select md5(p.prosrc) = '36af7e9cc4d6ec319b3d8004f3903473'
            and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
            and md5(coalesce(obj_description(p.oid, 'pg_proc'), '')) = '67f83881ece789fee1a37e0799123c18'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
    and not exists (select 1 from private.contadores_crudos_leads_citas() c
                     where c.objeto in (to_regprocedure('private.trg_actividades_no_contactar_solo_puerta()')::text,
                                        to_regprocedure('crm.levantar_no_contactar(uuid,text)')::text))
    and not exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto not in (select a.objeto from pg_temp._b6c_censo_antes a))
    and (select count(*) from pg_temp._b6c_censo_antes) = (select count(*) from private.contadores_crudos_leads_citas())
  ) is not true then
    raise exception 'POSTFLIGHT B6c: el sello, su trigger, levantar o el comentario de la base no quedaron como se ensayaron, marcar/postventa cambiaron o el censo se movio';
  end if;
  -- Aviso honesto (Codex r1, P3): aquí solo se acredita el CATÁLOGO.
  raise notice 'B6c CATALOGO OK: sello (BEFORE INSERT OR UPDATE OR DELETE, habilitado, md5 y ACL), levantar (nota antes de apagar la valvula), comentarios y censo. COMPORTAMIENTO NO PROBADO en esta migracion: tras el commit, correr supabase/scripts/base-gestion/b6c-comprobar-tras-aplicar.sql';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261004123611' and name = 'crm_base_gestion_reservar_nota_veto' and cardinality(statements) = 1
                   and md5(statements[1]) = 'abd20c567aaa1291bb6ec9fb3155789f') then
    raise exception 'REGISTRO: la fila 20261004123611 / crm_base_gestion_reservar_nota_veto no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261004123611 / crm_base_gestion_reservar_nota_veto (1 sentencia: el archivo entero)';
end $post$;
commit;

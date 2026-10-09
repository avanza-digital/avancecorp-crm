-- 20261009180000_crm_categoria_sin_operacion_solo_nuevo.sql
--
-- Un contrato SIN operación de cartera solo puede quedar como 'nuevo': se cierra el hueco inverso de la regla «la
-- operación decide» (20261009120000). Decisión de Miguel (09/10/2026).
--
-- POR QUÉ
--   20261009120000 (aplicada en producción el 08/10) dejó la guarda de public.contratos en «con operación, la categoría es
--   la de la operación; sin operación, no se restringe». Así, cualquier vía que no sea la puerta de Gerencia («Corregir»
--   del CRM y del portal, elegir una condición de catálogo de upgrade, SQL) puede pasar un contrato sin operación a
--   'upgrade' o 'renovacion' sin que exista la operación que lo respalde. El cinturón del alta
--   (trg_contratos_operacion_cartera_commit) solo mira el INSERT y el núcleo de la puerta ya lo rechaza; lo que faltaba es
--   la regla para toda vía en el UPDATE.
--   Medido en producción (09/10 12:15 Lima, solo lectura): 106 contratos sin operación con 'upgrade' o 'renovacion' (de
--   marzo a julio) y 19 con la categoría vacía. NO se tocan: la regla solo actúa cuando la categoría CAMBIA (WHEN del
--   trigger). Mes sellado: solo agosto.
--
-- QUÉ HACE (solo la guarda; orden: función → comentario)
--   private.trg_contrato_categoria_por_operacion() (trigger trg_contratos_01_categoria_por_operacion, AFTER UPDATE por fila,
--   WHEN la categoría cambió; el trigger no se toca) queda idéntica a la de 20261009120000 más UNA regla al final: si el
--   contrato NO tiene operación de cartera y la categoría nueva no es 'nuevo' (vacía cuenta como nuevo, igual que en el
--   núcleo) → 23514 «Un contrato sin operación de cartera solo puede quedar como nuevo» (el MISMO texto que ya da el núcleo
--   private.fijar_categoria_contrato por la puerta). El rechazo de aislamiento (25001) sigue primero y, con operación, todo
--   sigue igual (23514 «La categoría la decide la operación de cartera»). Pasar a 'nuevo' o a vacía sí se permite.
--   Mismo dueño, SECURITY DEFINER, search_path vacío y permisos (CREATE OR REPLACE los conserva; el postflight lo comprueba).
--   Solo cambia el comentario de la función (private): ningún DDL sobre objetos de public.
-- QUÉ NO CAMBIA: el trigger y su WHEN, la puerta y el núcleo, la sincronización al registrar una operación (la operación ya
--   existe cuando la guarda mira: el contrato toma su categoría), el alta (public.crear_contrato: INSERT, la guarda es de
--   UPDATE; el cinturón del alta sigue exigiendo la operación al confirmar), editar cualquier otra cosa de un contrato
--   (también de los 106: la categoría no cambia), el producto de catálogo (su propio trigger rechaza antes, BEFORE).
--   No toca datos ni la API (no hay tipos que regenerar).
-- EFECTO CONOCIDO: «Corregir» (CRM contrato-corregir.tsx → public.actualizar_contrato; portal →
--   public.actualizar_numero_contrato) que hoy deja pasar un contrato sin operación a 'upgrade' o 'renovacion' —también al
--   elegir una condición de catálogo de upgrade— recibirá el 23514. El portal muestra el texto del servidor; el CRM, por
--   ahora, el genérico «No se pudo guardar el cambio.» (app/src/data/crm-api.ts no traduce este 23514: arreglo de pantalla
--   aparte). De los 106, uno puede volver a 'nuevo' o quedar vacío, pero no cambiar entre 'upgrade' y 'renovacion'; y los 19
--   vacíos, si se corrigen eligiendo categoría, solo admiten 'nuevo'. Para un contrato que YA existe no hay pantalla que le
--   cuelgue una operación: hoy solo SQL (insertar la operación, como el backfill B; la sincronización pone la categoría).
-- AISLAMIENTO: la transacción va en READ COMMITTED (no REPEATABLE READ como otras de la casa): la guarda solo deja cambiar
--   una categoría en READ COMMITTED y el postflight cambia tres dentro de subtransacciones que se deshacen.
-- PREFLIGHT (con public en el search_path, como se midió): las huellas de la guarda y de las 7 piezas que la rodean (md5 de
--   pg_get_functiondef medido en producción el 09/10 a las 12:15 Lima; la de public.actualizar_numero_contrato, el 08/10),
--   dueño, permisos, SECURITY y search_path de la guarda, la huella de los 16 triggers de public.contratos (todos
--   habilitados) y la forma del trigger de la guarda. Si algo no cuadra (también si ya se aplicó): P0409 y no se aplica nada.
-- POSTFLIGHT: cuerpo nuevo (md5 de prosrc) con huella distinta de la medida; dueño, permisos, SECURITY y search_path
--   iguales; trigger intacto; las 7 piezas y los 16 triggers con la misma huella; comentario puesto; y tres pruebas en
--   negativo que se deshacen SIEMPRE (subtransacción que termina en raise), con la congelación del PDF abierta solo para ese
--   contrato, sobre contratos de producto LEGACY (con el puente legacy abierto), no demo, no en eliminación y de un mes NO
--   sellado: (a) sin operación 'nuevo' → 'upgrade' ⇒ 23514 con el texto exacto; (b) sin operación 'upgrade' (de los 106) →
--   'nuevo' ⇒ pasa; (c) con operación → otra categoría ⇒ 23514 «La categoría la decide la operación de cartera». Sin
--   candidato, aviso y sigue. Comprueba además que ninguna prueba dejó nada escrito (bitácora, foto de producto, categoría).
-- LÍMITES: la regla es inmediata (AFTER por fila, no diferida): un flujo futuro que registre una renovación o un upgrade sobre
--   un contrato existente inserta PRIMERO la operación. Como todo trigger, no frena a un superusuario con
--   session_replication_role = replica ni con el trigger deshabilitado.
-- REVERSA: supabase/scripts/categoria-sin-operacion/reversa.sql (devuelve EXACTAMENTE la guarda de 20261009120000 y su
--   comentario). Ojo: la reversa de 20261009120000 (categoria-por-operacion/reversa.sql) exige ANTES esta.
-- REGISTRO: supabase/scripts/categoria-sin-operacion/registrar/20261009180000.sql (`db query --file` NO registra).
-- TIPOS: no hacen falta (no cambia ninguna firma ni nada expuesto por la API).

-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

-- READ COMMITTED explícito (no se hereda el aislamiento por defecto de la sesión): el postflight cambia categorías.
begin;
set transaction isolation level read committed;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local quote_all_identifiers = off;
-- Las huellas se midieron con public en el search_path: el texto de pg_get_functiondef y de pg_get_triggerdef cambia con
-- él. Solo para el preflight y las huellas del postflight; las pruebas, con search_path vacío.
set local search_path = public;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
-- Producción, 09/10/2026 12:15 Lima (solo lectura). La guarda primero; las otras no deben cambiar. La de
-- public.actualizar_numero_contrato (el «Corregir» del portal, el otro escritor de la categoría) es la de producción del
-- 08/10 19:11 (R7 de 20261009120000, comprobada por su preflight al aplicarse a las 22:55; ninguna migración posterior la toca).
create temporary table categoria_sin_op_huellas on commit drop as
  select * from (values
    ('private.trg_contrato_categoria_por_operacion()', '8fdd5f1a3d74c073d5fe3327968132b9'),
    ('private.trg_operacion_cartera_fija_categoria()', 'ac816220dacf51cd70a5ffbd8b11b036'),
    ('private.fijar_categoria_contrato(uuid,text,text,text,uuid)', '718e7e0f9c9112f3996d9fe0fbf85415'),
    ('crm.corregir_categoria_contrato_fn(uuid,text,text)', '1d55b75d685737215ed0771d1db1b539'),
    ('public.crear_contrato(jsonb,jsonb)', 'dce8f0dd6d6776b960096c56bdc29173'),
    ('private.trg_contratos_producto_snapshot()', 'c4c222984db5bf6232edae70b0ee19f1'),
    ('public.actualizar_contrato(uuid,jsonb,jsonb)', '6184aad4be1b234db83b096e08e92428'),
    ('public.actualizar_numero_contrato(uuid,text,text,text)', '84ba035d9888b7d4b5494c82b8e04b00')
  ) as v(firma, huella);

do $preflight$
declare
  r record;
begin
  -- Ya aplicada: la guarda ya tiene el cuerpo que deja esta migración.
  if exists (select 1 from pg_proc p
              where p.oid = to_regprocedure('private.trg_contrato_categoria_por_operacion()')
                and md5(p.prosrc) = 'b8f9c14e5da959c6237b2d00df8423ae') then
    raise exception 'CATEGORIA SIN OPERACION: la guarda ya tiene la regla nueva; esta migración ya se aplicó'
      using errcode = 'P0409';
  end if;

  for r in select h.firma, h.huella from pg_temp.categoria_sin_op_huellas h loop
    if to_regprocedure(r.firma) is null
       or md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'CATEGORIA SIN OPERACION: % no tiene la huella medida en producción; revisar antes de aplicar', r.firma
        using errcode = 'P0409';
    end if;
  end loop;

  -- La guarda: dueño postgres, SECURITY DEFINER, search_path vacío y solo postgres la ejecuta (como la dejó 20261009120000).
  if not exists (select 1 from pg_proc p
                  where p.oid = 'private.trg_contrato_categoria_por_operacion()'::regprocedure
                    and p.proowner = 'postgres'::regrole and p.prosecdef
                    and p.proconfig = array['search_path=""']
                    and p.proacl::text = '{postgres=X/postgres}') then
    raise exception 'CATEGORIA SIN OPERACION: la guarda no tiene el dueño, la seguridad o los permisos medidos; revisar'
      using errcode = 'P0409';
  end if;

  -- Los 16 triggers de public.contratos tal como se midieron, todos habilitados.
  if (select md5(string_agg(t.tgname || '|' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname))
        from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and not t.tgisinternal)
       is distinct from '93a6e99cd87c7add3f3357a937c6ebda'
     or exists (select 1 from pg_trigger t
                 where t.tgrelid = 'public.contratos'::regclass and not t.tgisinternal and t.tgenabled <> 'O') then
    raise exception 'CATEGORIA SIN OPERACION: los triggers de public.contratos no son los medidos el 09/10; revisar'
      using errcode = 'P0409';
  end if;

  -- El trigger de la guarda: por fila, AFTER UPDATE (tgtype 17), sin lista de columnas y con su WHEN.
  if not exists (select 1 from pg_trigger t
                  where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_01_categoria_por_operacion'
                    and t.tgenabled = 'O' and t.tgtype = 17
                    and t.tgattr::text = '' and t.tgqual is not null
                    and pg_get_triggerdef(t.oid) like '%WHEN ((old.categoria IS DISTINCT FROM new.categoria))%'
                    and t.tgfoid = 'private.trg_contrato_categoria_por_operacion()'::regprocedure) then
    raise exception 'CATEGORIA SIN OPERACION: el trigger de la guarda no tiene la forma medida; revisar'
      using errcode = 'P0409';
  end if;
end;
$preflight$;

set local search_path = '';

-- ── 1 · La guarda (idéntica a la de 20261009120000 + la regla nueva al final) ──────────────────────────────────────────
-- SECURITY DEFINER, justificado (como antes): tiene que VER la operación aunque quien edita el contrato no pueda leerla por
-- RLS (si no la viera, con la regla nueva rechazaría un upgrade legítimo, y sin ella se saltaría la regla en silencio).
create or replace function private.trg_contrato_categoria_por_operacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $guarda$
declare
  v_tipo text;
  v_con_operacion boolean;
begin
  if new.categoria is not distinct from old.categoria then
    return new;
  end if;
  -- Solo READ COMMITTED, ANTES de buscar la operación: con una foto vieja (REPEATABLE READ o SERIALIZABLE) esta consulta
  -- no vería una operación confirmada después de la foto, y la categoría quedaría distinta de la operación sin aviso.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La categoría de un contrato solo se cambia en una transacción READ COMMITTED'
      using errcode = '25001',
            hint = 'La API ya trabaja en READ COMMITTED. En SQL: BEGIN ISOLATION LEVEL READ COMMITTED.';
  end if;
  select o.tipo into v_tipo from crm.operaciones_cartera o where o.contrato_nuevo_id = new.id;
  v_con_operacion := found;
  if found and new.categoria is distinct from v_tipo then
    raise exception 'La categoría la decide la operación de cartera'
      using errcode = '23514',
            detail = format('El contrato tiene una operación de cartera de tipo %s; su categoría no puede quedar como %s.',
                            v_tipo, coalesce(new.categoria, 'vacía')),
            hint = 'La categoría de un contrato con operación de cartera es la de su operación.';
  end if;
  -- 20261009180000: sin operación de cartera, solo 'nuevo' (vacía cuenta como nuevo, igual que en el núcleo). Ninguna vía
  -- pasa un contrato sin operación a renovación o upgrade. v_con_operacion guarda el FOUND del SELECT (no depende de lo
  -- que se escriba en medio).
  if not v_con_operacion and coalesce(new.categoria, 'nuevo') <> 'nuevo' then
    raise exception 'Un contrato sin operación de cartera solo puede quedar como nuevo'
      using errcode = '23514',
            detail = format('El contrato no tiene operación de cartera; su categoría no puede pasar a %s.', new.categoria),
            hint = 'Una renovación o un upgrade se registran desde la cartera del cliente, que crea su operación.';
  end if;
  return new;
end;
$guarda$;

-- Permisos: sin cambios (CREATE OR REPLACE conserva dueño y ACL; el postflight lo comprueba).

-- ── 2 · Comentarios ───────────────────────────────────────────────────────────────────────────────────────────────────
-- Solo el de la función (esquema private). El del trigger (public.contratos) no se toca: sigue siendo cierto, y así esta
-- migración no hace ningún DDL sobre objetos de public.
comment on function private.trg_contrato_categoria_por_operacion() is
  'Una categoría solo cambia en READ COMMITTED (25001). Con operación de cartera, la categoría no puede quedar distinta de la operación (23514 «La categoría la decide la operación de cartera», 20261009120000). Sin operación, solo puede quedar como nuevo o vacía (23514 «Un contrato sin operación de cartera solo puede quedar como nuevo», 20261009180000, decisión de Miguel 09/10/2026). Solo actúa cuando la categoría cambia: los contratos existentes no se tocan. Es inmediata (AFTER por fila): quien registre una renovación o un upgrade sobre un contrato que ya existe inserta PRIMERO la operación (la sincronización le pone la categoría).';

-- ── 3 · Postflight ────────────────────────────────────────────────────────────────────────────────────────────────────
-- 3a · Huellas y catálogo, con public en el search_path (como se midió).
set local search_path = public;
do $postflight$
declare
  r record;
begin
  if not exists (select 1 from pg_proc p
                  where p.oid = 'private.trg_contrato_categoria_por_operacion()'::regprocedure
                    and md5(p.prosrc) = 'b8f9c14e5da959c6237b2d00df8423ae'
                    and md5(pg_get_functiondef(p.oid)) is distinct from
                        (select h.huella from pg_temp.categoria_sin_op_huellas h
                          where h.firma = 'private.trg_contrato_categoria_por_operacion()')
                    and p.proowner = 'postgres'::regrole and p.prosecdef
                    and p.proconfig = array['search_path=""']
                    and p.proacl::text = '{postgres=X/postgres}') then
    raise exception 'CATEGORIA SIN OPERACION postflight: la guarda no quedó como se declara (cuerpo, dueño, seguridad, search_path o permisos)';
  end if;
  for r in select h.firma, h.huella from pg_temp.categoria_sin_op_huellas h
            where h.firma <> 'private.trg_contrato_categoria_por_operacion()' loop
    if md5(pg_get_functiondef(to_regprocedure(r.firma))) is distinct from r.huella then
      raise exception 'CATEGORIA SIN OPERACION postflight: % cambió durante la migración', r.firma;
    end if;
  end loop;
  if (select md5(string_agg(t.tgname || '|' || pg_get_triggerdef(t.oid), E'\n' order by t.tgname))
        from pg_trigger t where t.tgrelid = 'public.contratos'::regclass and not t.tgisinternal)
       is distinct from '93a6e99cd87c7add3f3357a937c6ebda'
     or exists (select 1 from pg_trigger t
                 where t.tgrelid = 'public.contratos'::regclass and not t.tgisinternal and t.tgenabled <> 'O')
     or not exists (select 1 from pg_trigger t
                     where t.tgrelid = 'public.contratos'::regclass and t.tgname = 'trg_contratos_01_categoria_por_operacion'
                       and t.tgenabled = 'O' and t.tgtype = 17 and t.tgattr::text = '' and t.tgqual is not null
                       and pg_get_triggerdef(t.oid) like '%WHEN ((old.categoria IS DISTINCT FROM new.categoria))%'
                       and t.tgfoid = 'private.trg_contrato_categoria_por_operacion()'::regprocedure) then
    raise exception 'CATEGORIA SIN OPERACION postflight: los triggers de public.contratos cambiaron';
  end if;
  -- «is not true»: un comentario que faltara (NULL) también rechaza.
  if (obj_description('private.trg_contrato_categoria_por_operacion()'::regprocedure, 'pg_proc')
        like '%20261009180000%') is not true then
    raise exception 'CATEGORIA SIN OPERACION postflight: falta el comentario de la guarda';
  end if;
end;
$postflight$;

-- 3b · Pruebas en negativo que se deshacen SIEMPRE. Contratos de producto LEGACY (con uno de catálogo, su trigger rechaza
-- antes), con términos que el puente legacy puede fotografiar y con ese puente abierto (cerrado, un legacy ya no cambia de
-- términos: no se prueba aquí), no demo, no en eliminación (otra regla rechazaría antes) y de un mes NO sellado; la
-- congelación del PDF, abierta solo para ese contrato y solo dentro del bloque.
set local search_path = '';
do $pruebas$
declare
  c_paso constant text := 'postflight: el UPDATE pasó y se deshace';
  v_puente_legacy constant boolean :=
    exists (select 1 from crm.productos_inversion p where p.es_legacy and p.permite_altas_legacy);
  v_id uuid;
  v_caso text;
  v_destino text;
  v_estado text;
  v_mensaje text;
  v_antes text;
  v_despues text;
  v_corridos text := '';
begin
  for v_id, v_caso, v_destino in
    select x.id, x.caso, x.destino from (
      -- (a) sin operación, 'nuevo' → 'upgrade' ⇒ 23514 con el texto exacto
      (select c.id, 'a' as caso, 'upgrade' as destino
         from public.contratos c
         join crm.producto_condiciones pc on pc.id = c.producto_condicion_id and pc.es_legacy
        where c.categoria = 'nuevo' and not c.es_demo
          and not exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = c.id)
          and not private.contrato_en_eliminacion(c.id)
          and not exists (select 1 from crm.periodos_cerrados s
                           where s.periodo = date_trunc('month', c.fecha_cierre_comercial)::date)
          and c.capital between 100 and 100000000 and c.tasa_anual > 0 and c.tasa_anual <= 50
          and c.fecha_vencimiento >= c.fecha_inicio
        order by c.creado_en desc, c.id limit 1)
      union all
      -- (b) sin operación, 'upgrade' (de los antiguos; si no hay, 'renovacion') → 'nuevo' ⇒ pasa
      (select c.id, 'b', 'nuevo'
         from public.contratos c
         join crm.producto_condiciones pc on pc.id = c.producto_condicion_id and pc.es_legacy
        where c.categoria in ('upgrade', 'renovacion') and not c.es_demo
          and not exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = c.id)
          and not private.contrato_en_eliminacion(c.id)
          and not exists (select 1 from crm.periodos_cerrados s
                           where s.periodo = date_trunc('month', c.fecha_cierre_comercial)::date)
          and c.capital between 100 and 100000000 and c.tasa_anual > 0 and c.tasa_anual <= 50
          and c.fecha_vencimiento >= c.fecha_inicio
        order by (c.categoria = 'upgrade') desc, c.creado_en desc, c.id limit 1)
      union all
      -- (c) con operación → otra categoría ⇒ 23514 «La categoría la decide la operación de cartera»
      (select c.id, 'c', case when o.tipo = 'upgrade' then 'renovacion' else 'upgrade' end
         from public.contratos c
         join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id
         join crm.producto_condiciones pc on pc.id = c.producto_condicion_id and pc.es_legacy
        where not c.es_demo
          and not private.contrato_en_eliminacion(c.id)
          and not exists (select 1 from crm.periodos_cerrados s
                           where s.periodo = date_trunc('month', c.fecha_cierre_comercial)::date)
          and c.capital between 100 and 100000000 and c.tasa_anual > 0 and c.tasa_anual <= 50
          and c.fecha_vencimiento >= c.fecha_inicio
        order by o.creado_en desc, o.id limit 1)
    ) as x
    where v_puente_legacy
  loop
    -- Lo de antes, para comprobar que la prueba no deja nada: categoría, bitácora del contrato y fotos de producto.
    select coalesce(c.categoria, 'vacía') || ' · ' ||
           (select count(*) from public.audit_log a where a.tabla = 'contratos' and a.fila_id = v_id::text) || ' · ' ||
           (select count(*) from crm.producto_condiciones f where f.es_legacy and f.legacy_contrato_id = v_id)
      into v_antes from public.contratos c where c.id = v_id;
    v_estado := null;
    v_mensaje := null;
    begin
      perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', v_id::text, true);
      update public.contratos c set categoria = v_destino where c.id = v_id;
      raise exception using errcode = 'P0001', message = c_paso;
    exception when others then
      v_estado := sqlstate;
      v_mensaje := sqlerrm;
    end;
    perform pg_catalog.set_config('crm.contrato_pdf_revision_autorizada', '', true);
    select coalesce(c.categoria, 'vacía') || ' · ' ||
           (select count(*) from public.audit_log a where a.tabla = 'contratos' and a.fila_id = v_id::text) || ' · ' ||
           (select count(*) from crm.producto_condiciones f where f.es_legacy and f.legacy_contrato_id = v_id)
      into v_despues from public.contratos c where c.id = v_id;
    if v_despues is distinct from v_antes then
      raise exception 'CATEGORIA SIN OPERACION postflight (%): la prueba dejó algo escrito (antes % · después %)',
        v_caso, v_antes, v_despues;
    end if;
    if v_caso = 'a' and (v_estado is distinct from '23514'
                         or v_mensaje is distinct from 'Un contrato sin operación de cartera solo puede quedar como nuevo') then
      raise exception 'CATEGORIA SIN OPERACION postflight (a): un contrato sin operación pasado a upgrade respondió % «%» (se esperaba 23514 «Un contrato sin operación de cartera solo puede quedar como nuevo»)', v_estado, v_mensaje;
    end if;
    if v_caso = 'b' and v_mensaje is distinct from c_paso then
      raise exception 'CATEGORIA SIN OPERACION postflight (b): un contrato sin operación devuelto a nuevo respondió % «%» (se esperaba que pasara)', v_estado, v_mensaje;
    end if;
    if v_caso = 'c' and (v_estado is distinct from '23514'
                         or v_mensaje is distinct from 'La categoría la decide la operación de cartera') then
      raise exception 'CATEGORIA SIN OPERACION postflight (c): un contrato con operación llevado a otra categoría respondió % «%» (se esperaba 23514 «La categoría la decide la operación de cartera»)', v_estado, v_mensaje;
    end if;
    v_corridos := v_corridos || v_caso;
    raise notice 'CATEGORIA SIN OPERACION postflight (%): OK (% → %)', v_caso, split_part(v_antes, ' · ', 1), v_destino;
  end loop;
  -- Un aviso por cada caso sin candidato: esa prueba no se pudo correr aquí (la suite del banco la cubre).
  if not v_puente_legacy then
    raise notice 'CATEGORIA SIN OPERACION postflight: el puente legacy está cerrado (un contrato legacy ya no cambia de términos); las pruebas (a), (b) y (c) no se pudieron correr aquí';
  end if;
  if strpos(v_corridos, 'a') = 0 then
    raise notice 'CATEGORIA SIN OPERACION postflight: no hay contrato candidato sin operación en nuevo; la prueba (a) no se pudo correr aquí';
  end if;
  if strpos(v_corridos, 'b') = 0 then
    raise notice 'CATEGORIA SIN OPERACION postflight: no hay contrato candidato sin operación en upgrade o renovacion; la prueba (b) no se pudo correr aquí';
  end if;
  if strpos(v_corridos, 'c') = 0 then
    raise notice 'CATEGORIA SIN OPERACION postflight: no hay contrato candidato con operación de cartera; la prueba (c) no se pudo correr aquí';
  end if;
end;
$pruebas$;

commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));

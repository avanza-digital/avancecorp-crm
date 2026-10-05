-- REVERSA de 20261004184501_crm_bases_cargadas_cargar.sql (Bases cargadas · B8: cargar un archivo y armar bases), r2.
-- Vuelve EXACTAMENTE a B7 (20261004160034): borra las tres puertas (crm.crear_base, crm.cargar_base_lote, crm.armar_base_crm),
-- las 17 funciones del núcleo private.bases_carga_*, el disparador trg_leads_zz_sello_descarte_base_cargada con su función y el
-- CHECK enfriamiento_politica_base_cargada_dias_positivos, y
-- repone private.leads_before_insert (texto y comentario de B7), private.trg_leads_disponibilidad_atomica (texto y comentario
-- de antes) y private.trg_leads_sla_versionado (texto de antes, sin comentario). Las tablas de B7 quedan (su reversa es aparte).
-- Solo mientras B8 no se usó: se NIEGA si hay una sola base, fila de base o recibo, o algún lead con origen o motivo
-- base_cargada (regla de la casa: en producción no se borra lo que tiene datos; se cierra y se observa). Se niega también si
-- otra función (B9 en adelante) usa las puertas o el núcleo de B8, o si otra función toca la válvula crm.op_bases_carga.
-- r2 (rama con datos): nada de huellas «globales» medidas en el banco (los comentarios de triggers AJENOS difieren entre el
--   banco y producción): de B8 se exige su huella exacta; del resto de crm.leads y del enfriamiento, que la reversa no lo cambie
--   (mismo conjunto de triggers —nombre, función, habilitado— y de restricciones antes y después, medido en esta misma base).
-- HUELLAS: antes de sobrescribir nada exige que lo vivo sea EXACTAMENTE lo que dejó B8 —cuerpo, seguridad, volatilidad,
--   configuración, dueño, ACL y comentario de cada función (puertas, núcleo y las tres del alta), definición, estado y
--   comentario del disparador y definición, validez y comentario del CHECK—; cualquier deriva posterior → se niega y la nombra
--   (no pisa trabajo ajeno). Huellas medidas con
--   B8 recién aplicada y search_path vacío (consulta en el bloque $huellas$).
-- CANDADOS: el de migración de la casa (crm_migracion_funciones); luego crm.leads ACCESS EXCLUSIVE (lo exige DROP TRIGGER),
--   crm.enfriamiento_politica ACCESS EXCLUSIVE (DROP CONSTRAINT) y las tres tablas de bases en SHARE (ninguna carga entra
--   mientras se comprueba el vacío), en ese orden (el de B7) y ANTES de comprobar.
--   Una carga en vuelo termina antes (y la reversa ve sus filas y se niega) o espera (y muere sin las puertas). Mientras se
--   retiene nadie lee ni escribe crm.leads: retención medida en el banco (ver MIGRACIONES.md). lock_timeout 3 s solo limita la
--   espera para obtenerlos. Correr en horario bajo.
-- Conserva la fila de schema_migrations: anotar la reversa en MIGRACIONES.md.
begin;
set transaction isolation level read committed;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;
select pg_advisory_xact_lock(hashtext('crm_migracion_funciones'));

do $chk$
begin
  if (
    to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)') is not null
    and to_regprocedure('private.bases_carga_nace_dormido(text,text,text,boolean)') is not null
    and to_regclass('crm.bases_carga') is not null
  ) is not true then
    raise exception 'REVERSA B8: la migracion no esta aplicada (faltan sus objetos)';
  end if;
  -- Ninguna función ajena a B8 usa sus puertas o su núcleo (B9 en adelante se revierte antes) ni toca la válvula.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname not in ('pg_catalog', 'information_schema')
                and p.prosrc ~ '(bases_carga_(constantes|nace_dormido|rol|supervisor_destino|base_visible|subarbol|en_subarbol|lead_ref|error_transitorio|operacion_previa|insertar_base|contacto_existente|fuera_de_ambito|crear_core|cargar_lote_core|armar_respuesta|armar_core))|crear_base|cargar_base_lote|armar_base_crm|sello_descarte_base_cargada'
                and not (n.nspname in ('crm', 'private') and (p.proname like 'bases\_carga\_%' or p.proname in ('crear_base', 'cargar_base_lote', 'armar_base_crm', 'trg_leads_sello_descarte_base_cargada')))
                and p.oid not in (to_regprocedure('private.leads_before_insert()'), to_regprocedure('private.trg_leads_disponibilidad_atomica()'),
                                  to_regprocedure('private.trg_leads_sla_versionado()'))) then
    raise exception 'REVERSA B8: hay funciones que usan las puertas o el nucleo de B8 (B9 en adelante): corre antes su reversa';
  end if;
  if exists (select 1 from pg_proc p where p.prosrc ~ 'op_bases_carga'
              and p.oid not in (to_regprocedure('private.trg_leads_base_cargada_solo_puerta()'), to_regprocedure('private.bases_carga_nace_dormido(text,text,text,boolean)'),
                                to_regprocedure('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)'))) then
    raise exception 'REVERSA B8: otra funcion usa la valvula crm.op_bases_carga: revisalo a mano';
  end if;
  if exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
              where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema')
                and pg_get_viewdef(c.oid) ~ 'crear_base|cargar_base_lote|armar_base_crm|bases_carga_') then
    raise exception 'REVERSA B8: hay vistas que usan B8: corre antes su reversa';
  end if;
end;
$chk$;

-- Foto del censo ANTES de los candados de tabla (solo catálogo).
create temp table _rb8_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

lock table crm.leads in access exclusive mode;
lock table crm.enfriamiento_politica in access exclusive mode;
lock table crm.bases_carga, crm.base_carga_leads, crm.base_carga_operaciones in share mode;

-- r2: foto (bajo los candados) de lo que la reversa NO debe cambiar: los triggers ajenos de crm.leads (nombre, función,
-- habilitado; sin comentarios, que dependen del entorno) y las restricciones del enfriamiento salvo el CHECK de B8.
create temp table _rb8_disparadores_antes on commit drop as
  select t.tgname::text as nombre, t.tgfoid::regprocedure::text as funcion, t.tgenabled::text as habilitado
    from pg_trigger t
   where t.tgrelid = 'crm.leads'::regclass and not t.tgisinternal and t.tgname <> 'trg_leads_zz_sello_descarte_base_cargada';
create temp table _rb8_restricciones_antes on commit drop as
  select c.conname::text as nombre, pg_get_constraintdef(c.oid) as definicion
    from pg_constraint c
   where c.conrelid = 'crm.enfriamiento_politica'::regclass and c.conname <> 'enfriamiento_politica_base_cargada_dias_positivos';

-- Lo vivo es EXACTAMENTE lo que dejó B8 (comprobado bajo los candados).
do $huellas$
declare
  v_deriva text;
begin
  with esperado(pieza, huella) as (values
      ('check', '520425c7e0cfaa6407beb1edbb9c3e3d'),
      ('crm.armar_base_crm(uuid,text,uuid,uuid[])', '134986bed6fbe8731dea09e09c44553b'),
      ('crm.cargar_base_lote(uuid,uuid,jsonb)', '8a1eded2b6dd1972af0008ebaf059000'),
      ('crm.crear_base(uuid,text,text,uuid,text)', 'bfc5b71441ffdc3fc44e447106b1f271'),
      ('private.bases_carga_armar_core(uuid,uuid,text,uuid,uuid[])', 'bd7bf4a3fb64fca8a93c4790d89e47b8'),
      ('private.bases_carga_armar_respuesta(jsonb,uuid[])', '02c870e048f227d71b25e21164efadff'),
      ('private.bases_carga_base_visible(uuid,text,uuid)', '33cbc8f99bae99127d46dfafc9d6edcf'),
      ('private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)', 'b8c1b5bbd1d1f4a67494eb0da6b51866'),
      ('private.bases_carga_constantes()', 'd4ea5693ab34872ab5f4905a90b51c36'),
      ('private.bases_carga_contacto_existente(text,text)', '3f7bfc2f6f042bf7331bfcdc78964268'),
      ('private.bases_carga_crear_core(uuid,uuid,text,text,uuid,text)', '0128e41b4d4854e382afa1e9465bc724'),
      ('private.bases_carga_en_subarbol(uuid[],uuid,uuid)', '4fd848b95439523b00981ff239f6f73d'),
      ('private.bases_carga_error_transitorio(text)', 'dc3bc2b03248a84b865ea2d4ac788ce3'),
      ('private.bases_carga_fuera_de_ambito(uuid,text,text,text)', 'fa1e99a7e31079562083461805037808'),
      ('private.bases_carga_insertar_base(uuid,uuid,text,text,uuid,text)', '5ddfa4ac63776d107210b320ba9c49cd'),
      ('private.bases_carga_lead_ref(uuid,text,uuid)', '39314ad1e31aca132f0417e74e05aaf4'),
      ('private.bases_carga_nace_dormido(text,text,text,boolean)', '9aa8ff4c209d8c2cd3f71dd4d47f73d5'),
      ('private.bases_carga_operacion_previa(uuid,text,uuid,text,text,uuid[])', '706501c77918a31a34b0647cb1efdf14'),
      ('private.bases_carga_rol(uuid)', 'b9d326e7c21c39a9d70eb1931e91a784'),
      ('private.bases_carga_subarbol(uuid)', '5db6a178f2139a70a9a7f2f15fd1efc3'),
      ('private.bases_carga_supervisor_destino(uuid,text,uuid)', '61fd9c92e3913a845f5b7bfb9e841c92'),
      ('private.leads_before_insert()', '8c7de3997d3ad2b154961c979e78a856'),
      ('private.trg_leads_disponibilidad_atomica()', 'db1d62f7812cf75465757900a826ae02'),
      ('private.trg_leads_sello_descarte_base_cargada()', '76d77c514af71fd796aee126c52eed2f'),
      ('private.trg_leads_sla_versionado()', '0eabb0f4a25734a7110f672d164a7215'),
      ('trigger', '8762d4f4969971c01f87e914223e9250')),
  vivo(pieza, huella) as (
    select e.pieza, md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|'
           || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), ''))
      from esperado e join pg_proc p on p.oid = to_regprocedure(e.pieza)
     where e.pieza not in ('trigger', 'check')
    union all
    select 'check', md5(pg_get_constraintdef(c.oid) || '|' || c.convalidated::text || '|' || coalesce(obj_description(c.oid, 'pg_constraint'), ''))
      from pg_constraint c where c.conrelid = 'crm.enfriamiento_politica'::regclass and c.conname = 'enfriamiento_politica_base_cargada_dias_positivos'
    union all
    select 'trigger', md5(pg_get_triggerdef(t.oid) || '|' || t.tgenabled::text || '|' || coalesce(obj_description(t.oid, 'pg_trigger'), ''))
      from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_descarte_base_cargada')
  select string_agg(e.pieza, ', ' order by e.pieza) into v_deriva
    from esperado e left join vivo v on v.pieza = e.pieza
   where v.huella is distinct from e.huella;
  if v_deriva is not null then
    raise exception 'REVERSA B8: deriva en %: lo vivo no es lo que dejo B8 (algo lo cambio despues); no se sobrescribe, revisalo a mano', v_deriva;
  end if;
  -- Y nada más con el nombre del núcleo de B8 (una sobrecarga nueva sería trabajo posterior).
  if (select count(*) from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
        and (p.proname like 'bases\_carga\_%' or p.proname in ('crear_base', 'cargar_base_lote', 'armar_base_crm', 'trg_leads_sello_descarte_base_cargada'))
        and p.oid <> to_regprocedure('private.bases_carga_operacion_inmutable()')) <> 21 then
    raise exception 'REVERSA B8: deriva en el numero de funciones de B8 (sobrecargas nuevas): revisalo a mano';
  end if;
end;
$huellas$;

-- Solo sin datos (bajo los candados: nada entra hasta el commit).
do $vacio$
begin
  if exists (select 1 from crm.bases_carga) or exists (select 1 from crm.base_carga_leads) or exists (select 1 from crm.base_carga_operaciones)
     or exists (select 1 from crm.leads l where l.origen = 'base_cargada' or l.motivo_descarte = 'base_cargada') then
    raise exception 'REVERSA B8: hay bases, filas, recibos o contactos cargados (origen o motivo base_cargada): no se revierte (cerrar y observar)';
  end if;
end;
$vacio$;

-- ── Deshacer ──
drop trigger trg_leads_zz_sello_descarte_base_cargada on crm.leads;
alter table crm.enfriamiento_politica drop constraint enfriamiento_politica_base_cargada_dias_positivos;

create or replace function private.leads_before_insert()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'crm', 'public'
as $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Tambien aplica a importaciones y mantenimiento: no crear nuevos Otro.
  -- B7: base_cargada solo con la valvula de la carga de bases (trg_leads_000_base_cargada_solo_puerta).
  if new.origen is null or new.origen not in ('referido','landing','formulario','oficina','web','campania','whatsapp','base_cargada') then
    raise exception using errcode = '22023', message = 'Selecciona un canal concreto: Landing, Formulario, Referido o Walking';
  end if;
  if not v_priv then
    if new.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada') then
      raise exception 'Un lead nuevo no puede nacer en estado terminal';
    end if;
    new.perfil_id := null;
    new.contrato_id := null;
    new.convertido_en := null;
  end if;
  return new;
end;
$function$;

create or replace function private.trg_leads_disponibilidad_atomica()
 returns trigger
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '5s'
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_disponibilidad jsonb;
  v_cambio_identidad boolean;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_descartado_por text;
  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if tg_op = 'UPDATE' then
    if new.telefono is distinct from old.telefono then
      new.telefono := private.normalizar_telefono(new.telefono);
      if new.telefono is null or new.telefono !~ '^\+519[0-9]{8}$' then
        raise exception using errcode = '22023', message = 'Telefono invalido';
      end if;
    end if;

    if new.dni is distinct from old.dni then
      new.dni := nullif(pg_catalog.btrim(new.dni), '');
      if new.dni is not null and new.dni !~ '^[0-9]{8}$' then
        raise exception using errcode = '22023', message = 'DNI invalido';
      end if;
    end if;

    v_cambio_identidad := new.telefono is distinct from old.telefono
      or new.dni is distinct from old.dni;

    perform private.bloquear_contactos_lead(
      array[old.telefono, new.telefono],
      array[old.dni, new.dni]
    );

    -- F2.b (b5) [E3-6]: la corrección de documento de Gerencia (RPC definer bajo válvula Y con su
    -- GUC propia crm.correccion_documento) cambia SOLO el DNI de un lead que conserva su persona; los terceros (otra identidad,
    -- otro cliente del Portal, otro lead vivo) ya los comprobó la RPC bajo sus locks. Ningún
    -- otro escritor bajo válvula cambia el DNI; fuera de esta forma exacta nada cambia.
    if v_priv and coalesce(pg_catalog.current_setting('crm.correccion_documento', true) = 'on', false)
       and private.resolver_en_puertas_bajo_candado()
       and new.dni is distinct from old.dni and new.telefono is not distinct from old.telefono
       and new.no_contactar = old.no_contactar and new.etapa = old.etapa and new.activo = old.activo
       and new.motivo_descarte is not distinct from old.motivo_descarte
       and old.inversionista_id is not null and new.inversionista_id = old.inversionista_id then
      return new;
    end if;
    if not v_cambio_identidad or v_actor is null then
      return new;
    end if;

    v_rol := private.rol_crm(v_actor);
    if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
      raise exception using errcode = '42501', message = 'Acceso CRM revocado';
    end if;

    -- Excluir OLD al validar el destino es correcto para un lead operativo,
    -- pero no debe permitir «mover» un No contactar o un enfriamiento y dejar
    -- libre la identidad anterior. Ambos vetos propios congelan teléfono y DNI
    -- mientras sigan vigentes; levantarlos es una operación separada y auditable.
    if old.no_contactar = true then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = pg_catalog.jsonb_build_object('estado', 'no_contactar')::text;
    end if;

    if old.etapa = 'descartado'
       and old.descartado_en is not null
       and old.motivo_descarte is not null then
      select
        ep.dias,
        old.descartado_en + pg_catalog.make_interval(days => ep.dias),
        p.nombre_completo
      into v_dias, v_disponible_desde, v_descartado_por
      from crm.enfriamiento_politica ep
      left join public.perfiles p on p.id = old.descartado_por
      where ep.motivo = old.motivo_descarte;

      if coalesce(v_dias, 0) > 0
         and v_disponible_desde > pg_catalog.now() then
        raise exception using
          errcode = 'P0481',
          message = 'Contacto no disponible',
          detail = pg_catalog.jsonb_build_object(
            'estado', 'enfriamiento',
            'motivo_descarte', old.motivo_descarte,
            'disponible_desde', v_disponible_desde,
            'descartado_por', v_descartado_por
          )::text;
      end if;
    end if;

    v_disponibilidad := private.verificar_disponibilidad_lead_impl(
      new.telefono,
      new.dni,
      old.id
    );
    if v_disponibilidad ->> 'estado' is distinct from 'libre' then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_disponibilidad::text;
    end if;
    return new;
  end if;

  new.telefono := private.normalizar_telefono(new.telefono);
  new.dni := nullif(pg_catalog.btrim(new.dni), '');

  if new.telefono is null or new.telefono !~ '^\+519[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'Telefono invalido';
  end if;
  if new.dni is not null and new.dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'DNI invalido';
  end if;

  perform private.bloquear_contactos_lead(array[new.telefono], array[new.dni]);

  -- Un escritor interno sin sesion humana se serializa, pero conserva su
  -- contrato especializado (por ejemplo crm-importar-leads con service_role).
  if v_actor is null then
    return new;
  end if;

  v_rol := private.rol_crm(v_actor);
  if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- La compatibilidad temporal es solo para el alta que ya hacía el bundle
  -- anterior. No abre una vía para fabricar leads terminales o inactivos.
  if new.activo is distinct from true
     or new.etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception using errcode = '22023', message = 'Un lead debe nacer activo y en etapa operativa';
  end if;

  v_disponibilidad := private.verificar_disponibilidad_lead_impl(new.telefono, new.dni);
  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    raise exception using
      errcode = 'P0481',
      message = 'Contacto no disponible',
      detail = v_disponibilidad::text;
  end if;

  return new;
end;
$function$;

create or replace function private.trg_leads_sla_versionado()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'pg_catalog'
as $function$
declare
  v_en timestamptz;
  v_p crm.sla_politicas%rowtype;
  v_maximo integer;
  v_n integer;
  v_motivo text;
begin
  v_en:=case when tg_op='INSERT' then new.sla_global_iniciado_en else statement_timestamp() end;
  perform set_config('crm.sla_writer','on',true);

  if tg_op='INSERT' or new.ciclo_actual is distinct from old.ciclo_actual then
    select p.* into v_p from crm.sla_politicas p
    where p.id=private.sla_politica_vigente(new.sla_global_iniciado_en);
    if not found then raise exception 'No existe politica SLA para el ciclo'; end if;
    insert into crm.lead_sla_ciclos(
      lead_id,ciclo_n,politica_id,iniciado_en,primera_gestion_limite_en,primer_contacto_limite_en
    ) values(new.id,new.ciclo_actual,v_p.id,new.sla_global_iniciado_en,
      new.sla_global_iniciado_en+v_p.primera_gestion_minutos*interval '1 minute',
      new.sla_global_iniciado_en+v_p.primer_contacto_minutos*interval '1 minute');
  end if;

  if tg_op='UPDATE' and (
    new.ciclo_actual is distinct from old.ciclo_actual or new.etapa is distinct from old.etapa
    or (old.activo and not new.activo)
  ) then
    v_motivo:=case
      when new.ciclo_actual is distinct from old.ciclo_actual then 'reapertura'
      when old.activo and not new.activo then 'desactivacion'
      when new.etapa in ('convertido','descartado') then 'cierre_terminal'
      else 'cambio_etapa' end;
    update crm.lead_sla_etapas set finalizado_en=v_en,motivo_cierre=v_motivo
    where lead_id=new.id and finalizado_en is null;
  end if;

  if new.activo and new.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and (tg_op='INSERT' or new.ciclo_actual is distinct from old.ciclo_actual
      or new.etapa is distinct from old.etapa or (not old.activo and new.activo)) then
    select p.* into v_p
    from crm.sla_politicas p
    where p.id=private.sla_politica_vigente(v_en);
    if not found then raise exception 'No existe politica SLA vigente'; end if;
    select pe.maximo_minutos into v_maximo
    from crm.sla_politica_etapas pe
    where pe.politica_id=v_p.id and pe.etapa=new.etapa;
    if not found then raise exception 'No existe SLA para etapa %',new.etapa; end if;
    select coalesce(max(e.episodio_n),0)+1 into v_n from crm.lead_sla_etapas e
    where e.lead_id=new.id and e.ciclo_n=new.ciclo_actual;
    insert into crm.lead_sla_etapas(
      lead_id,ciclo_n,episodio_n,etapa,politica_id,iniciado_en,limite_en
    ) values(new.id,new.ciclo_actual,v_n,new.etapa,v_p.id,v_en,
      v_en+v_maximo*interval '1 minute');
  end if;
  perform set_config('crm.sla_writer','off',true);
  return new;
end;
$function$;

comment on function private.leads_before_insert() is
'Alta de un lead (BEFORE INSERT): exige un canal concreto (sin nuevos Otro; base_cargada solo con la válvula de la carga de bases, B7 04/10/2026, la reserva vive en private.trg_leads_base_cargada_solo_puerta) y, sin crm.op_privilegiada, impide nacer en estado terminal y enlazar perfil, contrato o conversión. DEFINER, search_path crm, public.';
comment on function private.trg_leads_disponibilidad_atomica() is
'Serializa contactos y preserva vetos entre la RPC humana, importadores privilegiados y cambios de identidad.';
comment on function private.trg_leads_sla_versionado() is null;

drop function crm.crear_base(uuid, text, text, uuid, text);
drop function crm.cargar_base_lote(uuid, uuid, jsonb);
drop function crm.armar_base_crm(uuid, text, uuid, uuid[]);
drop function private.bases_carga_armar_core(uuid, uuid, text, uuid, uuid[]);
drop function private.bases_carga_armar_respuesta(jsonb, uuid[]);
drop function private.bases_carga_cargar_lote_core(uuid, uuid, uuid, jsonb);
drop function private.bases_carga_crear_core(uuid, uuid, text, text, uuid, text);
drop function private.bases_carga_contacto_existente(text, text);
drop function private.bases_carga_insertar_base(uuid, uuid, text, text, uuid, text);
drop function private.bases_carga_operacion_previa(uuid, text, uuid, text, text, uuid[]);
drop function private.bases_carga_fuera_de_ambito(uuid, text, text, text);
drop function private.bases_carga_error_transitorio(text);
drop function private.bases_carga_lead_ref(uuid, text, uuid);
drop function private.bases_carga_en_subarbol(uuid[], uuid, uuid);
drop function private.bases_carga_subarbol(uuid);
drop function private.bases_carga_base_visible(uuid, text, uuid);
drop function private.bases_carga_supervisor_destino(uuid, text, uuid);
drop function private.bases_carga_rol(uuid);
drop function private.trg_leads_sello_descarte_base_cargada();
drop function private.bases_carga_nace_dormido(text, text, text, boolean);
drop function private.bases_carga_constantes();

-- ── Postflight (catálogo): todo como en B7 ──
create temp table _rb8_censo_despues on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;
do $post$
begin
  if (
    -- Las tres del alta, idénticas a B7 (texto, seguridad, configuración, dueño, ACL y comentario).
    (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|'
            || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '')) = '2bbe78715b418a8987eadaf7907dc434'
       from pg_proc p where p.oid = to_regprocedure('private.leads_before_insert()'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|'
            || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '')) = '1ff5ec482d316ae97e690d72417574bb'
       from pg_proc p where p.oid = to_regprocedure('private.trg_leads_disponibilidad_atomica()'))
    and (select md5(p.prosrc || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || coalesce(array_to_string(p.proconfig, ','), '') || '|'
            || p.proowner::regrole::text || '|' || coalesce(p.proacl::text, 'NULL') || '|' || coalesce(obj_description(p.oid, 'pg_proc'), '')) = '9d57885819fba31e1499e70227becea5'
       from pg_proc p where p.oid = to_regprocedure('private.trg_leads_sla_versionado()'))
    -- r2: los triggers de crm.leads son los de la foto (nombre, función y habilitado: sin el de B8 y sin tocar ninguno ajeno).
    and not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_descarte_base_cargada')
    and not exists ((select t.tgname::text, t.tgfoid::regprocedure::text, t.tgenabled::text
                       from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and not t.tgisinternal
                     except select a.nombre, a.funcion, a.habilitado from pg_temp._rb8_disparadores_antes a)
                    union all
                    (select a.nombre, a.funcion, a.habilitado from pg_temp._rb8_disparadores_antes a
                     except select t.tgname::text, t.tgfoid::regprocedure::text, t.tgenabled::text
                       from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and not t.tgisinternal))
    -- … y el enfriamiento con las restricciones de la foto (sin el CHECK de B8).
    and not exists ((select c.conname::text, pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'crm.enfriamiento_politica'::regclass
                     except select a.nombre, a.definicion from pg_temp._rb8_restricciones_antes a)
                    union all
                    (select a.nombre, a.definicion from pg_temp._rb8_restricciones_antes a
                     except select c.conname::text, pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'crm.enfriamiento_politica'::regclass))
    -- Ningún objeto de B8; B7 intacta (sus tablas y su sello).
    and not exists (select 1 from pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
                     and (p.proname like 'bases\_carga\_%' or p.proname in ('crear_base', 'cargar_base_lote', 'armar_base_crm', 'trg_leads_sello_descarte_base_cargada'))
                     and p.oid <> to_regprocedure('private.bases_carga_operacion_inmutable()'))
    and to_regclass('crm.bases_carga') is not null and to_regprocedure('private.trg_leads_base_cargada_solo_puerta()') is not null
    -- El sello del descarte con la huella que sella assert_gestion_diaria_resultado.
    and (select md5(pg_get_functiondef(p.oid)) = '150d7ae56bb2094733f7620a1362c29e' from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_sello_descarte()'))
    -- Censo igual.
    and not exists (select 1 from pg_temp._rb8_censo_despues c where c.objeto not in (select a.objeto from pg_temp._rb8_censo_antes a))
    and (select count(*) from pg_temp._rb8_censo_antes) = (select count(*) from pg_temp._rb8_censo_despues)
  ) is not true then
    raise exception 'REVERSA B8: el estado final no es el de B7 (funciones del alta, disparadores de crm.leads, objetos de B8, sello del descarte o censo)';
  end if;
  raise notice 'REVERSA B8 OK: sin puertas ni nucleo de B8 ni su CHECK del enfriamiento; leads_before_insert, disponibilidad y sla_versionado como en B7; disparadores de crm.leads como en B7; censo igual.';
end;
$post$;
notify pgrst, 'reload schema';
commit;

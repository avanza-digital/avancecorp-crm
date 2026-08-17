-- F1 del plan «Verificación y toma de lead libre» (nota del vault, 2026-08-16).
-- Tres piezas, todas ADITIVAS:
--   1. crm.politica_abandono — las perillas de gerencia: Y (días sin conversación
--      real para considerar abandonado un lead tomado) y X (días de alerta
--      ignorada antes de caer a la bolsa). Nacen AQUÍ sin efectos — el motor que
--      las consume llega en F4/F5 — para que la fuente sea ÚNICA desde el día uno
--      (hoy conviven un 5 hardcodeado en el servidor y un 7 en el cliente).
--   2. crm.verificaciones_lead — registro anti-pesca de la verificación por
--      contacto: quién buscó qué identidad y con qué veredicto. SELECT solo
--      gerencia. Un vendedor legítimo puede iterar DNIs; sin esto, sin rastro.
--   3. La RPC de disponibilidad se enriquece: 'tomado' gana
--      ultima_conversacion_en (la última CONVERSACIÓN real — llamada_realizada,
--      whatsapp_recibido, reunion_realizada: espejo de TIPOS_CONVERSACION y del
--      WHEN de trg_zz_actividades_avance_etapa; los INTENTOS no cuentan,
--      decisión dura de Miguel 2026-08-16) y el wrapper pasa a VOLATILE para
--      asentar el registro. fecha_estimada de los TOMADOS llega recién en F4,
--      cuando exista el motor que la haga verdad — la tarjeta no promete.
--
-- ⚠️ ORDEN DE DEPLOY (no negociable): el front tolerante (commit 72d97f4,
-- release 28.º) debe estar VIVO antes de mergear esto a producción — clave
-- nueva en la RESPUESTA de una RPC con contrato estricto → FRONT PRIMERO
-- (la lección del 2026-08-15).

-- ── 0. Guardas de fidelidad ──────────────────────────────────────────────────
-- Esta migración re-crea dos funciones COPIANDO su cuerpo vigente + el cambio.
-- Si producción ya no es lo que se copió, se detiene ANTES de pisar nada.
do $$
declare
  v_md5 text;
begin
  select md5(p.prosrc) into v_md5
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'verificar_disponibilidad_lead_impl'
    and pg_get_function_identity_arguments(p.oid) = 'p_telefono text, p_dni text, p_excluir_lead_id uuid';
  if v_md5 is distinct from '7063fc89858587086037c53213e8a145' then
    raise exception 'impl canónico distinto del anclado (md5 %): re-anclar la migración antes de aplicar', coalesce(v_md5, 'AUSENTE');
  end if;

  select md5(p.prosrc) into v_md5
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm'
    and p.proname = 'verificar_disponibilidad_lead';
  if v_md5 is distinct from 'a1de9063b2674341cec8f54743564072' then
    raise exception 'wrapper distinto del anclado (md5 %): re-anclar la migración antes de aplicar', coalesce(v_md5, 'AUSENTE');
  end if;
end $$;

-- ── 1. crm.politica_abandono ─────────────────────────────────────────────────
create table crm.politica_abandono (
  -- Fila ÚNICA por diseño (patrón singleton): las perillas son globales.
  singleton boolean primary key default true check (singleton),
  dias_abandono integer not null check (dias_abandono between 1 and 365),
  dias_auto_bolsa integer not null check (dias_auto_bolsa between 1 and 365),
  actualizado_por uuid references public.perfiles(id),
  actualizado_en timestamptz not null default now()
);

comment on table crm.politica_abandono is
  'Perillas del plan lead libre, editables solo por gerencia. dias_abandono (Y): días sin CONVERSACIÓN real (TIPOS_CONVERSACION) medidos ante el dueño ACTUAL — greatest(última conversación, tenencia_desde) — para considerar abandonado un lead tomado. dias_auto_bolsa (X): días de alerta de abandono ignorada antes de que el barrido lo baje a la bolsa. El motor que las consume llega en F4/F5; nacen antes para que la fuente sea única.';
comment on column crm.politica_abandono.dias_abandono is
  'Y — el reloj JAMÁS se resetea con intentos (llamada no contestada, whatsapp enviado): solo conversaciones reales. Decisión de Miguel 2026-08-16.';
comment on column crm.politica_abandono.dias_auto_bolsa is
  'X — «confirmar seguimiento» del supervisor NO lo detiene: solo una conversación real posterior. Decisión de Miguel 2026-08-16.';

insert into crm.politica_abandono (singleton, dias_abandono, dias_auto_bolsa)
values (true, 7, 7);

alter table crm.politica_abandono enable row level security;

-- Predicado de la era post-endurecimiento (espejo de sla_politicas/meta_periodos):
-- las tablas nuevas NO heredan crm_actor_activo_gate, así que el filtro va aquí.
-- `using (true)` habría dejado leer las perillas a clientes del portal y a
-- miembros revocados (hallazgo del auditor, 2026-08-16).
create policy politica_abandono_select on crm.politica_abandono
  for select to authenticated
  using (
    (select private.es_lector_global())
    or (select private.rol_crm((select auth.uid()))) is not null
  );

create policy politica_abandono_update on crm.politica_abandono
  for update to authenticated
  using (private.rol_crm((select auth.uid())) = 'gerencia')
  with check (private.rol_crm((select auth.uid())) = 'gerencia');

-- Sin INSERT ni DELETE: la fila única nace aquí y no se borra jamás.

-- Autoría SELLADA en servidor (auditor M2): PostgREST no puede dejar rancio el
-- actualizado_en ni firmar con otro autor — el trigger pisa lo que llegue.
create function crm.politica_abandono_sellar_autoria()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.actualizado_por := (select auth.uid());
  new.actualizado_en := pg_catalog.now();
  return new;
end;
$$;

revoke all on function crm.politica_abandono_sellar_autoria()
  from public, anon, authenticated;

create trigger trg_politica_abandono_00_autoria
  before update on crm.politica_abandono
  for each row execute function crm.politica_abandono_sellar_autoria();

create trigger trg_audit_politica_abandono
  after insert or delete or update on crm.politica_abandono
  for each row execute function private.log_audit_crm();

revoke all on crm.politica_abandono from public, anon;
grant select, update on crm.politica_abandono to authenticated;

-- ── 2. crm.verificaciones_lead ───────────────────────────────────────────────
create table crm.verificaciones_lead (
  id uuid primary key default gen_random_uuid(),
  verificado_por uuid not null references public.perfiles(id),
  telefono_consultado text not null,
  dni_consultado text,
  veredicto text not null,
  creado_en timestamptz not null default now()
);

comment on table crm.verificaciones_lead is
  'Registro anti-pesca de la verificación por contacto (F1 lead libre): cada llamada a crm.verificar_disponibilidad_lead deja quién buscó qué identidad y el veredicto. Lo escribe SOLO la RPC (security definer); por policy lo lee gerencia — y, como TODA tabla crm.* auditada, su rastro en public.audit_log es legible por admin/superadmin del portal (vía preexistente; la bandeja del portal filtra tabla IN (perfiles, contratos) y NO lo muestra — verificado en prod 2026-08-16, md5 bandeja_actividad ff1bd19f…). Los prechecks internos del alta atómica llaman al impl directo y no dejan fila.';

alter table crm.verificaciones_lead enable row level security;

create policy verificaciones_lead_select on crm.verificaciones_lead
  for select to authenticated
  using (private.rol_crm((select auth.uid())) = 'gerencia');

-- Sin policies de escritura: nadie escribe por PostgREST — solo la RPC.

create index verificaciones_lead_autor_idx
  on crm.verificaciones_lead (verificado_por, creado_en desc);

create trigger trg_audit_verificaciones_lead
  after insert or delete or update on crm.verificaciones_lead
  for each row execute function private.log_audit_crm();

revoke all on crm.verificaciones_lead from public, anon;
grant select on crm.verificaciones_lead to authenticated;

-- ── 3a. El impl canónico gana ultima_conversacion_en ─────────────────────────
-- Cuerpo VIGENTE copiado tal cual (guarda md5 arriba) + DOS cambios en la rama
-- 'tomado': se selecciona l.id y se añade la última conversación real. El
-- delegador de 2 argumentos (contrato público histórico) no se toca: delega
-- aquí y sirve el enriquecimiento solo.
create or replace function private.verificar_disponibilidad_lead_impl(
  p_telefono text,
  p_dni text,
  p_excluir_lead_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tel text := private.normalizar_telefono(p_telefono);
  v_lead record;
  v_perfil record;
  v_dias integer;
  v_disponible_desde timestamptz;
begin
  if v_tel is null or pg_catalog.length(v_tel) = 0 then
    return pg_catalog.jsonb_build_object(
      'estado', 'error',
      'detalle', 'telefono_invalido'
    );
  end if;

  if exists (
    select 1
    from crm.leads l
    where l.id is distinct from p_excluir_lead_id
      and l.no_contactar = true
      and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  ) then
    return pg_catalog.jsonb_build_object('estado', 'no_contactar');
  end if;

  select per.id, asesor.nombre_completo as asesor_nombre
  into v_perfil
  from public.perfiles per
  left join public.perfiles asesor on asesor.id = per.asesor_perfil_id
  where per.rol = 'cliente'
    and per.activo = true
    and (
      private.normalizar_telefono(per.telefono) = v_tel
      or (p_dni is not null and per.dni = p_dni)
    )
  limit 1;

  if found then
    return pg_catalog.jsonb_build_object(
      'estado', 'ya_es_cliente',
      'asesor', coalesce(v_perfil.asesor_nombre, 'sin asesor asignado')
    );
  end if;

  select
    l.id,
    l.tenencia_desde,
    l.vendedor_id,
    l.asignado_supervisor_id,
    coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
  into v_lead
  from crm.leads l
  left join public.perfiles pv on pv.id = l.vendedor_id
  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
  where l.id is distinct from p_excluir_lead_id
    and l.activo = true
    and l.etapa not in ('convertido', 'descartado')
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  limit 1;

  if found then
    if v_lead.vendedor_id is null and v_lead.asignado_supervisor_id is null then
      return pg_catalog.jsonb_build_object('estado', 'en_bolsa');
    end if;
    return pg_catalog.jsonb_build_object(
      'estado', 'tomado',
      'vendedor', v_lead.tenedor,
      'tenencia_desde', v_lead.tenencia_desde,
      -- La última CONVERSACIÓN real: «¿el cliente RESPONDIÓ?» — espejo de
      -- TIPOS_CONVERSACION (tipos.ts) y del WHEN de
      -- trg_zz_actividades_avance_etapa. Los intentos (llamada_no_contestada,
      -- whatsapp_enviado) NO cuentan: decisión dura de Miguel, 2026-08-16.
      -- NULL si jamás hubo conversación — la tarjeta no pinta la línea.
      'ultima_conversacion_en', (
        select pg_catalog.max(a.creado_en)
        from crm.actividades a
        where a.lead_id = v_lead.id
          and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
      )
    );
  end if;

  select
    l.motivo_descarte,
    l.descartado_en,
    pd.nombre_completo as descartado_por_nombre
  into v_lead
  from crm.leads l
  left join public.perfiles pd on pd.id = l.descartado_por
  where l.id is distinct from p_excluir_lead_id
    and l.etapa = 'descartado'
    and l.descartado_en is not null
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  order by l.descartado_en desc
  limit 1;

  if found then
    select ep.dias
    into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;

    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en
      + pg_catalog.make_interval(days => v_dias);

    if v_dias > 0 and v_disponible_desde > pg_catalog.now() then
      return pg_catalog.jsonb_build_object(
        'estado', 'enfriamiento',
        'motivo_descarte', v_lead.motivo_descarte,
        'disponible_desde', v_disponible_desde,
        'descartado_por', v_lead.descartado_por_nombre
      );
    end if;
  end if;

  return pg_catalog.jsonb_build_object('estado', 'libre');
end;
$$;

comment on function private.verificar_disponibilidad_lead_impl(text, text, uuid) is
  'P-047 impl canónico. Desde F1 lead libre (2026-08-16): el estado tomado incluye ultima_conversacion_en — la última conversación REAL (llamada_realizada, whatsapp_recibido, reunion_realizada); los intentos no cuentan. p_excluir_lead_id permite al alta atómica no detectarse a sí misma.';

revoke all on function private.verificar_disponibilidad_lead_impl(text, text, uuid)
  from public, anon, authenticated, service_role;

-- ── 3b. El wrapper registra y pasa a VOLATILE ────────────────────────────────
create or replace function crm.verificar_disponibilidad_lead(
  p_telefono text,
  p_dni text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_rol text := private.rol_crm((select auth.uid()));
  v_resultado jsonb;
begin
  if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using
      errcode = '42501',
      message = 'Acceso CRM revocado';
  end if;

  v_resultado := private.verificar_disponibilidad_lead_impl(p_telefono, p_dni);

  -- Registro anti-pesca (F1 lead libre): la búsqueda por identidad deja
  -- rastro legible por gerencia. Se asienta TODO intento, también el teléfono
  -- inválido — iterar identidades es exactamente lo que se vigila. Si el
  -- normalizado no existe se guarda lo tecleado, acotado.
  insert into crm.verificaciones_lead (verificado_por, telefono_consultado, dni_consultado, veredicto)
  values (
    (select auth.uid()),
    pg_catalog.left(coalesce(private.normalizar_telefono(p_telefono), p_telefono, ''), 32),
    pg_catalog.left(p_dni, 16),
    v_resultado ->> 'estado'
  );

  return v_resultado;
end;
$$;

comment on function crm.verificar_disponibilidad_lead(text, text) is
  'P-047 con gate P04 + registro anti-pesca (F1 lead libre, por eso VOLATILE). Estados y reglas de negocio intactos; tomado incluye ultima_conversacion_en. Ejecutable solo por vendedor, supervisor o gerencia plenamente activos.';

revoke all on function crm.verificar_disponibilidad_lead(text, text)
  from public, anon;
grant execute on function crm.verificar_disponibilidad_lead(text, text) to authenticated;

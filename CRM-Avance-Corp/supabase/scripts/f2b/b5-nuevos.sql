-- ---------------------------------------------------------------------------
-- 2.1 Libro append-only de operaciones de Gerencia sobre identidades (corrección, enlace)
--     (la fusión tiene su propio libro; la reasignación, el ledger de tramos). Patrón F1: RLS, sin grants, auditado.
-- ---------------------------------------------------------------------------
create table if not exists crm.inversionista_operaciones (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('correccion','enlace')),
  inversionista_id uuid not null references crm.inversionistas(id),
  lead_id uuid references crm.leads(id),
  identificador_anterior_id uuid references crm.inversionista_identificadores(id),
  identificador_nuevo_id uuid references crm.inversionista_identificadores(id),
  motivo text not null check (length(btrim(motivo)) between 3 and 500),
  detalle jsonb,
  por uuid references public.perfiles(id),
  creado_en timestamptz not null default now() check (isfinite(creado_en))
);
comment on table crm.inversionista_operaciones is
  'F2.b b5: libro append-only de operaciones de Gerencia sobre identidades (correccion de documento, enlace de lead suelto). Guarda ids y motivo; NUNCA el documento en claro. RLS activa, sin grants a la Data API. Se conserva en la reversa.';
create index if not exists inv_operaciones_inv_idx on crm.inversionista_operaciones (inversionista_id);
alter table crm.inversionista_operaciones enable row level security;
revoke all on crm.inversionista_operaciones from public, anon, authenticated, service_role;
drop policy if exists inversionista_operaciones_select_gerencia on crm.inversionista_operaciones;
create policy inversionista_operaciones_select_gerencia on crm.inversionista_operaciones
  for select to authenticated using (private.es_gerencia_crm_activa());
drop trigger if exists trg_audit_inversionista_operaciones on crm.inversionista_operaciones;
create trigger trg_audit_inversionista_operaciones
  after insert or update or delete on crm.inversionista_operaciones
  for each row execute function private.log_audit_crm();
create or replace function private.inversionista_operaciones_append_only() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'crm.inversionista_operaciones es append-only: % no permitido', tg_op using errcode = '0A000';
end $$;
revoke all on function private.inversionista_operaciones_append_only() from public, anon, authenticated, service_role;
drop trigger if exists trg_inversionista_operaciones_append_only on crm.inversionista_operaciones;
create trigger trg_inversionista_operaciones_append_only
  before update or delete on crm.inversionista_operaciones
  for each row execute function private.inversionista_operaciones_append_only();

-- ---------------------------------------------------------------------------
-- 2.2 Helpers privados (sin EXECUTE para la API)
-- ---------------------------------------------------------------------------
-- Raíz de la cadena de canónicas (máx. 16 saltos). NULL -> NULL; id sin fila -> el mismo id.
create or replace function private.inversionista_canonica(p_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  with recursive c as (
    select i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i where i.id = p_id
    union all
    select i.id, i.inversionista_canonico_id, c.n + 1
    from c join crm.inversionistas i on i.id = c.inversionista_canonico_id
    where c.n < 16
  )
  select case when p_id is null then null
              else coalesce((select c.id from c where c.inversionista_canonico_id is null order by c.n desc limit 1), p_id) end
$$;
revoke all on function private.inversionista_canonica(uuid) from public, anon, authenticated, service_role;

-- Leads de un conjunto de identidades: UNIÓN del enlace vivo (leads.inversionista_id) y del puente
-- (inversionista_leads, incluidos los históricos del backfill). Es el conjunto que cuenta para «un solo lead».
create or replace function private.leads_de_identidades(p_ids uuid[])
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select l.id from crm.leads l where l.inversionista_id = any(p_ids)
  union
  select il.lead_id from crm.inversionista_leads il where il.inversionista_id = any(p_ids)
$$;
revoke all on function private.leads_de_identidades(uuid[]) from public, anon, authenticated, service_role;

-- Foto canónica y determinista de dos identidades, SIN documentos en claro (solo los 3 últimos
-- caracteres). La previsualización la devuelve; la fusión la recalcula bajo los locks y compara.
-- Incluye las tareas pendientes de los leads (la fusión las cancela: deben estar en lo aprobado) [E3-4].
create or replace function private.fusion_estado_jsonb(p_a uuid, p_b uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object('v', 2, 'identidades', coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', i.id, 'estado', i.estado, 'perfil_id', i.perfil_id, 'responsable', i.responsable_relacion_id,
      'no_contactar', i.no_contactar, 'canonico', i.inversionista_canonico_id,
      'identificadores', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', d.id, 'tipo', d.tipo_documento, 'estado', d.estado, 'verificado', d.verificado,
          'fin', pg_catalog.right(d.documento_normalizado, 3)) order by d.id)
        from crm.inversionista_identificadores d where d.inversionista_id = i.id), '[]'::jsonb),
      'leads', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', l.id, 'etapa', l.etapa, 'activo', l.activo, 'no_contactar', l.no_contactar,
          'vendedor_id', l.vendedor_id, 'perfil_id', l.perfil_id, 'inversionista_id', l.inversionista_id) order by l.id)
        from crm.leads l where l.id in (select private.leads_de_identidades(array[i.id]))), '[]'::jsonb),
      'tareas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', t.id, 'lead_id', t.lead_id, 'estado', t.estado) order by t.id)
        from crm.tareas t where t.estado = 'pendiente' and t.lead_id in (select private.leads_de_identidades(array[i.id]))), '[]'::jsonb),
      'puente', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', il.id, 'lead_id', il.lead_id, 'rol', il.rol) order by il.id)
        from crm.inversionista_leads il where il.inversionista_id = i.id), '[]'::jsonb),
      'tramos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', r.id, 'responsable_id', r.responsable_id) order by r.id)
        from crm.inversionista_responsables r where r.inversionista_id = i.id and r.hasta is null), '[]'::jsonb),
      'cierres', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', ce.id, 'lead_id', ce.lead_id, 'vigente', ce.anulado_en is null, 'inversionista_id', ce.inversionista_id) order by ce.id)
        from crm.cierres_externos ce
        where ce.inversionista_id = i.id or ce.lead_id in (select private.leads_de_identidades(array[i.id]))), '[]'::jsonb),
      'inversiones', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', inv.id, 'estado', inv.estado, 'empresa_id', inv.empresa_id) order by inv.id)
        from crm.inversiones inv where inv.inversionista_id = i.id), '[]'::jsonb),
      'titulares', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', t.id, 'inversion_id', t.inversion_id, 'rol', t.rol) order by t.id)
        from crm.inversion_titulares t where t.inversionista_id = i.id), '[]'::jsonb),
      'reservas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'lead_id', rv.lead_id, 'inversionista_id', rv.inversionista_id, 'expira', rv.expira_en, 'sellada', rv.efectos_iniciados_en is not null) order by rv.lead_id)
        from crm.conversion_reservas rv
        where rv.inversionista_id = i.id or rv.lead_id in (select private.leads_de_identidades(array[i.id]))), '[]'::jsonb),
      'claim', (select m.resultado->>'estado' from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || i.id::text),
      'predecesoras', coalesce((select pg_catalog.jsonb_agg(p.id order by p.id) from crm.inversionistas p where p.inversionista_canonico_id = i.id), '[]'::jsonb)
    ) order by i.id)
    from crm.inversionistas i where i.id in (p_a, p_b)), '[]'::jsonb))
$$;
revoke all on function private.fusion_estado_jsonb(uuid, uuid) from public, anon, authenticated, service_role;

-- Bloqueos de una fusión (los mismos textos en la previsualización y bajo los locks de la fusión).
-- Reservas: por identidad O por lead asociado (una reserva de la RPC de un argumento no lleva identidad) [E3-7].
create or replace function private.fusion_bloqueos(p_perdedora uuid, p_canonica uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_b text[] := '{}'; v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_n integer;
begin
  if p_perdedora is null or p_canonica is null then
    return array['Faltan las dos identidades'];
  end if;
  if p_perdedora = p_canonica then
    return array['La perdedora y la canónica son la misma identidad'];
  end if;
  select * into v_p from crm.inversionistas where id = p_perdedora;
  if not found then return array['La identidad perdedora no existe']; end if;
  select * into v_c from crm.inversionistas where id = p_canonica;
  if not found then return array['La identidad canónica no existe']; end if;
  if v_p.estado = 'fusionado' then
    v_b := pg_catalog.array_append(v_b, ('La perdedora ya está fusionada: usa su canónica ' || private.inversionista_canonica(v_p.id)::text)::text);
  elsif v_p.estado <> 'activo' then
    v_b := pg_catalog.array_append(v_b, ('La perdedora no está activa (' || v_p.estado || '): revisión de Gerencia')::text);
  end if;
  if v_c.estado = 'fusionado' then
    v_b := pg_catalog.array_append(v_b, ('La canónica ya está fusionada: usa su canónica ' || private.inversionista_canonica(v_c.id)::text)::text);
  elsif v_c.estado <> 'activo' then
    v_b := pg_catalog.array_append(v_b, ('La canónica no está activa (' || v_c.estado || '): revisión de Gerencia')::text);
  end if;
  select count(*) into v_n from private.leads_de_identidades(array[p_perdedora, p_canonica]);
  if v_n > 1 then
    v_b := pg_catalog.array_append(v_b, 'Las dos identidades tienen lead (enlace vivo o puente): reconciliación de clase E hasta F5 (dos leads)'::text);
  end if;
  if v_p.perfil_id is not null and v_c.perfil_id is not null and v_p.perfil_id <> v_c.perfil_id then
    v_b := pg_catalog.array_append(v_b, 'Las dos identidades tienen perfil de cliente: reconciliación de clase E hasta F5 (dos perfiles)'::text);
  end if;
  if exists (select 1 from crm.multiempresa_idempotencia m
              where m.clave in ('auth_persona:' || p_perdedora::text, 'auth_persona:' || p_canonica::text)
                and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    v_b := pg_catalog.array_append(v_b, 'Hay un alta o conversión en curso (claim de Auth no terminal): termina o deja caducar'::text);
  end if;
  if exists (select 1 from crm.conversion_reservas r
              left join crm.leads l on l.id = r.lead_id
              where (r.inversionista_id in (p_perdedora, p_canonica)
                     or r.lead_id in (select private.leads_de_identidades(array[p_perdedora, p_canonica])))
                and (r.expira_en > pg_catalog.now()
                     or (r.efectos_iniciados_en is not null and coalesce(l.etapa, '') <> 'convertido'))) then
    v_b := pg_catalog.array_append(v_b, 'Hay una reserva de conversión viva o sellada sin convertir (por persona o por lead): termina o deja caducar'::text);
  end if;
  return v_b;
end;
$$;
revoke all on function private.fusion_bloqueos(uuid, uuid) from public, anon, authenticated, service_role;

-- Advisory de TODOS los documentos vigentes de un conjunto de identidades, ordenados por texto
-- (misma clave que private.identidad_bloquear_documento; reentrante).
create or replace function private.identidad_bloquear_documentos_de(p_ids uuid[])
returns text[]
language plpgsql
security definer
set search_path = ''
as $$
declare v_docs text[]; v_k text;
begin
  select pg_catalog.array_agg(k order by k) into v_docs
  from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
        from crm.inversionista_identificadores d
        where d.inversionista_id = any(p_ids) and d.estado = 'vigente') s;
  if v_docs is not null then
    foreach v_k in array v_docs loop
      perform private.identidad_bloquear_documento(split_part(v_k, ':', 1), split_part(v_k, ':', 2));
    end loop;
  end if;
  return coalesce(v_docs, '{}');
end;
$$;
revoke all on function private.identidad_bloquear_documentos_de(uuid[]) from public, anon, authenticated, service_role;

-- Lead FOR UPDATE NOWAIT cuando ya se retienen sus tareas (derivar toma lead->tareas; cerrar_tarea tarea->lead):
-- un conflicto se traduce a 40001 en vez de esperar dentro de un ciclo potencial [E3-9].
create or replace function private.bloquear_leads_nowait(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_n integer;
begin
  begin
    select count(*) into v_n from (select l.id from crm.leads l where l.id = any(p_ids) order by l.id for update nowait) s;
  exception when lock_not_available then
    raise exception 'El lead está en uso por otra operación; vuelve a intentarlo' using errcode = '40001';
  end;
  return v_n;
end;
$$;
revoke all on function private.bloquear_leads_nowait(uuid[]) from public, anon, authenticated, service_role;

-- Cancela las tareas pendientes de un lead como sistema (mismo sello que marcar_no_contactar, b2: crm.cancela_sistema).
create or replace function private.cancelar_tareas_pendientes_lead(p_lead_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_n integer;
begin
  perform pg_catalog.set_config('crm.cancela_sistema', 'on', true);
  update crm.tareas t set estado = 'cancelada' where t.lead_id = p_lead_id and t.estado = 'pendiente';
  get diagnostics v_n = row_count;
  perform pg_catalog.set_config('crm.cancela_sistema', 'off', true);
  return v_n;
end;
$$;
revoke all on function private.cancelar_tareas_pendientes_lead(uuid) from public, anon, authenticated, service_role;

-- El motivo de una puerta de Gerencia no puede llevar ninguno de los documentos implicados.
create or replace function private.motivo_sin_documento(p_motivo text, p_docs text[])
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare v_m text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_motivo, ''), '[^A-Za-z0-9]', '', 'g')); v_d text;
begin
  if p_motivo is null or length(pg_catalog.btrim(p_motivo)) not between 3 and 500 then
    raise exception 'El motivo debe tener entre 3 y 500 caracteres' using errcode = '22023';
  end if;
  foreach v_d in array coalesce(p_docs, '{}') loop
    if v_d is not null and length(v_d) >= 6 and pg_catalog.strpos(v_m, pg_catalog.upper(v_d)) > 0 then
      raise exception 'El motivo no debe contener el número de documento' using errcode = '22023';
    end if;
  end loop;
end;
$$;
revoke all on function private.motivo_sin_documento(text, text[]) from public, anon, authenticated, service_role;

-- ¿(tipo, documento) es un identificador vigente y verificado de ESTA identidad?
create or replace function private.documento_es_de_identidad(p_inv uuid, p_tipo text, p_documento text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from crm.inversionista_identificadores d
                 where d.inversionista_id = p_inv and d.estado = 'vigente' and d.verificado = true
                   and d.tipo_documento = coalesce(nullif(pg_catalog.upper(pg_catalog.btrim(p_tipo)), ''), 'DNI')
                   and d.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento, ''), '[^A-Za-z0-9]', '', 'g')))
$$;
revoke all on function private.documento_es_de_identidad(uuid, text, text) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2.3 Previsualización de una fusión (Gerencia, solo lectura, sin locks)
-- ---------------------------------------------------------------------------
create or replace function crm.fusion_previsualizar_fn(p_perdedora uuid, p_canonica uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_lead crm.leads%rowtype;
  v_bloq text[]; v_adv text[] := '{}'; v_foto jsonb;
  v_tp crm.inversionista_responsables%rowtype; v_tc crm.inversionista_responsables%rowtype;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia previsualiza una fusión' using errcode = '42501';
  end if;
  v_bloq := private.fusion_bloqueos(p_perdedora, p_canonica);
  select * into v_p from crm.inversionistas where id = p_perdedora;
  select * into v_c from crm.inversionistas where id = p_canonica;
  if v_p.id is null or v_c.id is null or p_perdedora = p_canonica then
    return pg_catalog.jsonb_build_object('viable', false, 'bloqueos', pg_catalog.to_jsonb(v_bloq),
      'advertencias', '[]'::jsonb, 'hash', null, 'foto', null, 'impacto', null);
  end if;
  if exists (select 1 from crm.inversionista_identificadores a
             join crm.inversionista_identificadores b on b.tipo_documento = a.tipo_documento and b.documento_normalizado <> a.documento_normalizado
             where a.inversionista_id = p_perdedora and b.inversionista_id = p_canonica and a.estado = 'vigente' and b.estado = 'vigente') then
    v_adv := pg_catalog.array_append(v_adv, 'Las dos tienen un documento vigente del mismo tipo: una está mal; corrige el documento después de fusionar (indicando cuál sale)'::text);
  end if;
  if v_p.no_contactar <> v_c.no_contactar
     or exists (select 1 from crm.leads l where l.id in (select private.leads_de_identidades(array[p_perdedora, p_canonica])) and l.no_contactar <> (v_p.no_contactar or v_c.no_contactar)) then
    v_adv := pg_catalog.array_append(v_adv, 'Vetos distintos: el resultado es «No contactar» en la persona y el lead, y se cancelan las tareas pendientes del lead'::text);
  end if;
  select * into v_tp from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null;
  select * into v_tc from crm.inversionista_responsables where inversionista_id = p_canonica and hasta is null;
  if v_tp.responsable_id is not null and v_tc.responsable_id is not null and v_tp.responsable_id <> v_tc.responsable_id then
    v_adv := pg_catalog.array_append(v_adv, 'Responsables de relación distintos: gana el de la canónica; se cierra el tramo de la perdedora'::text);
  elsif v_tp.responsable_id is not null and v_tc.responsable_id is null then
    v_adv := pg_catalog.array_append(v_adv, 'La canónica hereda el responsable de relación de la perdedora'::text);
  end if;
  if exists (select 1 from crm.inversiones where inversionista_id = p_perdedora)
     or exists (select 1 from crm.inversion_titulares where inversionista_id = p_perdedora)
     or exists (select 1 from crm.cierres_externos where inversionista_id = p_perdedora) then
    v_adv := pg_catalog.array_append(v_adv, 'La perdedora tiene inversiones, titularidades o cierres: se reapuntan a la canónica; el dinero y sus fotos no se tocan'::text);
  end if;
  if exists (select 1 from crm.inversionistas where inversionista_canonico_id = p_perdedora) then
    v_adv := pg_catalog.array_append(v_adv, 'La perdedora es canónica de otras identidades fusionadas: se aplanan a la nueva canónica'::text);
  end if;
  select * into v_lead from crm.leads where id in (select private.leads_de_identidades(array[p_perdedora, p_canonica])) order by id limit 1;
  if v_lead.id is not null and not v_lead.activo then
    v_adv := pg_catalog.array_append(v_adv, 'El lead está inactivo: no se deja nota de actividad (el libro de fusiones es el rastro)'::text);
  end if;
  v_adv := pg_catalog.array_append(v_adv, 'La conversión mensual sigue siendo por lead/cliente hasta Contrato-F3: la fusión no altera cifras ni meses sellados'::text);
  v_foto := private.fusion_estado_jsonb(p_perdedora, p_canonica);
  return pg_catalog.jsonb_build_object(
    'viable', pg_catalog.cardinality(v_bloq) = 0,
    'bloqueos', pg_catalog.to_jsonb(v_bloq),
    'advertencias', pg_catalog.to_jsonb(v_adv),
    'hash', private.idem_hash(v_foto),
    'foto', v_foto,
    'impacto', pg_catalog.jsonb_build_object(
      'leads', (select count(*) from private.leads_de_identidades(array[p_perdedora])),
      'puente', (select count(*) from crm.inversionista_leads where inversionista_id = p_perdedora),
      'tareas_pendientes', (select count(*) from crm.tareas t where t.estado = 'pendiente' and t.lead_id in (select private.leads_de_identidades(array[p_perdedora, p_canonica]))),
      'identificadores', (select count(*) from crm.inversionista_identificadores where inversionista_id = p_perdedora and estado = 'vigente'),
      'tramos', (select count(*) from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null),
      'cierres', (select count(*) from crm.cierres_externos where inversionista_id = p_perdedora),
      'inversiones', (select count(*) from crm.inversiones where inversionista_id = p_perdedora),
      'titulares', (select count(*) from crm.inversion_titulares where inversionista_id = p_perdedora),
      'reservas', (select count(*) from crm.conversion_reservas where inversionista_id = p_perdedora),
      'predecesoras', (select count(*) from crm.inversionistas where inversionista_canonico_id = p_perdedora)));
end;
$$;
revoke all on function crm.fusion_previsualizar_fn(uuid, uuid) from public, anon, service_role;
grant execute on function crm.fusion_previsualizar_fn(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2.4 Fusión (Gerencia): orden total, huella recalculada bajo locks, matriz completa, libro append-only
-- ---------------------------------------------------------------------------
create or replace function crm.fusionar_inversionistas_fn(p_perdedora uuid, p_canonica uuid, p_motivo text, p_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid;
  v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_row crm.inversionistas%rowtype;
  v_lead crm.leads%rowtype; v_leads uuid[]; v_docs text[]; v_docs2 text[]; v_bloq text[]; v_foto jsonb; v_ahora timestamptz;
  v_veto boolean; v_tramo_p crm.inversionista_responsables%rowtype; v_tramo_c crm.inversionista_responsables%rowtype;
  v_t crm.inversion_titulares%rowtype; v_t2 crm.inversion_titulares%rowtype; v_fusion_id uuid; v_impacto jsonb;
  v_n_ident integer := 0; v_n_cierres integer := 0; v_n_inv integer := 0; v_n_tit integer := 0;
  v_n_tit_dup integer := 0; v_n_res integer := 0; v_n_pred integer := 0; v_n_tareas integer := 0; v_n_puente integer := 0;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia fusiona identidades' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  if p_perdedora is null or p_canonica is null or p_perdedora = p_canonica then
    raise exception 'Indica dos identidades distintas' using errcode = '22023';
  end if;
  if p_hash is null or p_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Falta la huella de la previsualización (p_hash)' using errcode = '22023';
  end if;

  -- 1. jerarquía compartida [E3-2] y Gerencia REVALIDADA bajo ella -> 2. documentos vigentes de ambas (sin lock, ordenados)
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia fusiona identidades (membresía revalidada)' using errcode = '42501';
  end if;
  v_docs := private.identidad_bloquear_documentos_de(array[p_perdedora, p_canonica]);
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(split_part(k, ':', 2)) from unnest(v_docs) k));
  -- 3. identidades FOR UPDATE por id ascendente (P, C y las predecesoras de P: el aplanado no espera después de las reservas [E3-12])
  for v_row in select * from crm.inversionistas where id in (p_perdedora, p_canonica) order by id for update loop
    if v_row.id = p_perdedora then v_p := v_row; else v_c := v_row; end if;
  end loop;
  if v_p.id is null or v_c.id is null then
    raise exception 'Alguna de las identidades no existe' using errcode = 'P0002';
  end if;
  perform 1 from crm.inversionistas i where i.inversionista_canonico_id = p_perdedora and i.id not in (p_perdedora, p_canonica) order by i.id for update;
  select pg_catalog.array_agg(k order by k) into v_docs2
  from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
        from crm.inversionista_identificadores d where d.inversionista_id in (p_perdedora, p_canonica) and d.estado = 'vigente') s;
  if coalesce(v_docs2, '{}') is distinct from v_docs then
    raise exception 'Los documentos de la persona cambiaron mientras se esperaba; vuelve a previsualizar' using errcode = '40001';
  end if;
  -- 4. perfil FOR SHARE -> 5. cierres -> 6. inversiones/titulares -> 7. tramos -> 8. tareas -> 9. leads (NOWAIT) -> 10. reservas -> 11. claims
  perform 1 from public.perfiles p where p.id in (v_p.perfil_id, v_c.perfil_id) order by p.id for share;
  v_leads := coalesce((select pg_catalog.array_agg(x order by x) from private.leads_de_identidades(array[p_perdedora, p_canonica]) x), '{}');
  perform 1 from crm.cierres_externos ce
   where ce.inversionista_id in (p_perdedora, p_canonica) or ce.lead_id = any(v_leads)
   order by ce.id for update;
  perform 1 from crm.inversiones i where i.inversionista_id in (p_perdedora, p_canonica) order by i.id for update;
  perform 1 from crm.inversion_titulares t
   where t.inversionista_id in (p_perdedora, p_canonica)
      or t.inversion_id in (select i.id from crm.inversiones i where i.inversionista_id in (p_perdedora, p_canonica))
   order by t.id for update;
  perform 1 from crm.inversionista_responsables r where r.inversionista_id in (p_perdedora, p_canonica) and r.hasta is null order by r.id for update;
  perform 1 from crm.tareas t where t.estado = 'pendiente' and t.lead_id = any(v_leads) order by t.id for update;
  perform private.bloquear_leads_nowait(v_leads);
  select * into v_lead from crm.leads l where l.id = any(v_leads) order by l.id limit 1;
  perform 1 from crm.conversion_reservas r
   where r.inversionista_id in (p_perdedora, p_canonica) or r.lead_id = any(v_leads)
   order by r.lead_id for update;
  perform 1 from crm.multiempresa_idempotencia m
   where m.clave in ('auth_persona:' || p_perdedora::text, 'auth_persona:' || p_canonica::text) order by m.clave for update;
  -- 12. huella y bloqueos bajo los locks [E3-4]
  v_foto := private.fusion_estado_jsonb(p_perdedora, p_canonica);
  if private.idem_hash(v_foto) <> p_hash then
    raise exception 'La previsualización caducó (la foto cambió): vuelve a previsualizar' using errcode = 'P0409';
  end if;
  v_bloq := private.fusion_bloqueos(p_perdedora, p_canonica);
  if pg_catalog.cardinality(v_bloq) > 0 then
    raise exception 'Fusión no viable: %', pg_catalog.array_to_string(v_bloq, ' · ') using errcode = 'P0409';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  v_veto := v_p.no_contactar or v_c.no_contactar or coalesce(v_lead.no_contactar, false);

  -- 13. hechos bajo la válvula, en este orden
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.inversionistas set estado = 'fusionado', inversionista_canonico_id = p_canonica, fusionado_en = v_ahora where id = p_perdedora;
  update crm.inversionistas set inversionista_canonico_id = p_canonica where inversionista_canonico_id = p_perdedora and id <> p_canonica;
  get diagnostics v_n_pred = row_count;
  if v_c.perfil_id is null and v_p.perfil_id is not null then
    update crm.inversionistas set perfil_id = v_p.perfil_id where id = p_canonica;
  end if;
  if v_veto and not v_c.no_contactar then
    update crm.inversionistas
       set no_contactar = true,
           no_contactar_en = coalesce(v_p.no_contactar_en, v_ahora),
           no_contactar_por = coalesce(v_p.no_contactar_por, v_uid)
     where id = p_canonica;
  end if;
  select * into v_tramo_p from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null;
  select * into v_tramo_c from crm.inversionista_responsables where inversionista_id = p_canonica and hasta is null;
  if v_tramo_p.id is not null then
    update crm.inversionista_responsables set hasta = v_ahora where id = v_tramo_p.id;
    if v_tramo_c.id is null then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
      values (p_canonica, v_tramo_p.responsable_id, v_ahora, 'fusion', v_uid);
      update crm.inversionistas set responsable_relacion_id = v_tramo_p.responsable_id where id = p_canonica;
    end if;
  end if;
  update crm.inversionista_identificadores d set estado = 'historico', vigente_hasta = v_ahora
   where d.inversionista_id = p_perdedora and d.estado = 'vigente';
  insert into crm.inversionista_identificadores
    (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente, vigente_desde, creado_por)
  select p_canonica, d.tipo_documento, d.documento_normalizado, d.documento_original, 'vigente', d.verificado, 'fusion', v_ahora, v_uid
  from crm.inversionista_identificadores d
  where d.inversionista_id = p_perdedora and d.estado = 'historico' and d.vigente_hasta = v_ahora
  order by d.id;
  get diagnostics v_n_ident = row_count;
  -- lead (enlace vivo) y TODO el puente de P (incluidos históricos del backfill)
  if v_lead.id is not null and v_lead.inversionista_id = p_perdedora then
    update crm.leads set inversionista_id = p_canonica where id = v_lead.id;
  end if;
  update crm.inversionista_leads set inversionista_id = p_canonica where inversionista_id = p_perdedora;
  get diagnostics v_n_puente = row_count;
  if v_lead.id is not null and v_veto and not v_lead.no_contactar then
    v_n_tareas := private.cancelar_tareas_pendientes_lead(v_lead.id);
    update crm.leads set no_contactar = true where id = v_lead.id;
  end if;
  update crm.cierres_externos ce set inversionista_id = p_canonica
   where ce.inversionista_id = p_perdedora
      or (v_lead.id is not null and v_lead.inversionista_id = p_perdedora and ce.lead_id = v_lead.id and ce.inversionista_id is null);
  get diagnostics v_n_cierres = row_count;
  update crm.inversiones set inversionista_id = p_canonica where inversionista_id = p_perdedora;
  get diagnostics v_n_inv = row_count;
  for v_t in select * from crm.inversion_titulares where inversionista_id = p_perdedora order by id loop
    v_t2 := null;
    select * into v_t2 from crm.inversion_titulares where inversion_id = v_t.inversion_id and inversionista_id = p_canonica;
    if v_t2.id is not null then
      delete from crm.inversion_titulares where id = v_t.id;
      if v_t.rol = 'principal' and v_t2.rol <> 'principal' then
        update crm.inversion_titulares set rol = 'principal' where id = v_t2.id;
      end if;
      v_n_tit_dup := v_n_tit_dup + 1;
    else
      update crm.inversion_titulares set inversionista_id = p_canonica where id = v_t.id;
      v_n_tit := v_n_tit + 1;
    end if;
  end loop;
  update crm.conversion_reservas set inversionista_id = p_canonica where inversionista_id = p_perdedora;
  get diagnostics v_n_res = row_count;
  v_impacto := pg_catalog.jsonb_build_object('lead_id', v_lead.id, 'lead_reapuntado', v_lead.id is not null and v_lead.inversionista_id = p_perdedora,
    'puente', v_n_puente, 'identificadores_reemitidos', v_n_ident, 'tramo_cerrado', v_tramo_p.id, 'tramo_heredado', v_tramo_c.id is null and v_tramo_p.id is not null,
    'perfil_heredado', v_c.perfil_id is null and v_p.perfil_id is not null, 'veto', v_veto, 'tareas_canceladas', v_n_tareas,
    'cierres', v_n_cierres, 'inversiones', v_n_inv, 'titulares', v_n_tit, 'titulares_duplicados_eliminados', v_n_tit_dup,
    'reservas', v_n_res, 'predecesoras_aplanadas', v_n_pred, 'hash', p_hash);
  insert into crm.inversionista_fusiones (canonico_id, fusionado_id, motivo, impacto, por)
  values (p_canonica, p_perdedora, p_motivo, v_impacto, v_uid) returning id into v_fusion_id;
  if v_lead.id is not null and v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Fusión de identidades (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'fusion', 'fusion_id', v_fusion_id, 'canonico_id', p_canonica, 'fusionado_id', p_perdedora),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'fusion_id', v_fusion_id, 'canonico_id', p_canonica, 'fusionado_id', p_perdedora, 'impacto', v_impacto);
end;
$$;
revoke all on function crm.fusionar_inversionistas_fn(uuid, uuid, text, text) from public, anon, service_role;
grant execute on function crm.fusionar_inversionistas_fn(uuid, uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2.5 Corrección de documento (Gerencia): el que sale pasa a histórico; nuevo vigente verificado (o se
--     reutiliza un vigente propio [E3-15]); realinea perfil y lead SOLO si llevaban el documento reemplazado;
--     contactos ANTES de comprobar terceros [E3-6]; libro de operaciones.
-- ---------------------------------------------------------------------------
create or replace function crm.corregir_documento_inversionista_fn(
  p_inversionista uuid, p_tipo text, p_documento text, p_motivo text, p_identificador_anterior uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid;
  v_tipo text; v_norm text;
  v_inv crm.inversionistas%rowtype; v_old_id uuid; v_old_tipo text; v_old_norm text; v_n integer; v_otro uuid; v_ahora timestamptz;
  v_perfil_id uuid; v_perfil_dni text; v_perfil_tipo text; v_lead crm.leads%rowtype; v_new_id uuid; v_op_id uuid;
  v_perfil_res text; v_lead_res text; v_k text; v_docs text[]; v_reusa boolean := false;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia corrige el documento de una persona' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  v_tipo := pg_catalog.upper(pg_catalog.btrim(coalesce(p_tipo, '')));
  v_norm := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento, ''), '[^A-Za-z0-9]', '', 'g'));
  if v_tipo not in ('DNI', 'CE', 'PASAPORTE') then
    raise exception 'Tipo de documento invalido' using errcode = '22023';
  end if;
  if (v_tipo = 'DNI' and v_norm !~ '^[0-9]{8}$')
     or (v_tipo = 'CE' and v_norm !~ '^[0-9]{9,12}$')
     or (v_tipo = 'PASAPORTE' and v_norm !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Documento invalido para el tipo' using errcode = '22023';
  end if;
  select * into v_inv from crm.inversionistas where id = p_inversionista;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: corrige en su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  -- El identificador que sale, leído SIN lock (solo para calcular los advisories); se revalida bajo la identidad [E3-5].
  -- La unicidad «único de su tipo» solo se exige cuando NO se indica cuál sale [E3-15].
  if p_identificador_anterior is not null then
    select d.id, d.tipo_documento, d.documento_normalizado into v_old_id, v_old_tipo, v_old_norm
    from crm.inversionista_identificadores d
    where d.id = p_identificador_anterior and d.inversionista_id = p_inversionista and d.estado = 'vigente';
    if v_old_id is null then
      raise exception 'El identificador anterior no es un documento vigente de esta persona' using errcode = 'P0409';
    end if;
  else
    select count(*) into v_n from crm.inversionista_identificadores d
    where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    if v_n > 1 then
      raise exception 'La persona tiene varios documentos vigentes de tipo %: indica cuál sustituir (p_identificador_anterior)', v_tipo using errcode = '22023';
    elsif v_n = 1 then
      select d.id, d.tipo_documento, d.documento_normalizado into v_old_id, v_old_tipo, v_old_norm
      from crm.inversionista_identificadores d
      where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    end if;
  end if;
  if v_old_tipo = v_tipo and v_old_norm = v_norm then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista);
  end if;
  perform private.motivo_sin_documento(p_motivo, array[v_norm, v_old_norm]);

  -- jerarquía [E3-2] + Gerencia revalidada -> advisories de viejo y nuevo, ordenados -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia corrige el documento de una persona (membresía revalidada)' using errcode = '42501';
  end if;
  select pg_catalog.array_agg(k order by k) into v_docs
  from (select distinct k from unnest(array[v_tipo || ':' || v_norm, v_old_tipo || ':' || v_old_norm]) k where k is not null) s;
  foreach v_k in array v_docs loop
    perform private.identidad_bloquear_documento(split_part(v_k, ':', 1), split_part(v_k, ':', 2));
  end loop;
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if v_inv.estado <> 'activo' then
    raise exception 'La persona cambió mientras se corregía (estado %); vuelve a intentarlo', v_inv.estado using errcode = '40001';
  end if;
  if v_old_id is not null then
    if not exists (select 1 from crm.inversionista_identificadores d where d.id = v_old_id and d.inversionista_id = p_inversionista
                     and d.estado = 'vigente' and d.tipo_documento = v_old_tipo and d.documento_normalizado = v_old_norm) then
      raise exception 'El documento de la persona cambió mientras se corregía; vuelve a intentarlo' using errcode = '40001';
    end if;
  end if;
  if p_identificador_anterior is null then
    select count(*) into v_n from crm.inversionista_identificadores d
    where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    if v_n <> (case when v_old_id is null then 0 else 1 end) then
      raise exception 'Los documentos de la persona cambiaron mientras se corregía; vuelve a intentarlo' using errcode = '40001';
    end if;
  end if;
  -- el nuevo, ¿ya es vigente de alguien?
  select d.inversionista_id, d.id into v_otro, v_new_id from crm.inversionista_identificadores d
  where d.tipo_documento = v_tipo and d.documento_normalizado = v_norm and d.estado = 'vigente';
  if v_otro is not null and v_otro <> p_inversionista then
    raise exception 'El documento pertenece a otra persona reconocida: fusiona las identidades en vez de corregir' using errcode = 'P0409';
  end if;
  if v_otro = p_inversionista then
    if v_old_id is null then
      return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista);
    end if;
    v_reusa := true;   -- [E3-15] el destino ya es un vigente propio (p. ej. tras una fusión): sale el anterior y se reutiliza
  else
    v_new_id := null;
  end if;
  -- alta/conversión en curso [E3-7]: claim y reservas (por persona O por lead) bajo lock
  perform 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text for update;
  if exists (select 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text
              and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    raise exception 'Hay un alta o conversión en curso para esta persona: termina o deja caducar antes de corregir' using errcode = 'P0409';
  end if;
  -- perfil enlazado FOR UPDATE (escribe) -> cierres -> tareas -> lead (NOWAIT) -> reservas -> contactos -> terceros
  if v_inv.perfil_id is not null then
    select p.id, p.dni, p.tipo_documento into v_perfil_id, v_perfil_dni, v_perfil_tipo from public.perfiles p where p.id = v_inv.perfil_id for update;
  end if;
  perform 1 from crm.cierres_externos ce
   where ce.inversionista_id = p_inversionista or ce.lead_id in (select private.leads_de_identidades(array[p_inversionista]))
   order by ce.id for update;
  perform 1 from crm.tareas t where t.estado = 'pendiente'
     and t.lead_id in (select private.leads_de_identidades(array[p_inversionista])) order by t.id for update;
  perform private.bloquear_leads_nowait(coalesce((select pg_catalog.array_agg(x) from private.leads_de_identidades(array[p_inversionista]) x), '{}'));
  select * into v_lead from crm.leads l where l.inversionista_id = p_inversionista order by l.id limit 1;
  perform 1 from crm.conversion_reservas r
   where r.inversionista_id = p_inversionista or r.lead_id in (select private.leads_de_identidades(array[p_inversionista])) order by r.lead_id for update;
  if exists (select 1 from crm.conversion_reservas r left join crm.leads l on l.id = r.lead_id
              where (r.inversionista_id = p_inversionista or r.lead_id in (select private.leads_de_identidades(array[p_inversionista])))
                and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(l.etapa, '') <> 'convertido'))) then
    raise exception 'Hay una reserva de conversión viva o sellada sin convertir (por persona o por lead): termina o deja caducar antes de corregir' using errcode = 'P0409';
  end if;
  -- contactos (último recurso del orden) ANTES de mirar a terceros [E3-6]: el trigger los retoma reentrante
  if v_lead.id is not null then
    perform private.bloquear_contactos_lead(array[v_lead.telefono], array[v_lead.dni, case when v_tipo = 'DNI' then v_norm end]);
  else
    perform private.bloquear_contactos_lead(array[]::text[], array[case when v_tipo = 'DNI' then v_norm end]);
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  if exists (select 1 from public.perfiles pp
              where pp.rol = 'cliente'
                and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(pp.dni, ''), '[^A-Za-z0-9]', '', 'g')) = v_norm
                and coalesce(nullif(pg_catalog.btrim(pp.tipo_documento), ''), 'DNI') = v_tipo
                and pp.id is distinct from v_inv.perfil_id) then
    raise exception 'Otro cliente del Portal lleva ese documento: revisión o fusión de Gerencia' using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and exists (select 1 from crm.leads l where l.dni = v_norm and l.id is distinct from v_lead.id
                                  and l.activo = true and l.etapa not in ('convertido', 'descartado')) then
    raise exception 'Otro lead vivo lleva ese DNI: fusiona o descarta ese lead primero' using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and exists (select 1 from crm.leads l where l.dni = v_norm and l.id is distinct from v_lead.id and l.inversionista_id is not null
                                  and l.inversionista_id <> p_inversionista) then
    raise exception 'Otro lead enlazado a otra persona lleva ese DNI: fusiona o corrige ese lead primero' using errcode = 'P0409';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_old_id is not null then
    update crm.inversionista_identificadores set estado = 'historico', vigente_hasta = v_ahora where id = v_old_id;
  end if;
  if not v_reusa then
    insert into crm.inversionista_identificadores
      (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente, vigente_desde, creado_por)
    values (p_inversionista, v_tipo, v_norm, p_documento, 'vigente', true, 'correccion', v_ahora, v_uid)
    returning id into v_new_id;
  end if;
  v_perfil_res := case when v_inv.perfil_id is null then 'ninguno' else 'sin_cambio' end;
  if v_perfil_id is not null and v_old_id is not null
     and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(v_perfil_dni, ''), '[^A-Za-z0-9]', '', 'g')) = v_old_norm
     and coalesce(nullif(pg_catalog.btrim(v_perfil_tipo), ''), 'DNI') = v_old_tipo then
    begin
      update public.perfiles set dni = v_norm, tipo_documento = v_tipo where id = v_perfil_id;
    exception when unique_violation then
      raise exception 'Otro cliente del Portal lleva ese documento: revisión o fusión de Gerencia' using errcode = 'P0409';
    end;
    v_perfil_res := 'actualizado';
  end if;
  v_lead_res := case when v_lead.id is null then 'sin_lead' else 'sin_cambio' end;
  if v_lead.id is not null and v_old_id is not null and v_old_tipo = 'DNI' and v_lead.dni = v_old_norm then
    if v_tipo = 'DNI' then
      begin
        update crm.leads set dni = v_norm where id = v_lead.id;
      exception when unique_violation then
        raise exception 'Otro lead vivo lleva ese DNI: fusiona o descarta ese lead primero' using errcode = 'P0409';
      end;
      v_lead_res := 'dni';
    else
      update crm.leads set dni = null where id = v_lead.id;
      v_lead_res := 'nulo';
    end if;
  end if;
  insert into crm.inversionista_operaciones
    (tipo, inversionista_id, lead_id, identificador_anterior_id, identificador_nuevo_id, motivo, detalle, por)
  values ('correccion', p_inversionista, v_lead.id, v_old_id, v_new_id, p_motivo,
          pg_catalog.jsonb_build_object('tipo_documento', v_tipo, 'perfil', v_perfil_res, 'lead', v_lead_res, 'reutilizado', v_reusa), v_uid)
  returning id into v_op_id;
  if v_lead.id is not null and v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Documento corregido por Gerencia (' || v_tipo || ')',
            pg_catalog.jsonb_build_object('evento', 'correccion_documento', 'operacion_id', v_op_id,
                                          'inversionista_id', p_inversionista, 'lead', v_lead_res),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'estado', 'corregido', 'inversionista_id', p_inversionista,
    'operacion_id', v_op_id, 'identificador_nuevo_id', v_new_id, 'identificador_anterior_id', v_old_id,
    'reutilizado', v_reusa, 'perfil', v_perfil_res, 'lead', v_lead_res);
end;
$$;
revoke all on function crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid) from public, anon, service_role;
grant execute on function crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2.6 Enlace de un lead suelto a una persona reconocida (Gerencia): la revisión humana de la clase E.
--     Unión de enlaces validada por DOCUMENTO (cierre y perfil) [E3-10]; motivo siempre en el libro [E3-16].
-- ---------------------------------------------------------------------------
create or replace function crm.enlazar_lead_inversionista_fn(p_lead_id uuid, p_inversionista uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid;
  v_inv crm.inversionistas%rowtype; v_lead0 crm.leads%rowtype; v_lead crm.leads%rowtype; v_cierre crm.cierres_externos%rowtype;
  v_perfil_inv uuid; v_perfil_dni text; v_perfil_tipo text; v_ahora timestamptz; v_veto boolean; v_n_tareas integer := 0;
  v_perfil_completado boolean := false; v_cierre_completado boolean := false; v_op_id uuid;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia enlaza un lead a una persona' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  select * into v_inv from crm.inversionistas where id = p_inversionista;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: enlaza a su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  select * into v_lead0 from crm.leads where id = p_lead_id;
  if not found then
    raise exception 'El lead no existe' using errcode = 'P0002';
  end if;
  if v_lead0.inversionista_id is not null then
    raise exception 'El lead ya está enlazado a una persona' using errcode = 'P0409';
  end if;
  if v_lead0.dni is null then
    raise exception 'El lead no tiene DNI: solo el documento exacto enlaza (corrige el DNI del lead primero)' using errcode = 'P0409';
  end if;
  perform private.motivo_sin_documento(p_motivo, array[v_lead0.dni]);

  -- jerarquía + Gerencia revalidada -> documento del lead -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia enlaza un lead a una persona (membresía revalidada)' using errcode = '42501';
  end if;
  perform private.identidad_bloquear_documento('DNI', v_lead0.dni);
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if v_inv.estado <> 'activo' then
    raise exception 'La persona cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  if not private.documento_es_de_identidad(p_inversionista, 'DNI', v_lead0.dni) then
    if private.inversionista_por_documento('DNI', v_lead0.dni) is not null then
      raise exception 'El DNI del lead pertenece a otra persona reconocida: fusiona o corrige primero' using errcode = 'P0409';
    end if;
    raise exception 'El DNI del lead no es un documento vigente y verificado de esta persona: corrige el documento primero' using errcode = 'P0409';
  end if;
  if exists (select 1 from private.leads_de_identidades(array[p_inversionista])) then
    raise exception 'La persona ya tiene su lead (enlace vivo o puente, activo o no): reconciliación de clase E hasta F5' using errcode = 'P0409';
  end if;
  -- unión de enlaces del lead [E3-10]: perfil (FOR SHARE, por DOCUMENTO) -> cierre (por DOCUMENTO) -> puente -> tareas -> lead -> reservas -> claim
  if v_lead0.perfil_id is not null then
    select p.dni, p.tipo_documento into v_perfil_dni, v_perfil_tipo from public.perfiles p where p.id = v_lead0.perfil_id for share;
    select i.id into v_perfil_inv from crm.inversionistas i where i.perfil_id = v_lead0.perfil_id and i.estado <> 'fusionado' limit 1;
    if v_perfil_inv is not null and v_perfil_inv <> p_inversionista then
      raise exception 'El perfil de cliente del lead pertenece a otra persona reconocida: reconciliación (fusión/corrección)' using errcode = 'P0409';
    end if;
    if v_perfil_inv is null then
      if v_inv.perfil_id is not null and v_inv.perfil_id <> v_lead0.perfil_id then
        raise exception 'La persona ya tiene otro perfil de cliente: reconciliación de clase E hasta F5 (dos perfiles)' using errcode = 'P0409';
      end if;
      if not private.documento_es_de_identidad(p_inversionista, v_perfil_tipo, v_perfil_dni) then
        raise exception 'El documento del perfil de cliente del lead no es de esta persona: corrige el documento primero' using errcode = 'P0409';
      end if;
    end if;
  end if;
  select * into v_cierre from crm.cierres_externos ce where ce.lead_id = p_lead_id for update;
  if v_cierre.id is not null then
    if v_cierre.inversionista_id is not null and v_cierre.inversionista_id <> p_inversionista then
      raise exception 'El cierre del lead pertenece a otra persona reconocida: reconciliación' using errcode = 'P0409';
    end if;
    if v_cierre.inversionista_id is null and not private.documento_es_de_identidad(p_inversionista, v_cierre.documento_tipo, v_cierre.documento) then
      raise exception 'El documento del cierre del lead no es de esta persona: reconciliación documental primero' using errcode = 'P0409';
    end if;
  end if;
  if exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id and il.inversionista_id <> p_inversionista) then
    raise exception 'El puente del lead apunta a otra persona: reconciliación' using errcode = 'P0409';
  end if;
  perform 1 from crm.tareas t where t.estado = 'pendiente' and t.lead_id = p_lead_id order by t.id for update;
  perform private.bloquear_leads_nowait(array[p_lead_id]);
  select * into v_lead from crm.leads where id = p_lead_id;
  if v_lead.inversionista_id is not null or v_lead.perfil_id is distinct from v_lead0.perfil_id or v_lead.dni is distinct from v_lead0.dni then
    raise exception 'El lead cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  perform 1 from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if exists (select 1 from crm.conversion_reservas r where r.lead_id = p_lead_id
              and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and v_lead.etapa <> 'convertido'))
              and (r.inversionista_id is null or r.inversionista_id <> p_inversionista)) then
    raise exception 'El lead tiene una reserva de conversión viva o sellada (de otra persona o sin persona): termina o deja caducar' using errcode = 'P0409';
  end if;
  perform 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text for update;
  if exists (select 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text
              and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    raise exception 'Hay un alta o conversión en curso para esta persona: termina o deja caducar antes de enlazar' using errcode = 'P0409';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  v_veto := v_inv.no_contactar or v_lead.no_contactar;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.leads set inversionista_id = p_inversionista where id = p_lead_id;   -- el trigger zz escribe el puente canónico si no existe
  if v_lead0.perfil_id is not null and v_inv.perfil_id is null then
    update crm.inversionistas set perfil_id = v_lead0.perfil_id where id = p_inversionista;
    v_perfil_completado := true;
  end if;
  if v_cierre.id is not null and v_cierre.inversionista_id is null then
    update crm.cierres_externos set inversionista_id = p_inversionista where id = v_cierre.id;
    v_cierre_completado := true;
  end if;
  if v_veto and not v_inv.no_contactar then
    update crm.inversionistas set no_contactar = true, no_contactar_en = v_ahora, no_contactar_por = v_uid where id = p_inversionista;
  end if;
  if v_veto and not v_lead.no_contactar then
    v_n_tareas := private.cancelar_tareas_pendientes_lead(p_lead_id);
    update crm.leads set no_contactar = true where id = p_lead_id;
  end if;
  insert into crm.inversionista_operaciones (tipo, inversionista_id, lead_id, motivo, detalle, por)
  values ('enlace', p_inversionista, p_lead_id, p_motivo,
          pg_catalog.jsonb_build_object('perfil_completado', v_perfil_completado, 'cierre_completado', v_cierre_completado,
                                        'veto', v_veto, 'tareas_canceladas', v_n_tareas, 'lead_activo', v_lead.activo), v_uid)
  returning id into v_op_id;
  if v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (p_lead_id, 'nota', 'Lead enlazado a una persona reconocida (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'enlace_identidad', 'operacion_id', v_op_id, 'inversionista_id', p_inversionista, 'veto', v_veto),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'inversionista_id', p_inversionista, 'operacion_id', v_op_id,
    'perfil_completado', v_perfil_completado, 'cierre_completado', v_cierre_completado, 'veto', v_veto, 'tareas_canceladas', v_n_tareas);
end;
$$;
revoke all on function crm.enlazar_lead_inversionista_fn(uuid, uuid, text) from public, anon, service_role;
grant execute on function crm.enlazar_lead_inversionista_fn(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2.7 Reasignación del responsable de relación (Gerencia): cierra/abre tramo; no mueve atribuciones (§6)
-- ---------------------------------------------------------------------------
create or replace function crm.reasignar_responsable_relacion_fn(p_inversionista uuid, p_nuevo_responsable uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid;
  v_inv crm.inversionistas%rowtype; v_tramo crm.inversionista_responsables%rowtype; v_nuevo_id uuid; v_ahora timestamptz; v_lead crm.leads%rowtype;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia reasigna el responsable de relación' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  if p_inversionista is null or p_nuevo_responsable is null then
    raise exception 'Faltan la persona o el nuevo responsable' using errcode = '22023';
  end if;
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista));
  -- jerarquía compartida (el offboarding la toma exclusiva) + Gerencia y destinatario revalidados bajo ella -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia reasigna el responsable de relación (membresía revalidada)' using errcode = '42501';
  end if;
  if not coalesce(private.rol_crm(p_nuevo_responsable) in ('vendedor', 'supervisor', 'gerencia'), false) then
    raise exception 'El nuevo responsable debe ser un miembro activo del equipo comercial (rol efectivo)' using errcode = '22023';
  end if;
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: reasigna en su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  select * into v_tramo from crm.inversionista_responsables where inversionista_id = p_inversionista and hasta is null for update;
  if v_tramo.id is not null and v_tramo.responsable_id = p_nuevo_responsable then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista, 'tramo_id', v_tramo.id);
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_tramo.id is not null then
    update crm.inversionista_responsables set hasta = v_ahora where id = v_tramo.id;
  end if;
  insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
  values (p_inversionista, p_nuevo_responsable, v_ahora, p_motivo, v_uid) returning id into v_nuevo_id;
  update crm.inversionistas set responsable_relacion_id = p_nuevo_responsable where id = p_inversionista;
  select * into v_lead from crm.leads where inversionista_id = p_inversionista and activo = true order by id limit 1;
  if v_lead.id is not null then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Responsable de relación reasignado (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'reasignacion_responsable', 'inversionista_id', p_inversionista,
                                          'anterior', v_tramo.responsable_id, 'nuevo', p_nuevo_responsable, 'tramo_id', v_nuevo_id),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'estado', 'reasignado', 'inversionista_id', p_inversionista,
    'tramo_anterior_id', v_tramo.id, 'tramo_nuevo_id', v_nuevo_id, 'responsable_anterior', v_tramo.responsable_id, 'responsable_nuevo', p_nuevo_responsable);
end;
$$;
revoke all on function crm.reasignar_responsable_relacion_fn(uuid, uuid, text) from public, anon, service_role;
grant execute on function crm.reasignar_responsable_relacion_fn(uuid, uuid, text) to authenticated;

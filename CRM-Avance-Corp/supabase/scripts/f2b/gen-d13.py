# gen-d13.py — F2.b prerrequisito de activación [D-13]: «un solo lead» y «el puente manda» en TODAS las puertas
# con la bandera encendida (bloque 2). v4.4 (05/09: Codex sobre la v4.3 — sin ABA; menores: la bandera apagada a mitad de la operación ya no deja claves «bloqueadas» sin candado, las reaperturas y la puerta exigen READ COMMITTED, y el registrador comprueba los objetos nuevos). Transforma 9 funciones VIVAS
# (8 de producción + la reserva por persona tal como la deja D-10, que por eso es REQUISITO) desde vivas/d13/*.sql (md5 en
# huellas-d13-prod.txt), crea 6 helpers privados y el trigger «reapertura solo por RPC». Genera la migración 20260905160000,
# su reversa (restaura byte a byte, suelta helpers y trigger, desregistra) y el registro (exige las 9 vivas = D-13).
# Uso: python3 gen-d13.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
viv = lambda n: (S/'vivas'/'d13'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:90], s.count(old)); return s.replace(old, new)
md5 = lambda t: hashlib.md5((t + '\n').encode('utf-8')).hexdigest()
prod = {l.split()[0]: l.split()[1] for l in (S/'huellas-d13-prod.txt').read_text().splitlines() if l.strip()}
H_LDI = '2421b2b78b02b8e93fd01598e2f54128'   # private.leads_de_identidades(uuid[]) en PROD (b5) = banco
ADV = 'crm_f2b_d13_un_solo_lead_todas_las_puertas'
FN = {  # clave -> (schema, nombre, args identidad, etiqueta)
  'private.verificar_disponibilidad_lead_impl.3': ('private','verificar_disponibilidad_lead_impl','p_telefono text, p_dni text, p_excluir_lead_id uuid','private.verificar_disponibilidad_lead_impl(text,text,uuid)'),
  'private.trg_leads_zz_enlaza_identidad': ('private','trg_leads_zz_enlaza_identidad','','private.trg_leads_zz_enlaza_identidad()'),
  'crm.tomar_lead_libre': ('crm','tomar_lead_libre','p_telefono text, p_dni text','crm.tomar_lead_libre(text,text)'),
  'crm.convertir_lead': ('crm','convertir_lead','p_lead_id uuid, p_perfil_id uuid','crm.convertir_lead(uuid,uuid)'),
  'crm.convertir_lead_externo': ('crm','convertir_lead_externo','p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text','crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'),
  'crm.marcar_efectos_conversion.3': ('crm','marcar_efectos_conversion','p_lead_id uuid, p_claim_id uuid, p_token text','crm.marcar_efectos_conversion(uuid,uuid,text)'),
  'crm.rescatar_descartes': ('crm','rescatar_descartes','p_episodios uuid[], p_analistas_destino uuid[], p_evitar_asesor_origen boolean','crm.rescatar_descartes(uuid[],uuid[],boolean)'),
  'private.deshacer_descarte_implementacion': ('private','deshacer_descarte_implementacion','p_lead uuid','private.deshacer_descarte_implementacion(uuid)'),
  'crm.reservar_conversion_lead.4': ('crm','reservar_conversion_lead','p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb','crm.reservar_conversion_lead(uuid,text,text,jsonb)'),
}
prev = {k: viv(k) for k in FN}
for k in FN: assert md5(prev[k]) == prod[k], (k, md5(prev[k]))
assert md5(viv('private.verificar_disponibilidad_lead_impl')) == prod['private.verificar_disponibilidad_lead_impl']

FLAG = "coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)"
HELPERS = r"""-- ============================================================================
-- 0. Helpers privados (definer, search_path '', sin EXECUTE a la API)
-- ============================================================================
-- 0.1 ¿La persona está EN CONVERSIÓN? Reserva por persona viva o sellada de un lead aún no convertido (mismo predicado
--     que private.fusion_bloqueos, b5). Los claims no cuentan: un claim abandonado sin reserva no debe bloquear para siempre.
create or replace function private.persona_en_conversion(p_inv uuid, p_excluir_lead_id uuid default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from crm.conversion_reservas r
    left join crm.leads l on l.id = r.lead_id
    where r.inversionista_id = p_inv
      and r.lead_id is distinct from p_excluir_lead_id
      and (r.expira_en > pg_catalog.now()
           or (r.efectos_iniciados_en is not null and coalesce(l.etapa, '') <> 'convertido'))
  )
$$;
revoke all on function private.persona_en_conversion(uuid, uuid) from public, anon, authenticated, service_role;

-- 0.2 «Los leads de una persona» = enlace vivo ∪ puente (private.leads_de_identidades, b5) ∪ los SUELTOS que llevan un
--     documento vigente de la persona (nacieron antes de que existiera la persona, o su DNI llegó después): vivos o convertidos,
--     no los descartados (esos los ofrece el camino «reutilizable» y los juzga la reapertura). Codex D-13 #1/#3/#6.
create or replace function private.leads_de_personas(p_ids uuid[])
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select x from private.leads_de_identidades(p_ids) x
  union
  select l.id
  from crm.leads l
  join crm.inversionista_identificadores d
    on d.tipo_documento = 'DNI' and d.estado = 'vigente' and d.verificado = true and d.documento_normalizado = l.dni
  where d.inversionista_id = any(p_ids)
    and l.inversionista_id is null
    and l.activo = true
    and l.etapa <> 'descartado'
$$;
revoke all on function private.leads_de_personas(uuid[]) from public, anon, authenticated, service_role;

-- 0.3 La persona de un lead a efectos de reapertura: su enlace (por la canónica), o la del documento, o la de su puente.
create or replace function private.lead_persona_reabrir(p_lead_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select private.inversionista_canonica(l.inversionista_id) from crm.leads l where l.id = p_lead_id and l.inversionista_id is not null),
    (select private.inversionista_por_documento('DNI', l.dni) from crm.leads l where l.id = p_lead_id and l.dni is not null),
    (select private.inversionista_canonica(il.inversionista_id) from crm.inversionista_leads il
      where il.lead_id = p_lead_id order by (il.rol = 'canonico') desc, il.id limit 1))
$$;
revoke all on function private.lead_persona_reabrir(uuid) from public, anon, authenticated, service_role;

-- 0.4 Candados ANTES de tocar filas (orden total documento → persona → lead, el de la reserva, el sellado y la fusión):
--     todos los documentos implicados (los de los leads, el tecleado y los vigentes de sus personas) en orden de texto, y las
--     personas FOR SHARE en orden de id. Devuelve {personas, claves} bloqueadas para que el llamador verifique tras tomar la fila
--     que el documento actual del lead está entre las claves y su persona entre las personas (ABA cerrado, Codex v4.2).
--     Inerte con la bandera apagada.
create or replace function private.bloquear_personas_de_leads(p_leads uuid[], p_dni_extra text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_personas uuid[]; v_claves text[]; v_k text;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return pg_catalog.jsonb_build_object('personas', '[]'::jsonb, 'claves', '[]'::jsonb);
  end if;
  -- Codex v4.3 [2]: la comprobación «sigue dentro de lo bloqueado» relee tras esperar y eso solo vale en READ COMMITTED
  -- (en REPEATABLE READ el snapshot viejo esconde a una persona confirmada por otra transacción).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  select pg_catalog.array_agg(distinct p order by p) into v_personas
  from (select private.lead_persona_reabrir(l.id) as p from crm.leads l where l.id = any(coalesce(p_leads, '{}'::uuid[]))
        union select private.inversionista_por_documento('DNI', p_dni_extra) where p_dni_extra is not null) s
  where p is not null;
  select pg_catalog.array_agg(distinct k order by k) into v_claves
  from (select 'DNI:' || l.dni as k from crm.leads l where l.id = any(coalesce(p_leads, '{}'::uuid[])) and l.dni is not null
        union select 'DNI:' || p_dni_extra where p_dni_extra is not null
        union select d.tipo_documento || ':' || d.documento_normalizado
                from crm.inversionista_identificadores d
               where d.inversionista_id = any(coalesce(v_personas, '{}'::uuid[])) and d.estado = 'vigente') s;
  if v_claves is not null then
    foreach v_k in array v_claves loop
      perform private.identidad_bloquear_documento(split_part(v_k, ':', 1), split_part(v_k, ':', 2));
    end loop;
  end if;
  if v_personas is not null then
    perform 1 from crm.inversionistas i where i.id = any(v_personas) order by i.id for share;
  end if;
  -- Codex v4.3 [1]: identidad_bloquear_documento es un no-op si la bandera está APAGADA; si alguien la apagó entre la primera
  -- lectura y los candados, no hay candados reales → no se declara nada bloqueado (el llamador da veredicto fresco / 40001).
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return pg_catalog.jsonb_build_object('personas', '[]'::jsonb, 'claves', '[]'::jsonb);
  end if;
  -- Devuelve lo que REALMENTE bloqueó (Codex v4.2, ABA): el llamador, tras tomar la fila, exige que el documento actual
  -- del lead esté entre las claves bloqueadas y su persona entre las bloqueadas; si no, veredicto fresco / 40001.
  return pg_catalog.jsonb_build_object('personas', pg_catalog.to_jsonb(coalesce(v_personas, '{}'::uuid[])),
                                       'claves', pg_catalog.to_jsonb(coalesce(v_claves, '{}'::text[])));
end;
$$;
revoke all on function private.bloquear_personas_de_leads(uuid[], text) from public, anon, authenticated, service_role;

-- 0.4b ¿El lead, ya bloqueado, sigue dentro de lo que se bloqueó? (documento actual entre las claves y persona entre las personas)
create or replace function private.lead_dentro_de_bloqueo(p_lead_id uuid, p_bloqueo jsonb)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select (l.dni is null or ('DNI:' || l.dni) in (select x from pg_catalog.jsonb_array_elements_text(p_bloqueo->'claves') x))
       and (private.lead_persona_reabrir(l.id) is null
            or private.lead_persona_reabrir(l.id)::text in (select x from pg_catalog.jsonb_array_elements_text(p_bloqueo->'personas') x))
    from crm.leads l where l.id = p_lead_id), false)
$$;
revoke all on function private.lead_dentro_de_bloqueo(uuid, jsonb) from public, anon, authenticated, service_role;

-- 0.5a Juicio de PERSONA: NULL si a la persona se le puede dar/reabrir el lead indicado; si no, el veredicto
--      (no_contactar si está vetada; ya_es_cliente si tiene OTRO lead, está en conversión o ya es cliente —perfil, activo o no—).
create or replace function private.juicio_persona(p_inv uuid, p_excluir_lead_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_asesor text;
begin
  if p_inv is null then return null; end if;
  if exists (select 1 from crm.inversionistas i where i.id = p_inv and i.no_contactar) then
    return pg_catalog.jsonb_build_object('estado', 'no_contactar');
  end if;
  select coalesce(resp.nombre_completo, res.nombre_completo, 'sin asesor asignado') into v_asesor
  from crm.inversionistas i
  left join public.perfiles resp on resp.id = i.responsable_relacion_id
  left join lateral (
    select p.nombre_completo from crm.conversion_reservas r join public.perfiles p on p.id = r.reservado_por
    left join crm.leads lr on lr.id = r.lead_id
    where r.inversionista_id = i.id and r.lead_id is distinct from p_excluir_lead_id
      and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))
    order by r.reservado_en desc limit 1) res on true
  where i.id = p_inv;
  if exists (select 1 from private.leads_de_personas(array[p_inv]) x where x is distinct from p_excluir_lead_id)
     or private.persona_en_conversion(p_inv, p_excluir_lead_id)
     or exists (select 1 from crm.inversionistas i where i.id = p_inv and i.perfil_id is not null) then
    return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_asesor, 'sin asesor asignado'), 'via', 'identidad');
  end if;
  return null;
end;
$$;
revoke all on function private.juicio_persona(uuid, uuid) from public, anon, authenticated, service_role;

-- 0.5 El JUICIO único de reapertura/toma: NULL si el lead puede reabrirse/tomarse; si no, el veredicto (forma del front:
--     estado ya_es_cliente, asesor, via identidad) que explica por qué. Reglas: cualquier ya_es_cliente del verificador con el
--     documento tecleado o con el del blanco; las personas halladas (enlace, documento tecleado, documento del blanco, puente)
--     deben ser UNA; la persona no puede tener OTRO lead (enlace ∪ puente ∪ suelto vivo con su documento), ni estar en
--     conversión, ni ser ya cliente (perfil, activo o no). Solo lecturas: se llama bajo los candados de 0.4 y la fila del lead.
create or replace function private.juicio_reapertura(p_lead_id uuid, p_telefono text, p_dni_tecleado text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lead crm.leads%rowtype; v_v jsonb; v_inv uuid; v_inv_tec uuid; v_inv_doc uuid; v_inv_puente uuid; v_asesor text;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found then return null; end if;
  if p_dni_tecleado is not null then
    v_v := private.verificar_disponibilidad_lead_impl(p_telefono, p_dni_tecleado, p_lead_id);
    if v_v->>'estado' = 'ya_es_cliente' then return v_v; end if;
  end if;
  if v_lead.dni is not null and v_lead.dni is distinct from p_dni_tecleado then
    v_v := private.verificar_disponibilidad_lead_impl(p_telefono, v_lead.dni, p_lead_id);
    if v_v->>'estado' = 'ya_es_cliente' then return v_v; end if;
  end if;
  v_inv_tec := case when p_dni_tecleado is not null then private.inversionista_por_documento('DNI', p_dni_tecleado) end;
  v_inv_doc := case when v_lead.dni is not null then private.inversionista_por_documento('DNI', v_lead.dni) end;
  select private.inversionista_canonica(il.inversionista_id) into v_inv_puente
    from crm.inversionista_leads il where il.lead_id = p_lead_id order by (il.rol = 'canonico') desc, il.id limit 1;
  v_inv := coalesce(private.inversionista_canonica(v_lead.inversionista_id), v_inv_doc, v_inv_puente, v_inv_tec);
  -- Un CLIENTE del Portal con ese documento, aunque esté inactivo y sin ficha de persona, ya es cliente (Codex v3 M2).
  if exists (select 1 from public.perfiles per where per.rol = 'cliente' and per.dni is not null
              and coalesce(nullif(pg_catalog.btrim(per.tipo_documento), ''), 'DNI') = 'DNI'
              and per.dni in (p_dni_tecleado, v_lead.dni)) then
    return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente',
      'asesor', coalesce((select a.nombre_completo from public.perfiles per join public.perfiles a on a.id = per.asesor_perfil_id
                           where per.rol = 'cliente' and coalesce(nullif(pg_catalog.btrim(per.tipo_documento), ''), 'DNI') = 'DNI'
                             and per.dni in (p_dni_tecleado, v_lead.dni) limit 1), 'sin asesor asignado'),
      'via', 'identidad');
  end if;
  -- Una reserva viva o sellada (sin convertir) de ESTE lead también lo hace no reabrible/no tomable (auditor v3 N3).
  if exists (select 1 from crm.conversion_reservas r where r.lead_id = p_lead_id
              and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and v_lead.etapa <> 'convertido'))) then
    return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente',
      'asesor', coalesce((select p.nombre_completo from crm.conversion_reservas r join public.perfiles p on p.id = r.reservado_por where r.lead_id = p_lead_id), 'sin asesor asignado'),
      'via', 'identidad');
  end if;
  if v_inv is null then return null; end if;
  select coalesce(resp.nombre_completo, 'sin asesor asignado') into v_asesor
  from crm.inversionistas i left join public.perfiles resp on resp.id = i.responsable_relacion_id where i.id = v_inv;
  if (v_inv_tec is not null and v_inv_tec is distinct from v_inv)
     or (v_inv_doc is not null and v_inv_doc is distinct from v_inv)
     or (v_inv_puente is not null and v_inv_puente is distinct from v_inv)
     or (v_lead.inversionista_id is not null and private.inversionista_canonica(v_lead.inversionista_id) is distinct from v_inv) then
    return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', coalesce(v_asesor, 'sin asesor asignado'), 'via', 'identidad');
  end if;
  -- Veto de la persona (también la hallada solo por puente, Codex v3 M1), otro lead, conversión en curso, ya cliente.
  return private.juicio_persona(v_inv, p_lead_id);
end;
$$;
revoke all on function private.juicio_reapertura(uuid, text, text) from public, anon, authenticated, service_role;

-- 0.6 Enlazar un lead reabierto/tomado a su persona (como al nacer), bajo válvula y restaurándola; el trigger zz escribe el
--     puente canónico si no existe, y un puente histórico del propio lead pasa a canónico si la persona no tiene otro (Codex 13).
create or replace function private.enlazar_lead_reabierto(p_lead_id uuid, p_inv uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_previo text;
begin
  if p_inv is null or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return;
  end if;
  v_previo := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off');
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.leads set inversionista_id = p_inv where id = p_lead_id and inversionista_id is null;
  update crm.inversionista_leads il set rol = 'canonico'
   where il.lead_id = p_lead_id and il.rol = 'historico'
     and not exists (select 1 from crm.inversionista_leads il2 where il2.inversionista_id = il.inversionista_id and il2.rol = 'canonico');
  perform pg_catalog.set_config('crm.op_privilegiada', v_previo, true);
end;
$$;
revoke all on function private.enlazar_lead_reabierto(uuid, uuid) from public, anon, authenticated, service_role;

-- 0.6b Puerta para fijar/cambiar el DNI de un lead con la identidad encendida (Codex v3 B1/B2): candado del documento nuevo y
--      persona FOR SHARE ANTES de la fila (orden documento -> persona -> lead), juicio de la persona, GUC para el trigger y
--      enlace si la persona existe. Ámbito: el de la policy leads_update. Con la bandera apagada: el UPDATE de hoy.
create or replace function crm.fijar_dni_lead_fn(p_lead_id uuid, p_dni text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_lead crm.leads%rowtype; v_inv uuid; v_v jsonb; v_previo text; v_k text; v_claves text[] := '{}';
  v_flag boolean := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
begin
  if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'Acceso CRM revocado' using errcode = '42501';
  end if;
  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception 'El DNI debe tener exactamente 8 digitos' using errcode = '22023';
  end if;
  -- Ámbito ANTES de cualquier candado (auditor v4 M1): un lead ajeno o inexistente muere aquí sin sondear a nadie.
  if not exists (select 1 from crm.leads l
                  where l.id = p_lead_id and l.activo = true
                    and (v_rol = 'gerencia'
                         or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
                         or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_flag then
    -- Candados del documento ANTERIOR y del nuevo, en orden de texto (Codex v4.1): una toma o reapertura en vuelo que
    -- bloqueó el documento anterior termina antes de que este cambio lo deje obsoleto; y quien llegue después ve el nuevo.
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    for v_k in select k from (select l.dni as k from crm.leads l where l.id = p_lead_id and l.dni is not null
                              union select v_dni where v_dni is not null) s order by k loop
      perform private.identidad_bloquear_documento('DNI', v_k);
      v_claves := v_claves || v_k;
    end loop;
    if v_dni is not null then
      v_inv := private.inversionista_por_documento('DNI', v_dni);
      if v_inv is not null then
        perform 1 from crm.inversionistas i where i.id = v_inv for share;
      end if;
    end if;
  end if;
  select * into v_lead
  from crm.leads l
  where l.id = p_lead_id and l.activo = true
    and (v_rol = 'gerencia'
         or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
         or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.dni is not distinct from v_dni then
    return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'sin_cambios', true);
  end if;
  if v_flag then
    -- Codex v4.3 [1]: si la bandera se apagó en medio, los candados de documento fueron no-ops: no se escribe con una lista vacía.
    if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
      raise exception 'La identidad unificada se apagó durante la operación; vuelve a intentarlo' using errcode = '40001';
    end if;
    -- El documento anterior ACTUAL debe ser uno de los bloqueados (Codex v4.2: otra llamada pudo cambiarlo mientras se esperaba).
    if v_lead.dni is not null and not (v_lead.dni = any(v_claves)) then
      raise exception 'El documento de este lead cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
    end if;
    if v_lead.inversionista_id is not null or exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id) then
      raise exception 'El documento de un lead ya reconocido solo lo corrige Gerencia (corrección de documento)' using errcode = 'P0409';
    end if;
    if exists (select 1 from crm.conversion_reservas r where r.lead_id = p_lead_id
                and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and v_lead.etapa <> 'convertido'))) then
      raise exception 'Este lead tiene una conversión en curso: no se cambia su documento' using errcode = 'P0409';
    end if;
    if v_inv is not null then
      v_v := private.juicio_persona(v_inv, p_lead_id);
      if v_v is not null then
        if v_v->>'estado' = 'no_contactar' then
          raise exception 'La persona de ese documento tiene la restricción «No insistir»' using errcode = 'P0429';
        end if;
        raise exception 'La persona de ese documento ya es cliente o ya tiene su lead: no se puede asignar a este'
          using errcode = 'P0409', detail = v_v::text;
      end if;
    end if;
  end if;
  v_previo := coalesce(pg_catalog.current_setting('crm.dni_por_puerta', true), 'off');
  perform pg_catalog.set_config('crm.dni_por_puerta', 'on', true);
  update crm.leads set dni = v_dni where id = p_lead_id;
  perform pg_catalog.set_config('crm.dni_por_puerta', v_previo, true);
  if v_flag and v_inv is not null then
    perform private.enlazar_lead_reabierto(p_lead_id, v_inv);
  end if;
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'dni', v_dni,
    'inversionista_id', case when v_flag then v_inv end, 'enlazado', v_flag and v_inv is not null);
end;
$$;
revoke all on function crm.fijar_dni_lead_fn(uuid, text) from public, anon, service_role;
grant execute on function crm.fijar_dni_lead_fn(uuid, text) to authenticated;
comment on function crm.fijar_dni_lead_fn(uuid, text) is
  'F2.b [D-13]: fija el DNI de un lead. Con la identidad encendida: candado del documento y persona antes de la fila, juicio de la persona, enlace si existe. Apagada: el UPDATE de hoy.';

-- 0.7 Trigger: con la bandera encendida, un descarte (o un lead inactivo) solo se reabre por sus puertas (tomar, rescatar,
--     deshacer), que juzgan a la persona y enlazan; el UPDATE directo de etapa no (Codex D-13 #7). Gerencia bajo válvula pasa.
create or replace function private.trg_leads_zz_reapertura_solo_rpc()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if v_priv or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  if ((old.etapa = 'descartado' and new.etapa is distinct from 'descartado') or (old.activo = false and new.activo = true))
     and coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off') <> 'on' then
    raise exception 'Con la identidad unificada encendida, un descarte se reabre solo por sus puertas (tomar, rescatar o deshacer): juzgan a la persona y enlazan el lead'
      using errcode = 'P0409';
  end if;
  return new;
end;
$$;
revoke all on function private.trg_leads_zz_reapertura_solo_rpc() from public, anon, authenticated, service_role;
drop trigger if exists trg_leads_zz_reapertura_solo_rpc on crm.leads;
create trigger trg_leads_zz_reapertura_solo_rpc
  before update of etapa, activo on crm.leads
  for each row execute function private.trg_leads_zz_reapertura_solo_rpc();
comment on trigger trg_leads_zz_reapertura_solo_rpc on crm.leads is
  'F2.b [D-13]: con resolver_en_puertas encendida, descartado -> vivo (o activo false -> true) solo bajo crm.reapertura_identidad=on (tomar/rescatar/deshacer) o válvula. Apagada: inerte.';
"""
GUC_ON  = "  v_previo_reab := coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off');\n  perform pg_catalog.set_config('crm.reapertura_identidad', 'on', true);\n"
GUC_OFF = "  perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);\n"

# ── T1 verificador ────────────────────────────────────────────────────────────────────────
t1 = rep(prev['private.verificar_disponibilidad_lead_impl.3'], """    select coalesce(resp.nombre_completo, 'sin asesor asignado')
      into v_asesor_identidad
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    -- Sin filtro li.activo: DELIBERADO. leads_inversionista_uidx es único por
    -- inversionista_id SIN filtro de activo, así que un lead soft-borrado que
    -- conserve el puntero seguiría bloqueando la conversión del nuevo; mejor
    -- bloquear aquí, en el alta, con mensaje claro, que reventar al convertir.
    join crm.leads li on li.inversionista_id = i.id
    left join public.perfiles resp on resp.id = i.responsable_relacion_id
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = v_dni_norm
      and idf.estado = 'vigente'
      and idf.verificado = true
      and i.estado <> 'fusionado'
      and li.id is distinct from p_excluir_lead_id
    limit 1;
""", """    -- F2.b [D-13]: «los leads de una persona» = enlace vivo ∪ PUENTE ∪ sueltos vivos con su documento (private.leads_de_personas;
    -- incluye históricos y soft-borrados enlazados, como ya contaba el join sin filtro de activo); una persona EN CONVERSIÓN
    -- (reserva por persona viva o sellada de OTRO lead) o que YA ES CLIENTE (perfil enlazado, activo o no) tampoco recibe
    -- otro lead. `asesor` = responsable de relación, o quien reservó (reserva vigente), o el centinela. Contrato del front intacto.
    select coalesce(resp.nombre_completo, res.nombre_completo, 'sin asesor asignado')
      into v_asesor_identidad
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    left join public.perfiles resp on resp.id = i.responsable_relacion_id
    left join lateral (
      select p.nombre_completo
      from crm.conversion_reservas r
      join public.perfiles p on p.id = r.reservado_por
      left join crm.leads lr on lr.id = r.lead_id
      where r.inversionista_id = i.id and r.lead_id is distinct from p_excluir_lead_id
        and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))
      order by r.reservado_en desc
      limit 1
    ) res on true
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = v_dni_norm
      and idf.estado = 'vigente'
      and idf.verificado = true
      and i.estado <> 'fusionado'
      and (exists (select 1 from private.leads_de_personas(array[i.id]) x where x is distinct from p_excluir_lead_id)
           or private.persona_en_conversion(i.id, p_excluir_lead_id)
           or i.perfil_id is not null)
    limit 1;
""")

# ── T2 trigger de nacimiento ─────────────────────────────────────────────────────────────
RESERVA_VIG = "(r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(lr.etapa, '') <> 'convertido'))"
t2 = rep(prev['private.trg_leads_zz_enlaza_identidad'], """  -- Un solo lead TOTAL por persona (invariante #6): vivos, convertidos y descartados.
  select l.id, coalesce(resp.nombre_completo, 'sin asesor asignado') as asesor
    into v_otro
  from crm.leads l
  join crm.inversionistas i on i.id = l.inversionista_id
  left join public.perfiles resp on resp.id = i.responsable_relacion_id
  where l.inversionista_id = v_inv
    and l.id is distinct from new.id
  limit 1;
  if found then
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente', 'asesor', v_otro.asesor, 'via', 'identidad', 'lead_id', v_otro.id)::text;
  end if;
""", f"""  -- Un solo lead TOTAL por persona (invariante #6): vivos, convertidos y descartados.
  -- F2.b [D-13]: enlace vivo ∪ PUENTE ∪ sueltos vivos con su documento (private.leads_de_personas; el enlace vivo primero en
  -- el detalle) y persona EN CONVERSIÓN (reserva por persona viva o sellada de otro lead). Serializado con la reserva por el
  -- candado documental que ya tomó el trigger 000 (inv_resolver:DNI:<doc>, la misma clave que toma la reserva; b1).
  select x as id, coalesce(resp.nombre_completo, 'sin asesor asignado') as asesor
    into v_otro
  from private.leads_de_personas(array[v_inv]) x
  join crm.inversionistas i on i.id = v_inv
  left join public.perfiles resp on resp.id = i.responsable_relacion_id
  where x is distinct from new.id
  order by (exists (select 1 from crm.leads l where l.id = x and l.inversionista_id = v_inv)) desc, x
  limit 1;
  if found then
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente', 'asesor', v_otro.asesor, 'via', 'identidad', 'lead_id', v_otro.id)::text;
  end if;
  if private.persona_en_conversion(v_inv, new.id)
     or exists (select 1 from crm.inversionistas i where i.id = v_inv and i.perfil_id is not null) then   -- ya cliente (Codex v3 M2)
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente',
              'asesor', coalesce((select p.nombre_completo
                                    from crm.conversion_reservas r
                                    join public.perfiles p on p.id = r.reservado_por
                                    left join crm.leads lr on lr.id = r.lead_id
                                   where r.inversionista_id = v_inv and r.lead_id is distinct from new.id
                                     and {RESERVA_VIG}
                                   order by r.reservado_en desc limit 1), 'sin asesor asignado'),
              'via', 'identidad',
              'lead_id', (select r.lead_id from crm.conversion_reservas r
                           left join crm.leads lr on lr.id = r.lead_id
                           where r.inversionista_id = v_inv and r.lead_id is distinct from new.id
                             and {RESERVA_VIG}
                           order by r.reservado_en desc limit 1))::text;
  end if;
""")
t2 = rep(t2, """    if old.inversionista_id is not null
       or (nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is not null
           and private.inversionista_por_documento('DNI', new.dni) is not null) then
      raise exception 'El documento pertenece a una persona reconocida: solo Gerencia lo corrige (corrección de documento)'
        using errcode = 'P0409';
    end if;
    return new;
""", """    if old.inversionista_id is not null
       or exists (select 1 from crm.inversionista_leads il where il.lead_id = new.id) then
      raise exception 'El documento pertenece a una persona reconocida: solo Gerencia lo corrige (corrección de documento)'
        using errcode = 'P0409';
    end if;
    -- F2.b [D-13] (Codex v3 B1, auditor v4 A1): con la identidad encendida, el DNI de un lead se FIJA por su puerta
    -- (crm.fijar_dni_lead_fn), que toma el candado del documento y a la persona ANTES de la fila (orden documento ->
    -- persona -> lead), juzga a la persona y enlaza si procede: por la puerta, el trigger deja pasar. El UPDATE directo
    -- (fila ya bloqueada, sin serialización posible con una reserva en vuelo) se rechaza: hacia una persona reconocida
    -- con el mensaje de siempre; hacia un documento sin dueño, «por su puerta».
    if coalesce(pg_catalog.current_setting('crm.dni_por_puerta', true), 'off') = 'on' then
      return new;
    end if;
    if nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is not null
       and private.inversionista_por_documento('DNI', new.dni) is not null then
      raise exception 'El documento pertenece a una persona reconocida: solo Gerencia lo corrige (corrección de documento)'
        using errcode = 'P0409';
    end if;
    raise exception 'Con la identidad unificada encendida, el DNI de un lead se fija por su puerta (fijar_dni_lead_fn) o lo corrige Gerencia'
      using errcode = 'P0409';
""")

# ── T3 tomar_lead_libre ──────────────────────────────────────────────────────────────────
t3 = rep(prev['crm.tomar_lead_libre'], "  v_dni text := nullif(pg_catalog.btrim(p_dni), '');\n",
         "  v_dni text := nullif(pg_catalog.btrim(p_dni), '');\n  v_veredicto_identidad jsonb;\n  v_flag_d13 boolean := " + FLAG + ";\n  v_candidato uuid;\n  v_bloqueo jsonb;\n  v_previo_reab text;\n")
t3 = rep(t3, """  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
  end if;
""", """  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
  end if;
  -- F2.b [D-13]: los candados de PERSONA van ANTES de la fila (orden total documento -> persona -> lead, el de la reserva,
  -- el sellado y la fusión). El blanco se localiza SIN lock con el mismo criterio de abajo (teléfono manda; si no, DNI),
  -- se bloquean sus documentos y su persona (y los del DNI tecleado), y después se toma la fila; si la fila ya no es la
  -- misma o su persona cambió, manda el veredicto fresco. Inerte con la bandera apagada.
  if v_flag_d13 then
    select l.id into v_candidato
    from crm.leads l
    where l.telefono = v_tel
      and l.no_contactar = false
      and not private.persona_vetada(l.id)
      and (
        (l.activo = true
          and l.etapa not in ('convertido', 'descartado')
          and l.vendedor_id is null
          and l.asignado_supervisor_id is null)
        or (l.etapa = 'descartado' and l.descartado_en is not null)
      )
    order by (l.etapa = 'descartado'), l.descartado_en desc, l.id
    limit 1;
    if v_candidato is null and v_dni is not null then
      select l.id into v_candidato
      from crm.leads l
      where l.dni = v_dni
        and l.no_contactar = false
        and not private.persona_vetada(l.id)
        and (
          (l.activo = true
            and l.etapa not in ('convertido', 'descartado')
            and l.vendedor_id is null
            and l.asignado_supervisor_id is null)
          or (l.etapa = 'descartado' and l.descartado_en is not null)
        )
      order by (l.etapa = 'descartado'), l.descartado_en desc nulls last, l.id
      limit 1;
    end if;
    v_bloqueo := private.bloquear_personas_de_leads(case when v_candidato is null then '{}'::uuid[] else array[v_candidato] end, v_dni);
  end if;
""")
t3 = rep(t3, """     or not private.es_destino_crm_activo(v_actor, array['vendedor']::text[]) then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- Si OTRO lead vivo del mismo contacto tiene DUEÑO, el contacto está tomado
""", """     or not private.es_destino_crm_activo(v_actor, array['vendedor']::text[]) then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- F2.b [D-13]: la fila tomada debe ser el candidato bloqueado y seguir DENTRO de lo bloqueado: su documento actual entre las
  -- claves y su persona entre las personas (Codex v4.1/v4.2: un cambio de DNI en medio, incluso A->B->A, dejaría obsoleto el
  -- candado); si no, veredicto fresco.
  if v_flag_d13 and (v_lead.id is distinct from v_candidato or not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo)) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, coalesce(v_dni, v_lead.dni)));
  end if;
  -- F2.b [D-13]: el JUICIO único de reapertura/toma (documento tecleado, documento del blanco, puente, enlace; otro lead de la
  -- persona, conversión en curso, ya cliente): con veredicto asentado y sin escribir nada.
  if v_flag_d13 then
    v_veredicto_identidad := private.juicio_reapertura(v_lead.id, v_tel, v_dni);
    if v_veredicto_identidad is not null then
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni, v_veredicto_identidad);
    end if;
  end if;

  -- Si OTRO lead vivo del mismo contacto tiene DUEÑO, el contacto está tomado
""")
t3 = rep(t3, """  v_previo := coalesce(pg_catalog.current_setting('crm.toma_directa', true), 'off');
  perform pg_catalog.set_config('crm.toma_directa', 'on', true);
""", """  v_previo := coalesce(pg_catalog.current_setting('crm.toma_directa', true), 'off');
  perform pg_catalog.set_config('crm.toma_directa', 'on', true);
""" + GUC_ON)
t3 = rep(t3, "\n  perform pg_catalog.set_config('crm.toma_directa', v_previo, true);\n",
             "\n  perform pg_catalog.set_config('crm.toma_directa', v_previo, true);\n" + GUC_OFF, n=1)
t3 = rep(t3, "        perform pg_catalog.set_config('crm.toma_directa', v_previo, true);\n",
             "        perform pg_catalog.set_config('crm.toma_directa', v_previo, true);\n        " + GUC_OFF.strip() + "\n")
t3 = rep(t3, """  if not found then
    -- CAS en 0 filas: el estado cambió entre el veredicto y la escritura.
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;
""", """  if not found then
    -- CAS en 0 filas: el estado cambió entre el veredicto y la escritura.
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;
  -- F2.b [D-13] (Codex #5): un lead con DNI (o puente) de una persona reconocida queda ENLAZADO al tomarse, como al nacer:
  -- así la reserva, el sellado y las conversiones lo ven por identidad. La persona ya está bloqueada FOR SHARE (arriba).
  if v_flag_d13 and v_lead.inversionista_id is null then
    perform private.enlazar_lead_reabierto(v_lead.id, private.lead_persona_reabrir(v_lead.id));
  end if;
""")

# ── T4/T5 conversiones: puente del propio lead, un solo lead por documento, reserva ajena ─
def puente(s, que):
    s = rep(s, """  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
""", """  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #1): también los leads SUELTOS vivos que llevan un documento vigente de la persona (nacieron antes
  -- de que existiera la persona) cuentan en «un solo lead».
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
""")
    return rep(s, f"""  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento {que}: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
""", f"""  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento {que}: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex D-10 #2): el PUENTE del propio lead también manda (por la canónica), como en la reserva por persona (D-10).
  if v_flag and v_inv is not null
     and exists (select 1 from crm.inversionista_leads il
                  where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento {que}: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
""")
t4 = puente(prev['crm.convertir_lead'], 'del cliente')
t4 = rep(t4, """    raise exception 'La persona de este lead (según su puente) no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
""", """    raise exception 'La persona de este lead (según su puente) no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #2): una reserva viva o sellada de ESTE lead pertenece a UNA persona (b4): no se convierte para otra
  -- por la puerta directa; el cierre de la saga trae la misma persona y pasa.
  if v_flag and exists (select 1 from crm.conversion_reservas r
                         where r.lead_id = p_lead_id and r.inversionista_id is not null
                           and r.inversionista_id is distinct from v_inv
                           and (r.efectos_iniciados_en is not null or r.expira_en > pg_catalog.now())) then
    raise exception 'Este lead está reservado para otra persona: espera a que caduque o pide a Gerencia que lo retome'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex v3 B4): una conversión Avance en curso en OTRO lead de la misma persona (reserva viva o sellada)
  -- también rechaza la puerta directa, como ya hace convertir_lead_externo; el cierre de la saga trae su propio lead y pasa.
  if v_flag and v_inv is not null and private.persona_en_conversion(v_inv, p_lead_id) then
    raise exception 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead' using errcode = 'P0409';
  end if;
""")
t5 = puente(prev['crm.convertir_lead_externo'], 'del cierre')

# ── T6 sellado (3 args) ──────────────────────────────────────────────────────────────────
t6 = rep(prev['crm.marcar_efectos_conversion.3'], """  -- Veto revalidado bajo el lock de la identidad, ANTES del punto de no retorno (Codex E2 #11).
  perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
""", """  -- F2.b [D-13]: los documentos vigentes de la persona ANTES de su lock (orden documento -> persona, el de la reserva, la toma
  -- y la fusión): una toma/reapertura por ese documento en vuelo termina antes o después de este sellado, nunca en medio.
  perform private.identidad_bloquear_documentos_de(array[v_loc.inversionista_id]);
  -- Veto revalidado bajo el lock de la identidad, ANTES del punto de no retorno (Codex E2 #11).
  perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
""")
t6 = rep(t6, """  return crm.marcar_efectos_conversion(p_lead_id);
""", """  -- F2.b [D-13] (Codex #4, auditor v3 M1): el lead FOR SHARE tras la persona y ANTES de la reserva (orden persona -> lead ->
  -- reserva, el mismo de la reserva por persona, la conversión coop y la fusión: sin arista nueva).
  perform 1 from crm.leads l where l.id = p_lead_id for share;
  -- F2.b [D-13] (Codex #5): la pareja (lead, claim, persona) se revalida bajo el lock de la RESERVA: tras esperar, otra reserva
  -- del mismo lead para otra persona no se sella con este claim.
  perform 1 from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if not exists (select 1 from crm.conversion_reservas r
                  where r.lead_id = p_lead_id and r.claim_id = p_claim_id and r.inversionista_id = v_loc.inversionista_id) then
    raise exception 'La reserva de este lead cambió mientras se sellaba; vuelve a reservar' using errcode = '40001';
  end if;
  -- F2.b [D-13] (Codex v3 B3): el token se relee tras los locks: una reanudación de la reserva mientras se esperaba rota el
  -- token del mismo claim, y esa ejecución vieja no debe autorizar efectos.
  perform 1 from crm.multiempresa_idempotencia m where m.clave = v_loc.clave for share;   -- orden reserva -> claim (b4)
  select * into v_loc from private.saga_auth_localizar(p_claim_id);
  if not found or v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_token) then
    raise exception 'El claim cambió (token rotado) mientras se sellaba; vuelve a reservar' using errcode = '40001';
  end if;
  -- F2.b [D-13] (Codex #4): el lead debe seguir vivo y sin otra persona (una conversión directa para otra persona, o un
  -- descarte, mientras la reserva esperaba, no se sella).
  if not exists (select 1 from crm.leads l where l.id = p_lead_id and l.activo
                  and l.etapa not in ('convertido', 'descartado')
                  and (l.inversionista_id is null or private.inversionista_canonica(l.inversionista_id) = v_loc.inversionista_id)
                  and (l.dni is null or private.inversionista_por_documento('DNI', l.dni) = v_loc.inversionista_id)) then   -- Codex v3 B2
    raise exception 'El lead ya no está disponible para esta conversión (convertido, descartado, con otro documento o de otra persona): no se sella'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #1/#3): «un solo lead» revalidado bajo el lock de la persona ANTES del punto de no retorno, contando
  -- enlace, puente y sueltos vivos con su documento: un lead de esta persona nacido, reabierto o tomado mientras la reserva
  -- esperaba (o ya vencida) no deja cuentas de portal huérfanas; Gerencia revisa o fusiona.
  if exists (select 1 from private.leads_de_personas(array[v_loc.inversionista_id]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene otro lead: no se sella la conversión (revisión o fusión de Gerencia)'
      using errcode = 'P0409';
  end if;
  return crm.marcar_efectos_conversion(p_lead_id);
""")

# ── T7 rescatar_descartes ────────────────────────────────────────────────────────────────
t7 = rep(prev['crm.rescatar_descartes'], "  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);\n",
         "  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);\n  v_veredicto jsonb;\n  v_bloqueo jsonb;\n  v_previo_reab text;\n")
t7 = rep(t7, """  -- Se bloquean los leads antes de modificar alguno. Si una carrera ya los
  -- reabrió, toda la operación falla y no deja un reparto parcial.
  for v_fila in
""", """  -- F2.b [D-13]: candados de PERSONA antes de las filas (documento -> persona -> lead): documentos y personas de todos los
  -- leads del lote, en orden; luego las filas. Si tras tomarlas la persona de un lead no está entre las bloqueadas -> 40001.
  v_bloqueo := private.bloquear_personas_de_leads(
    (select pg_catalog.array_agg(la.lead_id) from crm.lead_asignaciones la where la.id = any(p_episodios)), null);
  -- Se bloquean los leads antes de modificar alguno. Si una carrera ya los
  -- reabrió, toda la operación falla y no deja un reparto parcial.
  for v_fila in
""")
t7 = rep(t7, """      (l.no_contactar or (v_flag and coalesce(inv.no_contactar, false))) as no_contactar  -- veto de la PERSONA
    from crm.lead_asignaciones la""", """      (l.no_contactar or (v_flag and coalesce(inv.no_contactar, false))) as no_contactar,  -- veto de la PERSONA
      l.telefono, l.dni, l.inversionista_id
    from crm.lead_asignaciones la""")
t7 = rep(t7, """    if private.persona_vetada(v_fila.lead_id) then
      raise exception 'Uno de los leads pertenece a una persona con la restricción «No insistir» y no puede reactivarse'
        using errcode = 'P0429';
    end if;
  end loop;
""", """    if private.persona_vetada(v_fila.lead_id) then
      raise exception 'Uno de los leads pertenece a una persona con la restricción «No insistir» y no puede reactivarse'
        using errcode = 'P0429';
    end if;
    -- F2.b [D-13] (auditor M1 / Codex #6): con la identidad encendida, el JUICIO único de reapertura por lead; todo el lote
    -- falla, como con el veto. La persona debe ser una de las bloqueadas antes de las filas (si no, 40001).
    if v_flag then
      if not private.lead_dentro_de_bloqueo(v_fila.lead_id, v_bloqueo) then
        raise exception 'El documento o la persona de uno de los leads cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
      end if;
      v_veredicto := private.juicio_reapertura(v_fila.lead_id, v_fila.telefono, null);
      if v_veredicto->>'estado' = 'no_contactar' then
        raise exception 'Uno de los leads pertenece a una persona con la restricción «No insistir» y no puede reactivarse'
          using errcode = 'P0429';
      end if;
      if v_veredicto is not null then
        raise exception 'Uno de los leads pertenece a una persona que ya es cliente o ya tiene su lead y no puede reactivarse'
          using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', 'identidad', 'lead_id', v_fila.lead_id)::text;
      end if;
    end if;
  end loop;
""")
t7 = rep(t7, """  -- Una segunda pasada usa los mismos locks. La vuelta redonda conserva el
  -- orden seleccionado y, si se pidió, salta al asesor que lo descartó.
  for v_fila in
""", "  -- F2.b [D-13]: la reapertura pasa por la puerta (trigger «solo por RPC»).\n" + GUC_ON + """  -- Una segunda pasada usa los mismos locks. La vuelta redonda conserva el
  -- orden seleccionado y, si se pidió, salta al asesor que lo descartó.
  for v_fila in
""")
t7 = rep(t7, """     where id = v_fila.lead_id;

    v_orden := v_orden + 1;
  end loop;
""", """     where id = v_fila.lead_id;
    -- F2.b [D-13] (auditor M1 / Codex #6): el lead reabierto queda ENLAZADO a su persona (como al nacer), ya bloqueada FOR SHARE.
    if v_flag then
      perform private.enlazar_lead_reabierto(v_fila.lead_id, private.lead_persona_reabrir(v_fila.lead_id));
    end if;

    v_orden := v_orden + 1;
  end loop;
""" + GUC_OFF)

# ── T8 deshacer_descarte_implementacion ──────────────────────────────────────────────────
t8 = rep(prev['private.deshacer_descarte_implementacion'], "  v_lead    crm.leads%rowtype;\n",
         "  v_lead    crm.leads%rowtype;\n  v_veredicto jsonb;\n  v_bloqueo jsonb;\n  v_previo_reab text;\n  v_flag_d13 boolean := " + FLAG + ";\n")
t8 = rep(t8, """  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
""", """  -- F2.b [D-13]: candados de PERSONA antes de la fila (documento -> persona -> lead); inerte con la bandera apagada.
  v_bloqueo := private.bloquear_personas_de_leads(array[p_lead], null);
  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
""")
t8 = rep(t8, """  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;
""", """  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;
  -- F2.b [D-13] (auditor M1 / Codex #6): gemela de rescatar_descartes: el JUICIO único de reapertura con la identidad encendida.
  if v_flag_d13 then
    if not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo) then
      raise exception 'El documento o la persona de este lead cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
    end if;
    v_veredicto := private.juicio_reapertura(v_lead.id, v_lead.telefono, null);
    if v_veredicto->>'estado' = 'no_contactar' then
      raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»' using errcode = 'P0429';
    end if;
    if v_veredicto is not null then
      raise exception 'La persona ya es cliente o ya tiene su lead: no se puede reabrir'
        using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', 'identidad', 'lead_id', v_lead.id)::text;
    end if;
  end if;
""")
t8 = rep(t8, """  begin
    update crm.leads
       set etapa = 'nuevo', motivo_descarte = null
""", GUC_ON + """  begin
    update crm.leads
       set etapa = 'nuevo', motivo_descarte = null
""")
t8 = rep(t8, """  select * into v_lead from crm.leads where id = p_lead;

  return jsonb_build_object(""", GUC_OFF + """  -- F2.b [D-13]: el lead reabierto queda ENLAZADO a su persona (como al nacer), ya bloqueada FOR SHARE.
  if v_flag_d13 and v_lead.inversionista_id is null then
    perform private.enlazar_lead_reabierto(p_lead, private.lead_persona_reabrir(p_lead));
  end if;
  select * into v_lead from crm.leads where id = p_lead;

  return jsonb_build_object(""")

# ── T9 reserva por persona (texto de D-10): también los sueltos por documento ────────────
t9 = rep(prev['crm.reservar_conversion_lead.4'], """    select x into v_otro from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id order by x limit 1;
""", """    -- F2.b [D-13] (Codex #1): también los SUELTOS vivos con un documento vigente de la persona (private.leads_de_personas).
    select x into v_otro from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id order by x limit 1;
""")

new = {'private.verificar_disponibilidad_lead_impl.3': t1, 'private.trg_leads_zz_enlaza_identidad': t2,
       'crm.tomar_lead_libre': t3, 'crm.convertir_lead': t4, 'crm.convertir_lead_externo': t5,
       'crm.marcar_efectos_conversion.3': t6, 'crm.rescatar_descartes': t7, 'private.deshacer_descarte_implementacion': t8,
       'crm.reservar_conversion_lead.4': t9}
H_NEW = {k: md5(v) for k, v in new.items()}
for k in FN: assert H_NEW[k] != prod[k], k

def md5sel(k):
    sch, nm, args, _ = FN[k]
    return f"(select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='{sch}' and p.proname='{nm}' and pg_get_function_identity_arguments(p.oid)='{args}')"
GUARDS = ''.join(f"""  v_h := {md5sel(k)};
  if v_h is null then
    raise exception 'F2.b D-13: falta {FN[k][3]}';
  end if;
  if v_h is distinct from '{prod[k]}' and v_h is distinct from '{H_NEW[k]}' then
    raise exception 'F2.b D-13: {FN[k][3]} no es ni el texto vivo esperado ({"D-10" if k.startswith("crm.reservar") else "producción"}) ni el de D-13 (%)', v_h;
  end if;
""" for k in FN)
GUARD_000 = """  if not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
                   where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_000_hereda_veto' and not t.tgisinternal and t.tgenabled = 'O'
                     and pg_get_triggerdef(t.oid) like '%BEFORE INSERT ON crm.leads%'
                     and strpos(p.prosrc, 'identidad_bloquear_documento') > 0) then
    raise exception 'F2.b D-13: falta la premisa de serialización: trg_leads_000_hereda_veto (BEFORE INSERT, habilitado) tomando private.identidad_bloquear_documento (b1)';
  end if;
"""
GUARD_LDI = f"""  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='leads_de_identidades' and pg_get_function_identity_arguments(p.oid)='p_ids uuid[]') is distinct from '{H_LDI}' then
    raise exception 'F2.b D-13: private.leads_de_identidades(uuid[]) no es el texto vivo de producción (b5)';
  end if;
"""
POST_MD5 = ''.join(f"""  if {md5sel(k)} is distinct from '{H_NEW[k]}' then
    raise exception 'POSTFLIGHT D-13: {FN[k][3]} no quedó byte a byte como la genera gen-d13.py';
  end if;
""" for k in FN)
REV_MD5 = ''.join(f"""  if {md5sel(k)} is distinct from '{prod[k]}' then
    raise exception 'REVERSA D-13: {FN[k][3]} no volvió byte a byte al vivo esperado';
  end if;
""" for k in FN)
PRIV = ['private.verificar_disponibilidad_lead_impl(text,text,uuid)','private.verificar_disponibilidad_lead_impl(text,text)','private.trg_leads_zz_enlaza_identidad()','private.deshacer_descarte_implementacion(uuid)']
RPC  = ['crm.tomar_lead_libre(text,text)','crm.convertir_lead(uuid,uuid)','crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)','crm.marcar_efectos_conversion(uuid,uuid,text)','crm.rescatar_descartes(uuid[],uuid[],boolean)','crm.reservar_conversion_lead(uuid,text,text,jsonb)','crm.fijar_dni_lead_fn(uuid,text)']
RPC_VIVAS = [x for x in RPC if x != 'crm.fijar_dni_lead_fn(uuid,text)']
HELP = ['private.persona_en_conversion(uuid,uuid)','private.leads_de_personas(uuid[])','private.lead_persona_reabrir(uuid)','private.bloquear_personas_de_leads(uuid[],text)','private.lead_dentro_de_bloqueo(uuid,jsonb)','private.juicio_persona(uuid,uuid)','private.juicio_reapertura(uuid,text,text)','private.enlazar_lead_reabierto(uuid,uuid)','private.trg_leads_zz_reapertura_solo_rpc()']
lista = lambda a: "','".join(a)
regs  = lambda a: ",".join(f"'{x}'::regprocedure" for x in a)
GRANTS = f"""  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='verificar_disponibilidad_lead_impl' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text') is distinct from '{prod['private.verificar_disponibilidad_lead_impl']}' then
    raise exception 'D-13: la sobrecarga de 2 argumentos del verificador (solo delega) cambió';
  end if;
  if exists (select 1 from unnest(array['{lista(PRIV)}']) f(firma), unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ({regs(PRIV)}) and a.grantee = 0) then
    raise exception 'D-13: las funciones privadas transformadas no pueden tener EXECUTE para la API ni PUBLIC';
  end if;
  if exists (select 1 from unnest(array['{lista(RPC)}']) f(firma)
              where not has_function_privilege('authenticated', f.firma, 'EXECUTE') or has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ({regs(RPC)}) and a.grantee = 0) then
    raise exception 'D-13: los grants de las RPC transformadas cambiaron (solo authenticated)';
  end if;
"""
HELPER_POST = f"""  if exists (select 1 from unnest(array['{lista(HELP)}']) f(firma) where to_regprocedure(f.firma) is null)
     or exists (select 1 from unnest(array['{lista(HELP)}']) f(firma), unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ({regs(HELP)}) and a.grantee = 0)
     or exists (select 1 from unnest(array['{lista(HELP)}']) f(firma) where not exists (select 1 from pg_proc p where p.oid = f.firma::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'])) then
    raise exception 'POSTFLIGHT D-13: algún helper falta, tiene grants indebidos o perdió definer/search_path';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid='crm.leads'::regclass and tgname='trg_leads_zz_reapertura_solo_rpc' and not tgisinternal and tgenabled='O'
                   and pg_get_triggerdef(oid) = 'CREATE TRIGGER trg_leads_zz_reapertura_solo_rpc BEFORE UPDATE OF etapa, activo ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.trg_leads_zz_reapertura_solo_rpc()') then
    raise exception 'POSTFLIGHT D-13: el trigger de reapertura solo por RPC falta, está deshabilitado o no tiene la definición esperada';
  end if;
"""
FLAG_OFF = lambda tag: f"""  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception '{tag}: la bandera resolver_en_puertas está ENCENDIDA';
  end if;
"""
NAME = '20260905160000_crm_f2b_d13_un_solo_lead_en_todas_las_puertas'
mig = f"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-13] — «UN SOLO LEAD» Y «EL PUENTE
-- MANDA» EN TODAS LAS PUERTAS CON LA BANDERA ENCENDIDA (bloque 2; auditor D-10 M2, Codex D-10 #2/#3/#5, Codex D-13 #1-#9)
-- ============================================================================
--
-- QUE (todo dentro de la rama ON; con la bandera APAGADA las nueve funciones responden como hoy, el trigger es inerte y la puerta del DNI es el UPDATE de hoy):
--   * «Los leads de una persona» = enlace vivo ∪ puente ∪ SUELTOS vivos con un documento vigente de la persona (nacieron
--     antes de que existiera la persona): private.leads_de_personas. Cuenta en el verificador de disponibilidad, el
--     nacimiento del lead, la toma, el rescate, el deshacer, el sellado, las dos conversiones y la reserva por persona (D-10).
--   * Una persona EN CONVERSIÓN (reserva viva o sellada de otro lead) o que YA ES CLIENTE (perfil, activo o no) no recibe otro lead.
--   * Reabrir o tomar un lead lo ENLAZA a su persona (documento o puente), como al nacer; el juicio es único
--     (private.juicio_reapertura) y los candados van ANTES de la fila (documento -> persona -> lead, el orden de la reserva,
--     el sellado y la fusión): private.bloquear_personas_de_leads. Reabrir un descarte con la bandera encendida solo se
--     puede por esas puertas (trigger trg_leads_zz_reapertura_solo_rpc); el UPDATE directo de etapa no.
--   * El sellado de la conversión toma los documentos de la persona, bloquea a la persona, revalida la pareja
--     (lead, claim, persona) bajo el lock de la reserva, el estado del lead y «un solo lead» ANTES del punto de no retorno.
--   * Las conversiones respetan el puente del propio lead; convertir_lead no convierte un lead reservado para otra persona ni
--     mientras la persona tiene otra conversión Avance en curso (como la coop).
--   * El DNI de un lead se FIJA por su puerta (crm.fijar_dni_lead_fn: candado del documento y persona ANTES de la fila,
--     juicio de la persona, enlace si existe); el UPDATE directo de dni queda cerrado con la bandera encendida.
-- Generada desde el texto VIVO (scripts/f2b/gen-d13.py, vivas/d13, huellas-d13-prod.txt): 8 funciones de producción y la
-- reserva por persona tal como la deja D-10 (20260905150000), que por eso es REQUISITO. Guardas md5 EXACTAS, postflight byte
-- a byte, grants comprobados. Ensayo: scripts/oraculo-f2b-d13.sh. Reversa: scripts/rollback-f2b-d13.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.leads_de_identidades(uuid[])') is null
     or to_regprocedure('private.identidad_bloquear_documento(text,text)') is null
     or to_regprocedure('private.identidad_bloquear_documentos_de(uuid[])') is null
     or to_regprocedure('private.inversionista_canonica(uuid)') is null
     or to_regprocedure('private.inversionista_por_documento(text,text)') is null
     or to_regprocedure('private.toma_asienta_y_devuelve(uuid,text,text,text,jsonb)') is null
     or to_regprocedure('private.trg_leads_hereda_veto_persona()') is null then
    raise exception 'F2.b D-13: faltan b1 (20260904120000), b2 (20260904130000) o b5 (20260905120000)';
  end if;
{FLAG_OFF('F2.b D-13')}{GUARD_000}{GUARD_LDI}{GUARDS}end
$guard$;

{HELPERS}
-- ============================================================================
-- 1. Verificador de disponibilidad (3 args)
-- ============================================================================
{t1}
;

-- ============================================================================
-- 2. Trigger de nacimiento del lead
-- ============================================================================
{t2}
;

-- ============================================================================
-- 3. tomar_lead_libre: candados antes de la fila, juicio único, enlace al tomar
-- ============================================================================
{t3}
;

-- ============================================================================
-- 4. Conversiones: puente del propio lead, sueltos por documento, reserva ajena
-- ============================================================================
{t4}
;

{t5}
;

-- ============================================================================
-- 5. Sellado de la conversión: documentos -> persona; pareja, estado del lead y «un solo lead» antes del punto de no retorno
-- ============================================================================
{t6}
;

-- ============================================================================
-- 6. Reactivaciones (rescate de supervisión y deshacer descarte)
-- ============================================================================
{t7}
;

{t8}
;

-- ============================================================================
-- 7. Reserva por persona (texto de D-10): también los sueltos por documento
-- ============================================================================
{t9}
;

do $post$
begin
{POST_MD5}{GRANTS}{HELPER_POST}{GUARD_000}{FLAG_OFF('POSTFLIGHT D-13')}  raise notice 'F2.b D-13 OK: un solo lead (enlace ∪ puente ∪ sueltos por documento) y persona en conversión en todas las puertas; reabrir/tomar enlaza y solo por RPC; el sellado revalida (rama ON). Bandera APAGADA.';
end
$post$;
commit;
"""
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')

rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-13] (20260905160000): restaura las 9 funciones byte a byte (8 de prod + la reserva de D-10), suelta el
-- trigger y los 7 helpers y desregistra la versión. Se NIEGA si la bandera está encendida (y lo re-comprueba antes del commit).
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));
do $guard$
declare v_h text;
begin
{FLAG_OFF('REVERSA D-13')}{GUARDS}end
$guard$;

drop trigger if exists trg_leads_zz_reapertura_solo_rpc on crm.leads;

""" + "\n;\n\n".join(prev[k] for k in ['private.verificar_disponibilidad_lead_impl.3','private.trg_leads_zz_enlaza_identidad','crm.tomar_lead_libre','crm.convertir_lead','crm.convertir_lead_externo','crm.marcar_efectos_conversion.3','crm.rescatar_descartes','private.deshacer_descarte_implementacion','crm.reservar_conversion_lead.4']) + f"""
;

drop function if exists private.trg_leads_zz_reapertura_solo_rpc();
drop function if exists crm.fijar_dni_lead_fn(uuid, text);
drop function if exists private.enlazar_lead_reabierto(uuid, uuid);
drop function if exists private.juicio_reapertura(uuid, text, text);
drop function if exists private.juicio_persona(uuid, uuid);
drop function if exists private.lead_dentro_de_bloqueo(uuid, jsonb);
drop function if exists private.bloquear_personas_de_leads(uuid[], text);
drop function if exists private.lead_persona_reabrir(uuid);
drop function if exists private.leads_de_personas(uuid[]);
drop function if exists private.persona_en_conversion(uuid, uuid);

do $post$
begin
{REV_MD5}{GRANTS.replace(lista(RPC), lista(RPC_VIVAS)).replace(regs(RPC), regs(RPC_VIVAS))}  if exists (select 1 from unnest(array['{lista(HELP)}']) f(firma) where to_regprocedure(f.firma) is not null)
     or to_regprocedure('crm.fijar_dni_lead_fn(uuid,text)') is not null
     or exists (select 1 from pg_trigger where tgrelid='crm.leads'::regclass and tgname='trg_leads_zz_reapertura_solo_rpc') then
    raise exception 'REVERSA D-13: quedó algún helper, la puerta del DNI o el trigger';
  end if;
{FLAG_OFF('REVERSA D-13 (al confirmar)')}  delete from supabase_migrations.schema_migrations where version = '20260905160000';
  raise notice 'REVERSA F2.b D-13 OK (versión 20260905160000 desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-d13.sql').write_text(rb, encoding='utf-8')
H_MIG = hashlib.md5(mig.encode('utf-8')).hexdigest()
reg_checks = ''.join(f"""  if {md5sel(k)} is distinct from '{H_NEW[k]}' then
    raise exception 'REGISTRO D-13: {FN[k][3]} VIVA no es el texto de D-13 (aplica la migración ANTES de registrar)';
  end if;
""" for k in FN)
# Codex v4.3 [5]: el registrador también exige los objetos NUEVOS de D-13 vivos y con su forma (definer + search_path vacío),
# y el trigger de reapertura montado; si alguien los cambió después de aplicar, no se registra.
reg_checks += ''.join(f"""  if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('{h}') and p.prosecdef and coalesce(p.proconfig, '{{}}'::text[]) @> array['search_path=""']) then
    raise exception 'REGISTRO D-13: falta o cambió {h} (definer + search_path vacío)';
  end if;
""" for h in HELP + ['crm.fijar_dni_lead_fn(uuid,text)'])
reg_checks += """  if not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'crm' and c.relname = 'leads' and t.tgname = 'trg_leads_zz_reapertura_solo_rpc' and t.tgenabled <> 'D') then
    raise exception 'REGISTRO D-13: falta el trigger trg_leads_zz_reapertura_solo_rpc';
  end if;
"""
reg = ("-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-13]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.\n"
       "-- Mismo advisory que la ida y la reversa. Se niega si alguna de las 9 funciones vivas no es la de D-13, si la bandera está encendida\n"
       "-- o si la versión está registrada con OTRO contenido.\n"
       f"begin;\nselect pg_advisory_xact_lock(hashtext('{ADV}'));\ndo $chk$\nbegin\n" + reg_checks + FLAG_OFF('REGISTRO D-13') +
       "  if exists (select 1 from supabase_migrations.schema_migrations where version='20260905160000' and md5(statements[1]) <> '" + H_MIG + "') then\n"
       "    raise exception 'REGISTRO D-13: la versión 20260905160000 ya está registrada con otro contenido';\n  end if;\nend\n$chk$;\n"
       "insert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('20260905160000', 'crm_f2b_d13_un_solo_lead_en_todas_las_puertas', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n")
(W/'scripts'/'registrar-f2b-d13.sql').write_text(reg, encoding='utf-8')
print('D-13 v3 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; md5 migración', H_MIG)
for k in FN: print(' ', k, prod[k][:8], '->', H_NEW[k][:8])

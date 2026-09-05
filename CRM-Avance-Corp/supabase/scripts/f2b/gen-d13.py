# gen-d13.py — F2.b prerrequisito de activación [D-13]: «un solo lead» y «el puente manda» en TODAS las puertas
# con la bandera encendida (bloque 2). v1 (05/09). Transforma 5 funciones VIVAS de producción (vivas/d13/*.sql,
# md5 en huellas-d13-prod.txt) y crea el helper private.persona_en_conversion. Genera la migración 20260905160000,
# su reversa (restaura byte a byte, suelta el helper, desregistra) y el registro (exige las 5 vivas = D-13).
# Uso: python3 gen-d13.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
viv = lambda n: (S/'vivas'/'d13'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:90], s.count(old)); return s.replace(old, new)
md5 = lambda t: hashlib.md5((t + '\n').encode('utf-8')).hexdigest()
prod = {l.split()[0]: l.split()[1] for l in (S/'huellas-d13-prod.txt').read_text().splitlines() if l.strip()}
H_LDI = '2421b2b78b02b8e93fd01598e2f54128'   # private.leads_de_identidades(uuid[]) en PROD (b5) = banco
FN = {  # clave -> (schema, nombre, args identidad, etiqueta)
  'private.verificar_disponibilidad_lead_impl.3': ('private','verificar_disponibilidad_lead_impl','p_telefono text, p_dni text, p_excluir_lead_id uuid','private.verificar_disponibilidad_lead_impl(text,text,uuid)'),
  'private.trg_leads_zz_enlaza_identidad': ('private','trg_leads_zz_enlaza_identidad','','private.trg_leads_zz_enlaza_identidad()'),
  'crm.tomar_lead_libre': ('crm','tomar_lead_libre','p_telefono text, p_dni text','crm.tomar_lead_libre(text,text)'),
  'crm.convertir_lead': ('crm','convertir_lead','p_lead_id uuid, p_perfil_id uuid','crm.convertir_lead(uuid,uuid)'),
  'crm.convertir_lead_externo': ('crm','convertir_lead_externo','p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text','crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'),
}
prev = {k: viv(k) for k in FN}
for k in FN: assert md5(prev[k]) == prod[k], (k, md5(prev[k]))
assert md5(viv('private.verificar_disponibilidad_lead_impl')) == prod['private.verificar_disponibilidad_lead_impl']

HELPER = r"""-- ============================================================================
-- 0. Helper: ¿la persona está EN CONVERSIÓN? (reserva por persona viva o sellada de un lead aún no convertido;
--    mismo predicado que private.fusion_bloqueos, b5). Los claims no cuentan: un claim abandonado sin reserva
--    lo retoma Gerencia y no debe bloquear a la persona para siempre.
-- ============================================================================
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
comment on function private.persona_en_conversion(uuid, uuid) is
  'F2.b [D-13]: persona con reserva de conversión por persona viva o sellada (lead aún no convertido), excluido un lead. Solo la llaman las puertas definer.';
"""

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
""", """    -- F2.b [D-13]: «los leads de una persona» = enlace vivo ∪ PUENTE (private.leads_de_identidades, b5: incluye
    -- históricos y soft-borrados, como ya contaba el join sin filtro de activo), y una persona EN CONVERSIÓN
    -- (reserva por persona viva o sellada de OTRO lead, private.persona_en_conversion) ya está naciendo como
    -- cliente: tampoco se le abre otro lead. `asesor` = responsable de relación, o quien reservó, o el centinela
    -- de siempre. Contrato del front intacto (mismas claves, mismo `via`).
    select coalesce(resp.nombre_completo, res.nombre_completo, 'sin asesor asignado')
      into v_asesor_identidad
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    left join public.perfiles resp on resp.id = i.responsable_relacion_id
    left join lateral (
      select p.nombre_completo
      from crm.conversion_reservas r
      join public.perfiles p on p.id = r.reservado_por
      where r.inversionista_id = i.id and r.lead_id is distinct from p_excluir_lead_id
      order by r.reservado_en desc
      limit 1
    ) res on true
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = v_dni_norm
      and idf.estado = 'vigente'
      and idf.verificado = true
      and i.estado <> 'fusionado'
      and (exists (select 1 from private.leads_de_identidades(array[i.id]) x where x is distinct from p_excluir_lead_id)
           or private.persona_en_conversion(i.id, p_excluir_lead_id))
    limit 1;
""")

# ── T2 trigger de nacimiento (rama INSERT) ───────────────────────────────────────────────
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
""", """  -- Un solo lead TOTAL por persona (invariante #6): vivos, convertidos y descartados.
  -- F2.b [D-13]: enlace vivo ∪ PUENTE (private.leads_de_identidades, b5; el enlace vivo primero en el detalle)
  -- y persona EN CONVERSIÓN (reserva por persona viva o sellada de otro lead). Serializado con la reserva por el
  -- candado documental que ya tomó el trigger 000 (inv_resolver:DNI:<doc>, la misma clave que toma la reserva).
  select x as id, coalesce(resp.nombre_completo, 'sin asesor asignado') as asesor
    into v_otro
  from private.leads_de_identidades(array[v_inv]) x
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
  if private.persona_en_conversion(v_inv, new.id) then
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente',
              'asesor', coalesce((select p.nombre_completo
                                    from crm.conversion_reservas r
                                    join public.perfiles p on p.id = r.reservado_por
                                   where r.inversionista_id = v_inv and r.lead_id is distinct from new.id
                                   order by r.reservado_en desc limit 1), 'sin asesor asignado'),
              'via', 'identidad')::text;
  end if;
""")

# ── T3 tomar_lead_libre ─────────────────────────────────────────────────────────────────
t3 = rep(prev['crm.tomar_lead_libre'], "  v_dni text := nullif(pg_catalog.btrim(p_dni), '');\n",
         "  v_dni text := nullif(pg_catalog.btrim(p_dni), '');\n  v_veredicto_identidad jsonb;\n")
t3 = rep(t3, """     or not private.es_destino_crm_activo(v_actor, array['vendedor']::text[]) then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- Si OTRO lead vivo del mismo contacto tiene DUEÑO, el contacto está tomado
""", """     or not private.es_destino_crm_activo(v_actor, array['vendedor']::text[]) then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- F2.b [D-13]: con la identidad encendida, si el documento (el tecleado o el del blanco) resuelve a una
  -- persona que ya tiene OTRO lead (enlace vivo o puente) o está en conversión, no se toma: manda el veredicto
  -- fresco (solo lecturas bajo el lock del blanco; el blanco queda excluido del juicio).
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and coalesce(v_dni, v_lead.dni) is not null then
    v_veredicto_identidad := private.verificar_disponibilidad_lead_impl(v_tel, coalesce(v_dni, v_lead.dni), v_lead.id);
    if v_veredicto_identidad->>'via' = 'identidad' then
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni, v_veredicto_identidad);
    end if;
  end if;

  -- Si OTRO lead vivo del mismo contacto tiene DUEÑO, el contacto está tomado
""")

# ── T4/T5 conversiones: el puente del propio lead manda ─────────────────────────────────
def puente(s, que):
    return rep(s, f"""  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento {que}: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
""", f"""  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento {que}: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex D-10 #2): el PUENTE del propio lead también manda (por la canónica), como en la reserva
  -- por persona (D-10): un lead que solo está en el puente pertenece a la persona de su puente.
  if v_flag and v_inv is not null
     and exists (select 1 from crm.inversionista_leads il
                  where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento {que}: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
""")
t4 = puente(prev['crm.convertir_lead'], 'del cliente')
t5 = puente(prev['crm.convertir_lead_externo'], 'del cierre')

new = {'private.verificar_disponibilidad_lead_impl.3': t1, 'private.trg_leads_zz_enlaza_identidad': t2,
       'crm.tomar_lead_libre': t3, 'crm.convertir_lead': t4, 'crm.convertir_lead_externo': t5}
H_NEW = {k: md5(v) for k, v in new.items()}
for k in FN: assert H_NEW[k] != prod[k]

def md5sel(k):
    sch, nm, args, _ = FN[k]
    return f"(select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='{sch}' and p.proname='{nm}' and pg_get_function_identity_arguments(p.oid)='{args}')"
GUARDS = ''.join(f"""  v_h := {md5sel(k)};
  if v_h is null then
    raise exception 'F2.b D-13: falta {FN[k][3]}';
  end if;
  if v_h is distinct from '{prod[k]}' and v_h is distinct from '{H_NEW[k]}' then
    raise exception 'F2.b D-13: {FN[k][3]} no es ni el texto vivo de producción ni el de D-13 (%)', v_h;
  end if;
""" for k in FN)
GUARD_LDI = f"""  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='leads_de_identidades' and pg_get_function_identity_arguments(p.oid)='p_ids uuid[]') is distinct from '{H_LDI}' then
    raise exception 'F2.b D-13: private.leads_de_identidades(uuid[]) no es el texto vivo de producción (b5)';
  end if;
"""
POST_MD5 = ''.join(f"""  if {md5sel(k)} is distinct from '{H_NEW[k]}' then
    raise exception 'POSTFLIGHT D-13: {FN[k][3]} no quedó byte a byte como la genera gen-d13.py';
  end if;
""" for k in FN)
REV_MD5 = ''.join(f"""  if {md5sel(k)} is distinct from '{prod[k]}' then
    raise exception 'REVERSA D-13: {FN[k][3]} no volvió byte a byte al vivo de producción';
  end if;
""" for k in FN)
GRANTS = f"""  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='verificar_disponibilidad_lead_impl' and pg_get_function_identity_arguments(p.oid)='p_telefono text, p_dni text') is distinct from '{prod['private.verificar_disponibilidad_lead_impl']}' then
    raise exception 'D-13: la sobrecarga de 2 argumentos del verificador (solo delega) cambió';
  end if;
  if exists (select 1 from unnest(array['private.verificar_disponibilidad_lead_impl(text,text,uuid)','private.verificar_disponibilidad_lead_impl(text,text)','private.trg_leads_zz_enlaza_identidad()']) f(firma), unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('private.verificar_disponibilidad_lead_impl(text,text,uuid)'::regprocedure,'private.verificar_disponibilidad_lead_impl(text,text)'::regprocedure,'private.trg_leads_zz_enlaza_identidad()'::regprocedure) and a.grantee = 0) then
    raise exception 'D-13: las funciones privadas del verificador/trigger no pueden tener EXECUTE para la API ni PUBLIC';
  end if;
  if exists (select 1 from unnest(array['crm.tomar_lead_libre(text,text)','crm.convertir_lead(uuid,uuid)','crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)']) f(firma)
              where not has_function_privilege('authenticated', f.firma, 'EXECUTE') or has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('crm.tomar_lead_libre(text,text)'::regprocedure,'crm.convertir_lead(uuid,uuid)'::regprocedure,'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)'::regprocedure) and a.grantee = 0) then
    raise exception 'D-13: los grants de tomar_lead_libre / convertir_lead / convertir_lead_externo cambiaron (solo authenticated)';
  end if;
"""
HELPER_POST = """  if to_regprocedure('private.persona_en_conversion(uuid,uuid)') is null
     or exists (select 1 from unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, 'private.persona_en_conversion(uuid,uuid)', 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'private.persona_en_conversion(uuid,uuid)'::regprocedure and a.grantee = 0)
     or not exists (select 1 from pg_proc p where p.oid = 'private.persona_en_conversion(uuid,uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT D-13: el helper persona_en_conversion falta, tiene grants indebidos o perdió definer/search_path';
  end if;
"""
FLAG_OFF = lambda tag: f"""  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception '{tag}: la bandera resolver_en_puertas está ENCENDIDA';
  end if;
"""
NAME = '20260905160000_crm_f2b_d13_un_solo_lead_en_todas_las_puertas'
mig = f"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-13] — «UN SOLO LEAD» Y «EL PUENTE
-- MANDA» EN TODAS LAS PUERTAS CON LA BANDERA ENCENDIDA (bloque 2; auditor D-10 M2, Codex D-10 #2/#3/#5)
-- ============================================================================
--
-- QUE (todo dentro de la rama ON; con la bandera APAGADA las cinco funciones responden como hoy):
--   * private.verificar_disponibilidad_lead_impl(tel, dni, excluir): la persona del DNI «ya es cliente» (via identidad)
--     si tiene OTRO lead por enlace vivo o por PUENTE (private.leads_de_identidades, b5) o si está EN CONVERSIÓN
--     (reserva por persona viva o sellada de otro lead, helper nuevo private.persona_en_conversion). `asesor` =
--     responsable de relación, o quien reservó, o 'sin asesor asignado'. Contrato del front intacto.
--   * private.trg_leads_zz_enlaza_identidad (INSERT): mismo conjunto → P0481 con el detalle de hoy. Serializado con la
--     reserva por el candado documental (inv_resolver:DNI:<doc>) que toma el trigger 000 antes: la carrera de la saga
--     (reserva → sellado → Auth → perfil → cerrar) ya no deja cuentas de portal huérfanas por un lead nacido en medio.
--   * crm.tomar_lead_libre: tras el lock del blanco y la membresía, si el documento (tecleado o del blanco) resuelve
--     a una persona con otro lead o en conversión → devuelve el veredicto fresco sin tomar (Codex D-10 #5).
--   * crm.convertir_lead y crm.convertir_lead_externo: «el puente del propio lead manda» (por la canónica), como ya
--     hace la reserva por persona desde D-10 (Codex D-10 #2).
-- Generada desde el texto VIVO de producción (scripts/f2b/gen-d13.py, vivas/d13, huellas-d13-prod.txt): guardas
-- md5 EXACTAS, postflight byte a byte, grants comprobados. Independiente de D-10 (no comparten función).
-- Ensayo: scripts/oraculo-f2b-d13.sh. Reversa: scripts/rollback-f2b-d13.sql (restaura, suelta el helper, desregistra).

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d13_un_solo_lead_todas_las_puertas'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.leads_de_identidades(uuid[])') is null
     or to_regprocedure('private.inversionista_canonica(uuid)') is null
     or to_regprocedure('private.toma_asienta_y_devuelve(uuid,text,text,text,jsonb)') is null
     or to_regprocedure('private.trg_leads_hereda_veto_persona()') is null then
    raise exception 'F2.b D-13: faltan b2 (20260904130000) o b5 (20260905120000)';
  end if;
{FLAG_OFF('F2.b D-13')}{GUARD_LDI}{GUARDS}end
$guard$;

{HELPER}
-- ============================================================================
-- 1. Verificador de disponibilidad (3 args): enlace vivo ∪ puente, y persona en conversión
-- ============================================================================
{t1}
;

-- ============================================================================
-- 2. Trigger de nacimiento del lead (INSERT): mismo conjunto → P0481
-- ============================================================================
{t2}
;

-- ============================================================================
-- 3. tomar_lead_libre: el veredicto de identidad manda antes de tomar
-- ============================================================================
{t3}
;

-- ============================================================================
-- 4. Conversiones: el puente del propio lead manda
-- ============================================================================
{t4}
;

{t5}
;

do $post$
begin
{POST_MD5}{GRANTS}{HELPER_POST}{FLAG_OFF('POSTFLIGHT D-13')}  raise notice 'F2.b D-13 OK: un solo lead (enlace vivo ∪ puente) y persona en conversión en el verificador, el nacimiento del lead y la toma; el puente del propio lead manda en las conversiones (rama ON). Bandera APAGADA.';
end
$post$;
commit;
"""
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')

rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-13] (20260905160000): restaura las 5 funciones byte a byte (md5 de prod), suelta el helper
-- y desregistra la versión. Se NIEGA si la bandera está encendida (y lo re-comprueba antes del commit). Repetible.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d13_un_solo_lead_todas_las_puertas'));
do $guard$
declare v_h text;
begin
{FLAG_OFF('REVERSA D-13')}{GUARDS}end
$guard$;

{prev['private.verificar_disponibilidad_lead_impl.3']}
;

{prev['private.trg_leads_zz_enlaza_identidad']}
;

{prev['crm.tomar_lead_libre']}
;

{prev['crm.convertir_lead']}
;

{prev['crm.convertir_lead_externo']}
;

drop function if exists private.persona_en_conversion(uuid, uuid);

do $post$
begin
{REV_MD5}{GRANTS}  if to_regprocedure('private.persona_en_conversion(uuid,uuid)') is not null then
    raise exception 'REVERSA D-13: quedó el helper';
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
reg = ("-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-13]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.\n"
       "-- Se niega si alguna de las 5 funciones vivas no es la de D-13, si la bandera está encendida o si la versión está registrada con OTRO contenido.\n"
       "begin;\ndo $chk$\nbegin\n" + reg_checks + FLAG_OFF('REGISTRO D-13') +
       "  if exists (select 1 from supabase_migrations.schema_migrations where version='20260905160000' and md5(statements[1]) <> '" + H_MIG + "') then\n"
       "    raise exception 'REGISTRO D-13: la versión 20260905160000 ya está registrada con otro contenido';\n  end if;\nend\n$chk$;\n"
       "insert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('20260905160000', 'crm_f2b_d13_un_solo_lead_en_todas_las_puertas', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n")
(W/'scripts'/'registrar-f2b-d13.sql').write_text(reg, encoding='utf-8')
print('D-13 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; md5 migración', H_MIG)
for k in FN: print(' ', k, prod[k][:8], '->', H_NEW[k][:8])

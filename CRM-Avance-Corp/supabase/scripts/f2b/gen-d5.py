# gen-d5.py — F2.b prerrequisito de activación [D-5] (bloque 4): con la identidad unificada ENCENDIDA se cierran las dos
# RPC de UN argumento de la conversión Avance (reserva por lead y sellado sin persona; b4 M3 / Codex #8) y Gerencia gana
# una herramienta para ABANDONAR una conversión sellada que nunca creó la cuenta (Codex E2 #12: la persona quedaba «en
# conversión» para siempre). Genera la migración 20260906140000, su reversa y el registro TRANSFORMANDO el texto VIVO de
# producción (vivas/d5/*.sql, md5 en huellas-d5-prod.txt). Uso: python3 gen-d5.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib, re
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
md5s = lambda s: hashlib.md5(s.encode('utf-8')).hexdigest()
VER = '20260906140000'; NAME = f'{VER}_crm_f2b_d5_rpc_de_un_argumento_cerradas_con_on'; ADV = 'crm_f2b_d5_rpc_un_argumento_cerradas_con_on'
viv = lambda n: (S/'vivas'/'d5'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:80], s.count(old)); return s.replace(old, new)
H = {l.split()[0]: l.split()[1] for l in (S/'huellas-d5-prod.txt').read_text().splitlines() if l.strip() and not l.startswith('#')}
def body(fn_text):
    m = re.search(r'AS \$function\$(.*)\$function\$$', fn_text, re.S); assert m; return m.group(1)
AUTH = """  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
"""
def guard(que, pista):
    return AUTH + f"""  -- F2.b [D-5] (b4 M3, Codex #8): con la identidad unificada ENCENDIDA la conversión Avance reserva y sella POR PERSONA
  -- (sobrecargas de b4: reserva con documento + datos, sellado con claim + token, saga de Auth vigilada). Esta firma de UN
  -- argumento —{que}— queda SOLO para la bandera apagada: encendida, se cierra, para que ningún cliente
  -- viejo del edge abra una conversión que la saga no vigila (la cuenta de portal huérfana que b4 vino a impedir).
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Con la identidad unificada encendida, la conversión a cliente va por persona (documento y datos): actualiza el CRM y vuelve a intentarlo'
      using errcode = 'P0409', hint = '{pista}';
  end if;
"""
# ── 1. reserva por lead (1 arg) ─────────────────────────────────────────────────────────────────────────────────────
r_prev = viv('reservar_conversion_lead_1arg'); assert md5s(r_prev + '\n') == H['crm.reservar_conversion_lead.1']
r = rep(r_prev, AUTH, guard('la reserva por lead, sin persona', 'crm.reservar_conversion_lead(p_lead_id, p_tipo_documento, p_documento, p_payload)'))
# ── 2. sellado sin persona (1 arg): cerrado con ON salvo cuando lo llama el sellado POR PERSONA (3 args, b4) ─────────
# El sellado por persona (marcar_efectos_conversion(lead, claim, token), texto de D-13) valida claim, token, veto, pareja
# y «un solo lead» y DELEGA en la firma de un argumento para escribir efectos_iniciados_en. Por eso la guarda de la firma
# vieja deja pasar SOLO ese paso, marcado con un GUC transaccional que fija el sellado por persona (mismo patrón que
# crm.reapertura_identidad / crm.dni_por_puerta en D-13): una llamada directa a la firma vieja con la bandera encendida se cierra.
m_prev = viv('marcar_efectos_conversion_1arg'); assert md5s(m_prev + '\n') == H['crm.marcar_efectos_conversion.1']
GUARD_M = AUTH + """  -- F2.b [D-5] (b4 M3, Codex #8): con la identidad unificada ENCENDIDA la conversión Avance sella POR PERSONA (claim + token,
  -- crm.marcar_efectos_conversion(lead, claim, token), que valida y luego DELEGA aquí bajo la marca crm.sellado_por_persona).
  -- Esta firma de UN argumento —el sellado sin claim ni token— queda SOLO para la bandera apagada y para ese paso: una
  -- llamada directa con la bandera encendida se cierra, para que ningún cliente viejo del edge selle una conversión que la
  -- saga no vigila (la cuenta de portal huérfana que b4 vino a impedir).
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and coalesce(pg_catalog.current_setting('crm.sellado_por_persona', true), 'off') <> 'on' then
    raise exception 'Con la identidad unificada encendida, la conversión a cliente va por persona (documento y datos): actualiza el CRM y vuelve a intentarlo'
      using errcode = 'P0409', hint = 'crm.marcar_efectos_conversion(p_lead_id, p_claim_id, p_token)';
  end if;
"""
m = rep(m_prev, AUTH, GUARD_M)
m3_prev = viv('marcar_efectos_conversion_3arg'); assert md5s(m3_prev + '\n') == H['crm.marcar_efectos_conversion.3']
m3 = rep(m3_prev, "declare v_loc record;", "declare v_loc record; v_previo_d5 text; v_res_d5 jsonb;")
m3 = rep(m3, """  return crm.marcar_efectos_conversion(p_lead_id);
end;""", """  -- F2.b [D-5]: la firma de un argumento queda cerrada con la identidad encendida salvo para ESTE paso (b4 M3): aquí ya se
  -- validaron claim, token, veto, pareja y «un solo lead». La marca es transaccional y se restaura al salir.
  v_previo_d5 := coalesce(pg_catalog.current_setting('crm.sellado_por_persona', true), 'off');
  perform pg_catalog.set_config('crm.sellado_por_persona', 'on', true);
  v_res_d5 := crm.marcar_efectos_conversion(p_lead_id);
  perform pg_catalog.set_config('crm.sellado_por_persona', v_previo_d5, true);
  return v_res_d5;
end;""")
HB = {'r': md5s(body(r)), 'm': md5s(body(m)), 'm3': md5s(body(m3)), 'r0': md5s(body(r_prev)), 'm0': md5s(body(m_prev)), 'm30': md5s(body(m3_prev))}
assert HB['r'] != HB['r0'] and HB['m'] != HB['m0'] and HB['m3'] != HB['m30']
# ── 3. la herramienta de Gerencia: abandonar una conversión sellada que nunca creó la cuenta ───────────────────────
ABANDONAR_BODY = """
declare
  v_uid    uuid := (select auth.uid());
  v_inv    uuid;
  v_r      crm.conversion_reservas%rowtype;
  v_lead   crm.leads%rowtype;
  v_est    jsonb;
  v_clave  text;
  v_motivo text := nullif(pg_catalog.btrim(p_motivo), '');
  v_previo text;
begin
  -- F2.b [D-5] (Codex E2 #12): una reserva SELLADA (punto de no retorno) cuyo edge murió ANTES de crear la cuenta de Auth
  -- deja a la persona «en conversión» para siempre (persona_en_conversion: sellada y sin convertir): nadie puede darle un
  -- lead, tomarla, reabrirla ni convertirla. Gerencia la ABANDONA con motivo: solo si NADA externo existe (claim en
  -- `reclamado`: sin cuenta de acceso ni ficha) y la ejecución ya no está viva (reserva o lease vencidos): se borran la
  -- reserva y el claim (bitácora en audit_log por sus triggers) y queda una nota en el lead. Con cuenta o ficha creadas
  -- el camino es RETOMAR (crm.retomar_conversion_gerencia_fn); consumada (perfil enlazado) no hay nada que abandonar.
  -- Orden de candados, el de retomar: persona → reserva → lead → claim.
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia abandona una conversión' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if p_lead_id is null then
    raise exception 'El lead es obligatorio' using errcode = '22023';
  end if;
  if v_motivo is null or pg_catalog.length(v_motivo) < 5 or pg_catalog.length(v_motivo) > 300 then
    raise exception 'El motivo es obligatorio (entre 5 y 300 caracteres)' using errcode = '22023';
  end if;
  select r.inversionista_id into v_inv from crm.conversion_reservas r where r.lead_id = p_lead_id;
  if v_inv is null then
    raise exception 'Este lead no tiene una reserva por persona' using errcode = 'P0002';
  end if;
  perform 1 from crm.inversionistas i where i.id = v_inv for update;
  select * into v_r from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if v_r.efectos_iniciados_en is null then
    raise exception 'La reserva no está sellada: caduca sola a los pocos minutos, no hay nada que abandonar' using errcode = 'P0409';
  end if;
  select * into v_lead from crm.leads l where l.id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;
  if v_lead.etapa = 'convertido' then
    raise exception 'El lead ya está convertido: la conversión se consumó, no se abandona' using errcode = 'P0409';
  end if;
  v_clave := 'auth_persona:' || v_inv::text;
  select i.resultado into v_est from crm.multiempresa_idempotencia i where i.clave = v_clave for update;
  if v_est is not null then
    if (v_est->>'lead_id')::uuid is distinct from p_lead_id or v_r.claim_id is distinct from (v_est->>'claim_id')::uuid then
      raise exception 'La reserva y el claim de esta persona no corresponden a este lead' using errcode = 'P0409';
    end if;
    if v_est->>'estado' = 'enlazado' then
      raise exception 'La conversión ya se consumó (ficha enlazada): no se abandona' using errcode = 'P0409';
    end if;
    if v_est->>'estado' in ('auth_creado', 'perfil_creado') then
      raise exception 'Ya existe la cuenta de acceso (o la ficha) de esta persona: retoma la conversión en vez de abandonarla'
        using errcode = 'P0409', hint = 'crm.retomar_conversion_gerencia_fn(p_lead_id)';
    end if;
    if v_est->>'estado' <> 'reclamado' then
      raise exception 'Estado de saga desconocido (%): revisar antes de abandonar', v_est->>'estado' using errcode = 'P0409';
    end if;
  end if;
  -- Nunca expulsa a una ejecución viva (Codex E2 #10): solo pasado el tope de la reserva o vencido el lease del claim.
  if v_r.vence_absoluto_en > pg_catalog.now() and (v_est is null or (v_est->>'lease_hasta')::timestamptz > pg_catalog.now()) then
    raise exception 'La conversión sigue viva (reserva y claim vigentes): espera a que venza antes de abandonarla' using errcode = 'P0409';
  end if;
  delete from crm.multiempresa_idempotencia where clave = v_clave;
  delete from crm.conversion_reservas where lead_id = p_lead_id;
  -- Nota administrativa en el lead (no es contacto: entra aunque la persona esté vetada, bajo la válvula como las RPC de veto).
  if v_lead.activo then
    v_previo := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off');
    perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (p_lead_id, 'nota', 'Conversión abandonada por Gerencia: ' || v_motivo,
            pg_catalog.jsonb_build_object('evento', 'conversion_abandonada', 'inversionista_id', v_inv, 'claim_id', v_r.claim_id,
              'estado_previo', coalesce(v_est->>'estado', 'sin_claim'), 'reservado_por', v_r.reservado_por,
              'sellada_en', v_r.efectos_iniciados_en, 'motivo', v_motivo),
            v_uid);
    perform pg_catalog.set_config('crm.op_privilegiada', v_previo, true);
  end if;
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'inversionista_id', v_inv, 'claim_id', v_r.claim_id,
    'estado_previo', coalesce(v_est->>'estado', 'sin_claim'), 'abandonada_por', v_uid, 'abandonada_en', pg_catalog.now());
end;
"""
HB['a'] = md5s(ABANDONAR_BODY)
FA = 'crm.abandonar_conversion_gerencia_fn(uuid,text)'
CREA_A = f"""create or replace function crm.abandonar_conversion_gerencia_fn(p_lead_id uuid, p_motivo text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '5s'
as $function${ABANDONAR_BODY}$function$;
revoke all on function {FA} from public, anon, service_role;
grant execute on function {FA} to authenticated;
comment on function {FA} is 'F2.b [D-5]: Gerencia abandona (con motivo) una conversión Avance SELLADA que nunca creó la cuenta (claim en reclamado, ejecución vencida): borra reserva y claim, deja nota en el lead y libera a la persona. Con cuenta o ficha creadas: retomar_conversion_gerencia_fn. Solo con la identidad encendida.';
"""
GUARD = f"""  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'F2.b D-5: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.reservar_conversion_lead(uuid)')) not in ('{HB['r0']}', '{HB['r']}') then
    raise exception 'F2.b D-5: crm.reservar_conversion_lead(uuid) no es ni el texto vivo de producción ({HB['r0'][:8]}…) ni el de D-5';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.marcar_efectos_conversion(uuid)')) not in ('{HB['m0']}', '{HB['m']}') then
    raise exception 'F2.b D-5: crm.marcar_efectos_conversion(uuid) no es ni el texto vivo de producción ({HB['m0'][:8]}…) ni el de D-5';
  end if;
  if to_regprocedure('crm.reservar_conversion_lead(uuid,text,text,jsonb)') is null or to_regprocedure('crm.marcar_efectos_conversion(uuid,uuid,text)') is null then
    raise exception 'F2.b D-5: faltan las sobrecargas por persona de b4 (reserva de 4 argumentos / sellado de 3)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.marcar_efectos_conversion(uuid,uuid,text)')) not in ('{HB['m30']}', '{HB['m3']}') then
    raise exception 'F2.b D-5: crm.marcar_efectos_conversion(uuid,uuid,text) no es ni el texto vivo de producción (D-13, {HB['m30'][:8]}…) ni el de D-5';
  end if;
""" + ''.join(f"""  if to_regprocedure('{k}') is null or left(md5(pg_get_functiondef('{k}'::regprocedure)), 8) <> '{v}' then
    raise exception 'F2.b D-5: {k} falta o no es el texto vivo de producción (esperado {v}…)';
  end if;
""" for k, v in H.items() if not k[-2:] in ('.1', '.3')) + """  if not exists (select 1 from information_schema.columns where table_schema='crm' and table_name='conversion_reservas' and column_name in ('inversionista_id','claim_id','efectos_iniciados_en','vence_absoluto_en') having count(*) = 4)
     or to_regclass('crm.multiempresa_idempotencia') is null then
    raise exception 'F2.b D-5: crm.conversion_reservas no tiene las columnas de b4 o falta crm.multiempresa_idempotencia';
  end if;
"""
def post(tag):
    return f"""  if not exists (select 1 from pg_proc p where p.oid = 'crm.reservar_conversion_lead(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '{HB['r']}') then
    raise exception '{tag} D-5: crm.reservar_conversion_lead(uuid) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.marcar_efectos_conversion(uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '{HB['m']}') then
    raise exception '{tag} D-5: crm.marcar_efectos_conversion(uuid) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '{HB['m3']}') then
    raise exception '{tag} D-5: crm.marcar_efectos_conversion(uuid,uuid,text) no quedó como la genera gen-d5.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = '{FA}'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '{HB['a']}') then
    raise exception '{tag} D-5: crm.abandonar_conversion_gerencia_fn no quedó como la genera gen-d5.py';
  end if;
  if exists (select 1 from unnest(array['crm.reservar_conversion_lead(uuid)','crm.marcar_efectos_conversion(uuid)','crm.marcar_efectos_conversion(uuid,uuid,text)','{FA}']) f(firma)
             where not has_function_privilege('authenticated', f.firma, 'EXECUTE') or has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('crm.reservar_conversion_lead(uuid)'::regprocedure, 'crm.marcar_efectos_conversion(uuid)'::regprocedure, 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure, '{FA}'::regprocedure) and a.grantee = 0) then
    raise exception '{tag} D-5: los grants no son «solo authenticated» (ni anon, ni service_role, ni PUBLIC)';
  end if;
"""
mig = f"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-5] — LAS RPC DE UN ARGUMENTO DE LA CONVERSIÓN
-- SE CIERRAN CON LA IDENTIDAD ENCENDIDA, Y GERENCIA PUEDE ABANDONAR UNA CONVERSIÓN SELLADA SIN CUENTA (bloque 4, RETOMAR-60 §8)
-- ============================================================================
--
-- QUE: la conversión Avance de hoy (edge crm-convertir-lead, bandera apagada) reserva POR LEAD (reservar_conversion_lead de
-- 1 argumento) y sella sin persona (marcar_efectos_conversion de 1 argumento). b4 trajo las sobrecargas POR PERSONA
-- (reserva con documento + datos, sellado con claim + token) vigiladas por la saga de Auth, y dejó las firmas viejas para la
-- bandera apagada (paridad). Con la bandera ENCENDIDA esas firmas viejas seguían abiertas: un cliente viejo del edge (o
-- cualquier sesión con puede_gestionar_contratos) podía reservar y sellar SIN persona y crear una cuenta que la saga no ve
-- (b4 M3 / Codex #8: «la garantía sin cuentas huérfanas vale solo tras D-5»). Ahora, ENCENDIDA, las dos responden P0409
-- («la conversión va por persona: actualiza el CRM»); APAGADA no cambian ni un byte de comportamiento (guarda al entrar,
-- tras la autorización de siempre). Salvedad necesaria: el sellado por persona (3 argumentos) DELEGA en la firma de un
-- argumento para escribir efectos_iniciados_en; ese paso viaja marcado con el GUC transaccional crm.sellado_por_persona
-- (mismo patrón que crm.reapertura_identidad / crm.dni_por_puerta en D-13) y es el único que la guarda deja pasar encendida. Y Gerencia gana crm.abandonar_conversion_gerencia_fn(lead, motivo) (Codex E2 #12):
-- una reserva SELLADA cuyo edge murió antes de crear la cuenta dejaba a la persona «en conversión» para siempre; con
-- claim en `reclamado` (nada externo) y la ejecución vencida, Gerencia borra reserva y claim con motivo (nota en el lead,
-- audit_log por los triggers de las dos tablas). Con cuenta o ficha creadas, el camino sigue siendo RETOMAR (b4).
-- Transformación anclada al texto VIVO de producción (vivas/d5/, huellas-d5-prod.txt); reversa byte a byte.
-- Ensayo: scripts/oraculo-f2b-d5.sh. Reversa: scripts/rollback-f2b-d5.sql. Registro: scripts/registrar-f2b-d5.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));

do $guard$
begin
{GUARD}end
$guard$;

-- ============================================================================
-- 1. crm.reservar_conversion_lead(uuid): la reserva por lead se cierra con la bandera encendida
-- ============================================================================
{r};

-- ============================================================================
-- 2. crm.marcar_efectos_conversion(uuid): el sellado sin persona se cierra con la bandera encendida
-- ============================================================================
{m};

-- ============================================================================
-- 2b. crm.marcar_efectos_conversion(uuid,uuid,text): el sellado por persona (b4/D-13) marca su paso al delegar
-- ============================================================================
{m3};

-- ============================================================================
-- 3. crm.abandonar_conversion_gerencia_fn(uuid, text): Gerencia abandona una conversión sellada sin cuenta
-- ============================================================================
{CREA_A}
do $post$
begin
{post('POSTFLIGHT')}  raise notice 'F2.b D-5 OK: reserva y sellado de 1 argumento cerrados con la bandera encendida (apagada: intactos); abandonar_conversion_gerencia_fn creada.';
end
$post$;
commit;
"""
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')
rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-5] ({VER}): restaura byte a byte las dos firmas de un argumento y el sellado por persona (texto vivo de producción, md5 en
-- huellas-d5-prod.txt), suelta crm.abandonar_conversion_gerencia_fn y desregistra la versión. Repetible dos veces.
-- Se niega con la bandera encendida (con ON las firmas viejas abiertas son el hueco que D-5 cierra).
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));
do $pre$
begin
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'REVERSA D-5: la bandera resolver_en_puertas está ENCENDIDA; apágala antes de revertir';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.reservar_conversion_lead(uuid)')) not in ('{HB['r0']}', '{HB['r']}')
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.marcar_efectos_conversion(uuid)')) not in ('{HB['m0']}', '{HB['m']}')
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.marcar_efectos_conversion(uuid,uuid,text)')) not in ('{HB['m30']}', '{HB['m3']}') then
    raise exception 'REVERSA D-5: alguna de las dos firmas de un argumento no es ni el texto de D-5 ni el vivo de producción; no se pisa a ciegas';
  end if;
  if exists (select 1 from pg_proc p where p.oid = to_regprocedure('{FA}') and md5(p.prosrc) <> '{HB['a']}') then
    raise exception 'REVERSA D-5: crm.abandonar_conversion_gerencia_fn viva no tiene el cuerpo de gen-d5.py; no se suelta a ciegas';
  end if;
end
$pre$;
{r_prev};
{m_prev};
{m3_prev};
drop function if exists {FA};
do $post$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.reservar_conversion_lead(uuid)'::regprocedure) <> '{HB['r0']}'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.marcar_efectos_conversion(uuid)'::regprocedure) <> '{HB['m0']}'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure) <> '{HB['m30']}' then
    raise exception 'REVERSA D-5: las firmas transformadas no quedaron byte a byte como en producción';
  end if;
  if to_regprocedure('{FA}') is not null then
    raise exception 'REVERSA D-5: abandonar_conversion_gerencia_fn sigue existiendo';
  end if;
  delete from supabase_migrations.schema_migrations where version = '{VER}';
  raise notice 'REVERSA F2.b D-5 OK (versión {VER} desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-d5.sql').write_text(rb, encoding='utf-8')
H_MIG = md5s(mig)
reg = ("-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-5]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.\n"
       "-- Idempotente; toma el MISMO advisory que la migración y la reversa; exige las dos firmas transformadas y la herramienta con su\n"
       "-- cuerpo, definer, dueño, search_path y grants exactos, y se niega si la versión ya está registrada con OTRO contenido.\n"
       f"begin;\nset local lock_timeout = '5s';\nselect pg_advisory_xact_lock(hashtext('{ADV}'));\ndo $chk$\nbegin\n"
       + post('REGISTRO')
       + f"  if exists (select 1 from supabase_migrations.schema_migrations where version='{VER}' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> '{H_MIG}')) then\n"
       f"    raise exception 'REGISTRO D-5: la versión {VER} ya está registrada con otro contenido (o incompleto)';\n  end if;\nend\n$chk$;\n"
       f"insert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('{VER}', '{NAME[len(VER)+1:]}', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n")
(W/'scripts'/'registrar-f2b-d5.sql').write_text(reg, encoding='utf-8')
print('D-5 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; md5 migración', H_MIG, '; cuerpos', {k: v[:8] for k, v in HB.items()})

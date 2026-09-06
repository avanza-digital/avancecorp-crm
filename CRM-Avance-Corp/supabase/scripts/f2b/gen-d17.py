# gen-d17.py — F2.b prerrequisito de activación [D-17] (último de la lista previa al ENCENDIDO):
# las TRES puertas que aún leían la bandera sin coordinarse con su cambio —crm.marcar_no_contactar,
# crm.levantar_no_contactar (D-3) y crm.convertir_lead_externo (D-13)— pasan a leerla con READ COMMITTED
# y bajo el advisory COMPARTIDO crm_flag_resolver_en_puertas (el exclusivo lo toma el trigger de D-5 al
# cambiar la bandera). Hallazgo de Codex, 3.ª ronda del bloque 4. Genera 20260906160000 + reversa + registro.
# Uso: python3 gen-d17.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib, re
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
md5s = lambda s: hashlib.md5(s.encode('utf-8')).hexdigest()
VER = '20260906160000'; NAME = f'{VER}_crm_f2b_d17_veto_y_coop_bajo_el_candado_de_la_bandera'; ADV = 'crm_f2b_d17_bandera_en_las_tres_puertas'
viv = lambda n: (S/'vivas'/'d17'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:70], s.count(old)); return s.replace(old, new)
def body(t):
    m = re.search(r'AS \$function\$(.*)\$function\$$', t, re.S); assert m; return m.group(1)
H = {l.split()[0]: l.split()[1] for l in (S/'huellas-d17-prod.txt').read_text().splitlines() if l.strip() and not l.startswith('#')}

LOCK = """  -- F2.b [D-17] (Codex, 3.ª ronda del bloque 4): la bandera se lee con READ COMMITTED y bajo el candado
  -- COMPARTIDO por bandera; el UPDATE de crm.multiempresa_flags toma el EXCLUSIVO en su trigger (D-5).
  -- Así una llamada que entró APAGADA termina apagada aunque espere por una fila, y una que entra después
  -- del encendido lo ve: sin esto, una llamada en vuelo podía escribir con la bandera cambiada a medias.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'), false);
"""
T = {}
# ── 1. marcar_no_contactar: tras la autorización, antes de mirar el lead ─────────────────────────────
m_prev = viv('marcar_no_contactar'); assert md5s(m_prev + '\n') == H['crm.marcar_no_contactar']
m = rep(m_prev, "  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);\n", "  v_flag boolean;\n")
m = rep(m, """    raise exception 'No autorizado' using errcode = '42501';
  end if;
""", """    raise exception 'No autorizado' using errcode = '42501';
  end if;
""" + LOCK)
T['marcar_no_contactar'] = (m_prev, m, 'crm.marcar_no_contactar(uuid,text)')
# ── 2. levantar_no_contactar: tras la autorización y el motivo ───────────────────────────────────────
l_prev = viv('levantar_no_contactar'); assert md5s(l_prev + '\n') == H['crm.levantar_no_contactar']
l = rep(l_prev, "  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);\n", "  v_flag boolean;\n")
l = rep(l, """    raise exception 'Levantar No contactar exige un motivo' using errcode = '22023';
  end if;
""", """    raise exception 'Levantar No contactar exige un motivo' using errcode = '22023';
  end if;
""" + LOCK)
T['levantar_no_contactar'] = (l_prev, l, 'crm.levantar_no_contactar(uuid,text)')
# ── 3. convertir_lead_externo: tras la autorización, antes del primer uso de la bandera ──────────────
c_prev = viv('convertir_lead_externo'); assert md5s(c_prev + '\n') == H['crm.convertir_lead_externo']
c = rep(c_prev, "  v_flag        boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);\n", "  v_flag        boolean;\n")
c = rep(c, """    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
""", """    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
""" + LOCK)
T['convertir_lead_externo'] = (c_prev, c, 'crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)')

HB = {}
for k, (prev, new_, firma) in T.items():
    HB[k] = md5s(body(new_)); HB[k + '0'] = md5s(body(prev)); assert HB[k] != HB[k + '0']

GUARD = f"""  -- La guarda se lee bajo el MISMO candado compartido que usan las puertas (auditor D-17 #5): esta migración corre como
  -- `postgres`, así que el drenaje del script de encendido no la ve; sin el candado, un encendido confirmado entre esta
  -- lectura y el CREATE OR REPLACE dejaría aterrizar el lote con la bandera ya encendida.
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  if not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas') then
    raise exception 'F2.b D-17: no existe la bandera resolver_en_puertas (¿F1 aplicada?)';   -- auditor #11
  end if;
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'F2.b D-17: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'crm.multiempresa_flags'::regclass and tgname = 'trg_multiempresa_flags_00_serializa_puertas' and tgenabled = 'O') then
    raise exception 'F2.b D-17: falta el trigger que serializa el cambio de bandera (D-5, 20260906140000): aplica D-5 antes';
  end if;
""" + ''.join(f"""  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('{firma}')), '') not in ('{HB[k + '0']}', '{HB[k]}') then
    raise exception 'F2.b D-17: {firma} no es ni el texto vivo de producción ({HB[k + '0'][:8]}…) ni el de D-17';
  end if;
""" for k, (prev, new_, firma) in T.items())

def post(tag):
    return ''.join(f"""  if not exists (select 1 from pg_proc p where p.oid = '{firma}'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '{HB[k]}') then
    raise exception '{tag} D-17: {firma} no quedó como la genera gen-d17.py';
  end if;
""" for k, (prev, new_, firma) in T.items()) + f"""  if exists (select 1 from unnest(array['{T['marcar_no_contactar'][2]}','{T['levantar_no_contactar'][2]}','{T['convertir_lead_externo'][2]}']) f(firma)
             where not has_function_privilege('authenticated', f.firma, 'EXECUTE') or has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('{T['marcar_no_contactar'][2]}'::regprocedure, '{T['levantar_no_contactar'][2]}'::regprocedure, '{T['convertir_lead_externo'][2]}'::regprocedure) and a.grantee = 0) then
    raise exception '{tag} D-17: los grants de las tres puertas no son «solo authenticated»';
  end if;
"""

mig = f"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-17] — LAS TRES PUERTAS QUE SEÑALÓ CODEX
-- LEEN LA BANDERA BAJO EL CANDADO DEL ENCENDIDO
-- ============================================================================
--
-- QUE: el bloque 4 dejó a las puertas de D-5, D-13 y D-15 leyendo `resolver_en_puertas` con READ COMMITTED y bajo
-- el advisory COMPARTIDO `crm_flag_resolver_en_puertas`, mientras el UPDATE de crm.multiempresa_flags toma el
-- EXCLUSIVO (trigger `trg_multiempresa_flags_00_serializa_puertas`, D-5): así una llamada termina con la bandera
-- que leyó. Codex (3.ª ronda) encontró TRES que se habían quedado fuera y podían confirmar escrituras calculadas
-- con la bandera vieja si el encendido las pillaba esperando por una fila:
--   · crm.marcar_no_contactar(uuid,text)   (D-3) — vetaría solo el lead y no a la persona ni sus tareas.
--   · crm.levantar_no_contactar(uuid,text) (D-3) — levantaría solo el lead.
--   · crm.convertir_lead_externo(…)        (D-13) — cerraría en cooperativa sin resolver la identidad.
-- Ahora las tres exigen READ COMMITTED y toman el compartido justo DESPUÉS de su autorización (y del motivo, en
-- levantar) y ANTES de cualquier candado de negocio: un rechazado por permisos no espera por un encendido en curso.
-- Con la bandera estable (encendida o apagada) el comportamiento es el de hoy: solo cambia el momento en que se lee.
-- Dos matices honestos (auditor y Codex): (a) aparece un modo de fallo nuevo también apagada — quien llame en REPEATABLE
-- READ o SERIALIZABLE recibe `0A000` donde antes funcionaba; el front, las edges y la suite van por PostgREST (READ
-- COMMITTED), así que en la práctica no cambia nada, pero la paridad exacta se afirma SOLO bajo READ COMMITTED; (b) en
-- la conversión en cooperativa el candado va antes de las validaciones de payload, así que una fila inválida también
-- espera si hay un encendido en curso. ALCANCE: éstas son las TRES que nombró Codex. El censo del 06/09 encontró más
-- lectoras de la bandera; las escritoras que quedan fuera de D-17/D-18 NO están cubiertas por candado, solo por el
-- drenaje de scripts/encender-resolver-en-puertas.sql, y Codex advierte que ese drenaje NO cierra la admisión: una
-- llamada puede empezar después del recuento y antes del UPDATE. Cerrar eso es requisito del ENCENDIDO, no de aterrizar. Transformación anclada al texto VIVO de producción (vivas/d17/, huellas-d17-prod.txt).
-- Reversa byte a byte: scripts/rollback-f2b-d17.sql. Registro: scripts/registrar-f2b-d17.sql.
-- Ensayo: scripts/oraculo-f2b-d17.sh (encender y apagar esperan a cada puerta en vuelo; paridad con bandera estable).

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));

do $guard$
begin
{GUARD}end
$guard$;

-- ============================================================================
-- 1. crm.marcar_no_contactar(uuid,text)
-- ============================================================================
{T['marcar_no_contactar'][1]};

-- ============================================================================
-- 2. crm.levantar_no_contactar(uuid,text)
-- ============================================================================
{T['levantar_no_contactar'][1]};

-- ============================================================================
-- 3. crm.convertir_lead_externo(...)
-- ============================================================================
{T['convertir_lead_externo'][1]};

do $post$
begin
{post('POSTFLIGHT')}  raise notice 'F2.b D-17 OK: las tres puertas leen la bandera bajo el candado del encendido (apagada: sin cambio de comportamiento).';
end
$post$;
commit;
"""
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')

rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-17] ({VER}): restaura byte a byte las tres puertas (texto vivo de producción) y desregistra.
-- Repetible dos veces. Se niega con la bandera encendida.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));
do $pre$
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));   -- auditor D-17 #5
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'REVERSA D-17: la bandera resolver_en_puertas está ENCENDIDA; apágala antes de revertir';
  end if;
""" + ''.join(f"""  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('{firma}')), '') not in ('{HB[k + '0']}', '{HB[k]}') then
    raise exception 'REVERSA D-17: {firma} no es ni el texto de D-17 ni el vivo de producción; no se pisa a ciegas';
  end if;
""" for k, (prev, new_, firma) in T.items()) + f"""end
$pre$;
{T['marcar_no_contactar'][0]};

{T['levantar_no_contactar'][0]};

{T['convertir_lead_externo'][0]};

do $post$
begin
""" + ''.join(f"""  if not exists (select 1 from pg_proc p where p.oid = '{firma}'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '{HB[k + '0']}') then
    raise exception 'REVERSA D-17: {firma} no quedó byte a byte como en producción (cuerpo, definer, dueño o search_path)';
  end if;
""" for k, (prev, new_, firma) in T.items()) + f"""  delete from supabase_migrations.schema_migrations where version = '{VER}';
  raise notice 'REVERSA F2.b D-17 OK (versión {VER} desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-d17.sql').write_text(rb, encoding='utf-8')
H_MIG = md5s(mig)
reg = ("-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-17]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.\n"
       "-- Idempotente; mismo advisory que la ida y la reversa; exige las tres puertas con su cuerpo, definer, dueño, search_path y grants.\n"
       f"begin;\nset local lock_timeout = '5s';\nselect pg_advisory_xact_lock(hashtext('{ADV}'));\ndo $chk$\nbegin\n"
       + post('REGISTRO')
       + f"  if exists (select 1 from supabase_migrations.schema_migrations where version='{VER}' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> '{H_MIG}')) then\n"
       f"    raise exception 'REGISTRO D-17: la versión {VER} ya está registrada con otro contenido (o incompleto)';\n  end if;\nend\n$chk$;\n"
       f"insert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('{VER}', '{NAME[len(VER)+1:]}', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n")
(W/'scripts'/'registrar-f2b-d17.sql').write_text(reg, encoding='utf-8')
print('D-17 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; md5 migración', H_MIG, '; cuerpos', {k: v[:8] for k, v in HB.items() if not k.endswith('0')})

# gen-d18.py — F2.b: las DOS deudas del bloque 2 que quedaban para el encendido.
#  (a) crm.convertir_lead abría el tramo de responsable leyendo `crm.equipo.activo` SIN candado: una baja de analista
#      en vuelo (offboarding, D-2, que sí toma el interlock EXCLUSIVO de jerarquía) podía dejar a la persona con un
#      responsable que ya no está. Ahora la conversión toma el interlock COMPARTIDO de jerarquía al entrar (mismo
#      orden que el offboarding: jerarquía → documento → persona → lead, sin ciclo) y revalida `activo` bajo él.
#  (b) crm.fusionar_inversionistas_fn cancelaba las tareas del LEAD cuando la fusión heredaba el veto, pero no las
#      tareas de CLIENTE de la persona (N6). Ahora cancela ambas, con el mismo criterio de D-3.
# Genera 20260906190000 + reversa + registro. Uso: python3 gen-d18.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib, re
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
md5s = lambda s: hashlib.md5(s.encode('utf-8')).hexdigest()
VER='20260906190000'; NAME=f'{VER}_crm_f2b_d18_responsable_bajo_jerarquia_y_fusion_cancela_tareas_de_cliente'; ADV='crm_f2b_d18_deudas_bloque2'
viv = lambda n: (S/'vivas'/'d18'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:70], s.count(old)); return s.replace(old, new)
def body(t):
    m = re.search(r'AS \$function\$(.*)\$function\$$', t, re.S); assert m; return m.group(1)
H = {l.split()[0]: l.split()[1] for l in (S/'huellas-d18-prod.txt').read_text().splitlines() if l.strip() and not l.startswith('#')}

# ── (a) convertir_lead ───────────────────────────────────────────────────────────────────────────
c_prev = viv('convertir_lead'); assert md5s(c_prev + '\n') == H['crm.convertir_lead']
c = rep(c_prev, """  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
""", """  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  -- F2.b [D-18] (Codex #3 del bloque 2): el tramo de responsable se abre con el asesor del perfil «si está activo»,
  -- y eso se leía sin candado: una baja de analista en vuelo (crm.fijar_membresia_activa_fn, que toma el interlock
  -- EXCLUSIVO de jerarquía) podía cerrarle sus tramos mientras esta conversión le abría uno nuevo. Se toma el
  -- interlock COMPARTIDO al ENTRAR —antes de cualquier candado de negocio, el mismo orden que el offboarding:
  -- jerarquía → documento → persona → lead, así que no hay ciclo— y más abajo se revalida `activo` bajo él.
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
""")
c = rep(c, """    if v_asesor is not null
       and exists (select 1 from crm.equipo e where e.perfil_id = v_asesor and e.activo)""",
"""    if v_asesor is not null
       -- F2.b [D-18]: bajo el interlock compartido de jerarquía tomado al entrar, y con la fila del equipo FOR SHARE:
       -- si el analista se está dando de baja, o esta conversión espera a que termine, o la baja espera a ésta.
       and exists (select 1 from crm.equipo e where e.perfil_id = v_asesor and e.activo for share of e)""")
# ── (b) fusionar_inversionistas_fn ───────────────────────────────────────────────────────────────
f_prev = viv('fusionar_inversionistas_fn'); assert md5s(f_prev + '\n') == H['crm.fusionar_inversionistas_fn']
f = rep(f_prev, """  perform 1 from crm.tareas t where t.estado = 'pendiente' and t.lead_id = any(v_leads) order by t.id for update;""",
"""  -- F2.b [D-18] (N6): también las tareas de CLIENTE de las dos personas (por su perfil), que hasta ahora quedaban
  -- vivas cuando la fusión heredaba el veto. Mismo criterio que D-3 y mismo orden (tareas → leads).
  v_perfiles_fusion := array(select p.id from public.perfiles p
                              where p.id in (v_p.perfil_id, v_c.perfil_id) and p.id is not null);
  perform 1 from crm.tareas t
   where t.estado = 'pendiente'
     and (t.lead_id = any(v_leads) or (v_perfiles_fusion <> '{}' and t.perfil_id = any(v_perfiles_fusion)))
   order by t.id for update;""")
f = rep(f, """  if v_lead.id is not null and v_veto and not v_lead.no_contactar then
    v_n_tareas := private.cancelar_tareas_pendientes_lead(v_lead.id);
    update crm.leads set no_contactar = true where id = v_lead.id;
  end if;""",
"""  if v_lead.id is not null and v_veto and not v_lead.no_contactar then
    v_n_tareas := private.cancelar_tareas_pendientes_lead(v_lead.id);
    update crm.leads set no_contactar = true where id = v_lead.id;
  end if;
  -- F2.b [D-18] (N6): la fusión que hereda el veto cancela TAMBIÉN las tareas de cliente de las dos personas; si no,
  -- la ficha del cliente seguía con seguimientos pendientes de alguien a quien no se debe contactar. Se marca como
  -- cancelación del sistema (misma marca que usa D-3) para que el trigger de tareas no la trate como cierre humano.
  if v_veto and v_perfiles_fusion <> '{}' then
    perform pg_catalog.set_config('crm.cancela_sistema', 'on', true);
    update crm.tareas t set estado = 'cancelada'
     where t.estado = 'pendiente' and t.perfil_id = any(v_perfiles_fusion);
    get diagnostics v_n_tareas_cliente = row_count;
    perform pg_catalog.set_config('crm.cancela_sistema', 'off', true);
  end if;""")
f = rep(f, """  v_n_tit_dup integer := 0;""", """  v_perfiles_fusion uuid[] := '{}';        -- F2.b [D-18] (N6): perfiles cliente de las dos personas (tareas de cliente)
  v_n_tareas_cliente integer := 0;         -- F2.b [D-18] (N6)
  v_n_tit_dup integer := 0;""")
f = rep(f, """'tareas_canceladas', v_n_tareas,""", """'tareas_canceladas', v_n_tareas, 'tareas_cliente_canceladas', v_n_tareas_cliente,""")

T = {'convertir_lead': (c_prev, c, 'crm.convertir_lead(uuid,uuid)'),
     'fusionar_inversionistas_fn': (f_prev, f, 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)')}
HB = {}
for k,(prev,new_,firma) in T.items():
    HB[k]=md5s(body(new_)); HB[k+'0']=md5s(body(prev)); assert HB[k]!=HB[k+'0']

GUARD = ''.join(f"""  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('{firma}')), '') not in ('{HB[k+'0']}', '{HB[k]}') then
    raise exception 'F2.b D-18: {firma} no es ni el texto vivo de producción ({HB[k+'0'][:8]}…) ni el de D-18';
  end if;
""" for k,(prev,new_,firma) in T.items()) + """  if to_regprocedure('private.cancelar_tareas_pendientes_lead(uuid)') is null then
    raise exception 'F2.b D-18: falta private.cancelar_tareas_pendientes_lead(uuid)';
  end if;
  -- La guarda se lee bajo el MISMO candado compartido que usan las puertas (auditor D-17 #5): esta migración corre como
  -- `postgres`, así que el drenaje del script de encendido no la ve; sin el candado, un encendido confirmado entre esta
  -- lectura y el CREATE OR REPLACE dejaría aterrizar el lote con la bandera ya encendida.
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  if not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas') then
    raise exception 'F2.b D-18: no existe la bandera resolver_en_puertas (¿F1 aplicada?)';
  end if;
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'F2.b D-18: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
"""
def post(tag):
    return ''.join(f"""  if not exists (select 1 from pg_proc p where p.oid = '{firma}'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '{HB[k]}') then
    raise exception '{tag} D-18: {firma} no quedó como la genera gen-d18.py';
  end if;
""" for k,(prev,new_,firma) in T.items()) + f"""  if exists (select 1 from unnest(array['{T['convertir_lead'][2]}','{T['fusionar_inversionistas_fn'][2]}']) f(firma)
             where not has_function_privilege('authenticated', f.firma, 'EXECUTE') or has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('{T['convertir_lead'][2]}'::regprocedure, '{T['fusionar_inversionistas_fn'][2]}'::regprocedure) and a.grantee = 0) then
    raise exception '{tag} D-18: los grants no son «solo authenticated»';
  end if;
"""
mig = f"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b [D-18] — LAS DOS DEUDAS DEL BLOQUE 2, ANTES DEL ENCENDIDO
-- ============================================================================
--
-- (a) LA CONVERSIÓN NO LE DA UN RESPONSABLE QUE SE ESTÁ YENDO (Codex #3 del bloque 2). `crm.convertir_lead` abre el
--     tramo de responsable de relación con el asesor del perfil «si está activo», y leía `crm.equipo.activo` sin
--     candado. La baja de un analista (`crm.fijar_membresia_activa_fn`, D-2) toma el interlock EXCLUSIVO de jerarquía
--     `crm.equipo.usuarios_jerarquia`, cierra sus tramos y los abre al reemplazo; una conversión en vuelo podía
--     abrirle uno nuevo justo después y dejar a esa persona con un responsable que ya no trabaja. Ahora la conversión
--     toma el interlock COMPARTIDO al ENTRAR (antes de cualquier candado de negocio: jerarquía → documento → persona
--     → lead, el mismo orden que el offboarding, así que no hay ciclo) y comprueba `activo` con la fila FOR SHARE.
--
-- (b) LA FUSIÓN CANCELA TAMBIÉN LAS TAREAS DE CLIENTE (N6). Cuando la fusión hereda el veto «No insistir», cancelaba
--     los seguimientos del LEAD pero dejaba vivas las tareas de la FICHA DE CLIENTE de esas personas: quedaban
--     recordatorios para llamar a alguien a quien no se debe contactar. Ahora se bloquean y se cancelan también
--     (mismo criterio y misma marca de «cancelación del sistema» que D-3), y la respuesta informa cuántas.
--
-- Ambas transformaciones son ANCLADAS al texto vivo de producción (vivas/d18/, huellas-d18-prod.txt) y no cambian
-- nada más. Con la bandera apagada, (a) es un candado que nadie disputa y (b) no dispara (no hay veto de persona).
-- Reversa byte a byte: scripts/rollback-f2b-d18.sql. Registro: scripts/registrar-f2b-d18.sql.
-- Ensayo: scripts/oraculo-f2b-d18.sh.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));

do $guard$
begin
{GUARD}end
$guard$;

-- ============================================================================
-- 1. crm.convertir_lead(uuid,uuid) — el responsable, bajo el interlock de jerarquía
-- ============================================================================
{c};

-- ============================================================================
-- 2. crm.fusionar_inversionistas_fn(uuid,uuid,text,text) — la fusión cancela también las tareas de cliente
-- ============================================================================
{f};

do $post$
begin
{post('POSTFLIGHT')}  raise notice 'F2.b D-18 OK: la conversión respeta la baja del analista y la fusión cancela las tareas de cliente.';
end
$post$;
commit;
"""
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')
rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-18] ({VER}): restaura byte a byte las dos funciones (texto vivo de producción) y desregistra.
-- Repetible dos veces. Se niega con la bandera encendida.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));
do $pre$
begin
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));   -- auditor D-17 #5
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'REVERSA D-18: la bandera resolver_en_puertas está ENCENDIDA; apágala antes de revertir';
  end if;
""" + ''.join(f"""  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('{firma}')), '') not in ('{HB[k+'0']}', '{HB[k]}') then
    raise exception 'REVERSA D-18: {firma} no es ni el texto de D-18 ni el vivo de producción; no se pisa a ciegas';
  end if;
""" for k,(prev,new_,firma) in T.items()) + f"""end
$pre$;
{c_prev};

{f_prev};

do $post$
begin
""" + ''.join(f"""  if not exists (select 1 from pg_proc p where p.oid = '{firma}'::regprocedure
                  and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole
                  and md5(p.prosrc) = '{HB[k+'0']}') then
    raise exception 'REVERSA D-18: {firma} no quedó byte a byte como en producción (cuerpo, definer, dueño o search_path)';
  end if;
""" for k,(prev,new_,firma) in T.items()) + f"""  delete from supabase_migrations.schema_migrations where version = '{VER}';
  raise notice 'REVERSA F2.b D-18 OK (versión {VER} desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-d18.sql').write_text(rb, encoding='utf-8')
H_MIG = md5s(mig)
reg = ("-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-18]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.\n"
       f"begin;\nset local lock_timeout = '5s';\nselect pg_advisory_xact_lock(hashtext('{ADV}'));\ndo $chk$\nbegin\n"
       + post('REGISTRO')
       + f"  if exists (select 1 from supabase_migrations.schema_migrations where version='{VER}' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> '{H_MIG}')) then\n"
       f"    raise exception 'REGISTRO D-18: la versión {VER} ya está registrada con otro contenido (o incompleto)';\n  end if;\nend\n$chk$;\n"
       f"insert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('{VER}', '{NAME[len(VER)+1:]}', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n")
(W/'scripts'/'registrar-f2b-d18.sql').write_text(reg, encoding='utf-8')
print('D-18 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; md5', H_MIG, '; cuerpos', {k: v[:8] for k,v in HB.items() if not k.endswith('0')})

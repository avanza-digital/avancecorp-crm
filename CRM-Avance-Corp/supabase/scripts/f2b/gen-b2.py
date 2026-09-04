import sys, pathlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
viv = lambda n: (S/'vivas'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:70], s.count(old)); return s.replace(old, new)

VETO = "La persona tiene la restricción «No insistir»"
prev = {k: viv(k) for k in ['private.repartir_lead_implementacion','crm.derivar_leads_equipo_fn','crm.revertir_derivacion_equipo_fn',
        'crm.tomar_lead_libre','private.deshacer_descarte_implementacion','crm.resumen_reparto_fn','private.trg_gestion_lead_serializada',
        'crm.marcar_no_contactar','crm.levantar_no_contactar','crm.rescatar_descartes','private.leads_por_repartir_implementacion']}
t = dict(prev)

t['private.repartir_lead_implementacion'] = rep(t['private.repartir_lead_implementacion'],
"""  if v_lead.no_contactar then
    raise exception 'Lead marcado No Insista (Ley 29571): no se puede repartir'
      using errcode = 'P0429';
  end if;
""","""  if v_lead.no_contactar then
    raise exception 'Lead marcado No Insista (Ley 29571): no se puede repartir'
      using errcode = 'P0429';
  end if;
  -- F2.b (b2): el veto es de la PERSONA (contrato §7.3). Lectura sin lock tras el
  -- FOR UPDATE del lead: no altera el orden de locks.
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede repartir', '""" + VETO + """'
      using errcode = 'P0429';
  end if;
""")

t['crm.derivar_leads_equipo_fn'] = rep(t['crm.derivar_leads_equipo_fn'],
"""    if v_lead.no_contactar is true then
      raise exception 'El lead % está marcado No Insista y no se puede derivar', v_lead.id
        using errcode = 'P0429';
    end if;
""","""    if v_lead.no_contactar is true then
      raise exception 'El lead % está marcado No Insista y no se puede derivar', v_lead.id
        using errcode = 'P0429';
    end if;
    -- F2.b (b2): veto de la PERSONA (contrato §7.3).
    if private.persona_vetada(v_lead.id) then
      raise exception 'El lead % pertenece a una persona con la restricción «No insistir» y no se puede derivar', v_lead.id
        using errcode = 'P0429';
    end if;
""")

t['crm.revertir_derivacion_equipo_fn'] = rep(t['crm.revertir_derivacion_equipo_fn'],
"""  for update;
  if not found then
    raise exception 'El lead ya no está disponible'
      using errcode = 'P0001';
  end if;
""","""  for update;
  if not found then
    raise exception 'El lead ya no está disponible'
      using errcode = 'P0001';
  end if;
  -- F2.b (b2): con la bandera encendida, ni el lead vetado ni el de una persona
  -- vetada se devuelven a la bandeja (coherente con reparto/derivación).
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se devuelve a la bandeja', '""" + VETO + """'
      using errcode = 'P0429';
  end if;
""")

tl = t['crm.tomar_lead_libre']
tl = rep(tl, """    where l.no_contactar = true
      and (l.telefono = v_tel or (v_dni is not null and l.dni = v_dni))""",
"""    where (l.no_contactar = true or private.persona_vetada(l.id))  -- F2.b (b2): veto de la persona
      and (l.telefono = v_tel or (v_dni is not null and l.dni = v_dni))""")
import re as _re
_pat = _re.compile(r"^( +)and l\.no_contactar = false\n", _re.M)
assert len(_pat.findall(tl)) == 4, len(_pat.findall(tl))
tl = _pat.sub(lambda m: f"{m.group(1)}and l.no_contactar = false\n{m.group(1)}and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar\n", tl)
assert tl.count('persona_vetada') == 5
t['crm.tomar_lead_libre'] = tl

t['private.deshacer_descarte_implementacion'] = rep(t['private.deshacer_descarte_implementacion'],
"""  if not found then
    raise exception 'Solo puedes deshacer tus propios descartes de las últimas 24 horas, y solo si el lead sigue sin dueño'
      using errcode = 'P0002';
  end if;
""","""  if not found then
    raise exception 'Solo puedes deshacer tus propios descartes de las últimas 24 horas, y solo si el lead sigue sin dueño'
      using errcode = 'P0002';
  end if;
  -- F2.b (b2): gemela de rescatar_descartes: una persona vetada no se reabre.
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede reabrir', '""" + VETO + """'
      using errcode = 'P0429';
  end if;
""")

t['private.leads_por_repartir_implementacion'] = rep(t['private.leads_por_repartir_implementacion'],
"""    and (not v_flag or coalesce(inv.no_contactar, false) = false) -- el veto es de la PERSONA (contrato §7.3)""",
"""    and (not v_flag or coalesce(inv.no_contactar, false) = false) -- el veto es de la PERSONA (contrato §7.3)
    and not private.persona_vetada(l.id)                     -- F2.b (b2): también por documento exacto (lead suelto)""")

def documento_suelto(m, verbo):
    # F2.b (b2) [Codex v2 #6]: la puerta por PUNTERO pasa a ser por PERSONA: si el
    # lead está suelto, se resuelve la identidad por documento exacto (mismo orden:
    # documento -> identidad -> leads). El lead suelto NO se enlaza (eso es b5).
    m = rep(m, """  if not v_flag then v_inv := null; end if;
  if v_inv is not null then
    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;""", """  if not v_flag then v_inv := null; end if;
  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
    select l.dni into v_dni_suelto from crm.leads l where l.id = p_lead_id;
    perform private.identidad_bloquear_documento('DNI', v_dni_suelto);
    v_inv := private.inversionista_por_documento('DNI', v_dni_suelto);
    v_suelto := v_inv is not null;
  end if;
  if v_inv is not null then
    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;""")
    m = rep(m, """  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
begin""", """  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_dni_suelto text;
  v_suelto boolean := false;  -- F2.b (b2)
begin""")
    m = rep(m, """  if v_flag and v_lead.inversionista_id is distinct from v_inv then""",
               """  if v_flag and not v_suelto and v_lead.inversionista_id is distinct from v_inv then""")
    # Tras esperar el lead, el DNI del suelto pudo cambiar (Codex E1 #3): revalidar sin tomar otra identidad.
    i = m.index("  if v_flag and not v_suelto and v_lead.inversionista_id is distinct from v_inv then")
    j = m.index("  end if;", i) + len("  end if;")
    m = m[:j] + """
  if v_flag and v_suelto
     and (v_lead.inversionista_id is not null
          or private.inversionista_por_documento('DNI', v_lead.dni) is distinct from v_inv) then
    raise exception 'El documento del lead cambió mientras se %s; vuelve a intentarlo'
      using errcode = '40001';
  end if;""" % verbo + m[j:]
    return m

t['crm.levantar_no_contactar'] = documento_suelto(t['crm.levantar_no_contactar'], 'levantaba')
t['crm.levantar_no_contactar'] = rep(t['crm.levantar_no_contactar'], """      if v_lead.no_contactar then
        update crm.leads set no_contactar = false where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;""", """      if v_lead.no_contactar then
        update crm.leads set no_contactar = false where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;
    -- F2.b (b2): el propio lead suelto también.
    update crm.leads set no_contactar = false where id = p_lead_id and no_contactar = true;
    if found then v_n := v_n + 1; end if;""")

# BUG PREEXISTENTE (20260820181756, en prod desde el 20/08): `pg_catalog.coalesce(...)` no existe
# (coalesce es sintaxis, no función) y la línea corre en TODA llamada → el rescate fallaba siempre
# con 42883. Lo cazó el oráculo de b2 al ejercitar el rescate de verdad. Se corrige aquí.
t['crm.rescatar_descartes'] = rep(t['crm.rescatar_descartes'],
    """  v_total_destinos := pg_catalog.coalesce(pg_catalog.array_length(v_destinos_validos, 1), 0);""",
    """  v_total_destinos := coalesce(pg_catalog.array_length(v_destinos_validos, 1), 0);  -- F2.b (b2): pg_catalog.coalesce no existe (bug desde 20/08)""")
t['crm.rescatar_descartes'] = rep(t['crm.rescatar_descartes'], """    if v_fila.no_contactar then
      raise exception 'Uno de los leads tiene la restricción «No insistir» y no puede reactivarse'
        using errcode = 'P0429';
    end if;""", """    if v_fila.no_contactar then
      raise exception 'Uno de los leads tiene la restricción «No insistir» y no puede reactivarse'
        using errcode = 'P0429';
    end if;
    -- F2.b (b2): también por documento exacto (lead suelto de una persona vetada).
    if private.persona_vetada(v_fila.lead_id) then
      raise exception 'Uno de los leads pertenece a una persona con la restricción «No insistir» y no puede reactivarse'
        using errcode = 'P0429';
    end if;""")

t['crm.resumen_reparto_fn'] = rep(t['crm.resumen_reparto_fn'],
"""      and l.no_contactar = false
  ),""","""      and l.no_contactar = false
      and not private.persona_vetada(l.id)  -- F2.b (b2): mismo criterio que la cola (leads_por_repartir)
  ),""")

t['private.trg_gestion_lead_serializada'] = rep(t['private.trg_gestion_lead_serializada'],
"""  if v_autorizado is distinct from true then
    raise exception 'El lead cambió de responsable; recarga antes de registrar la gestión'
      using errcode = '42501';
  end if;
""","""  if v_autorizado is distinct from true then
    raise exception 'El lead cambió de responsable; recarga antes de registrar la gestión'
      using errcode = '42501';
  end if;
  -- F2.b (b2): el veto de la PERSONA bloquea el SEGUIMIENTO (contrato §7.3): los tipos
  -- de CONTACTO y las tareas. Las notas administrativas (corrección/anulación de un
  -- cierre, fusión, reingreso) no son contacto y siguen entrando; la nota de las RPC
  -- de veto entra además bajo la válvula op_privilegiada.
  if not coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     and (tg_table_name = 'tareas'
          or new.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'))
     and private.persona_vetada(new.lead_id) then
    raise exception '%: no se registra seguimiento', '""" + VETO + """'
      using errcode = 'P0429';
  end if;
""")

m = t['crm.marcar_no_contactar']
m = documento_suelto(m, 'marcaba')
m = rep(m, """  select * into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true""", """  -- F2.b (b2) [Codex E1 #2]: orden identidad -> TAREAS -> leads. crm.cerrar_tarea va
  -- tarea -> lead; cancelar las pendientes después de bloquear los leads formaría un ciclo.
  if v_flag then
    perform 1 from crm.tareas t
     where t.estado = 'pendiente'
       and t.lead_id in (select l.id from crm.leads l
                          where l.id = p_lead_id or (v_inv is not null and l.inversionista_id = v_inv))
     order by t.id
     for update;
  end if;

  select * into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true""")
m = rep(m, """  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  -- tipo 'nota' (el CHECK de actividades no admite un tipo nuevo; el evento va en metadata).
""", """  -- F2.b (b2): con la bandera encendida se cancelan las tareas PENDIENTES de todos
  -- los leads de la persona (selladas como sistema). Levantar el veto NO las revive.
  if v_flag then
    perform pg_catalog.set_config('crm.cancela_sistema', 'on', true);
    update crm.tareas t
       set estado = 'cancelada'
     where t.estado = 'pendiente'
       and t.lead_id in (select l.id from crm.leads l
                          where l.id = p_lead_id or (v_inv is not null and l.inversionista_id = v_inv));
    perform pg_catalog.set_config('crm.cancela_sistema', 'off', true);
  end if;

  -- tipo 'nota' (el CHECK de actividades no admite un tipo nuevo; el evento va en metadata).
  -- La nota se inserta BAJO la válvula: el trigger de gestión exime la válvula del veto (F2.b b2).
""")
m = rep(m, """    end loop;
  else
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;""", """    end loop;
    -- F2.b (b2): el propio lead suelto también hereda el veto.
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;
    if found then v_n := v_n + 1; end if;
  else
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;""")
m = rep(m, """          v_uid);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,""",
"""          v_uid);
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,""")
t['crm.marcar_no_contactar'] = m


hdr = r"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b sub-lote b2 — EL VETO DE LA PERSONA BLOQUEA
-- REPARTO, TOMA, REAPERTURA Y SEGUIMIENTO (contrato §7.3, invariante #7)
-- ============================================================================
--
-- QUE: hasta hoy las MUTACIONES solo miraban crm.leads.no_contactar (el veto del
-- lead). Con la bandera resolver_en_puertas ENCENDIDA pasan a respetar también el
-- veto de la PERSONA: por crm.leads.inversionista_id -> identidad canónica, o por
-- documento exacto (identificador vigente y verificado) cuando el lead no está
-- enlazado. Además el veto cancela las tareas pendientes y bloquea el seguimiento
-- (actividades/tareas humanas) por el trigger de gestión que ya bloquea el lead.
--
-- COMO: helper único private.persona_vetada(lead) (+ forma set-based), STABLE y sin
-- lock; se consulta DESPUÉS del FOR UPDATE del lead en cada puerta (lectura: no
-- cambia el orden de locks). Cada función se TRANSFORMA desde su texto vivo
-- (pg_get_functiondef de producción, 04/09/2026) con reemplazos anclados.
--   * repartir_lead_implementacion, derivar_leads_equipo_fn, revertir_derivacion_equipo_fn,
--     deshacer_descarte_implementacion -> P0429; tomar_lead_libre -> veredicto no_contactar;
--     resumen_reparto_fn -> mismo criterio que la cola; trg_gestion_lead_serializada -> P0429
--     (exime la válvula op_privilegiada, bajo la que las RPC de veto dejan su nota);
--     marcar/levantar_no_contactar -> por PERSONA también cuando el lead está suelto (documento
--     exacto) + marcar cancela tareas pendientes (selladas 'sistema'); rescatar_descartes -> P0429.
--     El offboarding NO se toca (la reasignación del responsable de relación es la puerta de
--     Gerencia de b5: evita el ciclo identidad<->crm.equipo que señaló Codex).
-- TODO detrás de la bandera: APAGADA = persona_vetada() devuelve false y ninguna
-- puerta cambia de respuesta, SQLSTATE ni efectos (paridad exacta).
-- Reversa: scripts/rollback-f2b-b2.sql (texto previo byte a byte).

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b2_veto_persona_mutaciones'));

do $guard$
begin
  if to_regprocedure('private.inversionista_por_documento(text,text)') is null
     or to_regprocedure('crm.marcar_no_contactar(uuid,text)') is null then
    raise exception 'F2.b b2: falta b1 (20260904120000) o el lote Contrato-F2';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b b2: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
end
$guard$;


-- Guarda del TEXTO VIVO (md5 de pg_get_functiondef en prod, 04/09/2026), o ya transformada
-- por este lote (marca 'F2.b (b2)' en prosrc) para reaplicar en banco.
do $vivo$
declare r record; v_h text; v_src text;
begin
  for r in select * from (values
    ('private.repartir_lead_implementacion','306e51ce145aae695f932b936199242e'),
    ('crm.derivar_leads_equipo_fn','9a4eae7eb21bbe0080139a0cf3686e3b'),
    ('crm.revertir_derivacion_equipo_fn','43699042a1b300a960a0696977f08b35'),
    ('crm.tomar_lead_libre','b0a3a3d185ff90504489fe9313023a13'),
    ('private.deshacer_descarte_implementacion','a386c107d7a7f04a9b369d5e152d8093'),
    ('crm.resumen_reparto_fn','51bdcdc6ed9849370a071d42e1a3600a'),
    ('private.leads_por_repartir_implementacion','6c6d2e57f7dd9a4c182e2513bab2c941'),
    ('private.trg_gestion_lead_serializada','03f171cc19acecb744b040bd7435a2a7'),
    ('crm.marcar_no_contactar','9807431e2b8511ea81395b037fe31c7a'),
    ('crm.levantar_no_contactar','6ec378121ea1736a0915be1d7e59213c'),
    ('crm.rescatar_descartes','7ecc2d7173578815d1d878ebfd7e11cb')
  ) as v(fn, h) loop
    select md5(pg_get_functiondef(p.oid)), p.prosrc into v_h, v_src
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname || '.' || p.proname = r.fn;
    if v_h is null then
      raise exception 'F2.b b2: falta %', r.fn;
    end if;
    if v_h <> r.h and strpos(v_src, 'F2.b (b2)') = 0 then
      raise exception 'F2.b b2: % no es el texto vivo esperado (%)', r.fn, v_h;
    end if;
  end loop;
end
$vivo$;

-- ============================================================================
-- 1. Helpers del veto de la persona (privados, STABLE, sin lock)
-- ============================================================================
create or replace function private.leads_vetados_persona(p_lead_ids uuid[])
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select l.id
  from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
  left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)
  where l.id = any (coalesce(p_lead_ids, array[]::uuid[]))
    and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
    and (
      l.no_contactar = true
      or coalesce(inv.no_contactar, false)
      or (l.inversionista_id is null
          and nullif(pg_catalog.btrim(coalesce(l.dni,'')), '') is not null
          and exists (
            select 1
            from crm.inversionista_identificadores idf
            join crm.inversionistas i on i.id = idf.inversionista_id
            where idf.tipo_documento = 'DNI'
              and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(l.dni, '[^A-Za-z0-9]', '', 'g'))
              and idf.estado = 'vigente'
              and idf.verificado = true
              and i.estado <> 'fusionado'
              and i.no_contactar = true))
    )
$$;
revoke all on function private.leads_vetados_persona(uuid[]) from public, anon, authenticated, service_role;

create or replace function private.persona_vetada(p_lead_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.leads_vetados_persona(array[p_lead_id]))
$$;
revoke all on function private.persona_vetada(uuid) from public, anon, authenticated, service_role;

"""
secs = [
 ('2. Reparto (implementación viva; el wrapper crm.repartir_lead no se toca)', 'private.repartir_lead_implementacion'),
 ('3. Derivación entre equipos', 'crm.derivar_leads_equipo_fn'),
 ('4. Reversión de derivación', 'crm.revertir_derivacion_equipo_fn'),
 ('5. Toma de lead libre (precheck + 2 FOR UPDATE + 2 CAS)', 'crm.tomar_lead_libre'),
 ('6. Deshacer descarte (implementación viva)', 'private.deshacer_descarte_implementacion'),
 ('7. Resumen de reparto (mismo criterio que la cola)', 'crm.resumen_reparto_fn'),
 ('7b. Cola de reparto (implementación viva de 250000): también por documento exacto', 'private.leads_por_repartir_implementacion'),
 ('8. Seguimiento: trigger de gestión (actividades y tareas humanas)', 'private.trg_gestion_lead_serializada'),
 ('9. Marcar no_contactar: nota bajo válvula + tareas pendientes canceladas', 'crm.marcar_no_contactar'),
 ('10. Levantar no_contactar: también por documento (lead suelto)', 'crm.levantar_no_contactar'),
 ('11. Rescate de descartes: veto de la persona también por documento', 'crm.rescatar_descartes'),
]
body = ''
for title, fn in secs:
    body += f"-- ============================================================================\n-- {title}\n-- ============================================================================\n{t[fn]}\n;\n\n"

post = r"""-- ============================================================================
-- 11. Postflight
-- ============================================================================
do $post$
declare v_fn text; v_src text;
begin
  if to_regprocedure('private.persona_vetada(uuid)') is null
     or to_regprocedure('private.leads_vetados_persona(uuid[])') is null then
    raise exception 'POSTFLIGHT b2: faltan los helpers';
  end if;
  foreach v_fn in array array['private.repartir_lead_implementacion','crm.derivar_leads_equipo_fn','crm.revertir_derivacion_equipo_fn',
                              'crm.tomar_lead_libre','private.deshacer_descarte_implementacion','crm.resumen_reparto_fn',
                              'private.leads_por_repartir_implementacion','private.trg_gestion_lead_serializada'] loop
    select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname || '.' || p.proname = v_fn;
    if v_src is null or strpos(v_src, 'persona_vetada') = 0 then
      raise exception 'POSTFLIGHT b2: % no consulta persona_vetada', v_fn;
    end if;
  end loop;
  if (select strpos(prosrc, 'crm.cancela_sistema') from pg_proc where proname='marcar_no_contactar') = 0 then
    raise exception 'POSTFLIGHT b2: marcar_no_contactar no cancela tareas';
  end if;
  if (select strpos(prosrc, 'identidad_bloquear_documento') from pg_proc where proname='levantar_no_contactar') = 0
     or (select strpos(prosrc, 'identidad_bloquear_documento') from pg_proc where proname='marcar_no_contactar') = 0 then
    raise exception 'POSTFLIGHT b2: marcar/levantar no resuelven la persona por documento';
  end if;
  if (select strpos(prosrc, 'persona_vetada') from pg_proc where proname='rescatar_descartes') = 0 then
    raise exception 'POSTFLIGHT b2: rescatar_descartes no consulta persona_vetada';
  end if;
  if (select count(*) from regexp_matches((select prosrc from pg_proc where proname='tomar_lead_libre'), 'persona_vetada', 'g')) <> 5 then
    raise exception 'POSTFLIGHT b2: tomar_lead_libre debe consultar persona_vetada 5 veces';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
             where p.oid in ('private.persona_vetada(uuid)'::regprocedure, 'private.leads_vetados_persona(uuid[])'::regprocedure,
                             'private.repartir_lead_implementacion(uuid,uuid)'::regprocedure, 'private.deshacer_descarte_implementacion(uuid)'::regprocedure,
                             'private.leads_por_repartir_implementacion()'::regprocedure, 'private.trg_gestion_lead_serializada()'::regprocedure)
               and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole)))
     or has_function_privilege('authenticated', 'private.persona_vetada(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.tomar_lead_libre(text,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.tomar_lead_libre(text,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.derivar_leads_equipo_fn(uuid[],uuid[])', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.revertir_derivacion_equipo_fn(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.resumen_reparto_fn()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.marcar_no_contactar(uuid,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.levantar_no_contactar(uuid,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.rescatar_descartes(uuid[],uuid[],boolean)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.repartir_lead_implementacion(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.deshacer_descarte_implementacion(uuid)', 'EXECUTE') then
    raise exception 'POSTFLIGHT b2: grants incorrectos (CREATE OR REPLACE conserva la ACL; verificar)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT b2: la bandera quedó encendida';
  end if;
  raise notice 'F2.b b2 OK: el veto de la persona bloquea reparto, derivación, reversión, toma, reapertura y seguimiento; marcar cancela tareas; marcar/levantar por persona en leads sueltos. Bandera APAGADA.';
end
$post$;

commit;
"""
(W/'migrations'/'20260904130000_crm_f2b_b2_veto_persona_mutaciones.sql').write_text(hdr + body + post, encoding='utf-8')

rb = r"""-- ============================================================================
-- REVERSA de F2.b sub-lote b2 (20260904130000_crm_f2b_b2_veto_persona_mutaciones)
-- ============================================================================
-- Restaura byte a byte (pg_get_functiondef de producción, 04/09/2026) las once
-- funciones transformadas y suelta los dos helpers. Conserva tareas canceladas y
-- tramos de responsable creados con la bandera encendida (hechos). Bandera APAGADA.
-- Repetible dos veces.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b2_reversa'));
update crm.multiempresa_flags set activo = false, actualizado_en = now()
  where nombre = 'resolver_en_puertas' and activo = true;

"""
for title, fn in secs:
    rb += f"-- {fn}: versión previa\n{prev[fn]}\n;\n\n"
rb += r"""drop function if exists private.persona_vetada(uuid);
drop function if exists private.leads_vetados_persona(uuid[]);

do $post$
declare v_fn text; v_src text; r record; v_h text;
begin
  foreach v_fn in array array['private.repartir_lead_implementacion','crm.derivar_leads_equipo_fn','crm.revertir_derivacion_equipo_fn',
                              'crm.tomar_lead_libre','private.deshacer_descarte_implementacion','crm.resumen_reparto_fn',
                              'private.trg_gestion_lead_serializada','crm.marcar_no_contactar','crm.levantar_no_contactar',
                              'crm.rescatar_descartes','private.leads_por_repartir_implementacion'] loop
    select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname || '.' || p.proname = v_fn;
    if v_src is null or strpos(v_src, 'persona_vetada') <> 0 or strpos(v_src, 'F2.b (b2)') <> 0
       or (v_fn in ('crm.marcar_no_contactar','crm.levantar_no_contactar') and strpos(v_src, 'identidad_bloquear_documento') <> 0) then
      raise exception 'REVERSA b2: % sigue transformada', v_fn;
    end if;
  end loop;
  if to_regprocedure('private.persona_vetada(uuid)') is not null then
    raise exception 'REVERSA b2: queda el helper';
  end if;
  -- El texto restaurado debe ser el VIVO de producción (md5 de pg_get_functiondef, 04/09/2026).
  for r in select * from (values
    ('private.repartir_lead_implementacion','306e51ce145aae695f932b936199242e'),
    ('crm.derivar_leads_equipo_fn','9a4eae7eb21bbe0080139a0cf3686e3b'),
    ('crm.revertir_derivacion_equipo_fn','43699042a1b300a960a0696977f08b35'),
    ('crm.tomar_lead_libre','b0a3a3d185ff90504489fe9313023a13'),
    ('private.deshacer_descarte_implementacion','a386c107d7a7f04a9b369d5e152d8093'),
    ('crm.resumen_reparto_fn','51bdcdc6ed9849370a071d42e1a3600a'),
    ('private.leads_por_repartir_implementacion','6c6d2e57f7dd9a4c182e2513bab2c941'),
    ('private.trg_gestion_lead_serializada','03f171cc19acecb744b040bd7435a2a7'),
    ('crm.marcar_no_contactar','9807431e2b8511ea81395b037fe31c7a'),
    ('crm.levantar_no_contactar','6ec378121ea1736a0915be1d7e59213c'),
    ('crm.rescatar_descartes','7ecc2d7173578815d1d878ebfd7e11cb')
  ) as v(fn, h) loop
    select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname || '.' || p.proname = r.fn;
    if v_h is distinct from r.h then
      raise exception 'REVERSA b2: % no volvió byte a byte al vivo de producción (%)', r.fn, v_h;
    end if;
  end loop;
  raise notice 'REVERSA F2.b b2 OK';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-b2.sql').write_text(rb, encoding='utf-8')
print('b2 migración', len((hdr+body+post).splitlines()), 'líneas; reversa', len(rb.splitlines()))

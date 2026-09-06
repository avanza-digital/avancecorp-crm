# gen-d2.py — F2.b prerrequisito de activación [D-2] (bloque 2): la SALIDA de un analista (offboarding,
# crm.fijar_membresia_activa_fn) no deja tramos abiertos ni personas sin responsable, y el nuevo responsable de
# relación (crm.reasignar_responsable_relacion_fn, b5) recibe CAPACIDAD OPERATIVA (tenencia de los leads vivos y
# cartera del perfil cliente). Transforma 3 funciones VIVAS de producción (vivas/bloque2/*.sql, md5 en
# huellas-bloque2-prod.txt). Genera la migración 20260906120000, su reversa (byte a byte, desregistra) y el registro.
# Uso: python3 gen-d2.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
viv = lambda n: (S/'vivas'/'bloque2'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:90], s.count(old)); return s.replace(old, new)
md5 = lambda t: hashlib.md5((t + '\n').encode('utf-8')).hexdigest()
prod = {l.split()[0]: l.split()[1] for l in (S/'huellas-bloque2-prod.txt').read_text().splitlines() if l.strip()}
H_LDP = '6eded477639796c1053f0190f6decc18'   # private.leads_de_personas(uuid[]) en PROD (D-13 v4.4) = banco
ADV = 'crm_f2b_d2_offboarding_atomico'
VER = '20260906120000'; NAME = f'{VER}_crm_f2b_d2_offboarding_atomico_y_capacidad_del_responsable'
FN = {
  'crm.impacto_desactivacion_usuario_fn': ('crm.impacto_desactivacion_usuario_fn(uuid)', 'p_perfil_id uuid'),
  'crm.fijar_membresia_activa_fn': ('crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)', 'p_perfil_id uuid, p_activo boolean, p_reemplazo_id uuid, p_version_equipo timestamp with time zone, p_idempotencia uuid'),
  'crm.reasignar_responsable_relacion_fn': ('crm.reasignar_responsable_relacion_fn(uuid,uuid,text)', 'p_inversionista uuid, p_nuevo_responsable uuid, p_motivo text'),
}
prev = {k: viv(k) for k in FN}
for k in FN:
    assert md5(prev[k]) == prod[k], (k, md5(prev[k]), prod[k])
nuevo = {}
PERSONAS_DEL = """crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id))"""

# ---------------------------------------------------------------- 1. impacto: las personas a cargo exigen reemplazo (solo con ON)
t = prev['crm.impacto_desactivacion_usuario_fn']
t = rep(t, "  v_clientes integer;\n", """  v_clientes integer;
  v_personas integer := 0;  -- F2.b [D-2]
  v_flag boolean := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);  -- F2.b [D-2]
""")
RET_OLD = """  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id,
    'subordinados_activos', v_subordinados,
    'leads_abiertos', v_leads,
    'leads_en_bandeja', v_bandeja,
    'tareas_pendientes', v_tareas,
    'clientes_activos', v_clientes,
    'requiere_reemplazo',
      v_subordinados + v_leads + v_bandeja + v_tareas + v_clientes > 0
  );
"""
t = rep(t, RET_OLD, f"""  -- F2.b [D-2]: con la identidad ENCENDIDA, las PERSONAS cuyo responsable de relación es el saliente (identidades
  -- activas con tramo abierto suyo o apuntándole) también exigen reemplazo: nadie se queda sin responsable. Con la
  -- bandera apagada la respuesta es byte a byte la de hoy (el front la valida con un esquema ESTRICTO: la clave
  -- personas_a_cargo solo aparece con ON, y el front la incorpora en el bloque 4, antes del encendido).
  if v_flag then
    select count(*)::integer into v_personas
    from {PERSONAS_DEL};
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id,
      'subordinados_activos', v_subordinados,
      'leads_abiertos', v_leads,
      'leads_en_bandeja', v_bandeja,
      'tareas_pendientes', v_tareas,
      'clientes_activos', v_clientes,
      'personas_a_cargo', v_personas,
      'requiere_reemplazo',
        v_subordinados + v_leads + v_bandeja + v_tareas + v_clientes + v_personas > 0
    );
  end if;
""" + RET_OLD)
nuevo['crm.impacto_desactivacion_usuario_fn'] = t

# ---------------------------------------------------------------- 2. offboarding: personas bloqueadas ANTES que sus leads; tramos al reemplazo en la misma transacción
t = prev['crm.fijar_membresia_activa_fn']
t = rep(t, "  v_evento_objetivo uuid;\n", """  v_evento_objetivo uuid;
  v_flag boolean;                          -- F2.b [D-2]
  v_personas uuid[] := array[]::uuid[];    -- F2.b [D-2]: identidades (no fusionadas) a cargo del saliente
  v_nuevas uuid[] := array[]::uuid[];      -- F2.b [D-2]: las que aparecieron entre el censo y el bloqueo de sus leads
  v_ahora timestamptz;                     -- F2.b [D-2]
""")
# (Codex #3) recenso DESPUÉS de bloquear los leads del saliente (los UPDATE de arriba): una conversión en vuelo sobre uno de
# sus leads (que no toma el interlock de jerarquía) pudo abrir un tramo al saliente tras el censo.
t = rep(t, """      update crm.leads l
      set asignado_supervisor_id = p_reemplazo_id
      where l.asignado_supervisor_id = p_perfil_id
        and l.activo is true and l.etapa not in ('convertido','descartado');
""", f"""      update crm.leads l
      set asignado_supervisor_id = p_reemplazo_id
      where l.asignado_supervisor_id = p_perfil_id
        and l.activo is true and l.etapa not in ('convertido','descartado');

      -- F2.b [D-2] (Codex #3): una conversión en vuelo sobre un lead del saliente (no toma el interlock de jerarquía) pudo
      -- abrir un tramo al saliente DESPUÉS del censo. Con sus leads ya bloqueados por los dos UPDATE de arriba ninguna
      -- conversión suya sigue en vuelo: se repite el censo; lo que apareció se bloquea SIN esperar (persona tras lead es
      -- la arista inversa: si alguien la tiene → 40001, Gerencia reintenta) y se suma al traslado.
      if v_flag then
        begin
          select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_nuevas
          from (select i.id from {PERSONAS_DEL}
                   and not (i.id = any(v_personas))
                 order by i.id
                 for no key update of i nowait) s;
        exception when lock_not_available then
          raise exception 'Una conversión de un lead del saliente sigue en curso; vuelve a intentar la baja'
            using errcode = '40001';
        end;
        if coalesce(pg_catalog.array_length(v_nuevas, 1), 0) > 0 then
          perform 1 from crm.inversionista_responsables r
           where r.inversionista_id = any(v_nuevas) and r.hasta is null
           order by r.id
           for update;
          v_personas := v_personas || v_nuevas;
        end if;
      end if;
""")
t = rep(t, """  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
""", """  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  -- F2.b [D-2]: la bandera se lee BAJO el interlock exclusivo (las puertas de identidad de b5 lo toman compartido).
  v_flag := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
""")
t = rep(t, """    if v_requiere_reemplazo and p_reemplazo_id is null then
      raise exception 'La membresia conserva dependencias; selecciona un reemplazo activo del mismo rol';
    end if;
""", f"""    if v_requiere_reemplazo and p_reemplazo_id is null then
      raise exception 'La membresia conserva dependencias; selecciona un reemplazo activo del mismo rol';
    end if;
    -- F2.b [D-2]: con la identidad encendida nadie se queda sin responsable: si el saliente tiene personas a cargo,
    -- la baja exige reemplazo (mismo mensaje), aunque la bandera cambiara entre la lectura del impacto y esta.
    if v_flag and p_reemplazo_id is null and exists (select 1 from {PERSONAS_DEL}) then
      raise exception 'La membresia conserva dependencias; selecciona un reemplazo activo del mismo rol';
    end if;
""")
t = rep(t, """      update crm.equipo e
      set supervisor_id = p_reemplazo_id
      where e.supervisor_id = p_perfil_id and e.activo is true;
""", f"""      -- F2.b [D-2]: las PERSONAS del saliente (identidades activas con tramo abierto suyo o apuntándole) se bloquean
      -- ANTES que sus leads —la misma arista persona → lead de conversiones y veto; FOR NO KEY UPDATE, que serializa
      -- contra el FOR UPDATE de reasignar/marcar/convertir sin chocar con las FK— y sus tramos abiertos FOR UPDATE.
      if v_flag then
        -- (Codex N2) SIN ESPERAR: el alta de una tarea de cliente toma a la persona y luego a este mismo equipo; esperar
        -- aquí con equipo en la mano sería el abrazo. Si alguien tiene a una persona del saliente → 40001, se reintenta.
        begin
          select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_personas
          from (select i.id from {PERSONAS_DEL}
                 order by i.id
                 for no key update of i nowait) s;
        exception when lock_not_available then
          raise exception 'Una persona a cargo del saliente está siendo actualizada; vuelve a intentar la baja'
            using errcode = '40001';
        end;
        perform 1 from crm.inversionista_responsables r
         where r.inversionista_id = any(v_personas) and r.hasta is null
         order by r.id
         for update;
        -- (auditor M5) y las tareas pendientes del saliente ANTES que sus leads (tareas → leads), la misma disciplina que
        -- el veto (b2/D-3), reasignar y cerrar_tarea: el offboarding iba leads → tareas y podía abrazarse con un veto en
        -- curso sobre una persona que no está «a cargo» del saliente. Solo con la identidad encendida (paridad OFF).
        perform 1 from crm.tareas t
         where t.activo is true and t.estado = 'pendiente'
           and (t.vendedor_id = p_perfil_id or t.asignado_supervisor_id = p_perfil_id
                or t.lead_id in (select l.id from crm.leads l
                                  where (l.vendedor_id = p_perfil_id or l.asignado_supervisor_id = p_perfil_id)
                                    and l.activo is true and l.etapa not in ('convertido', 'descartado')))
         order by t.id
         for update;
      end if;

      update crm.equipo e
      set supervisor_id = p_reemplazo_id
      where e.supervisor_id = p_perfil_id and e.activo is true;
""")
t = rep(t, """      update public.perfiles p
      set asesor_perfil_id = p_reemplazo_id,
          actualizado_en = pg_catalog.clock_timestamp()
      where p.rol = 'cliente' and p.activo is true
        and p.asesor_perfil_id = p_perfil_id;
    end if;
""", """      update public.perfiles p
      set asesor_perfil_id = p_reemplazo_id,
          actualizado_en = pg_catalog.clock_timestamp()
      where p.rol = 'cliente' and p.activo is true
        and p.asesor_perfil_id = p_perfil_id;

      -- F2.b [D-2]: el responsable de relación pasa al reemplazo en la MISMA transacción: se cierra cada tramo abierto
      -- del saliente y se abre otro al reemplazo (motivo 'offboarding', por = Gerencia), y responsable_relacion_id lo
      -- acompaña. Un único v_ahora tomado DESPUÉS de los locks [E3-14]. Con la bandera apagada, nada (paridad).
      if v_flag and coalesce(pg_catalog.array_length(v_personas, 1), 0) > 0 then
        v_ahora := pg_catalog.clock_timestamp();
        update crm.inversionista_responsables r
           set hasta = v_ahora
         where r.inversionista_id = any(v_personas) and r.hasta is null;
        insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
        select s.id, p_reemplazo_id, v_ahora, 'offboarding', v_actor
        from pg_catalog.unnest(v_personas) as s(id);
        update crm.inversionistas i
           set responsable_relacion_id = p_reemplazo_id
         where i.id = any(v_personas);
      end if;
    end if;
""")
t = rep(t, """        'clientes_transferidos', (v_impacto->>'clientes_activos')::integer
      ),
      p_idempotencia
""", """        'clientes_transferidos', (v_impacto->>'clientes_activos')::integer
      ) || case when v_flag then pg_catalog.jsonb_build_object('personas_transferidas', coalesce(pg_catalog.array_length(v_personas, 1), 0)) else '{}'::jsonb end,  -- F2.b [D-2]
      p_idempotencia
""")
nuevo['crm.fijar_membresia_activa_fn'] = t

# ---------------------------------------------------------------- 3. reasignar: capacidad operativa del nuevo responsable
t = prev['crm.reasignar_responsable_relacion_fn']
t = rep(t, "  v_inv crm.inversionistas%rowtype; v_tramo crm.inversionista_responsables%rowtype; v_nuevo_id uuid; v_ahora timestamptz; v_lead crm.leads%rowtype;\n",
"""  v_inv crm.inversionistas%rowtype; v_tramo crm.inversionista_responsables%rowtype; v_nuevo_id uuid; v_ahora timestamptz; v_lead crm.leads%rowtype;
  v_rol_nuevo text; v_leads uuid[] := array[]::uuid[]; v_leads_movidos integer := 0; v_perfil_movido boolean := false; v_tenencia text := 'sin_cambios';  -- F2.b [D-2]
""")
t = rep(t, "  v_ahora := pg_catalog.clock_timestamp();\n", """  -- F2.b [D-2]: capacidad operativa del nuevo responsable. Si puede tener cartera (vendedor/supervisor activo, rol
  -- efectivo), los leads VIVOS en tenencia operativa de la persona (enlace ∪ puente ∪ sueltos con su documento, D-13)
  -- pasan a su cartera y el perfil cliente de la persona también. Orden: persona (ya) → tramo (ya) → tareas
  -- pendientes → leads → perfil, como el veto (b2) y la fusión (b5). Con Gerencia como nuevo responsable no hay
  -- cartera que mover: solo el tramo (tenencia = 'sin_cambios').
  v_rol_nuevo := private.rol_crm(p_nuevo_responsable);
  if v_rol_nuevo in ('vendedor', 'supervisor') then
    select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_leads
    from (select l.id from crm.leads l
           where l.id in (select x from private.leads_de_personas(array[p_inversionista]) x)
             and l.activo = true
             and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
             and (l.vendedor_id is distinct from p_nuevo_responsable or l.asignado_supervisor_id is not null)
           order by l.id) s;
    -- (Codex N1/N4) tampoco se espera por una TAREA ni por el PERFIL: cerrar_tarea tiene la tarea y va tarea → lead/perfil;
    -- el Portal actualiza el perfil y su trigger va perfil → tareas. Con la persona y el tramo en la mano, todo lo demás
    -- se toma SIN esperar → 40001 y Gerencia reintenta.
    begin
      perform 1 from crm.tareas t
       where t.estado = 'pendiente'
         and (t.lead_id = any(v_leads) or (v_inv.perfil_id is not null and t.perfil_id = v_inv.perfil_id))
       order by t.id
       for update nowait;
      if v_inv.perfil_id is not null then
        perform 1 from public.perfiles p where p.id = v_inv.perfil_id for no key update nowait;
      end if;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando una tarea o la ficha de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
    -- (Codex #1) tareas → leads es el orden de b2/D-3 y de cerrar_tarea; derivar y repartir van lead → tareas (por el
    -- trigger de sincronización) bajo el mismo interlock compartido. Como la fusión (b5, E3-9): los leads se toman
    -- SIN esperar; si otra sesión tiene uno → 40001 y Gerencia reintenta.
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
    v_tenencia := 'movida';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
""")
# (Codex #12) el motivo se revalida contra los documentos DESPUÉS de bloquear a la persona (una corrección concurrente pudo cambiarlos).
t = rep(t, "  select * into v_tramo from crm.inversionista_responsables where inversionista_id = p_inversionista and hasta is null for update;\n",
"""  -- F2.b [D-2] (Codex #12): el motivo se revalida contra los documentos BAJO el lock de la persona (la validación de
  -- arriba corre antes del lock y una corrección documental concurrente pudo cambiarlos).
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista));
  select * into v_tramo from crm.inversionista_responsables where inversionista_id = p_inversionista and hasta is null for update;
""")
t = rep(t, "  update crm.inversionistas set responsable_relacion_id = p_nuevo_responsable where id = p_inversionista;\n",
"""  update crm.inversionistas set responsable_relacion_id = p_nuevo_responsable where id = p_inversionista;
  -- F2.b [D-2]: la cartera sigue al responsable (los triggers de leads llevan el ledger de asignaciones, la actividad
  -- «reasignacion», tenencia_desde y las tareas pendientes; el del perfil mueve las tareas de cliente y deja su actividad).
  if v_tenencia = 'movida' then
    if coalesce(pg_catalog.array_length(v_leads, 1), 0) > 0 then
      -- (auditor M2) se REVALIDA bajo los locks: sigue vivo, en etapa abierta y sigue siendo de la persona (un descarte o una
      -- conversión concurrentes solo bloquean el lead; la puerta del DNI de D-13 puede llevarse un suelto a otra persona).
      update crm.leads l
         set vendedor_id = p_nuevo_responsable,
             asignado_supervisor_id = null
       where l.id = any(v_leads)
         and l.activo = true
         and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
         and l.id in (select x from private.leads_de_personas(array[p_inversionista]) x);
      get diagnostics v_leads_movidos = row_count;
    end if;
    if v_inv.perfil_id is not null then
      update public.perfiles p
         set asesor_perfil_id = p_nuevo_responsable,
             actualizado_en = pg_catalog.clock_timestamp()
       where p.id = v_inv.perfil_id and p.rol = 'cliente' and p.activo is true
         and p.asesor_perfil_id is distinct from p_nuevo_responsable;
      v_perfil_movido := found;
    end if;
    -- (auditor N5) «movida» solo si algo se movió de verdad.
    if v_leads_movidos = 0 and not v_perfil_movido then
      v_tenencia := 'sin_cambios';
    end if;
  end if;
""")
t = rep(t, """    'tramo_anterior_id', v_tramo.id, 'tramo_nuevo_id', v_nuevo_id, 'responsable_anterior', v_tramo.responsable_id, 'responsable_nuevo', p_nuevo_responsable);
""", """    'tramo_anterior_id', v_tramo.id, 'tramo_nuevo_id', v_nuevo_id, 'responsable_anterior', v_tramo.responsable_id, 'responsable_nuevo', p_nuevo_responsable,
    'tenencia', pg_catalog.jsonb_build_object('estado', v_tenencia, 'leads_movidos', v_leads_movidos, 'perfil_movido', v_perfil_movido));  -- F2.b [D-2]
""")
nuevo['crm.reasignar_responsable_relacion_fn'] = t

H_PROD = {k: md5(prev[k]) for k in FN}
H_NEW = {k: md5(nuevo[k]) for k in FN}
for k in FN: assert H_NEW[k] != H_PROD[k]

def sel_md5(k):
    ident, args = FN[k]; sch, nom = k.split('.')
    return f"(select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='{sch}' and p.proname='{nom}' and pg_get_function_identity_arguments(p.oid)='{args}')"
GUARD = ''.join(f"""  v_h := {sel_md5(k)};
  if v_h is null then
    raise exception 'F2.b D-2: falta {FN[k][0]}';
  end if;
  if v_h is distinct from '{H_PROD[k]}' and v_h is distinct from '{H_NEW[k]}' then
    raise exception 'F2.b D-2: {FN[k][0]} no es ni el texto vivo de producción ni el de D-2 (%)', v_h;
  end if;
""" for k in FN)
GUARD_LDP = f"""  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.leads_de_personas(uuid[])'::regprocedure) is distinct from '{H_LDP}'
     or not exists (select 1 from pg_proc p where p.oid = 'private.leads_de_personas(uuid[])'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-2: private.leads_de_personas(uuid[]) no es el texto vivo de producción (D-13) o perdió definer/search_path';
  end if;
"""
FLAG_OFF = """  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b D-2: la bandera resolver_en_puertas está ENCENDIDA; este cambio aterriza apagado';
  end if;
"""
POST_BYTE = ''.join(f"""  if {sel_md5(k)} is distinct from '{H_NEW[k]}' then
    raise exception 'POSTFLIGHT D-2: {FN[k][0]} no quedó byte a byte como la genera gen-d2.py';
  end if;
""" for k in FN)
POST_GRANTS = "  if exists (select 1 from unnest(array[" + ','.join("'" + FN[k][0] + "'" for k in FN) + """]) f(firma)
             where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
                or not has_function_privilege('authenticated', f.firma, 'EXECUTE')
                or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f.firma::regprocedure and a.grantee = 0))
     or exists (select 1 from pg_proc p where p.oid in (""" + ','.join("'" + FN[k][0] + "'::regprocedure" for k in FN) + """) and not (p.prosecdef and p.proconfig @> array['search_path=""'])) then
    raise exception 'POSTFLIGHT D-2: los grants (solo authenticated; ni anon, ni service_role, ni PUBLIC) o definer/search_path de las tres cambiaron';
  end if;
"""
def bloque(k, titulo):
    return f"""-- ============================================================================
-- {titulo}
-- ============================================================================
{nuevo[k]}
;

"""
mig = f"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-2] — LA SALIDA DE UN ANALISTA NO DEJA
-- PERSONAS SIN RESPONSABLE, Y EL NUEVO RESPONSABLE RECIBE CAPACIDAD OPERATIVA (bloque 2 del plan, RETOMAR-60 §8)
-- ============================================================================
--
-- QUE (todo en la rama ON; con la bandera apagada las tres funciones responden byte a byte como hoy):
--  · crm.impacto_desactivacion_usuario_fn: cuenta las PERSONAS a cargo del saliente (identidades activas con tramo
--    abierto suyo en crm.inversionista_responsables o responsable_relacion_id) y las suma a requiere_reemplazo; la
--    clave personas_a_cargo aparece SOLO con ON (el front valida con un esquema estricto; bloque 4 la incorpora).
--  · crm.fijar_membresia_activa_fn (offboarding): con reemplazo, bloquea las personas del saliente ANTES que sus leads
--    (FOR NO KEY UPDATE: serializa contra el FOR UPDATE de reasignar/marcar/convertir sin chocar con las FK) y sus
--    tramos abiertos, y en la MISMA transacción cierra cada tramo abierto del saliente y abre otro al reemplazo
--    (motivo 'offboarding'), acompañado de responsable_relacion_id; el evento membresia_desactivada lleva
--    personas_transferidas. Sin reemplazo y con personas a cargo → se niega (mismo mensaje de hoy). Todo bajo el
--    interlock EXCLUSIVO de jerarquía que ya tomaba (las puertas de identidad de b5 lo toman compartido: no se cruzan).
--  · crm.reasignar_responsable_relacion_fn (b5): además del tramo, si el nuevo responsable puede tener cartera
--    (vendedor/supervisor), los leads VIVOS en tenencia operativa de la persona (enlace ∪ puente ∪ sueltos con su
--    documento, private.leads_de_personas de D-13) pasan a su cartera (vendedor_id, sin bandeja; los triggers de leads
--    llevan el ledger de asignaciones, la actividad «reasignacion», tenencia_desde y las tareas pendientes) y el
--    perfil cliente de la persona pasa a su cartera (asesor_perfil_id; el trigger del perfil mueve las tareas de
--    cliente y deja su actividad). Orden: persona → tramo → tareas → leads → perfil. Con Gerencia como nuevo
--    responsable solo cambia el tramo. La respuesta añade `tenencia` {{estado, leads_movidos, perfil_movido}}.
-- Transformadas desde el texto VIVO de producción (scripts/f2b/gen-d2.py + vivas/bloque2/, guardas md5 EXACTAS,
-- postflight byte a byte). Aterriza APAGADA. Ensayo: scripts/oraculo-f2b-d2.sh. Reversa: scripts/rollback-f2b-d2.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.leads_de_personas(uuid[])') is null or to_regprocedure('crm.fusionar_inversionistas_fn(uuid,uuid,text,text)') is null then
    raise exception 'F2.b D-2: falta b5 (20260905120000) o D-13 (20260905160000)';
  end if;
{FLAG_OFF}{GUARD}{GUARD_LDP}end
$guard$;

{bloque('crm.impacto_desactivacion_usuario_fn', '1. crm.impacto_desactivacion_usuario_fn(uuid): las personas a cargo exigen reemplazo (solo con ON)')}{bloque('crm.fijar_membresia_activa_fn', '2. crm.fijar_membresia_activa_fn(...): personas antes que leads; tramos al reemplazo en la misma transacción')}{bloque('crm.reasignar_responsable_relacion_fn', '3. crm.reasignar_responsable_relacion_fn(uuid,uuid,text): capacidad operativa del nuevo responsable')}do $post$
begin
{POST_BYTE}{POST_GRANTS}{GUARD_LDP}  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT D-2: la bandera quedó encendida';
  end if;
  raise notice 'F2.b D-2 OK: offboarding atómico sobre los tramos y capacidad operativa del nuevo responsable (rama ON). Bandera APAGADA.';
end
$post$;
commit;
"""
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')

REV_BYTE = ''.join(f"""  if {sel_md5(k)} is distinct from '{H_PROD[k]}' then
    raise exception 'REVERSA D-2: {FN[k][0]} no volvió byte a byte al vivo de producción';
  end if;
""" for k in FN)
rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-2] ({VER}): restaura byte a byte las 3 funciones vivas de producción y desregistra la versión.
-- Se NIEGA si la bandera está encendida. Repetible dos veces. No deshace tramos ya escritos (append-only con rastro).
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));
do $flags$
begin
  if exists (select 1 from crm.multiempresa_flags where nombre = 'resolver_en_puertas' and activo) then
    raise exception 'REVERSA D-2: la bandera está ENCENDIDA; apágala a propósito antes de revertir';
  end if;
end
$flags$;
do $guard$
declare v_h text;
begin
{GUARD}end
$guard$;

{prev['crm.impacto_desactivacion_usuario_fn']}
;
{prev['crm.fijar_membresia_activa_fn']}
;
{prev['crm.reasignar_responsable_relacion_fn']}
;

do $post$
begin
{REV_BYTE}{POST_GRANTS}  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'REVERSA D-2: la bandera se ENCENDIÓ mientras se revertía; no se confirma la reversa';
  end if;
  delete from supabase_migrations.schema_migrations where version = '{VER}';
  raise notice 'REVERSA F2.b D-2 OK (versión {VER} desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-d2.sql').write_text(rb, encoding='utf-8')
H_MIG = hashlib.md5(mig.encode('utf-8')).hexdigest()
reg = ("-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-2]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.\n"
       "-- Idempotente; toma el MISMO advisory que la migración y la reversa (Codex #13); se niega si la versión ya está registrada con OTRO\n"
       "-- contenido, si las 3 vivas no son las de D-2, si sus grants/definer cambiaron (Codex #14) o con la bandera encendida.\n"
       f"begin;\nselect pg_advisory_xact_lock(hashtext('{ADV}'));\ndo $chk$\nbegin\n"
       + ''.join(f"  if {sel_md5(k)} is distinct from '{H_NEW[k]}' then\n    raise exception 'REGISTRO D-2: {FN[k][0]} VIVA no es el texto de D-2 (aplica la migración ANTES de registrar)';\n  end if;\n" for k in FN)
       + POST_GRANTS.replace('POSTFLIGHT D-2', 'REGISTRO D-2') + GUARD_LDP.replace('F2.b D-2', 'REGISTRO D-2')
       + FLAG_OFF.replace('F2.b D-2: la bandera resolver_en_puertas está ENCENDIDA; este cambio aterriza apagado', 'REGISTRO D-2: la bandera está ENCENDIDA; D-2 aterriza apagada')
       + f"  if exists (select 1 from supabase_migrations.schema_migrations where version='{VER}' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> '{H_MIG}')) then\n"
       f"    raise exception 'REGISTRO D-2: la versión {VER} ya está registrada con otro contenido (o incompleto: Codex N5)';\n  end if;\nend\n$chk$;\n"
       f"insert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('{VER}', '{NAME[len(VER)+1:]}', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n")
(W/'scripts'/'registrar-f2b-d2.sql').write_text(reg, encoding='utf-8')
print('D-2 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; md5 migración', H_MIG)
for k in FN: print(' ', k, 'prod', H_PROD[k], 'D-2', H_NEW[k])

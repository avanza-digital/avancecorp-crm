# gen-d3.py — F2.b prerrequisito de activación [D-3] (bloque 2): el VETO de la persona («No insistir») es COHERENTE
# en todo lo que toca a esa persona con la bandera encendida: tareas de PERFIL (cliente), crm.actividades_cliente y
# leads SUELTOS con su documento (y los del PUENTE). v3 (06/09: auditor M1/M3 + Codex #1/#5/#7/#10/#12/#13/#14).
# Transforma 3 funciones VIVAS de producción (vivas/bloque2/*.sql, md5 en huellas-bloque2-prod.txt) y crea 4 helpers
# privados + 2 triggers. private.trg_gestion_lead_serializada NO se toca (v3: el gate de perfil vive en un trigger propio
# de crm.tareas que además bloquea a la persona; así el trigger compartido con actividades sigue byte a byte).
# Genera la migración 20260906110000, su reversa (byte a byte, suelta lo nuevo, desregistra) y el registro.
# Uso: python3 gen-d3.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
viv = lambda n: (S/'vivas'/'bloque2'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:90], s.count(old)); return s.replace(old, new)
md5 = lambda t: hashlib.md5((t + '\n').encode('utf-8')).hexdigest()
md5s = lambda t: hashlib.md5(t.encode('utf-8')).hexdigest()
prod = {l.split()[0]: l.split()[1] for l in (S/'huellas-bloque2-prod.txt').read_text().splitlines() if l.strip()}
H_LDI = '2421b2b78b02b8e93fd01598e2f54128'   # private.leads_de_identidades(uuid[]) en PROD (b5) = banco
H_GESTION = prod['private.trg_gestion_lead_serializada']  # NO se transforma: el postflight lo exige intacto
ADV = 'crm_f2b_d3_veto_coherente'
VER = '20260906110000'; NAME = f'{VER}_crm_f2b_d3_veto_coherente_perfil_cliente_y_sueltos'
FN = {  # clave -> (identidad, args identidad)
  'crm.marcar_no_contactar': ('crm.marcar_no_contactar(uuid,text)', 'p_lead_id uuid, p_motivo text'),
  'crm.levantar_no_contactar': ('crm.levantar_no_contactar(uuid,text)', 'p_lead_id uuid, p_motivo text'),
  'private.leads_vetados_persona': ('private.leads_vetados_persona(uuid[])', 'p_lead_ids uuid[]'),
}
prev = {k: viv(k) for k in FN}
for k in FN:
    assert md5(prev[k]) == prod[k], (k, md5(prev[k]), prod[k])
nuevo = {}

# ---------------------------------------------------------------- 1. el veto visto desde un lead: también por el PUENTE
t = prev['private.leads_vetados_persona']
t = rep(t, """      l.no_contactar = true
      or coalesce(inv.no_contactar, false)
      or (l.inversionista_id is null
""", """      l.no_contactar = true
      or coalesce(inv.no_contactar, false)
      -- F2.b [D-3]: un lead que está en el PUENTE de una persona vetada (histórico sin enlace vivo) también lo está.
      or exists (select 1
                 from crm.inversionista_leads il
                 join crm.inversionistas p0 on p0.id = il.inversionista_id
                 join crm.inversionistas p  on p.id  = coalesce(p0.inversionista_canonico_id, p0.id)
                 where il.lead_id = l.id and p.no_contactar = true)
      or (l.inversionista_id is null
""")
nuevo['private.leads_vetados_persona'] = t

# ---------------------------------------------------------------- 2. marcar / levantar: puente ∪ enlace ∪ sueltos + tareas de cliente, documento → persona, sin esperar leads
DECL = """  v_suelto boolean := false;  -- F2.b (b2)
"""
DECL_NEW = """  v_suelto boolean := false;  -- F2.b (b2)
  v_puente boolean := false;  -- F2.b [D-3]: la persona se resolvió por el PUENTE (lead histórico sin DNI ni enlace)
  v_leads  uuid[];            -- F2.b [D-3]: enlace vivo ∪ puente ∪ sueltos con su documento, más el propio lead
  v_docs   text[];            -- F2.b [D-3]: documentos vigentes de la persona, bloqueados ANTES que ella (tipo:documento)
  v_perfiles uuid[] := array[]::uuid[];  -- F2.b [D-3]: perfiles cliente de la persona (enlazado o con su documento): tareas de cliente
"""
SUELTO = """  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
"""
SUELTO_NEW = """  if v_flag and v_inv is null then
    -- F2.b [D-3] (Codex #7): un lead que solo está en el PUENTE (histórico sin DNI ni enlace vivo) también es de su
    -- persona: se resuelve por el puente (canónica) antes de intentar el documento. El puente solo cambia bajo el lock
    -- de la persona (fusión), que se toma más abajo y se revalida tras bloquear el lead.
    select private.inversionista_canonica(il.inversionista_id) into v_inv
    from crm.inversionista_leads il
    where il.lead_id = p_lead_id
    order by (il.rol = 'canonico') desc, il.inversionista_id
    limit 1;
    v_puente := v_inv is not null;
  end if;
  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
"""
LOCK = """  if v_inv is not null then
    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;
"""
LOCK_NEW = """  if v_inv is not null then
    -- F2.b [D-3] (auditor M1): DOCUMENTO → PERSONA, el orden del nacimiento (b1), la puerta del DNI (D-13) y la fusión (b5):
    -- se bloquean los documentos vigentes de la persona (en orden de texto) ANTES de bloquearla, y se releen después;
    -- así la puerta del DNI (que solo bloquea documentos y a la persona NUEVA) no puede llevarse un suelto a otra persona
    -- mientras el veto se propaga. Si el juego de documentos cambió mientras se esperaba → 40001.
    v_docs := private.identidad_bloquear_documentos_de(array[v_inv]);
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- La relectura es una LECTURA PURA (Codex N3): no vuelve a tomar candados con la persona ya bloqueada (documento → persona).
    if (select coalesce(pg_catalog.array_agg(s.k order by s.k), '{}'::text[])
          from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
                  from crm.inversionista_identificadores d
                 where d.inversionista_id = v_inv and d.estado = 'vigente') s) is distinct from v_docs then
      raise exception 'Los documentos de la persona cambiaron mientras se marcaba; vuelve a intentarlo'
        using errcode = '40001';
    end if;
    -- F2.b [D-3] (Codex #12): el motivo no lleva NINGÚN documento de la persona (vigentes ni históricos; la regla documental
    -- de las puertas de b5, sin imponer aquí su largo mínimo: el motivo de marcar es opcional).
    if p_motivo is not null and exists (
         select 1 from crm.inversionista_identificadores d
          where d.inversionista_id = v_inv
            and pg_catalog.length(d.documento_normalizado) >= 6
            and pg_catalog.strpos(pg_catalog.upper(pg_catalog.regexp_replace(p_motivo, '[^A-Za-z0-9]', '', 'g')), d.documento_normalizado) > 0) then
      raise exception 'El motivo no debe contener el número de documento' using errcode = '22023';
    end if;
  end if;
  -- F2.b [D-3]: bajo los locks de documentos y persona, «sus leads» = enlace vivo ∪ puente ∪ sueltos con su documento
  -- verificado (private.leads_de_persona_veto) más el propio lead; y sus perfiles cliente (el enlazado a la identidad o
  -- el que lleva su documento exacto, como persona_vetada_perfil) para las tareas de cliente. Estable hasta el commit.
  if v_inv is not null then
    v_leads := array(select x from private.leads_de_persona_veto(v_inv) x union select p_lead_id order by 1);
    v_perfiles := array(
      select i.perfil_id from crm.inversionistas i where i.id = v_inv and i.perfil_id is not null
      union
      select p.id from public.perfiles p
       where p.rol = 'cliente'
         and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
         and (coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') || ':' || pg_catalog.upper(pg_catalog.regexp_replace(p.dni, '[^A-Za-z0-9]', '', 'g'))) = any(v_docs)
      order by 1);
  else
    v_leads := array[p_lead_id];
  end if;
"""
NOWAIT = """  -- F2.b [D-3] (Codex #1): tareas → leads es el orden de b2 y de cerrar_tarea; derivar y repartir van al revés (lead →
  -- tareas por el trigger de sincronización). Como la fusión (b5, E3-9): los leads se toman SIN esperar; si otra sesión
  -- tiene uno, 40001 y el front reintenta. Solo con la bandera (con OFF no hay tareas bloqueadas: el propio lead se toma como hoy).
  if v_flag then
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
  end if;
"""
LOOP = """      select * from crm.leads where inversionista_id = v_inv order by id for update
"""
LOOP_NEW = """      select * from crm.leads where id = any(v_leads) order by id for update  -- F2.b [D-3]: enlace ∪ puente ∪ sueltos
"""
TAREAS = """t.lead_id in (select l.id from crm.leads l
                          where l.id = p_lead_id or (v_inv is not null and l.inversionista_id = v_inv))"""
TAREAS_NEW = """(t.lead_id = any(v_leads)  /* F2.b [D-3]: enlace ∪ puente ∪ sueltos, y también las tareas de CLIENTE */
            or t.perfil_id = any(v_perfiles))"""
# revalidación tras bloquear el propio lead: la rama del PUENTE tiene su propia comprobación
REVAL_M = """  if v_flag and not v_suelto and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
"""
REVAL_M_NEW = """  if v_flag and not v_suelto and not v_puente and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_puente
     and (v_lead.inversionista_id is not null
          or not exists (select 1 from crm.inversionista_leads il
                         where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) = v_inv)) then
    raise exception 'El puente del lead cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
"""
REVAL_L = REVAL_M.replace('se marcaba', 'se levantaba'); REVAL_L_NEW = REVAL_M_NEW.replace('se marcaba', 'se levantaba')

t = prev['crm.marcar_no_contactar']
t = rep(t, DECL, DECL_NEW); t = rep(t, SUELTO, SUELTO_NEW); t = rep(t, LOCK, LOCK_NEW); t = rep(t, LOOP, LOOP_NEW); t = rep(t, TAREAS, TAREAS_NEW, 2)
t = rep(t, REVAL_M, REVAL_M_NEW)
# (Codex N1/N4) tampoco se espera por una TAREA: cerrar_tarea la tiene y puede ir tarea → persona (siguiente tarea de perfil) o tarea → lead.
t = rep(t, """  if v_flag then
    perform 1 from crm.tareas t
     where t.estado = 'pendiente'
       and """ + TAREAS_NEW + """
     order by t.id
     for update;
  end if;

  select * into v_lead
""", """  if v_flag then
    begin
      perform 1 from crm.tareas t
       where t.estado = 'pendiente'
         and """ + TAREAS_NEW + """
       order by t.id
       for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está cerrando una tarea de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
  end if;
""" + NOWAIT + """
  select * into v_lead
""")
nuevo['crm.marcar_no_contactar'] = t
t = prev['crm.levantar_no_contactar']
t = rep(t, DECL, DECL_NEW); t = rep(t, SUELTO, SUELTO_NEW); t = rep(t, LOCK, LOCK_NEW); t = rep(t, LOOP, LOOP_NEW)
t = rep(t, REVAL_L, REVAL_L_NEW)
t = rep(t, "  select * into v_lead from crm.leads where id = p_lead_id for update;\n", NOWAIT + "  select * into v_lead from crm.leads where id = p_lead_id for update;\n")
nuevo['crm.levantar_no_contactar'] = t

H_PROD = {k: md5(prev[k]) for k in FN}
H_NEW = {k: md5(nuevo[k]) for k in FN}
for k in FN: assert H_NEW[k] != H_PROD[k]

# ---------------------------------------------------------------- 3. objetos nuevos (cuerpos con md5 de prosrc para registrador y postflight)
CUERPOS = {
'private.leads_de_persona_veto(uuid)': ('sql', 'setof uuid', 'stable security definer', """
  -- F2.b [D-3]: los leads que heredan el VETO de una persona = enlace vivo ∪ puente (private.leads_de_identidades, b5)
  -- ∪ SUELTOS con su documento (DNI vigente y verificado, sin enlace), en cualquier etapa: el veto es de la persona.
  select x from private.leads_de_identidades(array[p_inv]) x
  union
  select l.id
  from crm.leads l
  join crm.inversionista_identificadores d
    on d.tipo_documento = 'DNI' and d.estado = 'vigente' and d.verificado = true and d.documento_normalizado = l.dni
  where d.inversionista_id = p_inv
    and l.inversionista_id is null
"""),
'private.persona_vetada_perfil(uuid)': ('sql', 'boolean', 'stable security definer', """
  -- F2.b [D-3]: el veto de la PERSONA visto desde un perfil cliente (tareas de cliente, actividades_cliente): por el
  -- enlace perfil↔identidad (canónica) o por el documento exacto del perfil (identificador vigente y verificado).
  -- Con la bandera apagada es siempre false (paridad con hoy).
  select coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and (
       exists (select 1
               from crm.inversionistas i0
               join crm.inversionistas i on i.id = coalesce(i0.inversionista_canonico_id, i0.id)
               where i0.perfil_id = p_perfil_id and i0.estado <> 'fusionado' and i.no_contactar = true)
       or exists (select 1
                  from public.perfiles p
                  join crm.inversionista_identificadores idf
                    on idf.tipo_documento = coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI')
                   and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p.dni, ''), '[^A-Za-z0-9]', '', 'g'))
                   and idf.estado = 'vigente' and idf.verificado = true
                  join crm.inversionistas i on i.id = idf.inversionista_id
                  where p.id = p_perfil_id
                    and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
                    and i.estado <> 'fusionado' and i.no_contactar = true)
     )
"""),
'private.personas_de_perfil(uuid)': ('sql', 'setof uuid', 'stable security definer', """
  -- F2.b [D-3]: las identidades (canónicas, no fusionadas) de un perfil cliente: por el enlace o por su documento exacto.
  select coalesce(i0.inversionista_canonico_id, i0.id)
  from crm.inversionistas i0
  where i0.perfil_id = p_perfil_id and i0.estado <> 'fusionado'
  union
  select coalesce(i.inversionista_canonico_id, i.id)
  from public.perfiles p
  join crm.inversionista_identificadores idf
    on idf.tipo_documento = coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI')
   and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p.dni, ''), '[^A-Za-z0-9]', '', 'g'))
   and idf.estado = 'vigente' and idf.verificado = true
  join crm.inversionistas i on i.id = idf.inversionista_id
  where p.id = p_perfil_id
    and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
    and i.estado <> 'fusionado'
"""),
'private.trg_tareas_veto_persona_perfil()': ('plpgsql', 'trigger', 'security definer', """
declare
  v_personas uuid[];
begin
  -- F2.b [D-3] (v3/v4, Codex #5/#10/N1): la tarea de PERFIL (cliente) respeta el veto de la PERSONA (contrato §7.3) igual
  -- que la de lead, en un trigger propio de crm.tareas (el trigger de gestión compartido con actividades sigue byte a byte).
  -- Corre ANTES que el resto (00_0): toma a las personas del perfil FOR SHARE —persona → perfil, el orden de reasignar—
  -- SIN ESPERAR: si alguien las tiene (veto, fusión, reasignación, baja) → 40001 y se reintenta (nunca se espera con una
  -- tarea en la mano: cerrar_tarea agenda la siguiente con la tarea bloqueada y marcar espera esa tarea con la persona
  -- bloqueada). Después revalida que lo bloqueado siga siendo lo actual (una fusión pudo mover el perfil de persona).
  -- Writers internos (auth.uid NULL) y la válvula quedan fuera, como en leads.
  if (select auth.uid()) is null
     or new.lead_id is not null or new.perfil_id is null
     or coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  v_personas := array(select x from private.personas_de_perfil(new.perfil_id) x order by 1);
  begin
    perform 1 from crm.inversionistas i where i.id = any(v_personas) order by i.id for share nowait;
  exception when lock_not_available then
    raise exception 'La persona del cliente está siendo actualizada (veto, fusión o reasignación); vuelve a intentarlo'
      using errcode = '40001';
  end;
  if array(select x from private.personas_de_perfil(new.perfil_id) x order by 1) is distinct from v_personas then
    raise exception 'La persona del cliente cambió mientras se agendaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if private.persona_vetada_perfil(new.perfil_id) then
    raise exception '%: no se registra seguimiento', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;
  return new;
end;
"""),
'private.trg_actividades_cliente_veto_persona()': ('plpgsql', 'trigger', 'security definer', """
begin
  -- F2.b [D-3]: el veto de la persona bloquea el SEGUIMIENTO también en la ficha del cliente (contrato §7.3): los tipos
  -- de CONTACTO. Notas y reasignaciones entran. Writers internos (auth.uid NULL) y la válvula quedan fuera, como en leads.
  if (select auth.uid()) is null
     or coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     or new.tipo not in ('llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada') then
    return new;
  end if;
  if private.persona_vetada_perfil(new.cliente_id) then
    raise exception '%: no se registra seguimiento', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;
  return new;
end;
"""),
}
ARGN = {'private.leads_de_persona_veto(uuid)': 'p_inv uuid', 'private.persona_vetada_perfil(uuid)': 'p_perfil_id uuid', 'private.personas_de_perfil(uuid)': 'p_perfil_id uuid',
        'private.trg_tareas_veto_persona_perfil()': '', 'private.trg_actividades_cliente_veto_persona()': ''}
H_BODY = {k: md5s(v[3]) for k, v in CUERPOS.items()}
def crea(k):
    lang, ret, attrs, body = CUERPOS[k]; nombre = k.split('(')[0]
    return f"""create or replace function {nombre}({ARGN[k]})
 returns {ret}
 language {lang}
 {attrs}
 set search_path to ''
as $function${body}$function$;
revoke all on function {k} from public, anon, authenticated, service_role;
"""
DEF_TRG_T = "CREATE TRIGGER trg_tareas_00_0_veto_persona BEFORE INSERT ON crm.tareas FOR EACH ROW EXECUTE FUNCTION private.trg_tareas_veto_persona_perfil()"
DEF_TRG_A = "CREATE TRIGGER trg_actividades_cliente_01_veto_persona BEFORE INSERT ON crm.actividades_cliente FOR EACH ROW EXECUTE FUNCTION private.trg_actividades_cliente_veto_persona()"
NUEVOS = """-- ============================================================================
-- 0. Helpers privados nuevos (definer, search_path vacío, sin EXECUTE para la API) y los dos triggers
-- ============================================================================
""" + ''.join(crea(k) + '\n' for k in CUERPOS) + f"""drop trigger if exists trg_tareas_00_0_veto_persona on crm.tareas;
create trigger trg_tareas_00_0_veto_persona
  before insert on crm.tareas
  for each row execute function private.trg_tareas_veto_persona_perfil();
drop trigger if exists trg_actividades_cliente_01_veto_persona on crm.actividades_cliente;
create trigger trg_actividades_cliente_01_veto_persona
  before insert on crm.actividades_cliente
  for each row execute function private.trg_actividades_cliente_veto_persona();
"""

def sel_md5(k):
    ident, args = FN[k]; sch, nom = k.split('.')
    return f"(select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='{sch}' and p.proname='{nom}' and pg_get_function_identity_arguments(p.oid)='{args}')"
GUARD = ''.join(f"""  v_h := {sel_md5(k)};
  if v_h is null then
    raise exception 'F2.b D-3: falta {FN[k][0]}';
  end if;
  if v_h is distinct from '{H_PROD[k]}' and v_h is distinct from '{H_NEW[k]}' then
    raise exception 'F2.b D-3: {FN[k][0]} no es ni el texto vivo de producción ni el de D-3 (%)', v_h;
  end if;
""" for k in FN)
GUARD_FIJAS = f"""  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.leads_de_identidades(uuid[])'::regprocedure) is distinct from '{H_LDI}'
     or not exists (select 1 from pg_proc p where p.oid = 'private.leads_de_identidades(uuid[])'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-3: private.leads_de_identidades(uuid[]) no es el texto vivo de producción (b5) o perdió definer/search_path';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.trg_gestion_lead_serializada()'::regprocedure) is distinct from '{H_GESTION}' then
    raise exception 'F2.b D-3: private.trg_gestion_lead_serializada() no es el texto vivo de producción (D-3 v3 NO la toca)';
  end if;
  if to_regprocedure('private.identidad_bloquear_documentos_de(uuid[])') is null or to_regprocedure('private.inversionista_canonica(uuid)') is null then
    raise exception 'F2.b D-3: faltan private.identidad_bloquear_documentos_de (D-13) o private.inversionista_canonica (b5)';
  end if;
"""
FLAG_OFF = """  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b D-3: la bandera resolver_en_puertas está ENCENDIDA; este cambio aterriza apagado';
  end if;
"""
POST_BYTE = ''.join(f"""  if {sel_md5(k)} is distinct from '{H_NEW[k]}' then
    raise exception 'POSTFLIGHT D-3: {FN[k][0]} no quedó byte a byte como la genera gen-d3.py';
  end if;
""" for k in FN)
POST_OBJ = ''.join(f"""  if not exists (select 1 from pg_proc p where p.oid = '{k}'::regprocedure and p.prosecdef and p.proconfig = array['search_path=""'] and md5(p.prosrc) = '{H_BODY[k]}') then
    raise exception 'POSTFLIGHT D-3: {k} falta, su configuración no es exactamente definer + search_path vacío (Codex #14) o su cuerpo no es el de D-3';
  end if;
""" for k in CUERPOS) + f"""  if exists (select 1 from unnest(array['anon','authenticated','service_role']) r(rol), unnest(array['{"','".join(CUERPOS)}']) f(firma) where has_function_privilege(r.rol, f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ({','.join("'" + k + "'::regprocedure" for k in CUERPOS)}) and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-3: un helper privado quedó con EXECUTE para la API o PUBLIC';
  end if;
  if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.tareas'::regclass and t.tgname = 'trg_tareas_00_0_veto_persona' and not t.tgisinternal and t.tgenabled in ('O','A')) is distinct from '{DEF_TRG_T}'
     or (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.actividades_cliente'::regclass and t.tgname = 'trg_actividades_cliente_01_veto_persona' and not t.tgisinternal and t.tgenabled in ('O','A')) is distinct from '{DEF_TRG_A}' then
    raise exception 'POSTFLIGHT D-3: un trigger de D-3 no está montado tal cual o está deshabilitado';
  end if;
"""
POST_GRANTS = """  if exists (select 1 from unnest(array['crm.marcar_no_contactar(uuid,text)','crm.levantar_no_contactar(uuid,text)']) f(firma)
             where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
                or not has_function_privilege('authenticated', f.firma, 'EXECUTE')
                or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f.firma::regprocedure and a.grantee = 0))
     or exists (select 1 from unnest(array['anon','authenticated','service_role']) r(rol)
                where has_function_privilege(r.rol, 'private.leads_vetados_persona(uuid[])', 'EXECUTE')) then
    raise exception 'POSTFLIGHT D-3: los grants de marcar/levantar (solo authenticated) o del helper cambiaron';
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
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-3] — EL VETO DE LA PERSONA ES COHERENTE:
-- TAREAS DE PERFIL, FICHA DEL CLIENTE (actividades_cliente) Y LEADS SUELTOS/PUENTE CON SU DOCUMENTO (bloque 2) — v3
-- ============================================================================
--
-- QUE (contrato §7.3, «No insistir» es de la PERSONA; todo en la rama ON, con OFF nada cambia):
--  · Tareas de PERFIL (cliente): trigger propio BEFORE INSERT en crm.tareas (00_0, corre primero): con la bandera
--    encendida y fuera de la válvula bloquea a la persona del perfil FOR SHARE (persona → perfil) y rechaza la tarea
--    si la persona está vetada (P0429), por el enlace perfil↔identidad o por el documento exacto del perfil.
--    private.trg_gestion_lead_serializada (compartido con actividades) queda byte a byte (v3).
--  · Ficha del cliente: trigger BEFORE INSERT en crm.actividades_cliente: contacto de una persona vetada → P0429;
--    notas y reasignaciones entran; writers internos y válvula exentos.
--  · marcar_no_contactar / levantar_no_contactar: la persona se resuelve por enlace, por el PUENTE (lead histórico sin
--    DNI) o por documento; DOCUMENTO → PERSONA (los documentos vigentes se bloquean antes que la persona y se releen:
--    40001 si cambiaron); «sus leads» = enlace ∪ puente ∪ sueltos con DNI vigente y verificado, más el propio;
--    los leads se toman SIN esperar (40001 si otra sesión tiene uno: derivar/repartir van lead → tareas); marcar veta
--    a todos y cancela sus tareas pendientes —incluidas las de CLIENTE de los perfiles de la persona (enlazado o por
--    documento)—; levantar los levanta; el motivo no puede llevar el documento.
--  · private.leads_vetados_persona (gate por lead) ve además el PUENTE.
-- Transformadas desde el texto VIVO de producción (scripts/f2b/gen-d3.py + vivas/bloque2/, guardas md5 EXACTAS,
-- postflight byte a byte). Aterriza APAGADA. Ensayo: scripts/oraculo-f2b-d3.sh. Reversa: scripts/rollback-f2b-d3.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.leads_vetados_persona(uuid[])') is null or to_regprocedure('private.leads_de_identidades(uuid[])') is null then
    raise exception 'F2.b D-3: falta b2 (20260904130000) o b5 (20260905120000)';
  end if;
{FLAG_OFF}{GUARD}{GUARD_FIJAS}end
$guard$;

{NUEVOS}
{bloque('private.leads_vetados_persona', '1. private.leads_vetados_persona(uuid[]): el veto visto desde un lead cuenta el PUENTE')}{bloque('crm.marcar_no_contactar', '2. crm.marcar_no_contactar(uuid,text): puente ∪ enlace ∪ sueltos + tareas de cliente, documento → persona, sin esperar leads')}{bloque('crm.levantar_no_contactar', '3. crm.levantar_no_contactar(uuid,text): el mismo conjunto')}do $post$
begin
{POST_BYTE}{POST_OBJ}{POST_GRANTS}{GUARD_FIJAS}  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT D-3: la bandera quedó encendida';
  end if;
  raise notice 'F2.b D-3 OK (v3): veto coherente en tareas de perfil, ficha del cliente y leads sueltos/puente (rama ON). Bandera APAGADA.';
end
$post$;
commit;
"""
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')

REV_BYTE = ''.join(f"""  if {sel_md5(k)} is distinct from '{H_PROD[k]}' then
    raise exception 'REVERSA D-3: {FN[k][0]} no volvió byte a byte al vivo de producción';
  end if;
""" for k in FN)
rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-3] ({VER}, v3): restaura byte a byte las 3 funciones vivas de producción, suelta los 2 triggers y los
-- 5 helpers, desregistra la versión. Se NIEGA si la bandera está encendida. Repetible dos veces.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));
do $flags$
begin
  if exists (select 1 from crm.multiempresa_flags where nombre = 'resolver_en_puertas' and activo) then
    raise exception 'REVERSA D-3: la bandera está ENCENDIDA; apágala a propósito antes de revertir';
  end if;
end
$flags$;
do $guard$
declare v_h text;
begin
{GUARD}end
$guard$;

{prev['private.leads_vetados_persona']}
;
{prev['crm.marcar_no_contactar']}
;
{prev['crm.levantar_no_contactar']}
;
drop trigger if exists trg_tareas_00_0_veto_persona on crm.tareas;
drop trigger if exists trg_actividades_cliente_01_veto_persona on crm.actividades_cliente;
drop function if exists private.trg_tareas_veto_persona_perfil();
drop function if exists private.trg_actividades_cliente_veto_persona();
drop function if exists private.personas_de_perfil(uuid);
drop function if exists private.persona_vetada_perfil(uuid);
drop function if exists private.leads_de_persona_veto(uuid);

do $post$
begin
{REV_BYTE}{POST_GRANTS}  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'REVERSA D-3: la bandera se ENCENDIÓ mientras se revertía; no se confirma la reversa';
  end if;
  delete from supabase_migrations.schema_migrations where version = '{VER}';
  raise notice 'REVERSA F2.b D-3 OK (versión {VER} desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-d3.sql').write_text(rb, encoding='utf-8')
H_MIG = hashlib.md5(mig.encode('utf-8')).hexdigest()
reg = ("-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-3]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.\n"
       "-- Idempotente; toma el MISMO advisory que la migración y la reversa (Codex #13); se niega si la versión ya está registrada con OTRO\n"
       "-- contenido, si las 3 vivas no son las de D-3, si falta un objeto nuevo (cuerpo, definer, grants, trigger habilitado) o con la bandera encendida.\n"
       f"begin;\nselect pg_advisory_xact_lock(hashtext('{ADV}'));\ndo $chk$\nbegin\n"
       + ''.join(f"  if {sel_md5(k)} is distinct from '{H_NEW[k]}' then\n    raise exception 'REGISTRO D-3: {FN[k][0]} VIVA no es el texto de D-3 (aplica la migración ANTES de registrar)';\n  end if;\n" for k in FN)
       + POST_OBJ.replace('POSTFLIGHT D-3', 'REGISTRO D-3') + POST_GRANTS.replace('POSTFLIGHT D-3', 'REGISTRO D-3') + GUARD_FIJAS.replace('F2.b D-3', 'REGISTRO D-3')
       + FLAG_OFF.replace('F2.b D-3: la bandera resolver_en_puertas está ENCENDIDA; este cambio aterriza apagado', 'REGISTRO D-3: la bandera está ENCENDIDA; D-3 aterriza apagada')
       + f"  if exists (select 1 from supabase_migrations.schema_migrations where version='{VER}' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> '{H_MIG}')) then\n"
       f"    raise exception 'REGISTRO D-3: la versión {VER} ya está registrada con otro contenido (o incompleto: Codex N5)';\n  end if;\nend\n$chk$;\n"
       f"insert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('{VER}', '{NAME[len(VER)+1:]}', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n")
(W/'scripts'/'registrar-f2b-d3.sql').write_text(reg, encoding='utf-8')
print('D-3 v3 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; md5 migración', H_MIG)
for k in FN: print(' ', k, 'prod', H_PROD[k], 'D-3', H_NEW[k])
for k in CUERPOS: print('  cuerpo', k, H_BODY[k])

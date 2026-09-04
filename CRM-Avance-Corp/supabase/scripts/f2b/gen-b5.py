# gen-b5.py — F2.b E3 = b5. Genera la migración 20260905120000, su reversa y el registro
# TRANSFORMANDO el texto VIVO de producción (vivas/e3/*.sql, md5 en huellas-e3-prod.txt).
# Uso: python3 gen-b5.py <dir scripts/f2b> <dir supabase>   (nuevos.sql al lado de este archivo)
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
viv = lambda n: (S/'vivas'/'e3'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:80], s.count(old)); return s.replace(old, new)
prod = {}
for line in open(S/'huellas-e3-prod.txt', encoding='utf-8'):
    if line.strip():
        k, v = line.rsplit(' ', 1); prod[k.strip()] = v.strip()
def h(name):
    calc = hashlib.md5(open(S/'vivas'/'e3'/f'{name}.sql','rb').read()[:-1]).hexdigest()
    assert prod[name] == calc, (name, prod[name], calc); return prod[name]
for n in ('crm.convertir_lead','crm.convertir_lead_externo','crm.saga_conversion_fn','private.trg_leads_disponibilidad_atomica'):
    h(n)

# ── T1 crm.convertir_lead ─────────────────────────────────────────────────────────────────
cl_prev = viv('crm.convertir_lead')
cl = rep(cl_prev, """    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;
""", """    perform 1 from crm.inversionistas where id = v_inv for update;
    -- F2.b (b5) [Cx-15, E3-1]: una fusión pudo ganar mientras se esperaba este lock: la
    -- perdedora ya no convierte. Sin advisory documental AQUÍ a propósito: tomarlo después
    -- de la identidad invertiría el orden documento -> identidad que sigue la fusión.
    if exists (select 1 from crm.inversionistas i where i.id = v_inv and i.estado = 'fusionado') then
      raise exception 'La persona fue fusionada mientras se convertía; vuelve a intentarlo'
        using errcode = '40001';
    end if;
  end if;
""")
cl = rep(cl, """    if v_prev is not null then
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
""", """    if v_prev is not null then
      -- F2.b (b5) [E3-12]: el resultado guardado se conserva; la identidad se proyecta por su canónica.
      return v_prev || pg_catalog.jsonb_build_object('reintento', true,
        'inversionista_id', private.inversionista_canonica((v_prev->>'inversionista_id')::uuid));
    end if;
""", n=2)
cl = rep(cl, """      v_res := pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'perfil_id', p_perfil_id,
                                             'inversionista_id', v_lead.inversionista_id);""",
"""      v_res := pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'perfil_id', p_perfil_id,
                                             'inversionista_id', private.inversionista_canonica(v_lead.inversionista_id));""")
cl = rep(cl, """    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
""", """    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento de un perfil
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
""")

# ── T2 crm.convertir_lead_externo (texto de b4) ───────────────────────────────────────────
cle_prev = viv('crm.convertir_lead_externo')
cle = rep(cle_prev, """    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
""", """    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento del cierre
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cierre: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
""")

# ── T3 crm.saga_conversion_fn (texto de b4): documento ANTES de identidad en 'cerrar' ─────
saga_prev = viv('crm.saga_conversion_fn')
saga = rep(saga_prev, "  v_claim uuid; v_loc record; v_res jsonb; v_perfil uuid; v_lead uuid; v_inv_conv uuid;\n",
                      "  v_claim uuid; v_loc record; v_res jsonb; v_perfil uuid; v_lead uuid; v_inv_conv uuid; v_tipo text; v_doc text;\n")
saga = rep(saga, """    -- Veto revalidado también al cerrar (Codex E2 #11): con veto, la conversión no se consuma.
    perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
""", """    -- F2.b (b5) [E3-1]: documento ANTES de identidad (la fusión toma documento -> identidad;
    -- convertir_lead resolverá este mismo documento, reentrante).
    select coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI'), p.dni into v_tipo, v_doc
      from public.perfiles p where p.id = v_perfil;
    if v_doc is null then
      raise exception 'Saga: el perfil del claim no existe o no tiene documento' using errcode = 'P0409';
    end if;
    perform private.identidad_bloquear_documento(v_tipo, v_doc);
    -- Veto revalidado también al cerrar (Codex E2 #11): con veto, la conversión no se consuma.
    perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
""")

# ── T4 private.trg_leads_disponibilidad_atomica: excepción estrecha bajo válvula ─────────
trg_prev = viv('private.trg_leads_disponibilidad_atomica')
trg = rep(trg_prev, "  v_descartado_por text;\nbegin\n",
                    "  v_descartado_por text;\n  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);\nbegin\n")
trg = rep(trg, """    if not v_cambio_identidad or v_actor is null then
      return new;
    end if;
""", """    -- F2.b (b5) [E3-6]: la corrección de documento de Gerencia (RPC definer bajo válvula)
    -- cambia SOLO el DNI de un lead que conserva su persona; los terceros (otra identidad,
    -- otro cliente del Portal, otro lead vivo) ya los comprobó la RPC bajo sus locks. Ningún
    -- otro escritor bajo válvula cambia el DNI; fuera de esta forma exacta nada cambia.
    if v_priv and new.dni is distinct from old.dni and new.telefono is not distinct from old.telefono
       and old.inversionista_id is not null and new.inversionista_id = old.inversionista_id then
      return new;
    end if;
    if not v_cambio_identidad or v_actor is null then
      return new;
    end if;
""")

NUEVOS = (S/'b5-nuevos.sql').read_text(encoding='utf-8') if (S/'b5-nuevos.sql').exists() else '-- {{NUEVOS pendientes}}\n'
NUEVAS_FN = [  # (regprocedure, grant authenticated?) — se sueltan en la reversa
  ('private.inversionista_canonica(uuid)', False),
  ('private.fusion_estado_jsonb(uuid,uuid)', False),
  ('private.fusion_bloqueos(uuid,uuid)', False),
  ('private.identidad_bloquear_documentos_de(uuid[])', False),
  ('private.cancelar_tareas_pendientes_lead(uuid)', False),
  ('private.motivo_sin_documento(text,text[])', False),
  ('crm.fusion_previsualizar_fn(uuid,uuid)', True),
  ('crm.fusionar_inversionistas_fn(uuid,uuid,text,text)', True),
  ('crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)', True),
  ('crm.enlazar_lead_inversionista_fn(uuid,uuid,text)', True),
  ('crm.reasignar_responsable_relacion_fn(uuid,uuid,text)', True),
]
def guard_md5(fn_sql_name, ident_args, hkey):
    schema, name = fn_sql_name.split('.')
    return f"""  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='{schema}' and p.proname='{name}' and pg_get_function_identity_arguments(p.oid) = '{ident_args}';
  if v_h <> '{h(hkey)}' and (select strpos(p.prosrc,'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='{schema}' and p.proname='{name}' and pg_get_function_identity_arguments(p.oid) = '{ident_args}') = 0 then
    raise exception 'F2.b b5: {fn_sql_name} no es el texto vivo esperado (%)', v_h;
  end if;
"""
IA = {
 'crm.convertir_lead': 'p_lead_id uuid, p_perfil_id uuid',
 'crm.convertir_lead_externo': 'p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text',
 'crm.saga_conversion_fn': 'p_paso text, p_payload jsonb',
 'private.trg_leads_disponibilidad_atomica': '',
}
guards = ''.join(guard_md5(k, IA[k], k) for k in IA)

mig = r"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b sub-lote b5 (E3) — FUSIÓN DE IDENTIDADES, CORRECCIÓN
-- DOCUMENTAL, ENLACE DE LEAD SUELTO Y REASIGNACIÓN DEL RESPONSABLE (solo Gerencia)
-- ============================================================================
--
-- QUE (contrato §4.4, §6, invariantes #6/#8/#9/#19): las puertas de Gerencia que hoy no existen.
--   * crm.fusion_previsualizar_fn(perdedora, canonica): foto + huella + bloqueos/advertencias (solo lectura).
--   * crm.fusionar_inversionistas_fn(perdedora, canonica, motivo, hash): matriz de colisiones completa
--     (perfil, veto OR con tareas, responsable, identificadores reemitidos, lead y puente, cierres,
--     inversiones y titulares, reservas, predecesoras aplanadas), libro append-only, perdedora NUNCA borrada.
--     Alcance acotado hasta F5: como máximo un lead y un perfil entre las dos.
--   * crm.corregir_documento_inversionista_fn(...): el vigente pasa a histórico, nuevo vigente verificado,
--     realinea perfil y lead SOLO si llevaban el documento reemplazado; motivo en crm.inversionista_correcciones.
--   * crm.enlazar_lead_inversionista_fn(lead, inversionista, motivo): la revisión humana de la clase E.
--   * crm.reasignar_responsable_relacion_fn(inversionista, nuevo, motivo): cierra/abre tramo; no mueve atribuciones.
-- Y cuatro funciones VIVAS transformadas SOLO en su rama ON (guarda md5 del texto de producción):
--   convertir_lead (revalida fusión tras el lock [E3-1]; persona del lead manda [E3-11]; proyección canónica
--   en reintentos [E3-12]), convertir_lead_externo ([E3-11]), saga_conversion_fn ('cerrar': documento antes de
--   identidad [E3-1]) y trg_leads_disponibilidad_atomica (excepción estrecha bajo válvula para la corrección [E3-6]).
-- Orden total de b5: jerarquía -> documentos -> identidades -> perfil -> cierres -> inversiones/titulares ->
-- tramos -> tareas -> lead -> reservas -> claims -> contactos (por trigger).
-- TODO detrás de la bandera; RPC nuevas inertes (P0409) con la bandera apagada.
-- Reversa: scripts/rollback-f2b-b5.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b5_fusion_correccion_reasignacion'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('crm.saga_conversion_fn(text,jsonb)') is null
     or to_regprocedure('crm.alta_cliente_identidad_fn(text,jsonb)') is null
     or to_regprocedure('private.identidad_bloquear_documento(text,text)') is null
     or to_regprocedure('private.inversionista_por_documento(text,text)') is null
     or to_regprocedure('private.persona_vetada(uuid)') is null
     or to_regclass('crm.inversionista_fusiones') is null then
    raise exception 'F2.b b5: falta E1 o E2 (20260904120000..20260905110000)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false)
     or coalesce((select activo from crm.multiempresa_flags where nombre='inversiones_escritura'), false) then
    raise exception 'F2.b b5: alguna bandera está ENCENDIDA; este lote aterriza apagado';
  end if;
{{GUARDS}}end
$guard$;

-- ============================================================================
-- 1. Funciones VIVAS transformadas (rama ON; OFF byte a byte)
-- ============================================================================
{{CL}}
;

{{CLE}}
;

{{SAGA}}
;

{{TRG}}
;

-- ============================================================================
-- 2. Objetos nuevos: tabla de correcciones, helpers privados y las 5 puertas de Gerencia
-- ============================================================================
{{NUEVOS}}

do $post$
begin
{{POST_EXISTS}}
  if (select strpos(p.prosrc, 'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead') = 0
     or (select strpos(p.prosrc, 'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead_externo') = 0
     or (select strpos(p.prosrc, 'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='saga_conversion_fn') = 0
     or (select strpos(p.prosrc, 'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='trg_leads_disponibilidad_atomica') = 0 then
    raise exception 'POSTFLIGHT b5: transformaciones ausentes';
  end if;
{{POST_GRANTS}}
  if to_regclass('crm.inversionista_correcciones') is null
     or not (select relrowsecurity from pg_class where oid = 'crm.inversionista_correcciones'::regclass)
     or has_table_privilege('authenticated', 'crm.inversionista_correcciones', 'SELECT')
     or has_table_privilege('service_role', 'crm.inversionista_correcciones', 'SELECT') then
    raise exception 'POSTFLIGHT b5: tabla de correcciones sin RLS o con grants';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT b5: la bandera quedó encendida';
  end if;
  raise notice 'F2.b b5 OK: fusión, corrección documental, enlace de lead suelto y reasignación (Gerencia); 4 vivas transformadas en su rama ON. Bandera APAGADA.';
end
$post$;
commit;
"""
post_exists = "  if " + "\n     or ".join(f"to_regprocedure('{r}') is null" for r,_ in NUEVAS_FN + [('private.inversionista_correcciones_append_only()', False)]) + " then\n    raise exception 'POSTFLIGHT b5: falta alguna función nueva';\n  end if;\n"
post_grants = "  if " + "\n     or ".join(
    ([f"has_function_privilege('anon', '{r}', 'EXECUTE')", f"has_function_privilege('service_role', '{r}', 'EXECUTE')"] +
     ([f"not has_function_privilege('authenticated', '{r}', 'EXECUTE')"] if g else [f"has_function_privilege('authenticated', '{r}', 'EXECUTE')"]))[0]
    for r,g in NUEVAS_FN) + "\n     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (" + ", ".join(f"'{r}'::regprocedure" for r,_ in NUEVAS_FN) + ") and a.grantee = 0) then\n    raise exception 'POSTFLIGHT b5: grants incorrectos';\n  end if;\n"
# grants: cada función nueva se comprueba completa (anon/service_role fuera; authenticated según corresponda; nunca PUBLIC)
post_grants = "  if " + "\n     or ".join(
    f"has_function_privilege('anon', '{r}', 'EXECUTE') or has_function_privilege('service_role', '{r}', 'EXECUTE') or " +
    (f"not has_function_privilege('authenticated', '{r}', 'EXECUTE')" if g else f"has_function_privilege('authenticated', '{r}', 'EXECUTE')")
    for r,g in NUEVAS_FN) + "\n     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in (" + ", ".join(f"'{r}'::regprocedure" for r,_ in NUEVAS_FN) + ") and a.grantee = 0) then\n    raise exception 'POSTFLIGHT b5: grants incorrectos';\n  end if;\n"
mig = mig.replace("{{GUARDS}}", guards).replace("{{CL}}", cl).replace("{{CLE}}", cle).replace("{{SAGA}}", saga).replace("{{TRG}}", trg).replace("{{NUEVOS}}", NUEVOS).replace("{{POST_EXISTS}}", post_exists).replace("{{POST_GRANTS}}", post_grants)
(W/'migrations'/'20260905120000_crm_f2b_b5_fusion_correccion_reasignacion.sql').write_text(mig, encoding='utf-8')

rb = r"""-- ============================================================================
-- REVERSA de F2.b sub-lote b5 (20260905120000_crm_f2b_b5_fusion_correccion_reasignacion)
-- ============================================================================
-- Suelta las 5 RPC de Gerencia y los 2 helpers, restaura byte a byte las 4 funciones vivas (md5
-- contra el vivo de producción). CONSERVA crm.inversionista_correcciones (tabla aditiva con hechos) y no
-- deshace fusiones/correcciones/enlaces/tramos (append-only con rastro; coherentes sin las funciones).
-- Bandera APAGADA. Repetible dos veces.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b5_reversa'));
update crm.multiempresa_flags set activo = false, actualizado_en = now()
  where nombre in ('resolver_en_puertas','inversiones_escritura') and activo = true;

{{DROPS}}
{{CL_PREV}}
;

{{CLE_PREV}}
;

{{SAGA_PREV}}
;

{{TRG_PREV}}
;

do $post$
begin
  if {{POST_GONE}} then
    raise exception 'REVERSA b5: quedó alguna función del lote';
  end if;
{{POST_MD5}}
  raise notice 'REVERSA F2.b b5 OK (crm.inversionista_correcciones se conserva)';
end
$post$;
commit;
"""
drops = "\n".join(f"drop function if exists {r};" for r,_ in reversed(NUEVAS_FN)) + "\n"
post_gone = "\n     or ".join(f"to_regprocedure('{r}') is not null" for r,_ in NUEVAS_FN)
def md5_check(k):
    schema, name = k.split('.')
    return f"""  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='{schema}' and p.proname='{name}' and pg_get_function_identity_arguments(p.oid)='{IA[k]}') <> '{h(k)}' then
    raise exception 'REVERSA b5: {k} no volvió byte a byte al vivo de producción';
  end if;
"""
post_md5 = ''.join(md5_check(k) for k in IA)
rb = rb.replace("{{DROPS}}", drops).replace("{{CL_PREV}}", cl_prev).replace("{{CLE_PREV}}", cle_prev).replace("{{SAGA_PREV}}", saga_prev).replace("{{TRG_PREV}}", trg_prev).replace("{{POST_GONE}}", post_gone).replace("{{POST_MD5}}", post_md5)
(W/'scripts'/'rollback-f2b-b5.sql').write_text(rb, encoding='utf-8')

reg = "-- REGISTRO en supabase_migrations.schema_migrations de F2.b E3 (b5). `db query --linked --file` NO registra:\n-- correr ESTE archivo DESPUÉS de aplicar la migración. Un elemento = el fichero entero. Idempotente.\nbegin;\ninsert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('20260905120000', 'crm_f2b_b5_fusion_correccion_reasignacion', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n"
(W/'scripts'/'registrar-f2b-e3.sql').write_text(reg, encoding='utf-8')
print('b5 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; registro', len(reg.splitlines()))

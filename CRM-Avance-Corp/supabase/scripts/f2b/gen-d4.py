# gen-d4.py — F2.b prerrequisito de activación [D-4] (bloque 3): el IMPORTADOR entra por una puerta SQL.
# El edge crm-importar-leads (filas de la hoja de Google, service_role) INSERTA hoy directo en crm.leads y adivina el
# veredicto parseando errores (P0481/P0429/23505). La puerta nueva crm.importar_lead_fn(jsonb) toma los candados en el
# orden total del front (documento → persona → contactos), hace el MISMO INSERT (el contrato del importador es el de la
# fila al nacer sin sesión humana: sin veredicto comercial; mandan el índice único y, con ON, los triggers de identidad)
# y convierte 23505/P0481/P0429 en un VEREDICTO
# ({resultado: importado|duplicado|ya_cliente|rechazado, veredicto, lead_id, reingreso}); si está libre inserta la fila
# con el mismo payload del edge (creado_por null, alta_manual false). Con la identidad encendida, «ya es cliente» por
# identidad registra el reingreso en su lead (crm.registrar_reingreso_lead_fn, b1) dentro de la misma llamada.
# No transforma ninguna función viva: solo CREA la puerta (solo service_role) y sus guardas. Sin bandera propia: con
# resolver_en_puertas apagada responde exactamente lo que hoy da el INSERT directo (los helpers de identidad no toman
# nada y el verificador no mira la identidad). Genera la migración 20260906130000, su reversa (DROP) y el registro.
# Uso: python3 gen-d4.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
md5s = lambda t: hashlib.md5(t.encode('utf-8')).hexdigest()
ADV = 'crm_f2b_d4_importador_por_puerta'
VER = '20260906130000'; NAME = f'{VER}_crm_f2b_d4_importador_por_puerta_sql'
# Huellas de PROD (06/09) de lo que la puerta reutiliza (= banco); la guarda exige que sigan siendo esas.
H = {
  'private.verificar_disponibilidad_lead_impl(text,text)': '742d44ff',   # delega en la de 3 args (D-13 v4.4)
  'private.verificar_disponibilidad_lead_impl(text,text,uuid)': '4a2d7b8b',
  'private.bloquear_contactos_lead(text[],text[])': '0d52f58c',
  'private.identidad_bloquear_documento(text,text)': '96de62e3',
  'private.identidad_bloquear_persona(text,text)': 'b0ebfdb9',
  'crm.registrar_reingreso_lead_fn(uuid,text,jsonb)': '7acc82d8',
  'private.leads_de_personas(uuid[])': '6eded477',
  'private.inversionista_por_documento(text,text)': None,               # solo existencia
  'private.normalizar_telefono(text)': '00c30277',
}
FIRMA = 'crm.importar_lead_fn(jsonb)'
BODY = """
declare
  v_id         uuid := pg_catalog.gen_random_uuid();
  v_nombre     text := nullif(pg_catalog.btrim(p_fila->>'nombre_completo'), '');
  v_telefono   text := private.normalizar_telefono(p_fila->>'telefono');
  v_alt        text := nullif(pg_catalog.btrim(p_fila->>'telefono_alternativo'), '');
  v_alt_crudo  text := nullif(pg_catalog.btrim(p_fila->>'telefono_alternativo_crudo'), '');
  v_correo     text := nullif(pg_catalog.btrim(p_fila->>'correo'), '');
  v_dni        text := nullif(pg_catalog.btrim(p_fila->>'dni'), '');
  v_genero     text := nullif(pg_catalog.btrim(p_fila->>'genero'), '');
  v_fecha      date := nullif(pg_catalog.btrim(p_fila->>'fecha_nacimiento'), '')::date;
  v_distrito   text := nullif(pg_catalog.btrim(p_fila->>'distrito'), '');
  v_origen     text := nullif(pg_catalog.btrim(p_fila->>'origen'), '');
  v_monto      numeric := nullif(pg_catalog.btrim(p_fila->>'monto_estimado'), '')::numeric;
  v_moneda     text := nullif(pg_catalog.btrim(p_fila->>'moneda'), '');
  v_categoria  text := nullif(pg_catalog.btrim(p_fila->>'categoria_interes'), '');
  v_nota       text := nullif(pg_catalog.btrim(p_fila->>'nota'), '');
  v_cons_en    timestamptz := nullif(pg_catalog.btrim(p_fila->>'consentimiento_en'), '')::timestamptz;
  v_cons_fuente text := nullif(pg_catalog.btrim(p_fila->>'consentimiento_fuente'), '');
  v_vendedor   uuid := nullif(pg_catalog.btrim(p_fila->>'vendedor_id'), '')::uuid;
  v_detalle    text;
  v_veredicto  jsonb;
  v_resultado  text;
  v_lead       uuid;
  v_reingreso  jsonb;
begin
  -- F2.b [D-4]: solo el importador (service_role, sin sesión de usuario), la misma regla que registrar_reingreso_lead_fn.
  if (select auth.uid()) is not null then
    raise exception 'Solo el importador (service_role) usa esta puerta' using errcode = '42501';
  end if;
  if p_fila is null or pg_catalog.jsonb_typeof(p_fila) <> 'object' then
    raise exception 'Fila invalida' using errcode = '22023';
  end if;
  -- Lo mismo que hoy exige la fila al nacer (trigger de disponibilidad, CHECKs), dicho antes y con el mismo texto.
  if v_nombre is null then
    raise exception 'El nombre es obligatorio' using errcode = '22023';
  end if;
  if v_telefono is null or v_telefono !~ '^\\+519[0-9]{8}$' then
    raise exception 'Telefono invalido' using errcode = '22023';
  end if;
  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception 'DNI invalido' using errcode = '22023';
  end if;
  if v_origen is null then
    raise exception 'Origen invalido' using errcode = '22023';
  end if;
  if v_monto is null or v_monto <= 0 then
    raise exception 'Capital estimado invalido' using errcode = '22023';
  end if;
  if v_moneda is null or v_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda invalida' using errcode = '22023';
  end if;

  -- Orden TOTAL de candados (b1/D-13, el de crm.crear_lead_si_disponible): documento → persona → contactos → fila.
  -- Hoy el INSERT directo toma los contactos DENTRO del trigger (fila → contactos, [v2-2]); aquí van antes. Los
  -- triggers de nacimiento los vuelven a tomar (reentrantes, misma transacción). Con la bandera apagada los dos
  -- de identidad no toman nada.
  perform private.identidad_bloquear_documento('DNI', v_dni);
  perform private.identidad_bloquear_persona('DNI', v_dni);
  perform private.bloquear_contactos_lead(array[v_telefono], array[v_dni]);

  -- El CONTRATO del importador es el de la fila al nacer sin sesión humana (trigger de disponibilidad: «un escritor
  -- interno se serializa pero conserva su contrato especializado»): NO se consulta la disponibilidad comercial
  -- (enfriamiento, ficha de cliente, «no insistir» de un lead viejo) —el cliente que vuelve por la hoja es el mejor
  -- lead posible—; sí mandan el índice único de teléfono VIVO (duplicado) y, con la identidad encendida, los triggers
  -- de nacimiento: 000 (la persona vetada → P0429) y zz (la persona ya tiene lead o está en conversión → P0481 por
  -- identidad). Por eso la puerta hace el MISMO INSERT (payload exacto del edge: sin sesión, cola global, alta_manual
  -- por defecto) y convierte esos tres resultados en un veredicto en vez de una excepción.
  begin
    insert into crm.leads (
      id, nombre_completo, telefono, telefono_alternativo, telefono_alternativo_crudo, correo, dni, genero,
      fecha_nacimiento, distrito, origen, etapa, monto_estimado, moneda, categoria_interes, nota, no_contactar,
      consentimiento_en, consentimiento_fuente, vendedor_id, asignado_supervisor_id, activo, creado_por
    ) values (
      v_id, v_nombre, v_telefono, v_alt, v_alt_crudo, v_correo, v_dni, v_genero,
      v_fecha, v_distrito, v_origen, 'nuevo', v_monto, v_moneda, v_categoria, v_nota, false,
      v_cons_en, v_cons_fuente, v_vendedor, null, true, null
    );
    return pg_catalog.jsonb_build_object('resultado', 'importado', 'lead_id', v_id, 'veredicto', null, 'reingreso', null);
  exception
    when unique_violation then
      -- uq_leads_telefono_vivo (o uq_leads_dni_vivo): ya hay un lead VIVO con ese contacto → DUPLICADO (hoy: 23505).
      get stacked diagnostics v_detalle = pg_exception_detail;
      v_veredicto := pg_catalog.jsonb_build_object('estado', 'duplicado', 'detalle', pg_catalog.left(coalesce(v_detalle, ''), 200));
      v_resultado := 'duplicado';
    when sqlstate 'P0481' then
      -- «Contacto no disponible» con el veredicto en DETAIL (hoy lo parsea el edge): ya_es_cliente por identidad
      -- (con lead_id) o en conversión → ya_cliente; cualquier otro → rechazado.
      get stacked diagnostics v_detalle = pg_exception_detail;
      begin
        v_veredicto := v_detalle::jsonb;
      exception when others then
        v_veredicto := pg_catalog.jsonb_build_object('estado', 'no_disponible', 'detalle', pg_catalog.left(coalesce(v_detalle, ''), 200));
      end;
      v_resultado := case when v_veredicto->>'estado' = 'ya_es_cliente' and v_veredicto->>'via' = 'identidad' then 'ya_cliente' else 'rechazado' end;
    when sqlstate 'P0429' then
      -- La persona tiene «No insistir» (trigger 000, identidad encendida) → RECHAZADO (hoy: P0429).
      get stacked diagnostics v_detalle = pg_exception_detail;
      begin
        v_veredicto := coalesce(nullif(v_detalle, '')::jsonb, pg_catalog.jsonb_build_object('estado', 'no_contactar'));
      exception when others then
        v_veredicto := pg_catalog.jsonb_build_object('estado', 'no_contactar');
      end;
      v_resultado := 'rechazado';
  end;

  v_lead := nullif(v_veredicto->>'lead_id', '')::uuid;
  if v_resultado = 'ya_cliente' and v_lead is not null then
    -- El reingreso en la MISMA transacción (hoy el edge lo pedía aparte tras leer el error). Si fallara, la fila sigue
    -- siendo «ya cliente» y el edge lo dice en la hoja, como hoy.
    begin
      v_reingreso := crm.registrar_reingreso_lead_fn(v_lead, 'hoja', pg_catalog.jsonb_build_object(
        'fila', p_fila->'fila', 'nombre', v_nombre, 'telefono', v_telefono, 'telefono_alternativo', v_alt,
        'correo', v_correo, 'capital', v_monto, 'moneda', v_moneda, 'canal', v_origen, 'distrito', v_distrito,
        'interes', v_categoria, 'nota', v_nota));
    exception when others then
      v_reingreso := pg_catalog.jsonb_build_object('ok', false, 'error', sqlstate || ': ' || pg_catalog.left(sqlerrm, 120));
    end;
  end if;

  return pg_catalog.jsonb_build_object('resultado', v_resultado, 'lead_id', v_lead, 'veredicto', v_veredicto, 'reingreso', v_reingreso);
end;
"""
H_BODY = md5s(BODY)
CREA = f"""create or replace function crm.importar_lead_fn(p_fila jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
 set lock_timeout to '5s'
as $function${BODY}$function$;
revoke all on function {FIRMA} from public, anon, authenticated;
grant execute on function {FIRMA} to service_role;
comment on function crm.importar_lead_fn(jsonb) is 'F2.b [D-4]: puerta SQL del importador (solo service_role). Una fila de la hoja → veredicto {{resultado, lead_id, veredicto, reingreso}}; inserta si está libre con los candados en el orden total del front.';
"""
GUARD_DEPS = ''.join(
  (f"""  if to_regprocedure('{k}') is null then
    raise exception 'F2.b D-4: falta {k}';
  end if;
""" if v is None else f"""  if to_regprocedure('{k}') is null or left(md5(pg_get_functiondef('{k}'::regprocedure)), 8) <> '{v}' then
    raise exception 'F2.b D-4: {k} falta o no es el texto vivo de producción (esperado {v}…)';
  end if;
""") for k, v in H.items())
POST = f"""  if not exists (select 1 from pg_proc p where p.oid = '{FIRMA}'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and md5(p.prosrc) = '{H_BODY}') then
    raise exception 'POSTFLIGHT D-4: crm.importar_lead_fn no quedó como la genera gen-d4.py (cuerpo, definer, search_path, lock_timeout)';
  end if;
  if not has_function_privilege('service_role', '{FIRMA}', 'EXECUTE')
     or has_function_privilege('anon', '{FIRMA}', 'EXECUTE')
     or has_function_privilege('authenticated', '{FIRMA}', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = '{FIRMA}'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-4: los grants de la puerta no son «solo service_role»';
  end if;
"""
mig = f"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-4] — EL IMPORTADOR ENTRA POR UNA PUERTA SQL
-- (bloque 3 del plan de activación, RETOMAR-60 §8)
-- ============================================================================
--
-- QUE: el edge crm-importar-leads (las filas de la hoja de Google, cada 5 minutos, con service_role) INSERTA hoy directo
-- en crm.leads y adivina el veredicto parseando los errores del INSERT (P0481 con el veredicto en DETAIL, P0429, 23505).
-- Los leads del front entran por crm.crear_lead_si_disponible: candados en el orden TOTAL (documento → persona →
-- contactos → fila) y un veredicto único del mismo verificador. Esta puerta hace lo mismo para el importador:
--   crm.importar_lead_fn(p_fila jsonb) → {{resultado, lead_id, veredicto, reingreso}}   (SOLO service_role, sin sesión)
--   · resultado = importado (insertó, mismo payload del edge) | duplicado (lead vivo con ese teléfono/DNI) |
--     ya_cliente (persona reconocida por identidad, bandera encendida; anota el REINGRESO en su lead en la misma
--     transacción vía crm.registrar_reingreso_lead_fn) | rechazado (enfriamiento, reutilizable, no_contactar,
--     ya_es_cliente por perfil con la bandera apagada…), con el veredicto íntegro para que la hoja reciba el mismo texto.
--   · Con resolver_en_puertas APAGADA responde exactamente lo que hoy produce el INSERT directo: los candados de
--     identidad no toman nada y el verificador no mira la identidad. No hay bandera propia: la puerta es inerte hasta
--     que el edge la llame (fase 2 del bloque 3, deploy aparte).
-- No transforma ninguna función viva. Guardas: huellas de los helpers que reutiliza; postflight: cuerpo, definer,
-- search_path, lock_timeout y grants. Ensayo: scripts/oraculo-f2b-d4.sh (INSERT directo vs puerta, fila a fila, OFF y ON).
-- Reversa: scripts/rollback-f2b-d4.sql (DROP). Registro: scripts/registrar-f2b-d4.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));

do $guard$
begin
{GUARD_DEPS}end
$guard$;

-- ============================================================================
-- 1. crm.importar_lead_fn(jsonb): la puerta del importador
-- ============================================================================
{CREA}
do $post$
begin
{POST}  raise notice 'F2.b D-4 OK: crm.importar_lead_fn creada (solo service_role); inerte hasta que el edge la llame.';
end
$post$;
commit;
"""
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')
rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-4] ({VER}): suelta crm.importar_lead_fn y desregistra la versión. Repetible dos veces.
-- Antes de revertir, el edge crm-importar-leads debe estar en la versión que INSERTA directo (fase 2 deshecha).
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));
drop function if exists crm.importar_lead_fn(jsonb);
do $post$
begin
  if to_regprocedure('{FIRMA}') is not null then
    raise exception 'REVERSA D-4: la puerta sigue existiendo';
  end if;
  delete from supabase_migrations.schema_migrations where version = '{VER}';
  raise notice 'REVERSA F2.b D-4 OK (versión {VER} desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-d4.sql').write_text(rb, encoding='utf-8')
H_MIG = hashlib.md5(mig.encode('utf-8')).hexdigest()
reg = ("-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-4]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.\n"
       "-- Idempotente; toma el MISMO advisory que la migración y la reversa; exige la puerta con su cuerpo, definer, search_path,\n"
       "-- lock_timeout y grants exactos, los helpers vivos que reutiliza, y se niega si la versión ya está registrada con OTRO contenido.\n"
       f"begin;\nselect pg_advisory_xact_lock(hashtext('{ADV}'));\ndo $chk$\nbegin\n"
       + POST.replace('POSTFLIGHT D-4', 'REGISTRO D-4') + GUARD_DEPS.replace('F2.b D-4', 'REGISTRO D-4')
       + f"  if exists (select 1 from supabase_migrations.schema_migrations where version='{VER}' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> '{H_MIG}')) then\n"
       f"    raise exception 'REGISTRO D-4: la versión {VER} ya está registrada con otro contenido (o incompleto)';\n  end if;\nend\n$chk$;\n"
       f"insert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('{VER}', '{NAME[len(VER)+1:]}', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n")
(W/'scripts'/'registrar-f2b-d4.sql').write_text(reg, encoding='utf-8')
print('D-4 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; md5 migración', H_MIG, '; cuerpo', H_BODY)

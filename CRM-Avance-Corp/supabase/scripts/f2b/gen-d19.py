# gen-d19.py — F2.b [D-19]: TODA escritura lee la bandera bajo el candado del encendido.
#
# El problema (Codex sobre D-17, 06/09): el cambio de bandera no es instantáneo para quien ya está dentro. D-5 creó el
# trigger que serializa el UPDATE de `resolver_en_puertas` contra el candado consultivo `crm_flag_resolver_en_puertas`
# (EXCLUSIVO en el encendido) y las puertas de leads lo toman en COMPARTIDO antes de leerla; D-17 hizo lo mismo con el
# veto y la conversión en cooperativa. Pero el censo del 06/09 dejaba 18 funciones que ESCRIBEN y leían la bandera sin
# ese candado. Contraejemplo de Codex: `crm.convertir_lead` captura OFF, espera por el lead, se confirma ON, y sigue
# omitiendo su rama de identidad. El «drenaje» del script de encendido NO cierra eso: una llamada puede empezar después
# del recuento y antes del UPDATE, y no ve una edge entre dos operaciones SQL.
#
# La transformación es UNA por función: la lectura en línea de la bandera pasa a `private.resolver_en_puertas_bajo_candado()`,
# que (1) exige READ COMMITTED, (2) toma el compartido y (3) lee la bandera bajo él. Un solo sitio define el invariante
# «leer la bandera implica tener su candado», y el valor leído ya no puede cambiar en lo que queda de transacción.
#
# Uso: python3 gen-d19.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
md5s = lambda s: hashlib.md5(s.encode('utf-8')).hexdigest()
VER = '20260906200000'
NAME = f'{VER}_crm_f2b_d19_toda_escritura_lee_la_bandera_bajo_su_candado'
ADV = 'crm_f2b_d19_bandera_bajo_candado'
HELPER = 'private.resolver_en_puertas_bajo_candado()'

H = [l.rstrip('\n').split('\t') for l in (S/'huellas-d19-prod.txt').read_text().splitlines() if l.strip() and not l.startswith('#')]
A = {l.split('\t')[0]: l.rstrip('\n').split('\t') for l in (S/'atributos-d19-prod.txt').read_text().splitlines() if l.strip() and not l.startswith('#')}

# Las DOS formas en que hoy se lee la bandera en línea (una sola vez por función; el generador lo comprueba).
FORMAS = ["coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)",
          "coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false)"]

T = {}   # clave -> (texto_prod, texto_nuevo, firma, md5_prosrc_prod, md5_prosrc_nuevo)
LECTURAS = {}
for key, firma, md5def, md5src in H:
    prev = (S/'vivas'/'d19'/f'{key}.sql').read_text(encoding='utf-8')
    assert md5s(prev) == md5def, f'{key}: el volcado no coincide con la huella de producción'
    n = sum(prev.count(f) for f in FORMAS)
    assert n >= 1, f'{key}: no se encontró la lectura en línea de la bandera'
    LECTURAS[key] = n
    new = prev
    for f in FORMAS: new = new.replace(f, HELPER)
    assert new != prev
    if key == 'crm.fijar_membresia_activa_fn':
        # Auditor D-19 M1: tomaba el interlock EXCLUSIVO de jerarquía y SOLO DESPUÉS leía la bandera, al revés que
        # todas las demás. Con el exclusivo del encendido encolado eso cierra un ciclo blando. Se pone la lectura
        # (y por tanto el candado de la bandera) ANTES del interlock: orden global BANDERA → JERARQUÍA → documento
        # → persona → lead. El motivo original de D-2 (leer bajo el interlock) ya no aplica: la bandera tiene candado propio.
        viejo = ('''  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  -- F2.b [D-2]: la bandera se lee BAJO el interlock exclusivo (las puertas de identidad de b5 lo toman compartido).
  v_flag := ''' + HELPER + ';')
        nuevo = ('''  -- F2.b [D-19] (auditor M1): primero el candado de la BANDERA, después el interlock de jerarquía. El orden global
  -- es BANDERA → JERARQUÍA → documento → persona → lead; invertirlo aquí encolaba un ciclo blando con el encendido.
  v_flag := ''' + HELPER + ''';
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );''')
        assert new.count(viejo) == 1, 'M1: no se encontró el bloque del interlock'
        new = new.replace(viejo, nuevo)
    body = lambda t: t.split('AS $function$', 1)[1].rsplit('$function$', 1)[0]
    T[key] = (prev.rstrip('\n'), new.rstrip('\n'), firma, md5src, md5s(body(new)))

def q(s): return s.replace("'", "''")

GUARD = ''.join(f"""  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('{firma}')), '') not in ('{h0}', '{h1}') then
    raise exception 'F2.b D-19: {firma} no es ni el texto vivo de producción ({h0[:8]}…) ni el de D-19; no se pisa a ciegas';
  end if;
""" for key, (prev, new, firma, h0, h1) in T.items())

POST = ''.join(f"""  if not exists (select 1 from pg_proc p where p.oid = '{firma}'::regprocedure
                  and md5(p.prosrc) = '{h1}'
                  and p.prosecdef = {A[key][1]} and p.proowner = '{A[key][3]}'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = '{q(A[key][2])}'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = '{q(A[key][5])}') then
    raise exception 'POSTFLIGHT D-19: {firma} no quedó como se esperaba (cuerpo, definer, dueño, config o permisos)';
  end if;
""" for key, (prev, new, firma, h0, h1) in T.items())

PRE_RB = ''.join(f"""  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('{firma}')), '') not in ('{h1}', '{h0}') then
    raise exception 'REVERSA D-19: {firma} no es ni el texto de D-19 ni el vivo de producción; no se pisa a ciegas';
  end if;
""" for key, (prev, new, firma, h0, h1) in T.items())

POST_RB = ''.join(f"""  if not exists (select 1 from pg_proc p where p.oid = '{firma}'::regprocedure
                  and md5(p.prosrc) = '{h0}'
                  and p.prosecdef = {A[key][1]} and p.proowner = '{A[key][3]}'::regrole
                  and coalesce(array_to_string(p.proconfig, ','), '') = '{q(A[key][2])}'
                  and coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ',' order by a.grantee::regrole::text||a.privilege_type) from aclexplode(p.proacl) a), 'null') = '{q(A[key][5])}') then
    raise exception 'REVERSA D-19: {firma} no volvió byte a byte a producción (cuerpo, definer, dueño, config o permisos)';
  end if;
""" for key, (prev, new, firma, h0, h1) in T.items())

FLAG_GUARD = lambda tag, extra: f"""  -- La bandera se lee bajo el MISMO candado compartido que usan las puertas: esta migración corre como `postgres`, así
  -- que el drenaje del script de encendido no la ve; sin el candado, un encendido confirmado entre esta lectura y el
  -- CREATE OR REPLACE dejaría aterrizar el lote con la bandera ya encendida.
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  if not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas') then
    raise exception '{tag}: no existe la bandera resolver_en_puertas (¿F1 aplicada?)';
  end if;
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception '{tag}: la bandera resolver_en_puertas está ENCENDIDA; {extra}';
  end if;
"""

HELPER_DDL = """create or replace function private.resolver_en_puertas_bajo_candado()
returns boolean
language plpgsql
volatile
security definer
set search_path to ''
as $function$
declare
  v_aisl text := pg_catalog.current_setting('transaction_isolation');
begin
  -- F2.b [D-19]. Un solo sitio para el invariante «leer la bandera implica tener su candado».
  -- 1) READ COMMITTED obligatorio: bajo REPEATABLE READ o SERIALIZABLE la transacción vería una foto anterior al
  --    encendido aunque el candado la hubiese hecho esperar, que es justo el error que esto viene a impedir.
  if v_aisl <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', v_aisl
      using errcode = '0A000';
  end if;
  -- 2) El COMPARTIDO del encendido. Es de transacción: una vez tomado, el valor no puede cambiar hasta el commit, y
  --    el UPDATE de la bandera (que toma el EXCLUSIVO por el trigger de D-5) espera a que esta llamada termine.
  --    Reentrante: tomarlo dos veces en la misma transacción no cuesta nada.
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  -- 3) Y ahora sí, el valor.
  return coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
end;
$function$;
alter function private.resolver_en_puertas_bajo_candado() owner to postgres;
revoke all on function private.resolver_en_puertas_bajo_candado() from public;
-- Sin GRANT a authenticated a propósito: las 18 que la llaman son SECURITY DEFINER de `postgres`, así que la ejecutan
-- como su dueño. Si algún día la llama una función INVOKER, ese día se le da el permiso y se dice por qué.
"""

CENSO = """  -- EL invariante, en su forma TOTAL: NINGUNA función puede leer `resolver_en_puertas` sin tener su candado. Ya no
  -- se distingue entre escritoras y lectoras —el auditor y Codex mostraron que la distinción era falsa: un disparador
  -- BEFORE escribe con `new.<col> := …` sin decir «update», y un ayudante «de solo lectura» como `persona_vetada_perfil`
  -- gobierna lo que un disparador deja pasar—. La única exención es una LISTA BLANCA explícita de las puertas que ya
  -- toman el candado EN LÍNEA desde D-5/D-13/D-15/D-17, más el propio ayudante. Cualquier función nueva que lea la
  -- bandera sin llamarlo pone esto en rojo el mismo día.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname in ('crm','private','public')
         and pg_catalog.strpos(p.prosrc, 'resolver_en_puertas') > 0
         and pg_catalog.strpos(p.prosrc, 'resolver_en_puertas_bajo_candado') = 0
         and (n.nspname || '.' || p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')') <> all (array[
      'crm.abandonar_conversion_gerencia_fn(uuid, text)',
      'crm.convertir_lead_externo(uuid, text, numeric, text, text, text, text, text, text, date, text)',
      'crm.editar_lead_fn(uuid, jsonb)',
      'crm.fijar_dni_lead_fn(uuid, text)',
      'crm.levantar_no_contactar(uuid, text)',
      'crm.marcar_efectos_conversion(uuid, uuid, text)',
      'crm.marcar_efectos_conversion(uuid)',
      'crm.marcar_no_contactar(uuid, text)',
      'crm.reabrir_lead_fn(uuid)',
      'crm.rescatar_descartes(uuid[], uuid[], boolean)',
      'crm.reservar_conversion_lead(uuid)',
      'crm.retomar_conversion_gerencia_fn(uuid)',
      'crm.tomar_lead_libre(text, text)',
      'private.deshacer_descarte_implementacion(uuid)',
      -- El propio ayudante: es quien SOSTIENE el candado. Entra en la lista porque el criterio es TEXTUAL y su
      -- comentario dice «el UPDATE de la bandera», que el patrón de escritura confunde con una escritura de verdad.
      -- Vale como recordatorio de que este censo es un centinela de texto, no un análisis del flujo.
      'private.resolver_en_puertas_bajo_candado()'])) <> 0 then
    raise exception 'POSTFLIGHT D-19: sigue habiendo funciones que leen la bandera sin su candado compartido';
  end if;
"""

mig = f"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-19] — NADIE QUE ESCRIBA LEE LA BANDERA
-- SIN SU CANDADO (el último ítem de código antes del `!` que enciende la identidad unificada)
--
-- Por qué. D-5 puso el trigger que serializa el UPDATE de `resolver_en_puertas` contra el candado consultivo
-- `crm_flag_resolver_en_puertas` (EXCLUSIVO al encender) y transformó las puertas de leads para tomarlo en COMPARTIDO
-- antes de leerla; D-17 hizo lo mismo con el veto y la conversión en cooperativa. Quedaban {len(T)} funciones que
-- ESCRIBEN y leían la bandera sin ese candado: podían capturar «apagada», tardar en sus candados de negocio y escribir
-- con el criterio viejo cuando el resto del CRM ya juzga con la identidad unificada. El drenaje del script de encendido
-- NO cierra ese hueco (una llamada puede empezar después del recuento y antes del UPDATE), así que esto es requisito
-- del ENCENDIDO, no una mejora.
--
-- Qué hace. Crea {HELPER} —READ COMMITTED obligatorio, compartido, y entonces la lectura— y
-- sustituye la lectura en línea por esa llamada en las {len(T)} funciones que ESCRIBEN o pueden bloquear una escritura.
-- Anclado por md5 al texto VIVO de producción. Con la bandera estable el valor es el mismo, así que el comportamiento
-- es el de hoy: lo único que cambia es que ahora se lee con el candado puesto, y que quien llame en REPEATABLE READ o
-- SERIALIZABLE recibe `0A000` (el front, las edges y la suite van por PostgREST, que es READ COMMITTED).
--
-- ALCANCE, dicho con precisión (auditor #A1 y #A2). Entran: las RPC que escriben, las dos puertas de la saga, los
-- ayudantes que toman los candados de documento y persona, y **los cinco disparadores de `crm.leads` y `crm.tareas`
-- que leen la bandera**. Esos disparadores son la parte que faltaba: un `update crm.leads` directo desde el front (por
-- PostgREST, sin pasar por ninguna RPC) dispara validadores BEFORE que decidían con la bandera SIN candado, así que el
-- encendido no los esperaba y podían confirmar con el criterio viejo. Un disparador BEFORE escribe aunque no diga
-- «update»: muta con `new.<columna> := …`. Quedan FUERA, a propósito, las ocho funciones de SOLO LECTURA (correo de
-- Auth, cliente eliminable, previsualización de fusión, impacto de baja, leads por repartir, leads vetados, veto por
-- perfil y verificador de disponibilidad): una lectura obsoleta en una pantalla no corrompe nada.
--
-- ⚠️ Toca `public.crear_contrato`, la puerta de alta que comparte con el Portal. Es el mismo objeto que ya transformó
-- E4 con el `!` de Miguel; aquí solo cambia la lectura de la bandera. Sus permisos y su definer se comprueban intactos
-- en el postflight.
--
-- Aterriza APAGADA (se niega si la bandera está encendida). Reversa byte a byte: scripts/rollback-f2b-d19.sql.
-- Registro: scripts/registrar-f2b-d19.sql. Orden de reversa: D-19 → D-18 → D-17 → D-15 → D-5 → D-3/D-13.
-- ⚠️ Mientras D-19 esté aplicada quedan inservibles OCHO reversas anteriores, no seis (auditor #M5): además de las de
-- la cadena, las de **D-2** (offboarding y reasignar), **D-10** (la reserva de 4 argumentos), **b5** (alta de identidad,
-- conversión y saga) y **E4** (`crear_contrato_con_cuenta` y `public.crear_contrato`). Todas rehúsan solas con su
-- guarda de huella —el fallo es seguro—, pero conviene saberlo antes de intentarlo.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));

do $guard$
begin
{FLAG_GUARD('F2.b D-19', 'este lote aterriza apagado')}{GUARD}end
$guard$;

-- ── El único sitio donde se lee la bandera a partir de ahora ─────────────────────────────────────
{HELPER_DDL}
"""
for i, (key, (prev, new, firma, h0, h1)) in enumerate(T.items(), 1):
    mig += f"""
-- ── {i}/{len(T)} · {firma} ─────────────────────────────────────
{new};
"""
mig += f"""
do $post$
begin
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'private' and p.proname = 'resolver_en_puertas_bajo_candado'
                    and p.prosecdef and p.provolatile = 'v' and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
                    and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""']
                    and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
                    and not has_function_privilege('authenticated', '{HELPER}', 'EXECUTE')
                    and not has_function_privilege('anon', '{HELPER}', 'EXECUTE')
                    and not has_function_privilege('service_role', '{HELPER}', 'EXECUTE')) then
    raise exception 'POSTFLIGHT D-19: {HELPER} no quedó como se esperaba (plpgsql, volatile, definer, dueño, search_path o PUBLIC)';
  end if;
{POST}{CENSO}  raise notice 'F2.b D-19 OK: las {len(T)} escrituras leen la bandera bajo el candado del encendido (apagada: sin cambio de comportamiento).';
end
$post$;
commit;
"""
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')

rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-19] ({VER}): restaura byte a byte las {len(T)} funciones (texto vivo de producción, huellas en
-- huellas-d19-prod.txt), suelta {HELPER} y desregistra la versión. Repetible dos veces.
-- ORDEN: D-19 → D-18 → D-17 → D-15 → D-5 → D-3/D-13. Mientras D-19 esté aplicada quedan inservibles OCHO reversas
-- anteriores: las de esa cadena más las de D-2, D-10, b5 y E4, que restauran alguna de estas {len(T)} funciones.
-- Todas rehúsan solas con su guarda de huella (el fallo es seguro), pero conviene saberlo antes de intentarlo.
-- Se niega con la bandera encendida: con ON, quitar el candado es justo el hueco que D-19 cierra.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));
do $pre$
begin
{FLAG_GUARD('REVERSA D-19', 'apágala antes de revertir')}{PRE_RB}end
$pre$;
"""
for i, (key, (prev, new, firma, h0, h1)) in enumerate(T.items(), 1):
    rb += f"""
-- ── {i}/{len(T)} · {firma} (texto vivo de producción) ─────────
{prev};
"""
rb += f"""
do $dep$
declare v_dep text;
begin
  select string_agg(distinct d.classid::regclass::text || ' ' || d.objid::text, ', ')
    into v_dep
    from pg_depend d
   where d.refobjid = to_regprocedure('{HELPER}') and d.deptype in ('n','a') and d.classid <> 'pg_proc'::regclass;
  if v_dep is not null then
    raise exception 'REVERSA D-19: algo depende de {HELPER} (%): resuélvelo antes de soltarla', v_dep;
  end if;
end
$dep$;
drop function if exists private.resolver_en_puertas_bajo_candado();

do $post$
begin
{POST_RB}  if to_regprocedure('{HELPER}') is not null then
    raise exception 'REVERSA D-19: {HELPER} sigue viva';
  end if;
  delete from supabase_migrations.schema_migrations where version = '{VER}';
  raise notice 'REVERSA F2.b D-19 OK (versión {VER} desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-d19.sql').write_text(rb, encoding='utf-8')

MD5MIG = md5s(mig)
reg = f"""-- ============================================================================
-- REGISTRO de F2.b [D-19] ({VER}) en supabase_migrations.schema_migrations.
-- Idempotente: se puede correr dos veces. Se niega si lo aplicado no es lo que dice el archivo.
-- md5 del archivo de migración: {MD5MIG}
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));
do $chk$
begin
  if to_regprocedure('{HELPER}') is null then
    raise exception 'REGISTRO D-19: no está {HELPER}: ¿aplicaste la migración?';
  end if;
  -- Codex #5: no basta con que exista. Un ayudante alterado (sin el candado, o sin la exigencia de READ COMMITTED)
  -- dejaría registrar D-19 como si protegiera. Se comprueba su CUERPO, no solo su presencia.
  if (select md5(p.prosrc) from pg_proc p where p.oid = '{HELPER}'::regprocedure) <> '3d0fb83b13c9950461184de7c678ba64' then
    raise exception 'REGISTRO D-19: el cuerpo de {HELPER} no es el de esta migración; no se registra un candado que no se sabe cuál es';
  end if;
{POST}{CENSO}  if exists (select 1 from supabase_migrations.schema_migrations where version = '{VER}'
               and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null
                    or md5(statements[1]) <> '{MD5MIG}')) then
    raise exception 'REGISTRO D-19: la versión {VER} ya está registrada con otro contenido (o incompleto)';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '{VER}' and coalesce(name, '') <> '{NAME[15:]}') then
    raise exception 'REGISTRO D-19: la versión {VER} ya está registrada con otro nombre';
  end if;
end
$chk$;
-- Se registra la migración ENTERA, igual que D-17 y D-18: así `statements[1]` vuelve a dar el md5 del archivo.
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('{VER}', '{NAME[15:]}', array[$m${mig}$m$])
on conflict (version) do nothing;
commit;
"""
(W/'scripts'/'registrar-f2b-d19.sql').write_text(reg, encoding='utf-8')
print(f'D-19 migración {len(mig.splitlines())} líneas; reversa {len(rb.splitlines())}; md5 migración {MD5MIG}; {len(T)} funciones')

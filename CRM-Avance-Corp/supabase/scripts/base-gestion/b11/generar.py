#!/usr/bin/env python3
"""Genera la migración B11 a partir de los textos VIVOS (pg_get_functiondef con search_path '').

Cada cambio es un reemplazo EXACTO con su número de apariciones: si el texto vivo no es el
esperado, el generador falla en vez de producir una migración distinta. Las huellas nuevas
(md5 de prosrc) se miden en el banco y se pasan en `huellas-nuevas.json` (segunda pasada).
"""
import json, os, sys

AQUI = os.path.dirname(os.path.abspath(__file__))
VIVO = os.path.join(AQUI, 'vivo')
SALIDA = sys.argv[1]
NUEVAS = json.load(open(os.path.join(AQUI, 'huellas-nuevas.json'))) if os.path.exists(os.path.join(AQUI, 'huellas-nuevas.json')) else {}

def leer(nombre):
    t = open(os.path.join(VIVO, nombre + '.sql')).read()
    assert t.startswith('CREATE OR REPLACE FUNCTION '), nombre
    return t.rstrip('\n') + ';\n'

def cambiar(texto, nombre, reemplazos):
    for viejo, nuevo, veces in reemplazos:
        n = texto.count(viejo)
        if n != veces:
            sys.exit(f'{nombre}: se esperaban {veces} apariciones y hay {n} de:\n{viejo}')
        texto = texto.replace(viejo, nuevo)
    return texto

AYUDA = 'private.conversion_origen_con_cierre'
LFR = "e.origen in ('landing', 'formulario', 'referido')"

# Firma → (md5(prosrc) vivo en producción, 05/10/2026)
VIVAS = {
    'private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])': 'b1d6c336d198036db4ddad83a075ebdb',
    'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)': '00b17e7774f821eb04f0802f18039569',
    'private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)': '6e62d66e1c9536a50657245d6e633f56',
    'crm.metricas_conversiones_equipo_fn(date,date)': 'cbae26a3031e01580068c9336baf798b',
    'private.metricas_conversiones_implementacion(date,date,text)': '1a0e7f7fd01977e556a13fea14ddc5aa',
    'private.metricas_distribucion_leads_v3_core(date,date,timestamptz)': 'd73e12275649b756b71de50fd176d697',
    'crm.conversion_mensual_sin_cartera_fn(date)': 'f613d94208b035f241c4e13b351c55be',
    'private.conversion_divisor_empresa(date,date)': '5700d2770d1796440aa0184b035d623a',
    'private.conversion_divisor_empresa_totales(date,date)': 'e97995f5ffd9109fce87f2e5dafb11a6',
    'crm.conversion_divisor_coordinacion_fn(date,date,date)': 'b881b83ca8d4dd2f0f081d736828c8c5',
}
ACL = {
    'crm.metricas_conversiones_equipo_fn(date,date)': '{postgres=X/postgres,authenticated=X/postgres}',
    'crm.conversion_divisor_coordinacion_fn(date,date,date)': '{postgres=X/postgres,authenticated=X/postgres}',
}
# Las cuatro declaraciones del censo analítico cuyo cuerpo cambia (misma fila: conserva clase, tipo, razón y fecha).
DECLARADAS = [
    'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',
    'crm.metricas_conversiones_equipo_fn(date,date)',
    'private.metricas_conversiones_implementacion(date,date,text)',
    'crm.conversion_mensual_sin_cartera_fn(date)',
]

cuerpos = {}

cuerpos['private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])'] = cambiar(
    leer('private.conversion_cierres'), 'conversion_cierres', [
        ("    when l.origen in ('landing', 'formulario') then 1\n",
         f"    -- B11: landing, formulario y base_cargada pesan 1 (el referido ya salió por su rama).\n    when {AYUDA}(l.origen) then 1\n", 1),
        ("    when ca.origen in ('landing', 'formulario') then 1\n",
         f"    when {AYUDA}(ca.origen) then 1\n", 1),
    ])

cuerpos['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'] = cambiar(
    leer('private.registrar_ajuste_si_mes_cerrado'), 'registrar_ajuste_si_mes_cerrado', [
        ("when v_acreditacion.origen in ('landing','formulario') then 1",
         f"when {AYUDA}(v_acreditacion.origen) then 1", 1),
    ])

for firma, nombre, veces in [
    ('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)', 'private.conversion_mensual_por_vendedor', 1),
    ('crm.metricas_conversiones_equipo_fn(date,date)', 'crm.metricas_conversiones_equipo_fn', 3),
    ('private.metricas_conversiones_implementacion(date,date,text)', 'private.metricas_conversiones_implementacion', 9),
    ('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)', 'private.metricas_distribucion_leads_v3_core', 2),
]:
    cuerpos[firma] = cambiar(leer(nombre), nombre, [(LFR, f'{AYUDA}(e.origen)', veces)])

cuerpos['crm.conversion_mensual_sin_cartera_fn(date)'] = cambiar(
    leer('crm.conversion_mensual_sin_cartera_fn'), 'conversion_mensual_sin_cartera_fn', [
        ("      and l.origen in ('landing', 'formulario', 'referido')\n",
         f"      and {AYUDA}(l.origen)\n", 1),
    ])

cuerpos['private.conversion_divisor_empresa(date,date)'] = cambiar(
    leer('private.conversion_divisor_empresa'), 'conversion_divisor_empresa', [
        ('renovacion_aporte numeric, desglose_disponible boolean)\n',
         'renovacion_aporte numeric, desglose_disponible boolean, cierres_base_cargada integer)\n', 1),
        ('           f.con_desglose\n    from foto f\n',
         '           f.con_desglose,\n'
         '           -- B11: la foto del cierre no guarda los cierres de base cargada: NULL (no se inventa un 0).\n'
         '           null::integer\n'
         '    from foto f\n', 1),
        ("    -- agrupados. Formulario y landing aportan 1 por cierre; referido, su peso;\n",
         "    -- agrupados. Formulario, landing y base cargada (B11) aportan 1 por cierre; referido, su peso;\n", 1),
        ("           -- Otros orígenes admitidos (otro, web, campaña, whatsapp…) tampoco pesan; se cuentan para no esconderlos.\n"
         "           (count(*) filter (where e.tipo = 'cierre' and coalesce(e.origen, '') not in ('formulario', 'landing', 'referido', 'oficina')))::integer as cierres_otros,\n",
         "           -- Otros orígenes admitidos (otro, web, campaña, whatsapp…) tampoco pesan; se cuentan para no esconderlos.\n"
         "           (count(*) filter (where e.tipo = 'cierre' and coalesce(e.origen, '') not in ('formulario', 'landing', 'referido', 'oficina', 'base_cargada')))::integer as cierres_otros,\n"
         "           -- B11: contactos de una base cargada por archivo. Pesan 1 y no están en el divisor.\n"
         "           (count(*) filter (where e.tipo = 'cierre' and e.origen = 'base_cargada'))::integer as cierres_base_cargada,\n", 1),
        ('         coalesce(c.renovacion_aporte, 0::numeric),\n         true\n  from base b\n',
         '         coalesce(c.renovacion_aporte, 0::numeric),\n         true,\n         coalesce(c.cierres_base_cargada, 0)\n  from base b\n', 1),
    ])

cuerpos['private.conversion_divisor_empresa_totales(date,date)'] = cambiar(
    leer('private.conversion_divisor_empresa_totales'), 'conversion_divisor_empresa_totales', [
        ('sin_analista_divisor integer, sin_analista_numerador numeric)\n',
         'sin_analista_divisor integer, sin_analista_numerador numeric, cierres_base_cargada integer)\n', 1),
        ('      coalesce(sum(f.cierres_otros), 0)::integer as cierres_otros,\n',
         '      coalesce(sum(f.cierres_otros), 0)::integer as cierres_otros,\n'
         '      -- B11: un mes sellado no la tiene en la foto (NULL); abierto o rango, la suma de las filas.\n'
         '      case when v_cierre.periodo is null then coalesce(sum(f.cierres_base_cargada), 0)::integer end as cierres_base_cargada,\n', 1),
        ('    (select sa.numerador from sin_analista sa limit 1)\n  from suma s;\n',
         '    (select sa.numerador from sin_analista sa limit 1),\n'
         '    case when s.desglose_disponible then s.cierres_base_cargada end\n'
         '  from suma s;\n', 1),
    ])

cuerpos['crm.conversion_divisor_coordinacion_fn(date,date,date)'] = cambiar(
    leer('crm.conversion_divisor_coordinacion_fn'), 'conversion_divisor_coordinacion_fn', [
        ("        'otros', v_totales.cierres_otros\n      ) end,\n",
         "        'otros', v_totales.cierres_otros,\n        'base_cargada', v_totales.cierres_base_cargada\n      ) end,\n", 1),
        ("            'otros', f.cierres_otros\n          ) end,\n",
         "            'otros', f.cierres_otros,\n            'base_cargada', f.cierres_base_cargada\n          ) end,\n", 1),
    ])

assert set(cuerpos) == set(VIVAS)

COMENTARIOS = {
    'private.conversion_divisor_empresa(date,date)': open(os.path.join(VIVO, 'comentario-divisor-empresa.txt')).read().strip()
        + ' B11 (05/10/2026): cierres_base_cargada (al final) = cierres de contactos de una base cargada por archivo, que pesan 1 y no están en el divisor; NULL en un mes sellado (la foto no los guarda); cierres_otros ya no los incluye.',
    'private.conversion_divisor_empresa_totales(date,date)': open(os.path.join(VIVO, 'comentario-divisor-empresa-totales.txt')).read().strip()
        + ' B11 (05/10/2026): cierres_base_cargada (al final) = suma de las filas en un mes abierto o rango; NULL en un mes sellado.',
    'crm.conversion_divisor_coordinacion_fn(date,date,date)': open(os.path.join(VIVO, 'comentario-coordinacion.txt')).read().strip()
        + ' B11 (05/10/2026): cierres.base_cargada = cierres de contactos de una base cargada por archivo (pesan 1, fuera del divisor; null en un mes sellado); otros ya no los incluye.',
}

def lit(s):
    return "'" + s.replace("'", "''") + "'"

def md5_prosrc(firma):
    return f"(select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure({lit(firma)}))"

def acl(firma):
    return ACL.get(firma, '{postgres=X/postgres}')

o = []
w = o.append
w(open(os.path.join(AQUI, 'cabecera.sql')).read().rstrip('\n') + '\n\n')
w("""-- Exclusión de migraciones ANTES de la instantánea: candado de SESIÓN en su propia transacción.
begin;
set local lock_timeout = '5s';
select pg_advisory_lock(hashtext('crm_migracion_funciones'));
commit;

begin;
set transaction isolation level repeatable read;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
set local search_path = '';
set local quote_all_identifiers = off;

-- ── 0 · Preflight ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
declare
  r record;
begin
  if not exists (select 1 from pg_locks l
                  where l.locktype = 'advisory' and l.pid = pg_backend_pid() and l.granted and l.mode = 'ExclusiveLock'
                    and l.objsubid = 1
                    and ((l.classid::bigint << 32) | l.objid::bigint) = hashtext('crm_migracion_funciones')::bigint) then
    raise exception 'B11: falta el candado de migraciones' using errcode = 'P0409';
  end if;
  if to_regprocedure('private.conversion_origen_con_cierre(text)') is not null
     or exists (select 1 from pg_proc p where p.proname = 'conversion_origen_con_cierre') then
    raise exception 'B11: el ayudante ya existe (¿B11 ya aplicada?)' using errcode = 'P0409';
  end if;
  -- B7 aplicada: el origen base_cargada existe.
  if not exists (select 1 from pg_constraint c where c.conrelid = 'crm.leads'::regclass and c.conname = 'leads_origen_check'
                  and pg_get_constraintdef(c.oid) like '%base_cargada%') then
    raise exception 'B11: falta el origen base_cargada (B7)' using errcode = 'P0409';
  end if;
  -- Los diez cuerpos vivos, su dueño y su ACL, tal como se ensayaron.
  for r in select * from (values
""")
filas = [f"    ({lit(f)}, {lit(h)}, {lit(acl(f))})" for f, h in VIVAS.items()]
w(',\n'.join(filas) + '\n')
w("""  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl) then
      raise exception 'B11: % cambió desde el ensayo; revisar antes de aplicar', r.firma using errcode = 'P0409';
    end if;
  end loop;
  -- Las dos privadas que se recrean (drop + create) solo tienen los dos llamadores ensayados. pg_depend no ve una
  -- llamada hecha desde plpgsql, así que se mira el texto: un llamador nuevo quedaría roto por el cambio de columnas.
  if exists (select 1 from pg_proc p
              where p.prosrc ~ 'conversion_divisor_empresa(_totales)?\\s*\\('
                and p.oid not in (to_regprocedure('private.conversion_divisor_empresa_totales(date,date)'),
                                  to_regprocedure('crm.conversion_divisor_coordinacion_fn(date,date,date)'))) then
    raise exception 'B11: hay un llamador nuevo del divisor de empresa; revisar antes de aplicar' using errcode = 'P0409';
  end if;
  -- Las cuatro declaraciones del censo analítico existen y están vigentes (su huella = su cuerpo de hoy).
  if (select count(*) from private.analitica_leads_citas_exenciones e
        join pg_proc p on p.oid = to_regprocedure(e.objeto)
       where to_regprocedure(e.objeto) in (""" + ', '.join(f"to_regprocedure({lit(f)})" for f in DECLARADAS) + """)
         and e.huella = md5(regexp_replace(regexp_replace(lower(p.prosrc), '--[^\\n]*', ' ', 'g'), '/\\*.*?\\*/', ' ', 'g'))) <> 4 then
    raise exception 'B11: una declaracion analitica de las funciones tocadas no esta vigente' using errcode = 'P0409';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'B11: el sello del censo analitico no esta al dia' using errcode = 'P0409';
  end if;
  -- Freno (prometido a Miguel): B11 no cambia ningún número ya existente. Si ya hay un cierre de base, se para y se mira.
  if exists (select 1 from crm.lead_asignaciones la join crm.leads l on l.id = la.lead_id
              where la.resultado = 'convertido' and l.origen = 'base_cargada')
     or exists (select 1 from crm.conversion_acreditaciones ca where ca.origen = 'base_cargada') then
    raise exception 'B11: ya existe un cierre de un contacto de base; revisar con Miguel antes de aplicar' using errcode = 'P0409';
  end if;
end;
$preflight$;

-- Foto del censo ANTES (los rojos ajenos deben seguir exactamente iguales después).
create temporary table b11_censo_antes on commit drop as
  select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c;

-- ── 1 · El ayudante único ─────────────────────────────────────────────────────────────────────────────────────────────
create function private.conversion_origen_con_cierre(p_origen text)
returns boolean
language sql
immutable
parallel safe
security invoker
set search_path = ''
as $$
  select p_origen in ('landing', 'formulario', 'referido', 'base_cargada')
$$;
revoke all on function private.conversion_origen_con_cierre(text) from public, anon, authenticated, service_role;
comment on function private.conversion_origen_con_cierre(text) is
  'B11 (05/10/2026): UNA definición de qué orígenes cuentan un cierre en la conversión: landing, formulario, referido y base_cargada (contactos de una base cargada por archivo: pesan 1 y NO entran al divisor, como la regla cerrada del registro manual). Oficina y los demás orígenes no cuentan. NULL con origen NULL (como el `in` al que reemplaza). El divisor no la usa: lo define private.conversion_episodios (solo landing y formulario sin alta manual). Usada por private.conversion_cierres (peso 1 tras la rama del referido), private.registrar_ajuste_si_mes_cerrado, private.conversion_mensual_por_vendedor, crm.metricas_conversiones_equipo_fn, private.metricas_conversiones_implementacion, private.metricas_distribucion_leads_v3_core y la sonda de crm.conversion_mensual_sin_cartera_fn.';

-- ── 2 · Las piezas que copiaban la lista: mismo texto vivo con la lista cambiada por el ayudante ────────────────────────
""")
for firma in ['private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])',
              'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',
              'private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)',
              'crm.metricas_conversiones_equipo_fn(date,date)',
              'private.metricas_conversiones_implementacion(date,date,text)',
              'private.metricas_distribucion_leads_v3_core(date,date,timestamptz)',
              'crm.conversion_mensual_sin_cartera_fn(date)']:
    w(f'-- {firma}\n')
    w(cuerpos[firma] + '\n')

w("""-- ── 3 · Divisor de coordinación: la columna de base cargada (cambia RETURNS TABLE ⇒ drop + create, misma ACL) ──────
drop function private.conversion_divisor_empresa_totales(date,date);
drop function private.conversion_divisor_empresa(date,date);
""")
for firma in ['private.conversion_divisor_empresa(date,date)', 'private.conversion_divisor_empresa_totales(date,date)']:
    w(cuerpos[firma] + '\n')
    w(f"revoke all on function {firma} from public, anon, authenticated, service_role;\n")
    w(f"comment on function {firma} is\n  {lit(COMENTARIOS[firma])};\n\n")
f = 'crm.conversion_divisor_coordinacion_fn(date,date,date)'
w(cuerpos[f] + '\n')
w(f"comment on function {f} is\n  {lit(COMENTARIOS[f])};\n\n")

w("""-- ── 4 · Censo analítico: la declaración se queda en su fila (clase, tipo, razón y fecha) con la huella del cuerpo nuevo ──
update private.analitica_leads_citas_exenciones e set
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc), '--[^\\n]*', ' ', 'g'), '/\\*.*?\\*/', ' ', 'g'))
from pg_proc p
where p.oid = to_regprocedure(e.objeto)
  and to_regprocedure(e.objeto) in (""" + ', '.join(f"to_regprocedure({lit(x)})" for x in DECLARADAS) + """);
update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc(), sellado_en = now() where id;

-- ── 5 · Postflight ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  r record;
  v_cols text;
begin
""")
if NUEVAS:
    w("  for r in select * from (values\n")
    w(',\n'.join(f"    ({lit(fi)}, {lit(NUEVAS[fi])}, {lit(acl(fi))})" for fi in VIVAS) + ',\n')
    w(f"    ('private.conversion_origen_con_cierre(text)', {lit(NUEVAS['private.conversion_origen_con_cierre(text)'])}, '{{postgres=X/postgres}}')\n")
    w("""  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl
                    and p.prosecdef = (r.firma not in ('private.conversion_origen_con_cierre(text)', 'private.metricas_distribucion_leads_v3_core(date,date,timestamptz)'))) then
      raise exception 'B11 postflight: % no quedó como se ensayó', r.firma;
    end if;
  end loop;
""")
else:
    w("  raise exception 'B11: generador en primera pasada (sin huellas nuevas medidas)';\n")
w("""  -- Ninguna copia de la lista de cierres queda en las piezas tocadas.
  if exists (select 1 from pg_proc p where p.oid in (""" + ', '.join(f"to_regprocedure({lit(x)})" for x in VIVAS) + """)
              and (p.prosrc like '%origen in (''landing'', ''formulario'', ''referido'')%'
                   or p.prosrc like '%origen in (''landing'', ''formulario'') then 1%'
                   or p.prosrc like '%origen in (''landing'',''formulario'') then 1%')) then
    raise exception 'B11 postflight: quedó una copia de la lista de orígenes con cierre';
  end if;
  -- El ayudante: los cuatro orígenes que cuentan, ninguno más.
  if not (private.conversion_origen_con_cierre('landing') and private.conversion_origen_con_cierre('formulario')
          and private.conversion_origen_con_cierre('referido') and private.conversion_origen_con_cierre('base_cargada')
          and not private.conversion_origen_con_cierre('oficina') and not private.conversion_origen_con_cierre('otro')
          and not private.conversion_origen_con_cierre('web') and not private.conversion_origen_con_cierre('campania')
          and not private.conversion_origen_con_cierre('whatsapp')
          and private.conversion_origen_con_cierre(null) is null) then
    raise exception 'B11 postflight: el ayudante no dice lo ensayado';
  end if;
  -- La forma nueva del divisor de empresa y de su total: la columna al final, entera.
  select string_agg(a0.attname || ':' || format_type(a0.atttypid, null), ',' order by a0.n) into v_cols
    from pg_proc p, unnest(p.proargnames, p.proargmodes, p.proallargtypes) with ordinality as a0(attname, modo, atttypid, n)
   where p.oid = to_regprocedure('private.conversion_divisor_empresa(date,date)') and a0.modo = 't';
  if v_cols not like '%,desglose_disponible:boolean,cierres_base_cargada:integer' then
    raise exception 'B11 postflight: conversion_divisor_empresa sin la columna de base al final (%)', v_cols;
  end if;
  select string_agg(a0.attname || ':' || format_type(a0.atttypid, null), ',' order by a0.n) into v_cols
    from pg_proc p, unnest(p.proargnames, p.proargmodes, p.proallargtypes) with ordinality as a0(attname, modo, atttypid, n)
   where p.oid = to_regprocedure('private.conversion_divisor_empresa_totales(date,date)') and a0.modo = 't';
  if v_cols not like '%,sin_analista_numerador:numeric,cierres_base_cargada:integer' then
    raise exception 'B11 postflight: conversion_divisor_empresa_totales sin la columna de base al final (%)', v_cols;
  end if;
  -- Censo: las cuatro declaraciones vigentes, el sello al día y los rojos de antes, exactamente los mismos.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
              where to_regprocedure(c.objeto) in (""" + ', '.join(f"to_regprocedure({lit(x)})" for x in DECLARADAS) + """)
                and not (c.declarada and c.huella_ok)) then
    raise exception 'B11 postflight: una declaracion analitica tocada no quedo vigente';
  end if;
  if (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'B11 postflight: el sello del censo no quedo al dia';
  end if;
  if exists ((select tipo, objeto, declarada, huella_ok from pg_temp.b11_censo_antes
              except select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c)
             union all
             (select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c
              except select tipo, objeto, declarada, huella_ok from pg_temp.b11_censo_antes)) then
    raise exception 'B11 postflight: el censo analitico cambio (rojos nuevos o desaparecidos)';
  end if;
  -- Paridad en vivo del Divisor de coordinación: en el mes en curso, las partes suman el bruto en cada fila.
  if exists (select 1 from private.conversion_divisor_empresa(
                 pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima')::date,
                 (pg_catalog.date_trunc('month', pg_catalog.now() at time zone 'America/Lima') + interval '1 month' - interval '1 day')::date) f
              where f.desglose_disponible and f.numerador_bruto is not null
                and abs(f.cierres_formulario + f.cierres_landing + f.cierres_base_cargada + f.cierres_referido_aporte
                        + f.upgrade + f.renovacion_aporte - f.numerador_bruto) > 0.000001) then
    raise exception 'B11 postflight: el desglose del divisor de coordinación no suma el numerador';
  end if;
end;
$postflight$;

commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
""")
open(SALIDA, 'w').write(''.join(o))
print('escrita', SALIDA, sum(len(x) for x in o), 'bytes')

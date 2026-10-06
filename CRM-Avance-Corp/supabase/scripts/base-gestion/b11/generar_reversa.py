#!/usr/bin/env python3
"""Genera supabase/scripts/base-gestion/reversa-b11.sql: vuelve EXACTAMENTE al estado vivo de antes de B11."""
import json, os, sys
AQUI = os.path.dirname(os.path.abspath(__file__))
sys.argv_salida = sys.argv[1]
exec(open(os.path.join(AQUI, 'generar.py')).read().split("cuerpos = {}")[0].replace("SALIDA = sys.argv[1]", "SALIDA = None"))
NUEVAS = json.load(open(os.path.join(AQUI, 'huellas-nuevas.json')))
NOMBRE = {f: f.split('(')[0] for f in VIVAS}
COMENTARIO_VIEJO = {
    'private.conversion_divisor_empresa(date,date)': open(os.path.join(VIVO, 'comentario-divisor-empresa.txt')).read().strip(),
    'private.conversion_divisor_empresa_totales(date,date)': open(os.path.join(VIVO, 'comentario-divisor-empresa-totales.txt')).read().strip(),
    'crm.conversion_divisor_coordinacion_fn(date,date,date)': open(os.path.join(VIVO, 'comentario-coordinacion.txt')).read().strip(),
}
def lit(s): return "'" + s.replace("'", "''") + "'"
def acl(f): return ACL.get(f, '{postgres=X/postgres}')
o = []; w = o.append
w("""-- reversa-b11.sql — deshace 20261006042144_crm_bases_cargadas_conversion.sql y deja el estado vivo de ANTES, byte a byte:
-- los diez cuerpos (md5 de prosrc de producción, 05/10/2026), las firmas viejas de private.conversion_divisor_empresa y de
-- private.conversion_divisor_empresa_totales (sin cierres_base_cargada) con su ACL y su comentario, el comentario de la puerta
-- de coordinación, las cuatro huellas del censo analítico (resellado) y SIN el ayudante.
-- Se NIEGA si ya hay cierres de contactos de base: revertir les quitaría su peso (un número que la gente ya vio).
-- Antes de revertir en producción: publicar la pantalla anterior NO hace falta (la pantalla nueva tolera la clave ausente).
-- Uso: psql … -X -v ON_ERROR_STOP=1 -c "$(cat supabase/scripts/base-gestion/reversa-b11.sql)"   (un mensaje, como la migración)

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

do $preflight$
declare r record;
begin
  for r in select * from (values
""")
w(',\n'.join(f"    ({lit(f)}, {lit(NUEVAS[f])}, {lit(acl(f))})" for f in VIVAS) + ',\n')
w(f"    ('private.conversion_origen_con_cierre(text)', {lit(NUEVAS['private.conversion_origen_con_cierre(text)'])}, '{{postgres=X/postgres}}')\n")
w("""  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl) then
      raise exception 'reversa B11: % no es el de B11; revisar antes de revertir', r.firma using errcode = 'P0409';
    end if;
  end loop;
  if exists (select 1 from crm.lead_asignaciones la join crm.leads l on l.id = la.lead_id
              where la.resultado = 'convertido' and l.origen = 'base_cargada')
     or exists (select 1 from crm.conversion_acreditaciones ca where ca.origen = 'base_cargada') then
    raise exception 'reversa B11: ya hay cierres de contactos de base; revertir les quitaría su peso' using errcode = 'P0409';
  end if;
end;
$preflight$;

create temporary table b11_censo_antes on commit drop as
  select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c;

""")
for f in ['private.conversion_cierres(timestamptz,timestamptz,date,boolean,uuid[],numeric,uuid[])',
          'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',
          'private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)',
          'crm.metricas_conversiones_equipo_fn(date,date)',
          'private.metricas_conversiones_implementacion(date,date,text)',
          'private.metricas_distribucion_leads_v3_core(date,date,timestamptz)',
          'crm.conversion_mensual_sin_cartera_fn(date)',
          'crm.conversion_divisor_coordinacion_fn(date,date,date)']:
    w(f'-- {f}: texto vivo de antes de B11\n' + leer(NOMBRE[f]) + '\n')
w(f"comment on function crm.conversion_divisor_coordinacion_fn(date,date,date) is\n  {lit(COMENTARIO_VIEJO['crm.conversion_divisor_coordinacion_fn(date,date,date)'])};\n\n")
w("drop function private.conversion_divisor_empresa_totales(date,date);\ndrop function private.conversion_divisor_empresa(date,date);\n")
for f in ['private.conversion_divisor_empresa(date,date)', 'private.conversion_divisor_empresa_totales(date,date)']:
    w(leer(NOMBRE[f]) + '\n')
    w(f"revoke all on function {f} from public, anon, authenticated, service_role;\n")
    w(f"comment on function {f} is\n  {lit(COMENTARIO_VIEJO[f])};\n\n")
w("drop function private.conversion_origen_con_cierre(text);\n\n")
w("""update private.analitica_leads_citas_exenciones e set
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc), '--[^\\n]*', ' ', 'g'), '/\\*.*?\\*/', ' ', 'g'))
from pg_proc p
where p.oid = to_regprocedure(e.objeto)
  and to_regprocedure(e.objeto) in (""" + ', '.join(f"to_regprocedure({lit(x)})" for x in DECLARADAS) + """);
update private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc(), sellado_en = now() where id;

do $postflight$
declare r record;
begin
  for r in select * from (values
""")
w(',\n'.join(f"    ({lit(f)}, {lit(h)}, {lit(acl(f))})" for f, h in VIVAS.items()) + '\n')
w("""  ) as v(firma, huella, acl) loop
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure(r.firma) and md5(p.prosrc) = r.huella
                    and p.proowner = 'postgres'::regrole and p.proacl::text = r.acl) then
      raise exception 'reversa B11 postflight: % no volvió al texto vivo', r.firma;
    end if;
  end loop;
  if to_regprocedure('private.conversion_origen_con_cierre(text)') is not null then
    raise exception 'reversa B11 postflight: el ayudante sigue vivo';
  end if;
""")
for f in COMENTARIO_VIEJO:
    w(f"  if md5(coalesce(obj_description(to_regprocedure({lit(f)}), 'pg_proc'), '')) <> md5({lit(COMENTARIO_VIEJO[f])}) then\n"
      f"    raise exception 'reversa B11 postflight: comentario de % sin reponer', {lit(f)};\n  end if;\n")
w("""  if (select s.sello from private.analitica_lc_sello s where s.id) is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'reversa B11 postflight: el sello del censo no quedo al dia';
  end if;
  if exists ((select tipo, objeto, declarada, huella_ok from pg_temp.b11_censo_antes
              except select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c)
             union all
             (select c.tipo, c.objeto, c.declarada, c.huella_ok from private.contadores_crudos_leads_citas() c
              except select tipo, objeto, declarada, huella_ok from pg_temp.b11_censo_antes)) then
    raise exception 'reversa B11 postflight: el censo analitico cambio';
  end if;
end;
$postflight$;

commit;
select pg_advisory_unlock(hashtext('crm_migracion_funciones'));
""")
open(sys.argv_salida, 'w').write(''.join(o))
print('escrita', sys.argv_salida)

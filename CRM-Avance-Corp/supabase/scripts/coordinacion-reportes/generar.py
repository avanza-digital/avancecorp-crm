"""Permisos de reportes sobre cuerpos capturados de producción, sin alterar cálculos."""
from pathlib import Path
import hashlib
import json

BASE = Path(__file__).resolve().parent
MIGRACION = BASE.parents[1] / 'migrations/20261012165115_crm_coordinacion_reportes_lectura.sql'


def cambiar(texto, anterior, nuevo, cantidad=1):
    assert texto.count(anterior) == cantidad, (anterior, texto.count(anterior))
    return texto.replace(anterior, nuevo)


def huella(texto):
    return hashlib.md5(texto.encode()).hexdigest()


originales = json.loads((BASE / 'vivo/catalogo.json').read_text())
assert set(originales) == {
    'crm.conversion_mensual_fn(date)', 'crm.conversion_mensual_sin_cartera_fn(date)',
    'crm.cumplimiento_metas_fn(date)', 'crm.cumplimiento_metas_sin_cartera_fn(date)',
    'crm.metricas_conversiones_equipo_fn(date,date)', 'crm.metricas_conversiones_fn(date,date,text)',
    'crm.metricas_cartera_fn(date)', 'private.metricas_conversiones_implementacion(date,date,text)',
    'private.facturacion_operaciones_visibles(timestamp with time zone,timestamp with time zone)',
    'private.facturacion_lista(date,date,date[],uuid[],boolean,uuid,boolean,text[],text,integer,integer)',
}
fotos = {
    'crm.conversion_mensual_fn(date)': 2,
    'crm.conversion_mensual_sin_cartera_fn(date)': 1,
    'crm.cumplimiento_metas_fn(date)': 1,
    'crm.cumplimiento_metas_sin_cartera_fn(date)': 1,
    'crm.metricas_conversiones_equipo_fn(date,date)': 2,
}
nuevas = {}
for firma, texto in originales.items():
    if firma.startswith(('crm.conversion_mensual', 'crm.cumplimiento_metas_fn', 'crm.metricas_conversiones_equipo', 'crm.metricas_cartera_fn')):
        texto = cambiar(texto, 'private.es_lector_global();', 'private.es_lector_global() or private.es_coordinador_reportes();')
    elif firma.startswith('crm.cumplimiento_metas_sin_cartera'):
        texto = cambiar(texto, 'and (private.es_lector_global()', 'and (private.es_lector_global() or private.es_coordinador_reportes()')
    elif firma.startswith('crm.metricas_conversiones_fn'):
        texto = cambiar(texto, "private.rol_crm(v_actor)='gerencia' or private.es_lector_global(),", "private.rol_crm(v_actor)='gerencia' or private.es_lector_global() or private.es_coordinador_reportes(),")
    elif firma.startswith('private.metricas_conversiones_implementacion'):
        texto = cambiar(texto, ') or private.es_lector_global() into v_autorizado;', ') or private.es_lector_global() or private.es_coordinador_reportes() into v_autorizado;')
    elif firma.startswith('private.facturacion_operaciones_visibles'):
        texto = cambiar(texto, 'private.es_lector_global() as lector', 'private.es_lector_global() or private.es_coordinador_reportes() as lector')
    elif firma.startswith('private.facturacion_lista'):
        texto = cambiar(texto, '  v_contratos_todos boolean;', '  v_solo_cifras boolean := private.es_coordinador_reportes();\n  v_contratos_todos boolean;')
        texto = cambiar(texto, '  if not v_contratos_todos then', '  if not v_contratos_todos and not v_solo_cifras then')
        texto = cambiar(texto, '      coalesce(case when p.tipo', '      coalesce(not v_solo_cifras and case when p.tipo')
        texto = cambiar(texto, 'where not v_contratos_todos and ce.inversionista_id is not null', 'where not v_contratos_todos and not v_solo_cifras and ce.inversionista_id is not null')
    assert texto.count('private.cierre_mes_visible(') == fotos.get(firma, 0), firma
    if firma in fotos:
        texto = cambiar(texto, 'private.cierre_mes_visible(', 'private.cierre_mes_reportes_visible(', fotos[firma])
    nuevas[firma] = texto

helper = """create function private.es_coordinador_reportes()
returns boolean language sql stable security invoker set search_path = '' as $func$
  select coalesce(private.rol_crm((select auth.uid())) = 'coordinador', false);
$func$;
revoke all on function private.es_coordinador_reportes() from public, anon, authenticated, service_role;
comment on function private.es_coordinador_reportes() is
  'Coordinación activa: capacidad exclusiva de consulta de Facturación y Ranking. No es lector global ni autoridad operativa.';

create function private.cierre_mes_reportes_visible(p_periodo date, p_uid uuid)
returns setof crm.cierre_mes_vendedor language sql stable security invoker set search_path = '' as $func$
  select f.* from crm.cierre_mes_vendedor f
  where f.periodo = p_periodo and (
    private.es_lector_global() or private.rol_crm(p_uid) = 'gerencia'
    or (p_uid = (select auth.uid()) and private.es_coordinador_reportes())
    or f.supervisor_id = p_uid or f.vendedor_id = p_uid
  );
$func$;
revoke all on function private.cierre_mes_reportes_visible(date,uuid) from public, anon, authenticated, service_role;
comment on function private.cierre_mes_reportes_visible(date,uuid) is
  'Foto mensual para reportes autorizados, incluida Coordinación. No altera cierre_mes_visible ni la visibilidad operativa.';

create function crm.equipo_reportes_fn()
returns table(perfil_id uuid, nombre_completo text, rol_crm text, supervisor_id uuid, activo boolean)
language plpgsql stable security definer set search_path = '' as $func$
begin
  if not coalesce(private.es_coordinador_reportes() or private.rol_crm((select auth.uid())) = 'gerencia'
          or private.es_lector_global(), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  return query select e.perfil_id, p.nombre_completo, e.rol_crm, e.supervisor_id, e.activo
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where private.rol_crm(e.perfil_id) in ('vendedor','supervisor','gerencia')
  order by p.nombre_completo, e.perfil_id;
end;
$func$;
revoke all on function crm.equipo_reportes_fn() from public, anon, authenticated, service_role;
grant execute on function crm.equipo_reportes_fn() to authenticated;
comment on function crm.equipo_reportes_fn() is
  'Nombres y jerarquía comercial activa para Facturación y Ranking. Sin contactos, clientes, documentos ni permisos de gestión.';
"""


def guarda(cuerpos, nuevos=False):
    valores = ',\n'.join("    ('" + f.replace("'", "''") + "', '" + huella(t) + "')" for f, t in cuerpos.items())
    return f"""do $guardia$
declare r record;
begin
  for r in select * from (values\n{valores}\n  ) f(firma, huella) loop
    if (select md5(pg_get_functiondef(to_regprocedure(r.firma)))) is distinct from r.huella then
      raise exception 'Permisos de Coordinación: cuerpo inesperado en %, se deshace todo', r.firma;
    end if;
  end loop;
end $guardia$;
"""


cabecera = """-- Coordinación: Facturación y Ranking generales, exclusivamente lectura.
-- Aprobado por Miguel el 12/10/2026. Clientes/contratos/PII permanecen ocultos.
-- No modifica es_lector_global, vendedor_ids_visibles, policies, escrituras ni datos.
-- Las únicas diferencias de los cuerpos vivos son autorización/alcance del reporte.
-- Reversa: supabase/scripts/coordinacion-reportes/reversa.sql (antes de cambios posteriores).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
"""
preflight = """do $nuevos$
begin
  if to_regprocedure('private.es_coordinador_reportes()') is not null
     or to_regprocedure('private.cierre_mes_reportes_visible(date,uuid)') is not null
     or to_regprocedure('crm.equipo_reportes_fn()') is not null then
    raise exception 'Coordinación reportes: funciones nuevas ya existen; no se sobrescriben';
  end if;
end $nuevos$;
create temporary table coord_acl on commit drop as
select oid, proacl, proowner, prosecdef, provolatile, proconfig
from pg_proc where oid in (
""" + ',\n'.join("  to_regprocedure('" + f + "')" for f in originales) + '\n);\n'
postflight = """do $contrato$
begin
  if exists(select 1 from pg_temp.coord_acl a join pg_proc p on p.oid = a.oid
    where p.proacl is distinct from a.proacl or p.proowner <> a.proowner
      or p.prosecdef <> a.prosecdef or p.provolatile <> a.provolatile or p.proconfig is distinct from a.proconfig) then
    raise exception 'Coordinación reportes: cambió el contrato o ACL de una función existente';
  end if;
end $contrato$;
"""
MIGRACION.write_text(cabecera + guarda(originales) + preflight + helper
                     + '\n'.join(t + ';\n' for t in nuevas.values()) + guarda(nuevas) + postflight + 'commit;\n')
reversa = cabecera.replace('-- Coordinación:', '-- REVERSA Coordinación:') + guarda(nuevas)
reversa += preflight[preflight.index('create temporary table'):]
reversa += '\n'.join(t + ';\n' for t in originales.values())
reversa += guarda(originales) + postflight
reversa += """drop function crm.equipo_reportes_fn();
drop function private.cierre_mes_reportes_visible(date,uuid);
drop function private.es_coordinador_reportes();
commit;
"""
(BASE / 'reversa.sql').write_text(reversa)
print(f'Generadas migración y reversa: {len(nuevas)} funciones existentes, 3 nuevas')

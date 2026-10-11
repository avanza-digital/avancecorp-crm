#!/usr/bin/env python3
"""Fase 6 de Facturación: genera el cuerpo nuevo de crm.inversionista_ficha_fn a partir del VIVO de producción y
escribe la migración, la reversa, el ensayo de producción y el registro. --verificar no escribe."""
import argparse
import hashlib
from pathlib import Path

CARPETA = Path(__file__).resolve().parent
VERSION, NOMBRE = '20261010203951', 'crm_ficha_analista_venta'
MIGRACION = CARPETA.parents[1] / 'migrations' / f'{VERSION}_{NOMBRE}.sql'
VIVO = CARPETA / 'vivo' / 'crm.inversionista_ficha_fn.sql'
REVERSA = CARPETA / 'reversa.sql'
ENSAYO = CARPETA / 'ensayo-produccion.sql'
REGISTRAR = CARPETA / 'registrar.sql'

FIRMA = 'crm.inversionista_ficha_fn(uuid,integer,integer)'
HUELLA_VIVA = 'd0c6543bc7226e027fb8364f137fd02a'  # md5(pg_get_functiondef) en producción, 10/10/2026
ACL = '{postgres=X/postgres,authenticated=X/postgres}'
COMENTARIO = (
    'Ficha de un inversionista (cartera multiempresa F5): persona, capacidades, inversiones paginadas de 25 en 25, '
    'continuidad, totales por empresa y moneda, historial y tareas. SECURITY DEFINER porque la API no tiene permisos '
    'sobre las tablas: autoriza con private.cartera_f5_personas_visibles al entrar y al salir; Directorio (lector '
    'global) ve solo Avance, sin documentos, PDF, cotitulares ni antecedentes del lead. En cada inversión, '
    'analista_origen_* es a quién CUENTA hoy (cadena de upgrade y, tras una baja, quien heredó al cliente) y '
    'analista_venta_* quién la VENDIÓ (analista de cierre del contrato o vendedor de la cooperativa). Fase 6 de '
    'Facturación, 10/10/2026.'
)

# Los dos fragmentos que se INSERTAN en el cuerpo vivo. Nada más cambia.
ANCLA_CLAVES = "      'analista_origen_nombre',(select nombre_completo from public.perfiles where id=f.analista_origen_id),\n"
CLAVES = (
    "      -- Fase 6 de Facturación (10/10/2026): quién VENDIÓ (analista de cierre del contrato o vendedor de la\n"
    "      -- cooperativa), aparte de a quién CUENTA hoy (analista_origen_*: cadena de upgrade y baja).\n"
    "      'analista_venta_id',av.analista_id,\n"
    "      'analista_venta_nombre',(select nombre_completo from public.perfiles where id=av.analista_id),\n"
)
ANCLA_LATERAL = "from pagina f),'[]'),\n"
LATERAL = (
    "\n      cross join lateral (select case when f.empresa='avance'"
    "\n        then (select c.analista_cierre_id from public.contratos c where c.id=f.fuente_id)"
    "\n        else (select ce.vendedor_id from crm.cierres_externos ce where ce.id=f.fuente_id) end as analista_id) av"
)
LINEA_ENSAYO = "set local crm.ficha_analista_venta_ensayo = 'on';\n"
ANCLA_ENSAYO = "set local statement_timeout = '60s';\n"


def md5(texto):
    return hashlib.md5(texto.encode()).hexdigest()


def literal(texto):
    return "'" + texto.replace("'", "''") + "'"


def cuerpo_nuevo(vivo):
    assert md5(vivo) == HUELLA_VIVA, 'vivo/ no es el cuerpo medido en producción'
    assert vivo.count(ANCLA_CLAVES) == 1 and vivo.count(ANCLA_LATERAL) == 1, 'anclas ausentes o repetidas'
    assert CLAVES not in vivo and LATERAL not in vivo
    nuevo = vivo.replace(ANCLA_CLAVES, ANCLA_CLAVES + CLAVES).replace(
        ANCLA_LATERAL, ANCLA_LATERAL.replace('from pagina f', 'from pagina f' + LATERAL))
    assert nuevo.count(CLAVES) == 1 and nuevo.count(LATERAL) == 1
    # Quitar los dos fragmentos devuelve el vivo al byte (la migración repite esta prueba en SQL).
    assert nuevo.replace(CLAVES, '', 1).replace(LATERAL, '', 1) == vivo
    for etiqueta in ('$def$', '$fragmento$', '$migracion$', '$reversa$'):
        assert etiqueta not in nuevo and etiqueta not in CLAVES + LATERAL
    return nuevo


SELECT_ESTADO = """  select pg_get_functiondef(p.oid), p.proacl::text, pg_get_userbyid(p.proowner), p.prosecdef,
         obj_description(p.oid, 'pg_proc')
    into @@DESTINO@@, v_acl, v_dueno, v_definer, v_comentario
  from pg_proc p where p.oid = v_firma;
"""

MIGRACION_PLANTILLA = """-- Facturación fase 6 (Miguel, 10/10/2026, «los dos nombres»): la ficha del inversionista distingue quién VENDIÓ cada
-- inversión de a quién CUENTA hoy.
--
-- Hoy «Analista de la operación» enseña analista_origen_nombre, que es la atribución efectiva: cadena de upgrade y, tras
-- una baja, quien heredó al cliente (20261009200000). En producción (10/10, solo lectura) no es quien vendió en 46 de
-- 820 inversiones, todas de 2 analistas dados de baja.
--
-- Cambio: crm.inversionista_ficha_fn añade a cada inversión analista_venta_id y analista_venta_nombre: el analista de
-- cierre del contrato (public.contratos.analista_cierre_id) o el vendedor de la cooperativa
-- (crm.cierres_externos.vendedor_id). La pantalla enseña los dos nombres solo cuando son personas distintas.
-- El cuerpo nuevo es el vivo (huella @@HUELLA_VIVA@@) con DOS fragmentos insertados y nada más; esta migración lo
-- comprueba por texto. Sin cambios de firma, permisos, cifras ni filas visibles: los dos datos salen de la misma fila
-- que ya se ve. La función no tenía comentario; se añade.
--
-- Reversa: supabase/scripts/ficha-analista-venta/reversa.sql (cuerpo anterior al byte y sin comentario).
-- Kit, banco y ensayo: supabase/scripts/ficha-analista-venta/ (LEEME.md). Generada por generar.py (no editar a mano).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
do $migracion$
declare
  v_firma constant regprocedure := '@@FIRMA@@'::regprocedure;
  v_antes text;
  v_despues text;
  v_acl text;
  v_dueno text;
  v_definer boolean;
  v_comentario text;
begin
@@SELECT_ANTES@@
  -- Permisos, dueño y modo ANTES de cualquier salida (Codex r1): un «ya aplicada» también los acredita.
  if v_acl is distinct from '@@ACL@@' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'PREFLIGHT: permisos, dueño o modo de la ficha distintos de los medidos (%, %, %)',
      v_acl, v_dueno, v_definer;
  end if;
  -- Ya aplicada (cuerpo y comentario): repetir no hace nada. El ensayo acaba en error también aquí.
  if md5(v_antes) = '@@HUELLA_NUEVA@@' and v_comentario = @@COMENTARIO@@ then
    if current_setting('crm.ficha_analista_venta_ensayo', true) = 'on' then
      raise exception 'ENSAYO FICHA: ya aplicada; no hay nada que ensayar — SE DESHACE TODO';
    end if;
    raise notice 'Ficha con analista de venta: ya aplicada';
    return;
  end if;
  if md5(v_antes) is distinct from '@@HUELLA_VIVA@@' then
    raise exception 'PREFLIGHT: crm.inversionista_ficha_fn no es la medida (huella %); volver a generar el kit', md5(v_antes);
  end if;
  if v_comentario is not null then
    raise exception 'PREFLIGHT: la ficha ya tiene comentario; revisar a mano';
  end if;

  execute $def$
@@NUEVO@@$def$;

@@SELECT_DESPUES@@
  if md5(v_despues) is distinct from '@@HUELLA_NUEVA@@' then
    raise exception 'POSTFLIGHT: el cuerpo instalado no es el generado (huella %)', md5(v_despues);
  end if;
  -- Por texto: quitar los dos fragmentos devuelve el cuerpo anterior al byte.
  if (replace(replace(v_despues, $fragmento$@@CLAVES@@$fragmento$, ''),
      $fragmento$@@LATERAL@@$fragmento$, '') = v_antes) is not true then
    raise exception 'POSTFLIGHT: el cuerpo nuevo cambia algo más que los dos fragmentos';
  end if;
  if v_acl is distinct from '@@ACL@@' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'POSTFLIGHT: cambiaron los permisos, el dueño o el modo de la ficha';
  end if;

  comment on function crm.inversionista_ficha_fn(uuid, integer, integer) is @@COMENTARIO@@;

  if current_setting('crm.ficha_analista_venta_ensayo', true) = 'on' then
    raise exception 'ENSAYO FICHA PASS: cuerpo % -> %, solo los dos fragmentos, permisos iguales, comentario puesto — SE DESHACE TODO',
      left(md5(v_antes), 8), left(md5(v_despues), 8);
  end if;
end
$migracion$;
commit;
"""

REVERSA_PLANTILLA = """-- REVERSA de @@VERSION@@_@@NOMBRE@@: vuelve a poner el cuerpo anterior de crm.inversionista_ficha_fn al byte
-- (huella @@HUELLA_VIVA@@) y le quita el comentario. Idempotente; se niega ante un cuerpo desconocido. No toca
-- supabase_migrations (si hiciera falta, se desregistra a mano). La pantalla nueva tolera el cuerpo anterior: los dos
-- datos son opcionales y, sin ellos, la ficha enseña una sola línea como antes.
-- Generada por generar.py (no editar a mano).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
do $reversa$
declare
  v_firma constant regprocedure := '@@FIRMA@@'::regprocedure;
  v_actual text;
  v_despues text;
  v_acl text;
  v_dueno text;
  v_definer boolean;
  v_comentario text;
begin
@@SELECT_ACTUAL@@
  -- Permisos, dueño y modo ANTES de cualquier salida (Codex r1).
  if v_acl is distinct from '@@ACL@@' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'REVERSA: permisos, dueño o modo distintos de los esperados; revisar a mano';
  end if;
  if md5(v_actual) = '@@HUELLA_VIVA@@' and v_comentario is null then
    raise notice 'Reversa de la ficha: ya está el cuerpo anterior';
    return;
  end if;
  if md5(v_actual) is distinct from '@@HUELLA_NUEVA@@' then
    raise exception 'REVERSA: cuerpo desconocido de la ficha (huella %); revisar a mano', md5(v_actual);
  end if;
  -- Un comentario distinto del que puso la migración es un cambio ajeno: no se borra (Codex r1).
  if v_comentario is distinct from @@COMENTARIO@@ then
    raise exception 'REVERSA: la ficha tiene otro comentario; revisar a mano';
  end if;

  execute $def$
@@VIVO@@$def$;
  comment on function crm.inversionista_ficha_fn(uuid, integer, integer) is null;

@@SELECT_DESPUES@@
  if md5(v_despues) is distinct from '@@HUELLA_VIVA@@' or v_comentario is not null
     or v_acl is distinct from '@@ACL@@' or v_dueno is distinct from 'postgres' or v_definer is not true then
    raise exception 'REVERSA POSTFLIGHT: el estado final no es el anterior; se deshace';
  end if;
  raise notice 'Reversa de la ficha hecha';
end
$reversa$;
commit;
"""

REGISTRAR_PLANTILLA = """-- REGISTRO en supabase_migrations.schema_migrations de @@VERSION@@_@@NOMBRE@@.
-- Correr DESPUÉS de aplicar la migración, por la misma vía. Idempotente; se niega si la ficha no tiene el cuerpo y el
-- comentario nuevos o si la versión ya está registrada con otro nombre u otro texto.
-- Generado por generar.py: md5 del texto de la migración @@MD5_TEXTO@@.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('@@NOMBRE@@'));
do $chk$
begin
  if (select md5(pg_get_functiondef(p.oid)) = '@@HUELLA_NUEVA@@'
             and obj_description(p.oid, 'pg_proc') = @@COMENTARIO@@
             and p.proacl::text = '@@ACL@@' and pg_get_userbyid(p.proowner) = 'postgres' and p.prosecdef
      from pg_proc p where p.oid = '@@FIRMA@@'::regprocedure) is not true then
    raise exception 'REGISTRO: la ficha no tiene el cuerpo nuevo con sus permisos; aplica primero @@VERSION@@';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '@@VERSION@@' and coalesce(name, '') <> '@@NOMBRE@@') then
    raise exception 'REGISTRO: la versión @@VERSION@@ ya está registrada con otro nombre';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '@@VERSION@@' and (cardinality(statements) is distinct from 1
               or md5(statements[1]) is distinct from '@@MD5_TEXTO@@')) then
    raise exception 'REGISTRO: la versión @@VERSION@@ ya está registrada con OTRO texto; revisar a mano';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('@@VERSION@@', '@@NOMBRE@@', array[$migracion_@@VERSION@@$@@TEXTO@@$migracion_@@VERSION@@$])
on conflict (version) do nothing;
select version, name, md5(statements[1]) as md5_texto from supabase_migrations.schema_migrations where version = '@@VERSION@@';
commit;
"""

CABECERA_ENSAYO = (
    f'-- ENSAYO DE PRODUCCIÓN de {VERSION}_{NOMBRE}: la migración entera, que acaba SIEMPRE en error y lo deshace todo.\n'
    '-- Resultado correcto: «ENSAYO FICHA PASS: … — SE DESHACE TODO». Cualquier otro error es un fallo.\n'
    '-- Generado por generar.py (no editar a mano).\n'
)


def rellenar(plantilla, valores):
    for clave, valor in valores.items():
        plantilla = plantilla.replace(f'@@{clave}@@', valor)
    assert '@@' not in plantilla, 'marcador sin rellenar'
    return plantilla


def generar():
    vivo = VIVO.read_text()
    nuevo = cuerpo_nuevo(vivo)
    comunes = {'VERSION': VERSION, 'NOMBRE': NOMBRE, 'FIRMA': FIRMA, 'ACL': ACL, 'HUELLA_VIVA': HUELLA_VIVA,
               'HUELLA_NUEVA': md5(nuevo), 'COMENTARIO': literal(COMENTARIO)}
    migracion = rellenar(MIGRACION_PLANTILLA, {
        **comunes, 'NUEVO': nuevo, 'CLAVES': CLAVES, 'LATERAL': LATERAL,
        'SELECT_ANTES': SELECT_ESTADO.replace('@@DESTINO@@', 'v_antes').rstrip('\n'),
        'SELECT_DESPUES': SELECT_ESTADO.replace('@@DESTINO@@', 'v_despues').rstrip('\n')})
    reversa = rellenar(REVERSA_PLANTILLA, {
        **comunes, 'VIVO': vivo,
        'SELECT_ACTUAL': SELECT_ESTADO.replace('@@DESTINO@@', 'v_actual').rstrip('\n'),
        'SELECT_DESPUES': SELECT_ESTADO.replace('@@DESTINO@@', 'v_despues').rstrip('\n')})
    assert migracion.count(ANCLA_ENSAYO) == 1 and LINEA_ENSAYO not in migracion
    ensayo = CABECERA_ENSAYO + migracion.replace(ANCLA_ENSAYO, ANCLA_ENSAYO + LINEA_ENSAYO)
    # Quitar lo añadido devuelve la migración al byte: el ensayo prueba exactamente lo que se aplicará.
    assert ensayo[len(CABECERA_ENSAYO):].replace(LINEA_ENSAYO, '', 1) == migracion
    etiqueta = f'$migracion_{VERSION}$'
    assert etiqueta not in migracion
    registrar = rellenar(REGISTRAR_PLANTILLA, {**comunes, 'MD5_TEXTO': md5(migracion), 'TEXTO': migracion})
    return {MIGRACION: migracion, REVERSA: reversa, ENSAYO: ensayo, REGISTRAR: registrar}, md5(nuevo)


def principal():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verificar', action='store_true')
    args = parser.parse_args()
    salidas, huella_nueva = generar()
    if args.verificar:
        malos = [p.name for p, contenido in salidas.items() if not p.exists() or p.read_text() != contenido]
        if malos:
            raise SystemExit(f'FAIL: desactualizados {malos}; correr generar.py')
        print(f'PASS: migración, reversa, ensayo y registro al día (cuerpo nuevo {huella_nueva}, '
              f'texto {md5(salidas[MIGRACION])})')
        return
    for ruta, contenido in salidas.items():
        ruta.write_text(contenido)
    print(f'escritos {[p.name for p in salidas]} (cuerpo nuevo {huella_nueva})')


if __name__ == '__main__':
    principal()

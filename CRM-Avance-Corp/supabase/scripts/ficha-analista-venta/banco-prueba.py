#!/usr/bin/env python3
"""Banco de la fase 6 (ficha del inversionista con analista de venta) contra el banco Docker con el esquema de
producción. Deja el banco como estaba (cuerpo vivo, sin comentario). Las fichas se piden como usuarios reales del banco
(gerencia, supervisores, vendedores, Directorio) en transacciones que se deshacen.

La cartera multiempresa del banco está apagada (bandera y conciliación de datos sintéticos): en cada foto se sustituye
crm.cartera_inversionistas_estado_fn por un doble que la da por habilitada, igual en la foto de antes y en la de después,
así que la comparación sigue siendo exacta."""
import argparse
import json
import subprocess
import sys
from pathlib import Path

CARPETA = Path(__file__).resolve().parent
sys.path.insert(0, str(CARPETA))
import generar as G  # noqa: E402

CLAVES_NUEVAS = ('analista_venta_id', 'analista_venta_nombre')
CONTENEDOR = 'supabase_db_avancecorp-fact0c-20261009'
RESULTADOS = []

DOBLE = """
create or replace function crm.cartera_inversionistas_estado_fn() returns jsonb language sql as
$doble$ select jsonb_build_object('version',1,'habilitada',true,'escritura_habilitada',false,'motivo',null) $doble$;
create schema banco_ficha;
create function banco_ficha.ficha_segura(p uuid) returns jsonb language plpgsql as $segura$
begin
  return coalesce(crm.inversionista_ficha_fn(p), 'null'::jsonb);
exception when others then
  return jsonb_build_object('error', sqlstate, 'mensaje', sqlerrm);
end $segura$;
grant usage on schema banco_ficha to authenticated;
grant execute on function banco_ficha.ficha_segura(uuid) to authenticated;
"""


def psql(sql, usuario='supabase_admin'):
    r = subprocess.run(['docker', 'exec', '-i', CONTENEDOR, 'psql', '-U', usuario, '-d', 'postgres', '-At', '-q',
                        '-v', 'ON_ERROR_STOP=1'], input=sql, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def valor(sql):
    rc, out, err = psql(sql)
    assert rc == 0, err
    return out.strip()


def caso(nombre, ok, detalle=''):
    RESULTADOS.append((nombre, ok))
    print(f"{'PASS' if ok else 'FAIL'}  {nombre}{' — ' + detalle if detalle else ''}")


def estado():
    fila = valor(f"""select md5(pg_get_functiondef(p.oid)) || '|' || coalesce(p.proacl::text, '') || '|'
      || coalesce(md5(obj_description(p.oid, 'pg_proc')), 'sin comentario')
    from pg_proc p where p.oid = '{G.FIRMA}'::regprocedure""")
    huella, acl, comentario = fila.split('|')
    return huella, acl, comentario


def foto(actores, inversionistas, preparar=''):
    """{actor: {inversionista: ficha}} pidiendo cada ficha como ese actor; todo se deshace."""
    lista = ','.join(inversionistas)
    salida = {}
    for actor in actores:
        rc, out, err = psql(f"""begin;
{DOBLE}
{preparar}
select set_config('request.jwt.claims', json_build_object('sub', '{actor}', 'role', 'authenticated')::text, true)
  as _claims \\gset
set local role authenticated;
select jsonb_object_agg(i::text, banco_ficha.ficha_segura(i)) from unnest('{{{lista}}}'::uuid[]) i;
rollback;
""")
        assert rc == 0, err
        salida[actor] = json.loads(out.strip().splitlines()[-1])
    return salida


def sin_claves_nuevas(ficha):
    if not isinstance(ficha, dict) or 'inversiones' not in ficha:
        return ficha
    copia = dict(ficha)
    copia['inversiones'] = [{k: v for k, v in inv.items() if k not in CLAVES_NUEVAS} for inv in ficha['inversiones']]
    return copia


def diferencias(antes, despues):
    """Fichas (actor, inversionista) que cambian en algo más que las dos claves nuevas."""
    return [(a, i) for a in antes for i in antes[a] if sin_claves_nuevas(despues[a][i]) != antes[a][i]]


def inversiones(foto_):
    for actor, fichas in foto_.items():
        for inv_id, ficha in fichas.items():
            if isinstance(ficha, dict) and 'inversiones' in ficha:
                for inv in ficha['inversiones']:
                    yield actor, inv_id, inv


def errores_de_venta(foto_, esperado):
    """Inversiones sin las dos claves o con un analista de venta distinto del registrado en su fila."""
    malos = []
    for actor, inv_id, inv in inversiones(foto_):
        if any(k not in inv for k in CLAVES_NUEVAS):
            malos.append((actor, inv['fuente_id'], 'faltan claves'))
            continue
        e = esperado.get(inv['fuente_id'])
        if e is None or inv['analista_venta_id'] != e['id'] or inv['analista_venta_nombre'] != e['nombre']:
            malos.append((actor, inv['fuente_id'], inv.get('analista_venta_id')))
    return malos


def bloque_do(texto, etiqueta):
    inicio = texto.index(f'do {etiqueta}\n')
    fin = texto.index(f'{etiqueta};\n', inicio) + len(f'{etiqueta};\n')
    return texto[inicio:fin]


def negativa(nombre, sabotaje, bloque, esperado):
    rc, _, err = psql(f'begin;\n{sabotaje}\n{bloque}rollback;\n')
    caso(nombre, rc != 0 and esperado in err, err.strip().splitlines()[0] if err.strip() else 'no falló')


def principal():
    global CONTENEDOR
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contenedor', default=CONTENEDOR)
    args = parser.parse_args()
    CONTENEDOR = args.contenedor

    salidas, huella_nueva = G.generar()
    migracion, reversa, ensayo, registrar = (salidas[G.MIGRACION], salidas[G.REVERSA], salidas[G.ENSAYO],
                                             salidas[G.REGISTRAR])
    vivo = G.VIVO.read_text()
    acl_viva = G.ACL
    if estado() != (G.HUELLA_VIVA, acl_viva, 'sin comentario'):
        raise SystemExit(f'El banco no está en el estado de producción: {estado()}')

    # Actores y datos del banco.
    gerencia = valor("select perfil_id from crm.equipo where rol_crm = 'gerencia' and activo order by perfil_id limit 1")
    supervisores = valor("select string_agg(perfil_id::text, ' ' order by perfil_id) from crm.equipo "
                         "where rol_crm = 'supervisor' and activo").split()
    vendedores = valor("select string_agg(perfil_id::text, ' ' order by perfil_id) from crm.equipo "
                       "where rol_crm = 'vendedor' and activo").split()
    directorio = valor("select string_agg(id::text, ' ' order by id) from public.perfiles p where p.activo "
                       "and p.rol = 'directorio' and not exists (select 1 from crm.equipo e where e.perfil_id = p.id)"
                       ).split()
    actores = [gerencia, *supervisores, *vendedores, *directorio]
    invs = valor("select string_agg(id::text, ' ' order by id) from crm.inversionistas").split()
    esperado = json.loads(valor("""select jsonb_object_agg(f.fuente_id::text, jsonb_build_object('id', v.id,
        'nombre', (select p.nombre_completo from public.perfiles p where p.id = v.id)))
      from private.cartera_f5_fuentes() f
      cross join lateral (select case when f.empresa = 'avance'
        then (select c.analista_cierre_id from public.contratos c where c.id = f.fuente_id)
        else (select ce.vendedor_id from crm.cierres_externos ce where ce.id = f.fuente_id) end as id) v"""))
    # La baja: el vendedor con más inversiones en fichas deja el equipo y sus clientes pasan a otro vendedor activo,
    # como hace la baja real (responsable del cliente y de la relación).
    x = valor("""select f.analista_origen_id from private.cartera_f5_fuentes() f
      join crm.equipo e on e.perfil_id = f.analista_origen_id and e.rol_crm = 'vendedor' and e.activo
      where f.inversionista_id is not null group by 1 order by count(*) desc, 1 limit 1""")
    y = next(v for v in vendedores if v != x)
    baja = f"""set local session_replication_role = replica;
update crm.equipo set activo = false where perfil_id = '{x}';
update public.perfiles set asesor_perfil_id = '{y}' where asesor_perfil_id = '{x}';
update crm.inversionistas set responsable_relacion_id = '{y}' where responsable_relacion_id = '{x}';
set local session_replication_role = origin;"""
    print(f'banco: {len(actores)} actores, {len(invs)} inversionistas, baja de {x[:8]} → {y[:8]}')

    # ANTES (cuerpo vivo).
    antes = foto(actores, invs)
    antes_baja = foto([gerencia], invs, baja)
    con_inversiones = {a: sum(1 for f in antes[a].values() if isinstance(f, dict) and f.get('inversiones'))
                       for a in actores}
    caso('la prueba no es vacía: gerencia, Directorio y al menos un vendedor ven inversiones',
         con_inversiones[gerencia] > 0 and all(con_inversiones[d] > 0 for d in directorio) and directorio != []
         and any(con_inversiones[v] > 0 for v in vendedores), str(con_inversiones))

    # Ensayo, negativas y registro antes de aplicar.
    rc, _, err = psql(ensayo)
    caso('ensayo: acaba en «ENSAYO FICHA PASS» y no deja nada',
         rc != 0 and 'ENSAYO FICHA PASS' in err and estado() == (G.HUELLA_VIVA, acl_viva, 'sin comentario'),
         err.strip().splitlines()[0] if err.strip() else '')
    bloque = bloque_do(migracion, '$migracion$')
    sabotaje_cuerpo = vivo.replace('begin\n  perform private.cartera_f5_exigir();',
                                   'begin\n  -- cambio ajeno\n  perform private.cartera_f5_exigir();', 1)
    assert sabotaje_cuerpo != vivo
    negativa('negativa: cuerpo distinto del medido', sabotaje_cuerpo + ';', bloque, 'PREFLIGHT: crm.inversionista_ficha_fn no es la medida')
    negativa('negativa: permisos distintos (anon con EXECUTE)',
             f'grant execute on function {G.FIRMA} to anon;', bloque, 'PREFLIGHT: permisos')
    negativa('negativa: ya tiene comentario', f"comment on function {G.FIRMA} is 'otro';", bloque,
             'PREFLIGHT: la ficha ya tiene comentario')
    envuelto = registrar.rsplit('commit;\n', 1)[0] + 'rollback;\n'
    rc, _, err = psql(envuelto)
    caso('registro antes de aplicar: se niega', rc != 0 and 'REGISTRO: la ficha no tiene el cuerpo nuevo' in err)

    # APLICAR y repetir.
    rc, _, err = psql(migracion)
    caso('aplicar', rc == 0 and estado()[0] == huella_nueva and estado()[1] == acl_viva
         and estado()[2] == G.md5(G.COMENTARIO), err.strip()[:200])
    rc, _, err = psql(migracion)
    caso('repetir: «ya aplicada» y nada cambia', rc == 0 and 'ya aplicada' in err and estado()[0] == huella_nueva)
    rc, out, err = psql(envuelto)
    caso('registro después de aplicar (deshecho): registra el texto exacto',
         rc == 0 and f'{G.VERSION}|{G.NOMBRE}|{G.md5(migracion)}' in out, err.strip()[:200])
    anon = f'grant execute on function {G.FIRMA} to anon;'
    negativa('repetir con permisos ajenos (anon): se niega, no dice «ya aplicada»', anon, bloque, 'PREFLIGHT: permisos')
    rc, _, err = psql(ensayo)
    caso('ensayo sobre la ficha ya aplicada: también acaba en error', rc != 0 and 'ENSAYO FICHA: ya aplicada' in err
         and estado()[0] == huella_nueva, err.strip().splitlines()[0] if err.strip() else 'no falló')
    rc, _, err = psql(envuelto.replace('begin;\n', 'begin;\n' + anon + '\n', 1))
    caso('registro con permisos ajenos: se niega', rc != 0 and 'REGISTRO: la ficha no tiene el cuerpo nuevo' in err)

    # DESPUÉS.
    despues = foto(actores, invs)
    difs = diferencias(antes, despues)
    caso('después: cada ficha de cada actor es la de antes más las dos claves', not difs, str(difs[:3]))
    malos = errores_de_venta(despues, esperado)
    total = sum(1 for _ in inversiones(despues))
    caso(f'después: las {total} inversiones traen quién vendió, el de su fila', total > 0 and not malos, str(malos[:3]))
    lector = [inv for a in directorio for _, _, inv in inversiones({a: despues[a]})]
    caso('Directorio: solo Avance y con las dos claves',
         lector != [] and all(inv['empresa'] == 'avance' and all(k in inv for k in CLAVES_NUEVAS) for inv in lector))
    despues_baja = foto([gerencia], invs, baja)
    difs = diferencias(antes_baja, despues_baja)
    distintos = [inv for _, _, inv in inversiones(despues_baja)
                 if inv['analista_venta_id'] == x and inv['analista_origen_id'] not in (x, None)]
    caso('baja: igual que antes salvo las claves; vendió el que se fue y cuenta para quien heredó',
         not difs and len(distintos) > 0 and not errores_de_venta(despues_baja, esperado),
         f'{len(distintos)} inversiones con dos nombres')

    # Contrato sin analista de cierre (la columna admite NULL, p. ej. importados): la ficha dice que no consta.
    nulo = valor("""select f.fuente_id from private.cartera_f5_fuentes() f
      where f.inversionista_id is not null and f.empresa = 'avance' order by f.fuente_id limit 1""")
    sin_vendedor = [inv for _, _, inv in inversiones(foto([gerencia], invs, f"""set local session_replication_role = replica;
update public.contratos set analista_cierre_id = null where id = '{nulo}';
set local session_replication_role = origin;""")) if inv['fuente_id'] == nulo]
    caso('vendedor desconocido: las dos claves llegan con null', sin_vendedor != [] and all(
         'analista_venta_id' in inv and inv['analista_venta_id'] is None and inv['analista_venta_nombre'] is None
         for inv in sin_vendedor))

    # MUTANTES: cada uno debe hacer fallar la comprobación que lo vigila.
    nuevo = G.cuerpo_nuevo(vivo)
    m1 = nuevo.replace("'analista_venta_id',av.analista_id,", "'analista_venta_id',f.analista_origen_id,", 1)
    m1 = m1.replace('where id=av.analista_id),', 'where id=f.analista_origen_id),', 1)
    assert m1 != nuevo
    caso('mutante: venta = a quién cuenta → la baja lo detecta',
         errores_de_venta(foto([gerencia], invs, baja + '\n' + m1 + ';'), esperado) != [])
    m2 = nuevo.replace("      'numero_transaccion',case", "      'numero_transaccion_x',case", 1)
    assert m2 != nuevo
    caso('mutante: otra clave cambia → la comparación antes/después lo detecta',
         diferencias(antes, foto(actores, invs, m2 + ';')) != [])

    # REVERSA.
    bloque_reversa = bloque_do(reversa, '$reversa$')
    negativa('reversa con otro comentario: no lo borra', f"comment on function {G.FIRMA} is 'documentación posterior';",
             bloque_reversa, 'REVERSA: la ficha tiene otro comentario')
    negativa('reversa con permisos ajenos (anon): se niega', anon, bloque_reversa, 'REVERSA: permisos')
    rc, _, err = psql(reversa)
    caso('reversa: cuerpo anterior al byte, sin comentario, mismos permisos',
         rc == 0 and estado() == (G.HUELLA_VIVA, acl_viva, 'sin comentario'), err.strip()[:200])
    rc, _, err = psql(reversa)
    caso('reversa repetida: no hace nada', rc == 0 and 'ya está el cuerpo anterior' in err)
    caso('tras la reversa: fichas idénticas a las de antes', foto(actores, invs) == antes)
    negativa('reversa negativa: cuerpo desconocido', sabotaje_cuerpo + ';', bloque_reversa,
             'REVERSA: cuerpo desconocido')
    negativa('reversa ya hecha pero con permisos ajenos: se niega, no dice «ya está»', anon, bloque_reversa,
             'REVERSA: permisos')

    final = estado()
    caso('el banco queda como estaba', final == (G.HUELLA_VIVA, acl_viva, 'sin comentario'), str(final))
    fallos = [n for n, ok in RESULTADOS if not ok]
    print(f'\n{len(RESULTADOS) - len(fallos)}/{len(RESULTADOS)} PASS')
    sys.exit(1 if fallos else 0)


if __name__ == '__main__':
    principal()

#!/usr/bin/env python3
"""Venta cruzada · ensayo de publicación que NUNCA escribe.

Genera un único `DO` que aplica las migraciones indicadas, en orden, dentro de la MISMA
transacción, compara los guardianes `private.assert_*()` antes y después y termina SIEMPRE
en `raise exception`: la transacción entera se deshace pase lo que pase. El veredicto viaja en
el mensaje del error:
  ENSAYO_VC_OK   → todas las migraciones aplicaron (preflights y postflights en verde) y
                   ningún guardián pasó a rojo ni cambió de motivo;
  ENSAYO_VC_ROJO → aplicaron, pero algún guardián empeoró (se listan);
  cualquier otro → una migración abortó (su propio preflight/postflight dice por qué).

Uso: ensayo-prod.py <dir-migraciones> <version_nombre>... > ensayo.sql
Cada migración debe tener exactamente un `begin;` y un `commit;` de fichero, cada uno solo en su
línea: se retiran para que todas vivan en la transacción del ensayo.
"""
import pathlib
import re
import sys

directorio = pathlib.Path(sys.argv[1])
migraciones = sys.argv[2:]
if not migraciones:
    sys.exit('faltan las migraciones')

CAPTURA = """
  for f in select p.oid::regprocedure::text as firma from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'private' and p.proname like 'assert\\_%%' and p.pronargs = 0 order by 1 loop
    begin
      execute 'select ' || f.firma;
    exception when others then
      %s := %s || (f.firma || ' :: ' || left(regexp_replace(sqlerrm, '\\s+', ' ', 'g'), 300));
    end;
  end loop;"""

partes = []
for i, nombre in enumerate(migraciones, 1):
    texto = (directorio / f'{nombre}.sql').read_text()
    lineas = texto.split('\n')
    inicios = [n for n, l in enumerate(lineas) if re.fullmatch(r'\s*begin;\s*', l, re.I)]
    finales = [n for n, l in enumerate(lineas) if re.fullmatch(r'\s*commit;\s*', l, re.I)]
    if len(inicios) != 1 or len(finales) != 1 or inicios[0] >= finales[0]:
        sys.exit(f'{nombre}: se esperaba exactamente un begin; y un commit; de fichero')
    cuerpo = '\n'.join(lineas[:inicios[0]] + lineas[inicios[0] + 1:finales[0]] + lineas[finales[0] + 1:])
    etiqueta = f'$vc_m{i}_ensayo$'
    if etiqueta in cuerpo:
        sys.exit(f'{nombre}: contiene la etiqueta {etiqueta}')
    partes.append(f"  -- {nombre}\n  execute {etiqueta}{cuerpo}{etiqueta};\n  aplicadas := array_append(aplicadas, '{nombre}'::text);")

sql = f"""-- Ensayo de publicación de la venta cruzada: SIEMPRE termina en raise (no escribe nada).
do $vc_ensayo$
declare
  f record;
  rojas_antes text[] := '{{}}';
  rojas_despues text[] := '{{}}';
  nuevas text[];
  aplicadas text[] := '{{}}';
begin
  -- Guardianes ANTES (la foto viva de producción)
{CAPTURA % ('rojas_antes', 'rojas_antes')}

{chr(10).join(partes)}

  -- Guardianes DESPUÉS, dentro de la misma transacción
{CAPTURA % ('rojas_despues', 'rojas_despues')}
  select coalesce(array_agg(x order by x), '{{}}') into nuevas
    from unnest(rojas_despues) x where not x = any(rojas_antes);
  if cardinality(nuevas) > 0 then
    raise exception 'ENSAYO_VC_ROJO aplicadas=% rojas_antes=% nuevas_rojas=%',
      cardinality(aplicadas), cardinality(rojas_antes), nuevas;
  end if;
  raise exception 'ENSAYO_VC_OK aplicadas=% rojas_antes=% rojas_despues=% (deshecho: nada quedó escrito)',
    cardinality(aplicadas), cardinality(rojas_antes), cardinality(rojas_despues);
end $vc_ensayo$;
"""
sys.stdout.write(sql)

#!/usr/bin/env python3
"""Genera, desde el texto de 20261001154153_crm_cartera_filtro_gestion.sql (la firma de 13 de
crm.cartera_filtrada_fn, la que sustituye la entrega B), dos archivos que NO se editan a mano:

  banco/anterior-13.sql   la función anterior, tal cual, como pg_temp.cartera_filtrada_anterior
                          (va delante de prueba-filtro.sql: es la vara de la igualdad)
  reversa-filtro.sql      la reversa de 20261001212341: reinstala la firma de 13 byte a byte

Una función viva no se reteclea: el cuerpo sale del archivo de la migración que la instaló. Imprime
el md5 del cuerpo (prosrc), que prueba-filtro.sql comprueba antes de comparar.

  python3 banco/generar-anterior-y-reversa.py [--comprobar]
"""
import hashlib, io, os, re, sys

aqui = os.path.dirname(os.path.abspath(__file__))
raiz = os.path.join(aqui, "..")
mig = io.open(os.path.join(aqui, "..", "..", "..", "migrations", "20261001154153_crm_cartera_filtro_gestion.sql"), encoding="utf-8").read()

F13 = "crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)"
F14 = "crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)"
F13L = F13.replace("timestamptz", "timestamp with time zone")
F14L = F14.replace("timestamptz", "timestamp with time zone")
MD5_13 = "bf06666fb8ef533a39a50c7d70420153"   # md5(pg_get_functiondef), postflight de 20261001154153
MD5_14 = "23a63cc3965472b9db85aa81cadffbeb"   # md5(pg_get_functiondef), postflight de 20261001212341
MD5_AYUDANTE = "73e993d618b203cdbe21e8127f7ea5b4"   # md5(pg_get_functiondef) de private.cartera_potencial_fn, ídem
MD5_ENVOLTORIO = "4a896597486e8b23788a2b2497f16309"  # md5(pg_get_functiondef) de crm.resumen_cartera_fn, guarda 7 de 20261001212341

ini = mig.index("create function crm.cartera_filtrada_fn(")
fin_fn = mig.index("\n$$;\n", ini) + len("\n$$;\n")
funcion = mig[ini:fin_fn]
# Permisos y comentario de la firma de 13, tal como los dejó su migración.
fin_acl = mig.index("\n\n", mig.index("comment on function " + F13, fin_fn)) + 1
permisos = mig[fin_fn:fin_acl]
assert permisos.count("revoke all on function " + F13) == 1 and permisos.count("grant execute on function " + F13) == 1
razon = re.search(r"\n  razon = ('(?:[^']|'')*')\nfrom pg_proc p", mig[fin_acl:]).group(1)
cuerpo = funcion[funcion.index(" as $$") + len(" as $$"):funcion.rindex("$$;")]
md5_prosrc = hashlib.md5(cuerpo.encode("utf-8")).hexdigest()

anterior = f"""-- GENERADO por banco/generar-anterior-y-reversa.py. No editar a mano.
-- La función ANTERIOR a la entrega B (crm.cartera_filtrada_fn, firma de 13, de
-- 20261001154153_crm_cartera_filtro_gestion.sql), tal cual, como pg_temp.cartera_filtrada_anterior.
-- Va delante de prueba-filtro.sql (misma sesión): es la vara de la igualdad. md5 del cuerpo: {md5_prosrc}.
{funcion.replace("create function crm.cartera_filtrada_fn(", "create function pg_temp.cartera_filtrada_anterior(", 1)}
grant execute on function pg_temp.cartera_filtrada_anterior(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) to authenticated;
"""

reversa = f"""-- GENERADO por banco/generar-anterior-y-reversa.py. No editar a mano.
-- REVERSA de 20261001212341_crm_cartera_filtro_potencial (fase 3, entrega B).
-- ANTES: retirar el frente que envía `p_potencial` (con la firma de 13 recibiría PGRST202).
-- Quita la firma de 14 y el ayudante private.cartera_potencial_fn, reinstala la de 13 byte a byte
-- (md5 {MD5_13}, el del postflight de 20261001154153), devuelve la exención analítica a su firma
-- con su razón y resella. No toca datos: las marcas y su historial se quedan. Conserva la fila de
-- schema_migrations: anotarlo en MIGRACIONES.md. Debe correr ANTES que la reversa de la migración
-- de gestión (`scripts/cartera-gestion/reversa.sql`), que exige la firma de 13.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';
set local quote_all_identifiers = off;

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $guarda$
begin
  if (
    to_regprocedure('{F13}') is null
    and to_regprocedure('{F14}') is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure('{F14}'))) = '{MD5_14}'
    and to_regprocedure('private.cartera_potencial_fn()') is not null
    and md5(pg_get_functiondef(to_regprocedure('private.cartera_potencial_fn()'))) = '{MD5_AYUDANTE}'
  ) is not true then
    raise exception 'REVERSA filtro_potencial: la entrega B no esta aplicada tal como se publico';
  end if;
  if (
    exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto = '{F14L}' and c.declarada and c.huella_ok)
    and (select s.sello from private.analitica_lc_sello s where s.id)
          = private.huella_exenciones_analitica_lc()
  ) is not true then
    raise exception 'REVERSA filtro_potencial: la declaracion analitica no esta vigente y sellada';
  end if;
  -- Nadie más depende del ayudante: solo lo nombra la cartera.
  if exists (select 1 from pg_proc p
              where p.prosrc ilike '%cartera_potencial_fn%'
                and p.oid not in (to_regprocedure('{F14}'), to_regprocedure('private.cartera_potencial_fn()'))) then
    raise exception 'REVERSA filtro_potencial: otra funcion usa private.cartera_potencial_fn';
  end if;
  -- Ni hay un consumidor de servidor nuevo de la cartera. plpgsql enlaza tarde: uno que ya pase el
  -- argumento 14 (con `=>`, con `:=` o por posición) fallaría al EJECUTARSE, no ahora. Por eso no
  -- se busca una forma de llamar: se exige el mismo censo estricto que la migración (su guarda 7),
  -- el envoltorio `crm.resumen_cartera_fn` con el cuerpo ensayado y nadie más (Codex f3b r2).
  if (
    (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text)
       from pg_proc p where p.prosrc ~* 'cartera_filtrada_fn') = 'crm.resumen_cartera_fn()'
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = '{MD5_ENVOLTORIO}'
  ) is not true then
    raise exception 'REVERSA filtro_potencial: los consumidores de servidor de la cartera no son los ensayados (revisarlos antes de quitar el argumento 14)';
  end if;
end;
$guarda$;

create temporary table cartera_potencial_reversa on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid = '{F14}'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
    from private.contadores_crudos_leads_citas() c
    where not (c.declarada and c.huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by e.objeto)
    from private.analitica_leads_citas_exenciones e
    where e.objeto <> '{F14L}') as otras,
  (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
    from private.analitica_leads_citas_exenciones e
    where e.objeto = '{F14L}') as declaracion,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

drop function {F14};

{funcion}{permisos}
update private.analitica_leads_citas_exenciones e set
  objeto = p.oid::regprocedure::text,
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\\n]*',' ','g'),'/\\*.*?\\*/',' ','g')),
  razon = {razon}
from pg_proc p
where p.oid = '{F13}'::regprocedure
  and e.objeto = '{F14L}';
update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

drop function private.cartera_potencial_fn();

do $post$
declare
  pre record;
begin
  select * into strict pre from pg_temp.cartera_potencial_reversa;
  if (
    to_regprocedure('{F14}') is null
    and to_regprocedure('private.cartera_potencial_fn()') is null
    and to_regprocedure('{F13}') is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure('{F13}'))) = '{MD5_13}'
    and not has_function_privilege('anon', '{F13}', 'EXECUTE')
    and not has_function_privilege('service_role', '{F13}', 'EXECUTE')
    and has_function_privilege('authenticated', '{F13}', 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure('{F13}')) p) = pre.contrato
  ) is not true then
    raise exception 'REVERSA filtro_potencial: la firma de 13 no quedo como estaba';
  end if;
  if (
    (select s.sello from private.analitica_lc_sello s where s.id)
      = private.huella_exenciones_analitica_lc()
    and (select count(*) from private.contadores_crudos_leads_citas()) = pre.censo
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = '{F13L}' and c.declarada and c.huella_ok)
    and (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
           from private.contadores_crudos_leads_citas() c
          where not (c.declarada and c.huella_ok)) = pre.censo_rojo
    and (select jsonb_agg(to_jsonb(e) order by e.objeto)
           from private.analitica_leads_citas_exenciones e
          where e.objeto <> '{F13L}') is not distinct from pre.otras
    and (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
           from private.analitica_leads_citas_exenciones e
          where e.objeto = '{F13L}') = pre.declaracion
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = pre.resumen_md5
  ) is not true then
    raise exception 'REVERSA filtro_potencial: cambio un contador, una declaracion o un consumidor ajeno';
  end if;
  raise notice 'REVERSA filtro_potencial OK: firma unica de 13 (md5 {MD5_13[:8]}…), sin ayudante, declaracion analitica devuelta y sellada. Las marcas se conservan.';
end;
$post$;
notify pgrst, 'reload schema';
commit;
"""

salidas = {os.path.join(aqui, "anterior-13.sql"): anterior, os.path.join(raiz, "reversa-filtro.sql"): reversa}
if "--comprobar" in sys.argv:
    mal = [os.path.basename(r) for r, t in salidas.items() if not os.path.exists(r) or io.open(r, encoding="utf-8").read() != t]
    print("generados al día" if not mal else "DESACTUALIZADOS: " + ", ".join(mal))
    sys.exit(1 if mal else 0)
for ruta, texto in salidas.items():
    io.open(ruta, "w", encoding="utf-8").write(texto)
    print(os.path.basename(ruta), len(texto.splitlines()), "líneas")
print("md5 del cuerpo (prosrc) de la firma de 13:", md5_prosrc)

#!/usr/bin/env bash
# Ciclo completo de la FASE 3, entrega B (20261001212341_crm_cartera_filtro_potencial) en el BANCO
# Docker propio. Nunca contra producción. Exige las fases 1, 2 y 3A, la migración de gestión
# (20261001154153) y el trinquete analítico SEMBRADO (un volcado de solo esquema lo deja vacío:
# scripts/cartera-gestion/siembra-control-banco.sql). Deja la migración aplicada y registrada.
#
#   BANCO_CONTENEDOR=avancecorp-potencial-20261001 bash banco/ciclo-fase3b.sh
#
# Qué corre:
#   1 · ciclo: migración → repetida (se niega) → reversa → repetida (se niega) → la firma de 13 vuelve
#       byte a byte → migración; con la foto de los trinquetes sin, con y tras la reversa
#   2 · prueba-filtro.sql (con la función anterior delante), las fases 1, 2 y 3A sin regresión y el
#       oráculo de la regla de gestión de scripts/cartera-gestion contra la firma de 14
#   3 · mutantes de LÓGICA sobre prueba-filtro.sql (cada uno debe hacerla fallar)
#   4 · mutantes de la MIGRACIÓN (postflight) y del PREFLIGHT: deben ser rechazados
#   5 · la medición (medir-filtro.sql): la función anterior contra la nueva, sin y con filtro
#   6 · registrar ×2, verificar, y el verificador frente a dos estados malos (debe verlos)
# Termina con un VEREDICTO de máquina: sale con 1 si algún paso no dio lo esperado, si un mutante
# de lógica sobrevivió o si un mutante de migración no fue rechazado.
set -uo pipefail
C="${BANCO_CONTENEDOR:-avancecorp-potencial-20261001}"
D="$(cd "$(dirname "$0")/../../.." && pwd)"   # …/supabase
P="$D/scripts/potencial-lead"
V=20261001212341
M="$D/migrations/${V}_crm_cartera_filtro_potencial.sql"
R="$P/reversa-filtro.sql"
A="$P/banco/anterior-13.sql"
G="$D/scripts/cartera-gestion/test-cartera-gestion.sql"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
MALOS=0
# paso <etiqueta> <salida> <patrón que debe aparecer>: imprime y anota si no dio lo esperado.
paso() { if grep -q -- "$3" <<<"$2"; then echo "$1 $2"; else echo "$1 $2   ← ¡NO ES LO ESPERADO! (se esperaba: $3)"; MALOS=$((MALOS + 1)); fi; }

q() { docker exec -i -e PGPASSWORD=postgres "$C" psql -U "${2:-postgres}" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt -c "$1" 2>&1; }
archivo() { docker cp "$1" "$C:/tmp/x.sql" >/dev/null; docker exec -e PGPASSWORD=postgres "$C" psql -U "${2:-postgres}" -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -q -f /tmp/x.sql 2>&1; }
msg() { local o; o=$(archivo "$1"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-150; else grep -o 'NOTICE:.*' <<<"$o" | tail -1 | cut -c1-175; fi; }
rechazo() { local o; o=$(archivo "$1"); if grep -q 'ERROR:' <<<"$o"; then grep -m1 -o 'ERROR:.*' <<<"$o" | cut -c1-140; else echo "SIN ERROR (¡el mutante pasó!)"; fi; }
sint() { archivo "$1" supabase_admin | grep -o 'FILTRO.*\|LECTURA.*\|CADUCIDAD.*\|SINTETICA.*\|MEDIR.*\|ERROR:.*' | head -1 | cut -c1-"${2:-330}"; }
trinquetes() { docker cp "$P/banco/trinquetes.sql" "$C:/tmp/t.sql" >/dev/null; docker exec -e PGPASSWORD=postgres "$C" psql -U postgres -h 127.0.0.1 -d postgres -qAt -f /tmp/t.sql 2>&1 | sed 's/^psql:[^ ]* NOTICE:  //'; }
# La foto sin la fila de la cartera en el censo (esa fila cambia de firma y de huella a propósito).
ajenos() { python3 -c '
import sys
for l in sys.stdin.read().splitlines():
    if l.startswith("CENSO "):
        f = [x for x in l[6:].split(" ;; ") if "crm.cartera_filtrada_fn(" not in x]
        print("CENSO (sin la cartera) %d filas: %s" % (len(f), " ;; ".join(f)))
    else:
        print(l)' < "$1"; }
cartera_en_censo() { python3 -c '
import sys
for l in sys.stdin.read().splitlines():
    if l.startswith("CENSO "):
        f = [x for x in l[6:].split(" ;; ") if "crm.cartera_filtrada_fn(" in x]
        print(" · ".join(f) if f else "(no está)")' < "$1"; }
aplicada() { q "select (to_regprocedure('private.cartera_potencial_fn()') is not null)::int"; }
md5fn() { q "set search_path = ''; select coalesce((select string_agg(md5(pg_get_functiondef(p.oid)), ',') from pg_proc p where p.proname = 'cartera_filtrada_fn' and p.pronamespace = 'crm'::regnamespace), '(sin función)')" | tail -1; }
estado() { echo "ayudante=$(aplicada), md5 de la cartera=$(md5fn), SELECT de authenticated sobre la tabla de marcas=$(q "select has_table_privilege('authenticated','crm.lead_potencial','SELECT') or has_any_column_privilege('authenticated','crm.lead_potencial','SELECT')"), sello vigente=$(q "select (select s.sello from private.analitica_lc_sello s where s.id) = private.huella_exenciones_analitica_lc()")"; }

if [ "$(q "select (to_regclass('crm.lead_potencial') is not null and to_regprocedure('crm.potencial_leads_fn(uuid[])') is not null)::int")" != "1" ]; then
  echo "Faltan las fases 1, 2 y 3A en el banco: corre antes banco/ciclo-fase1.sh, ciclo-fase2.sh y ciclo-fase3a.sh." >&2; exit 2
fi
if [ "$(q "select (select count(*) from private.analitica_lc_sello) > 0")" != "t" ]; then
  echo "El trinquete analítico está vacío (banco de solo esquema): corre antes scripts/cartera-gestion/siembra-control-banco.sql." >&2; exit 2
fi
if ! python3 "$P/banco/generar-anterior-y-reversa.py" --comprobar; then
  echo "Regenera con: python3 banco/generar-anterior-y-reversa.py" >&2; exit 2
fi
[ "$(aplicada)" = "1" ] && echo "0 reversa del estado previo: $(msg "$R")"
if [ "$(md5fn)" != "bf06666fb8ef533a39a50c7d70420153" ]; then
  echo "La cartera del banco no es la firma de 13 de 20261001154153 (md5 $(md5fn)): aplica antes esa migración." >&2; exit 2
fi

echo "── 1 · ciclo"
trinquetes > "$T/sin.txt"
paso "1 migración:       " "$(msg "$M")" 'cartera_filtro_potencial OK'
paso "2 repetida:        " "$(rechazo "$M")" 'ERROR:  PREFLIGHT'
trinquetes > "$T/con.txt"
paso "3 reversa:         " "$(msg "$R")" 'REVERSA filtro_potencial OK'
paso "4 reversa repetida:" "$(rechazo "$R")" 'ERROR:  REVERSA filtro_potencial'
paso "5 tras la reversa: " "md5 de la cartera $(md5fn), ayudante=$(aplicada)" 'md5 de la cartera bf06666fb8ef533a39a50c7d70420153, ayudante=0'
trinquetes > "$T/rev.txt"
paso "6 migración:       " "$(msg "$M")" 'cartera_filtro_potencial OK'
ajenos "$T/sin.txt" > "$T/sin-a.txt"; ajenos "$T/con.txt" > "$T/con-a.txt"
if diff -q "$T/sin-a.txt" "$T/con-a.txt" >/dev/null; then
  echo "7 trinquetes:       idénticos sin y con la migración, salvo la fila de la cartera ($(grep -c 'pasa$' "$T/con.txt") pasan, $(grep -c 'cae:' "$T/con.txt") caen igual, $(grep -o 'CENSO (sin la cartera) [0-9]* filas' "$T/con-a.txt"))"
else
  echo "7 trinquetes:       ¡CAMBIARON!"; diff "$T/sin-a.txt" "$T/con-a.txt" | cut -c1-220 | head -12; MALOS=$((MALOS + 1))
fi
paso "  la cartera en el censo, antes:  " "$(cartera_en_censo "$T/sin.txt" | cut -c1-230)" 'boolean,text)",t,t)'
paso "  la cartera en el censo, después:" "$(cartera_en_censo "$T/con.txt" | cut -c1-230)" 'boolean,text,text)",t,t)'
if diff -q "$T/sin.txt" "$T/rev.txt" >/dev/null; then echo "8 tras la reversa:  la foto entera es la de antes (censo incluido)"; else echo "8 tras la reversa:  ¡la foto NO es la de antes!"; diff "$T/sin.txt" "$T/rev.txt" | cut -c1-220 | head -8; MALOS=$((MALOS + 1)); fi

echo "── 2 · pruebas"
cat "$A" "$P/prueba-filtro.sql" > "$T/prueba.sql"
paso "9  filtro:           " "$(sint "$T/prueba.sql")" 'FILTRO potencial_lead: \([0-9]*\) de \1 OK'
paso "10 fase 1 intacta:   " "$(sint "$P/prueba-sintetica.sql")" 'SINTETICA potencial_lead: 75 de 75 OK'
paso "11 fase 2 intacta:   " "$(sint "$P/prueba-caducidad.sql")" 'CADUCIDAD potencial_lead: 51 de 51 OK'
paso "12 fase 3A intacta:  " "$(sint "$P/prueba-lectura.sql")" 'LECTURA potencial_lead: 94 de 94 OK'
# El oráculo de la regla de gestión es de otra sesión y está atado a la firma de 13 (su propio ensayo
# parte de la de 12): aquí se corre contra la de 14 cambiando SOLO la firma y su única aserción de
# forma. El archivo de ellos no se toca.
if python3 - "$G" "$T/gestion.sql" <<'PY'
import io, sys
t = io.open(sys.argv[1], encoding="utf-8").read()
f13 = "crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)"
assert t.count(f13) >= 1, "el oráculo de gestión ya no nombra la firma de 13"
# Su única aserción de FORMA exige que p_gestion sea el último de 13: ahora es el 13.º de 14.
vieja = """  perform pg_temp.afirmar(p.pronargs = 13 and p.pronargdefaults = 13 and p.proargnames[13] = 'p_gestion'
    and right(pg_get_function_arguments(p.oid), 35) = ', p_gestion text DEFAULT NULL::text', 'el 13.o argumento es p_gestion text default null, al final');"""
nueva = """  perform pg_temp.afirmar(p.pronargs = 14 and p.pronargdefaults = 14 and p.proargnames[13] = 'p_gestion' and p.proargnames[14] = 'p_potencial'
    and pg_get_function_arguments(p.oid) like '%, p_gestion text DEFAULT NULL::text, p_potencial text DEFAULT NULL::text', 'el 13.o argumento es p_gestion text default null y el 14.o p_potencial');"""
assert t.count(vieja) == 1, "el oráculo de gestión cambió su aserción de forma"
io.open(sys.argv[2], "w", encoding="utf-8").write(t.replace(vieja, nueva).replace(f13, f13[:-1] + ",text)"))
PY
then
  paso "13 regla de gestión: " "$(archivo "$T/gestion.sql" | grep -o 'CARTERA_GESTION_OK.*\|ORACULO.*\|ERROR:.*' | head -1 | cut -c1-220) (oráculo de scripts/cartera-gestion contra la firma de 14)" 'CARTERA_GESTION_OK 128/128'
else
  echo "13 regla de gestión:  NO SE PUDO ADAPTAR el oráculo de scripts/cartera-gestion (ver el error de arriba)"; MALOS=$((MALOS + 1))
fi

echo "── 3 · mutantes de lógica (la prueba del filtro debe reportar fallas)"
python3 - "$T" <<'PY'
import sys
T = sys.argv[1]
t = open(f"{T}/prueba.sql").read()
def cuerpo(n, fn, a, b):
    return f"""do $m$ declare d text := pg_get_functiondef('{fn}'::regprocedure);
begin
  if position($a${a}$a$ in d) = 0 then raise exception 'mutante {n}: no encontré el fragmento'; end if;
  execute replace(d, $a${a}$a$, $b${b}$b$);
end $m$;
"""
def mut(n, *pares):
    assert t.count("begin;\n") >= 1
    open(f"{T}/m-{n}.sql", "w").write(t.replace("begin;\n", "begin;\n" + "".join(cuerpo(n, *p) for p in pares), 1))
FN = "crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)"
AY = "private.cartera_potencial_fn()"
GATE = "if v_uid is null or private.puede_acceder_crm() is not true then"
PROPIOS = "        l.vendedor_id = any (v_visibles)\n"
BANDEJA = "        or (l.vendedor_id is null and l.asignado_supervisor_id = any (v_visibles))\n"
mut("ayu-sin-bandera", (AY, "if crm.bandera_activa('potencial_lead') is not true then", "if false then"))
mut("ayu-sin-gate", (AY, GATE, "if v_uid is null then"))
mut("ayu-sin-sesion-ni-gate", (AY, GATE, "if false then"))
mut("ayu-ve-inactivos", (AY, "where l.activo = true", "where true"))
mut("ayu-todo-global", (AY, PROPIOS, "        true\n"))
mut("ayu-sin-propios", (AY, PROPIOS, "        false\n"))
mut("ayu-sin-bandeja", (AY, BANDEJA, ""))
mut("ayu-sin-gerencia", (AY, "        or v_rol = 'gerencia'\n", ""))
mut("ayu-sin-lector", (AY, "        or v_lector\n", ""))
# El ámbito ancho que se descartó: quien opera el reparto leería las marcas de una bandeja que su RLS no le deja ver.
mut("ayu-con-reparto", (AY, BANDEJA, BANDEJA + "        or (l.vendedor_id is null and private.cartera_puede_operar_reparto_fn())\n"))
mut("fn-sin-bandera", (FN, "if p_potencial is not null and not v_potencial then", "if false then"))
mut("fn-clave-siempre", (FN, "|| case when v_potencial then jsonb_build_object('potencial'", "|| case when true then jsonb_build_object('potencial'"))
mut("fn-potencial-sin-ambito", (FN, "    and (coalesce(v_global, false) or cardinality(v_visibles) > 0);", "    and true;"))
mut("fn-llama-siempre", (FN, "from private.cartera_potencial_fn() m where v_potencial", "from private.cartera_potencial_fn() m"))
mut("fn-sin-validar", (FN, "     or (p_potencial is not null and p_potencial not in ('estrella','tibio','frio','sin_marca'))\n", ""))
mut("fn-no-recorta", (FN, "    where p_potencial is null\n      or (p_potencial = 'sin_marca' and pv.potencial_nivel is null)\n      or pv.potencial_nivel = p_potencial\n", "    where true\n"))
mut("fn-sin-marca-rota", (FN, "      or (p_potencial = 'sin_marca' and pv.potencial_nivel is null)\n", ""))
mut("fn-sin-marca-trae-todo", (FN, "(p_potencial = 'sin_marca' and pv.potencial_nivel is null)", "(p_potencial = 'sin_marca')"))
mut("fn-conteos-tras-filtro", (FN, "'sin_marca',count(*) filter(where pv.potencial_nivel is null)) from previa pv))", "'sin_marca',count(*) filter(where pv.potencial_nivel is null)) from base pv))"))
mut("fn-columna-viaja", (FN, "to_jsonb(f) - 'potencial_nivel'", "to_jsonb(f)"))
mut("fn-sin-eco", (FN, "'filtro',p_potencial,", "'filtro',null,"))
mut("fn-estrella-cuenta-tibio", (FN, "'estrella',count(*) filter(where pv.potencial_nivel='estrella')", "'estrella',count(*) filter(where pv.potencial_nivel='tibio')"))
mut("fn-frio-cuenta-sin-marca", (FN, "'frio',count(*) filter(where pv.potencial_nivel='frio')", "'frio',count(*) filter(where pv.potencial_nivel is null)"))
mut("fn-totales-de-previa", (FN, "    from base\n  ), capital as (", "    from previa\n  ), capital as ("))
mut("fn-pagina-de-previa", (FN, "    select b.* from base b\n", "    select b.* from previa b\n"))
mut("fn-sin-union", (FN, "    left join marcas mk on mk.lead_id = l.id\n", "    left join marcas mk on false\n"))
mut("fn-embudo-de-previa", (FN, "(select count(*) from base b where b.etapa=e.etapa)", "(select count(*) from previa b where b.etapa=e.etapa)"))
# Solo el envoltorio DEFINER falla: el verificador de sumas tiene que contar esas respuestas como malas.
mut("fn-envoltorio-falla", (FN, "  if v_uid is null or not private.puede_acceder_crm() then", "  if current_user = 'postgres' then raise exception 'roto' using errcode = 'P0778'; end if;\n  if v_uid is null or not private.puede_acceder_crm() then"))
PY
for f in "$T"/m-*.sql; do
  o="$(sint "$f" 170)"; printf "  %-30s → %s\n" "$(basename "$f" .sql)" "$o"
  grep -q 'FALLAS de' <<<"$o" || { echo "      ↑ ¡el mutante SOBREVIVIÓ o no se pudo aplicar!"; MALOS=$((MALOS + 1)); }
done
# El mutante del envoltorio tiene que ser visto por el verificador de sumas, no solo por los tres casos sueltos.
paso "  el verificador de sumas ve el envoltorio roto:" "$(archivo "$T/m-fn-envoltorio-falla.sql" supabase_admin | grep -o 'los cuatro conteos suman[^|]*' | head -1 | cut -c1-200)" 'esperado 18 respuestas, 0 malas, obtenido 18 respuestas, 9 malas'

echo "── 4 · mutantes de la migración y del preflight (deben ser rechazados)"
python3 - "$T" "$M" "$R" <<'PY'
import sys
T, M, R = sys.argv[1:]
CAB = "begin;\nset local lock_timeout = '10s';\nset local statement_timeout = '30s';\nset local search_path = '';\nset local quote_all_identifiers = off;\n"
FIN = "notify pgrst, 'reload schema';\ncommit;"
def cuerpo(p):
    t = open(p).read()
    assert t.count(CAB) == 1 and t.count(FIN) == 1, p
    t = t.replace(CAB, "", 1)
    return t[:t.rindex(FIN)]
m, rev = cuerpo(M), cuerpo(R)
F13 = "crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)"
F14 = F13[:-1] + ",text)"
def mut(n, a, b):
    assert m.count(a) == 1, (n, m.count(a))
    open(f"{T}/mf-post-{n}.sql", "w").write(CAB + rev + "\n" + m.replace(a, b, 1) + "\ncommit;\n")
def pre(n, antes):
    open(f"{T}/mf-pre-{n}.sql", "w").write(CAB + rev + "\n" + antes + "\n" + m + "\ncommit;\n")
AYU = "returns table(lead_id uuid, nivel text)\nlanguage plpgsql stable security definer set search_path = '' as $$"
G_AYU = "grant execute on function private.cartera_potencial_fn() to authenticated;"
R_AYU = "revoke all on function private.cartera_potencial_fn() from public, anon, authenticated, service_role;\n"
G_FN = f"grant execute on function {F14} to authenticated;"
CAR = "returns jsonb language plpgsql stable security invoker set search_path = '' as $$"
MOVER = m[m.index("update private.analitica_leads_citas_exenciones e set"):m.index("update private.analitica_lc_sello")]
SELLAR = m[m.index("update private.analitica_lc_sello"):m.index("do $postflight$")]
mut("ayudante-invoker", AYU, AYU.replace("security definer", "security invoker"))
mut("ayudante-volatil", AYU, AYU.replace("stable", "volatile"))
mut("ayudante-sin-search-path", AYU, AYU.replace(" set search_path = ''", ""))
mut("ayudante-set-de-mas", AYU, AYU.replace(" set search_path = ''", " set search_path = '' set statement_timeout = '30s'"))
mut("ayudante-a-anon", G_AYU, G_AYU.replace("to authenticated;", "to authenticated, anon;"))
mut("ayudante-a-service-role", G_AYU, G_AYU.replace("to authenticated;", "to authenticated, service_role;"))
mut("ayudante-con-opcion", G_AYU, G_AYU.replace("to authenticated;", "to authenticated with grant option;"))
mut("ayudante-publico", R_AYU, "")
mut("ayudante-sin-grant", G_AYU, "")
mut("ayudante-cuenta", "  v_visibles := array(select private.vendedor_ids_visibles(v_uid));\n  return query\n", "  v_visibles := array(select private.vendedor_ids_visibles(v_uid));\n  perform (select count(*) from crm.leads x where false);\n  return query\n")
# Codex f3b r1: el ámbito abierto CONSERVANDO el gate y la bandera; solo lo ve la huella del ayudante.
mut("ayudante-ambito-abierto", "        l.vendedor_id = any (v_visibles)\n        or (l.vendedor_id is null", "        true\n        or (l.vendedor_id is null")
mut("ayudante-sin-sesion", "  if v_uid is null or private.puede_acceder_crm() is not true then\n    raise exception 'No autorizado' using errcode = '42501';\n  end if;\n  -- Con la bandera apagada", "  if false then\n    raise exception 'No autorizado' using errcode = '42501';\n  end if;\n  -- Con la bandera apagada")
mut("cuerpo-cambiado", "  v_potencial := crm.bandera_activa('potencial_lead') is true\n    and (coalesce(v_global, false) or cardinality(v_visibles) > 0);\n", "  v_potencial := true;\n")
mut("cartera-definer", CAR, CAR.replace("security invoker", "security definer"))
mut("cartera-a-service-role", G_FN, G_FN.replace("to authenticated;", "to authenticated, service_role;"))
mut("cartera-a-anon", G_FN, G_FN.replace("to authenticated;", "to authenticated, anon;"))
mut("sin-mover-la-declaracion", MOVER, "")
mut("sin-resellar", SELLAR, "")
mut("abre-la-tabla", "do $postflight$", "grant select (lead_id, nivel) on crm.lead_potencial to authenticated;\ndo $postflight$")
mut("toca-otra-declaracion", "do $postflight$", "update private.analitica_leads_citas_exenciones set razon = razon || ' x' where objeto = (select min(e.objeto) from private.analitica_leads_citas_exenciones e where e.objeto not like 'crm.cartera\\_filtrada\\_fn(%');\nupdate private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;\ndo $postflight$")
mut("cambia-la-clase", "do $postflight$", "update private.analitica_leads_citas_exenciones set clase = 'mixta' where objeto like 'crm.cartera\\_filtrada\\_fn(%';\nupdate private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;\ndo $postflight$")
mut("toca-el-envoltorio", "do $postflight$", "alter function crm.resumen_cartera_fn() set statement_timeout = '30s';\ndo $postflight$")
mut("otro-consumidor", "do $postflight$", "create function crm.mutante_fn() returns jsonb language sql stable as 'select crm.cartera_filtrada_fn(p_limite => 1)';\ndo $postflight$")
mut("policy-cambia-durante", "do $postflight$", "alter policy leads_select on crm.leads using (activo = true);\ndo $postflight$")
pre("funcion-cambiada", f"do $x$ begin execute replace(pg_get_functiondef('{F13}'::regprocedure), 'v_salida jsonb;', 'v_salida jsonb; v_x integer;'); end $x$;")
pre("sobrecarga", "create function crm.cartera_filtrada_fn(p_x integer) returns jsonb language sql as 'select null::jsonb';")
pre("ayudante-ya-existe", "create function private.cartera_potencial_fn() returns table(lead_id uuid, nivel text) language sql as 'select null::uuid, null::text where false';")
pre("huella-vieja", "update private.analitica_leads_citas_exenciones set huella = 'x' where objeto like 'crm.cartera\\_filtrada\\_fn(%';")
pre("sello-roto", "update private.analitica_lc_sello set sello = 'x' where id;")
pre("select-a-la-api", "grant select on crm.lead_potencial to authenticated;")
pre("select-por-columna", "grant select (lead_id, nivel) on crm.lead_potencial to authenticated;")
pre("select-a-anon", "grant select on crm.lead_potencial to anon;")
pre("sin-rls", "alter table crm.lead_potencial disable row level security;")
pre("sin-bandera", "delete from crm.multiempresa_flags where nombre = 'potencial_lead';")
pre("columna-nueva", "alter table crm.lead_potencial add column x integer;")
pre("nivel-nuevo", "alter type crm.nivel_potencial add value 'caliente';")
pre("ayudante-de-ambito-cambiado", "alter function private.es_lector_global() set statement_timeout = '30s';")
pre("clase-cambiada", "update private.analitica_leads_citas_exenciones set clase = 'mixta' where objeto like 'crm.cartera\\_filtrada\\_fn(%';\nupdate private.analitica_lc_sello set sello = private.huella_exenciones_analitica_lc() where id;")
pre("actividades-abiertas", "create policy mutante_all on crm.actividades for all to authenticated using (true) with check (true);")
pre("select-de-columna-a-anon", "grant select (lead_id) on crm.lead_potencial to anon;")
pre("leads-sin-rls", "alter table crm.leads disable row level security;")
pre("sin-indice-unico", "alter table crm.lead_potencial drop constraint lead_potencial_lead_unico;")
pre("sin-usage-de-private", "revoke usage on schema private from authenticated;")
pre("policy-de-lectura-nueva", "create policy lectura_mutante on crm.leads as restrictive for select to authenticated using (true);")
pre("policy-cambiada", "alter policy leads_select on crm.leads using (activo = true);")
pre("gate-cambiado", "alter policy crm_actor_activo_gate on crm.leads using (true);")
pre("envoltorio-cambiado", "alter function crm.resumen_cartera_fn() set statement_timeout = '30s';")
pre("otro-consumidor", "create function crm.mutante_fn() returns jsonb language sql stable as 'select crm.cartera_filtrada_fn(p_limite => 1)';")
pre("visibles-cambiado", "alter function private.vendedor_ids_visibles(uuid) volatile;")
pre("bandera-sin-execute", "revoke execute on function crm.bandera_activa(text) from authenticated;")
pre("bandera-a-anon", "grant execute on function crm.bandera_activa(text) to anon;")
PY
for f in "$T"/mf-*.sql; do
  o="$(rechazo "$f")"; printf "  %-34s → %s\n" "$(basename "$f" .sql | sed 's/^mf-//')" "$o"
  grep -q '^ERROR:' <<<"$o" || { echo "      ↑ ¡el mutante NO fue rechazado!"; MALOS=$((MALOS + 1)); }
done
# La REVERSA frente a estados que no debe aceptar (con la migración aplicada; todo se deshace).
python3 - "$T" "$R" <<'PY'
import sys
T, R = sys.argv[1:]
CAB = "begin;\nset local lock_timeout = '10s';\nset local statement_timeout = '30s';\nset local search_path = '';\nset local quote_all_identifiers = off;\n"
rev = open(R).read()
assert rev.count(CAB) == 1
rev = rev.replace(CAB, "", 1)
def antes(n, sql):
    open(f"{T}/mr-{n}.sql", "w").write(CAB + sql + "\n" + rev)
# Un consumidor de servidor que ya pasa el argumento 14, en las tres formas de llamar.
antes("consumidor-con-flecha", "create function crm.mutante_fn() returns jsonb language plpgsql stable as $m$ begin return crm.cartera_filtrada_fn(p_limite => 1, p_potencial => 'estrella'); end $m$;")
antes("consumidor-con-dos-puntos", "create function crm.mutante_fn() returns jsonb language plpgsql stable as $m$ begin return crm.cartera_filtrada_fn(p_limite := 1, p_potencial := 'estrella'); end $m$;")
antes("consumidor-por-posicion", "create function crm.mutante_fn() returns jsonb language plpgsql stable as $m$ begin return crm.cartera_filtrada_fn(1, null, null, null, null, false, null, null, null, null, null, false, null, 'estrella'); end $m$;")
antes("envoltorio-cambiado", "alter function crm.resumen_cartera_fn() set statement_timeout = '30s';")
antes("ayudante-ensanchado", "do $x$ begin execute replace(pg_get_functiondef('private.cartera_potencial_fn()'::regprocedure), 'l.vendedor_id = any (v_visibles)', 'true'); end $x$;")
antes("otra-funcion-usa-el-ayudante", "create function private.mutante_fn() returns bigint language sql stable as 'select 1::bigint from private.cartera_potencial_fn() limit 1';")
antes("cartera-cambiada", "do $x$ begin execute replace(pg_get_functiondef('crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)'::regprocedure), 'v_salida jsonb;', 'v_salida jsonb; v_x integer;'); end $x$;")
antes("sello-roto", "update private.analitica_lc_sello set sello = 'x' where id;")
PY
for f in "$T"/mr-*.sql; do
  o="$(rechazo "$f")"; printf "  %-34s → %s\n" "reversa-$(basename "$f" .sql | sed 's/^mr-//')" "$o"
  grep -q '^ERROR:  REVERSA filtro_potencial' <<<"$o" || { echo "      ↑ ¡la reversa NO se negó!"; MALOS=$((MALOS + 1)); }
done
paso "  tras los mutantes:" "$(estado)" 'ayudante=1, md5 de la cartera=23a63cc3965472b9db85aa81cadffbeb, SELECT de authenticated sobre la tabla de marcas=f, sello vigente=t'

echo "── 5 · medición"
cat "$A" "$P/banco/medir-filtro.sql" > "$T/medir.sql"
paso "14" "$(sint "$T/medir.sql" 600)" 'MEDIR filtro'

echo "── 6 · registro y verificación"
if grep -q "md5 $(md5 -q "$M" 2>/dev/null || md5sum "$M" | cut -d' ' -f1)" "$P/registrar-filtro.sql"; then echo "15 el registrador lleva el md5 de la migración"; else echo "15 ¡el registrador NO coincide con la migración! Regenerar con banco/generar-registrador.py"; MALOS=$((MALOS + 1)); fi
paso "16 registrar:         " "$(msg "$P/registrar-filtro.sql")" 'REGISTRO: 20261001212341 / crm_cartera_filtro_potencial'
paso "17 registrar otra vez:" "$(msg "$P/registrar-filtro.sql")" 'REGISTRO: 20261001212341 / crm_cartera_filtro_potencial'
paso "18 verificar:         " "$(q "$(cat "$P/verificar-filtro.sql")" | grep -o 'VERIFICAR.*' | cut -c1-1100)" 'md5 de la cartera 23a63cc3965472b9db85aa81cadffbeb (debe ser 23a63cc3965472b9db85aa81cadffbeb), md5 del ayudante 73e993d618b203cdbe21e8127f7ea5b4 (debe ser 73e993d618b203cdbe21e8127f7ea5b4), ejecutan la cartera \[authenticated\] (debe ser authenticated), ejecutan el ayudante \[authenticated\] (debe ser authenticated), forma del ayudante \[DEFINER/s/search_path=""/postgres\]'
# El verificador frente a tres estados malos (se deshacen): debe decirlo.
paso "19 verificar con la tabla abierta por columna:" "$(q "begin; grant select (lead_id) on crm.lead_potencial to authenticated; $(cat "$P/verificar-filtro.sql")" | grep -o 'leen la tabla de marcas por la API \[[^]]*\]')" '\[authenticated\]'
paso "20 verificar con el ayudante abierto a PUBLIC: " "$(q "begin; grant execute on function private.cartera_potencial_fn() to public; $(cat "$P/verificar-filtro.sql")" | grep -o 'ejecutan el ayudante \[[^]]*\]')" '\[anon,authenticated,service_role\]'
paso "21 verificar con el ayudante ensanchado:       " "$(q "begin; do \$x\$ begin execute replace(pg_get_functiondef('private.cartera_potencial_fn()'::regprocedure), 'l.vendedor_id = any (v_visibles)', 'true'); end \$x\$; $(cat "$P/verificar-filtro.sql")" | grep -o 'md5 del ayudante [0-9a-f]*' | grep -v 73e993d618b203cdbe21e8127f7ea5b4)" 'md5 del ayudante [0-9a-f]*'
paso "   estado final:" "$(estado)" 'ayudante=1, md5 de la cartera=23a63cc3965472b9db85aa81cadffbeb, SELECT de authenticated sobre la tabla de marcas=f, sello vigente=t'
echo "── VEREDICTO"
if [ "$MALOS" -eq 0 ]; then echo "CICLO FASE 3B: TODO COMO SE ESPERABA"; else echo "CICLO FASE 3B: $MALOS RESULTADOS FUERA DE LO ESPERADO"; exit 1; fi

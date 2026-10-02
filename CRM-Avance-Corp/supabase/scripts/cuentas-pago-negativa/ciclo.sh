#!/usr/bin/env bash
# Ciclo completo de la migración «Retirar y Cambiar cuenta solo READ COMMITTED» en un BANCO Docker propio.
# Nunca contra producción. El banco se monta antes con supabase/scripts/potencial-lead/banco/montar-banco.sh
# (esquema de producción sin datos) y se le pasa por DB_URL. Cada paso se compara con lo esperado (✓/✗);
# el ciclo sale con 1 si hubo algún ✗.
#
#   DB_URL=postgresql://supabase_admin:postgres@127.0.0.1:55474/postgres bash supabase/scripts/cuentas-pago-negativa/ciclo.sh
#
# Tramos:
#   0 · banco listo: storage.objects mínimo (la imagen pelada no lo trae), auth.uid() como en producción, fotos
#   1 · mundo SIN la migración: la prueba de la negativa debe FALLAR (es el mutante natural: sin guarda no hay 0A000)
#   2 · migración → fila OK y huellas nuevas; otra vez → se niega y nada cambia
#   3 · prueba de la negativa PASS; las pruebas existentes de retirar y cambiar (cuentas-gloria) siguen PASS
#   4 · registrar → fila; otra vez → idempotente
#   5 · reversa en REPEATABLE READ → se niega; reversa → REVERTIDA, huellas de antes, registro borrado;
#       la prueba vuelve a FALLAR (mundo sin guarda); reaplicar + registrar → PASS otra vez
set -uo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"; SUPA="$(cd "$AQUI/../.." && pwd)"
: "${DB_URL:?Falta DB_URL del banco}"
MIG=$(ls "$SUPA"/migrations/*_crm_retirar_y_cambiar_cuenta_solo_read_committed.sql | tail -1)
VER=$(basename "$MIG" | cut -c1-14)
H_RET_VIVO=3ab8983f87f343e896acaefafbbcf4d4; H_CAM_VIVO=61bec6b3d7d7589e67b4740bd9e7d630
H_RET_NUEVO=$(grep -o "retirar vivo [0-9a-f]* → [0-9a-f]*" "$MIG" | awk '{print $5}'); H_CAM_NUEVO=$(grep -o "cambiar vivo [0-9a-f]* → [0-9a-f]*" "$MIG" | awk '{print $5}')
FALLOS=0; RES=()
ok()  { RES+=("✓ $1"); echo "✓ $1"; }
ko()  { RES+=("✗ $1"); echo "✗ $1"; FALLOS=$((FALLOS+1)); }
q()   { psql "$DB_URL" -qAt -v ON_ERROR_STOP=1 -c "$1"; }
huellas() { q "select string_agg(p.proname||':'||md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.oid in (to_regprocedure('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)'), to_regprocedure('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)'))"; }
acl() { q "select string_agg(p.proname||':'||coalesce(p.proacl::text,'null')||':'||p.prosecdef||':'||array_to_string(p.proconfig,','), ' ' order by p.proname) from pg_proc p where p.proname in ('retirar_cuenta_cliente_autorizado','cambiar_cuenta_pago_contratos_autorizado')"; }
registro() { q "select count(*) from supabase_migrations.schema_migrations where version = '$VER'"; }
espera_huellas() { local h; h=$(huellas); [[ "$h" == *"cambiar_cuenta_pago_contratos_autorizado:$1"* && "$h" == *"retirar_cuenta_cliente_autorizado:$2"* ]]; }

echo "── 0 · banco listo ──"
if espera_huellas "$H_CAM_NUEVO" "$H_RET_NUEVO"; then psql "$DB_URL" -v ON_ERROR_STOP=1 -qAt -f "$AQUI/reversa.sql" >/tmp/rev0.txt 2>&1 && ok "0.0 banco venía con la migración: revertida para partir de producción" || ko "0.0 no se pudo revertir el banco: $(tail -1 /tmp/rev0.txt)"; fi
q "create schema if not exists storage; create table if not exists storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid, owner_id text, metadata jsonb, created_at timestamptz default now(), updated_at timestamptz default now(), version text);" >/dev/null && ok "0.1 storage.objects mínimo (solo banco)"
q "create or replace function auth.uid() returns uuid language sql stable as \$\$ select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'sub')::uuid \$\$;" >/dev/null && ok "0.2 auth.uid() lee request.jwt.claims como producción (solo banco)"
q "alter table crm.producto_versiones disable trigger user; alter table crm.producto_condiciones disable trigger user; insert into crm.productos_inversion (id, codigo) values ('d0000000-0000-4000-8000-000000000000', 'BANCO-NEGATIVA') on conflict (id) do nothing; insert into crm.producto_versiones (id, producto_id, numero_version, estado, nombre, vigente_desde, publicada_en) values ('d0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000000', 1, 'publicada', 'BANCO PRODUCTO', '2026-01-01', now()) on conflict (id) do nothing; insert into crm.producto_condiciones (id, version_id, orden, categoria, moneda, plazo_meses, modalidad, tipo_interes, capital_minimo, capital_maximo, tasa_referencia, tasa_minima, tasa_maxima, activa) values ('d0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001', 1, 'nuevo', 'PEN', 12, 'semestral', 'simple', 100, 100000000, 12, 1, 50, true) on conflict (id) do nothing; alter table crm.producto_versiones enable trigger user; alter table crm.producto_condiciones enable trigger user;" >/dev/null && ok "0.4 catálogo mínimo d0…02 que usan las pruebas de cuentas-gloria (solo banco; igual que mundo-backfill.sql)" || ko "0.4 no se pudo sembrar el catálogo"
q "create schema if not exists supabase_migrations; create table if not exists supabase_migrations.schema_migrations (version text primary key, statements text[], name text);" >/dev/null
espera_huellas "$H_CAM_VIVO" "$H_RET_VIVO" && ok "0.3 huellas vivas = las de producción" || ko "0.3 huellas vivas distintas: $(huellas)"
ACL0=$(acl); COM0=$(q "select string_agg(coalesce(obj_description(p.oid,'pg_proc'),''), ' | ' order by p.proname) from pg_proc p where p.proname in ('retirar_cuenta_cliente_autorizado','cambiar_cuenta_pago_contratos_autorizado')")

python3 "$AQUI/generar-derivados.py" --verificar >/tmp/verificar.txt 2>&1 && ok "0.5 derivados al día ($(cat /tmp/verificar.txt))" || ko "0.5 derivados viejos: $(cat /tmp/verificar.txt)"

echo "── 1 · mundo SIN la migración ──"
if psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$AQUI/test-negativa.sql" >/tmp/neg-sin.txt 2>&1; then ko "1.1 la prueba PASÓ sin la migración (no detecta la falta de guarda)"; else ok "1.1 sin la migración la prueba FALLA ($(grep -c '✗' /tmp/neg-sin.txt) casos sin 0A000): detecta el mundo sin guarda"; fi

echo "── 2 · migración ──"
if psql "$DB_URL" -v ON_ERROR_STOP=1 -qAt -f "$MIG" >/tmp/mig1.txt 2>&1 && grep -q RETIRAR_CAMBIAR_SOLO_READ_COMMITTED_OK /tmp/mig1.txt; then ok "2.1 migración aplicada: fila RETIRAR_CAMBIAR_SOLO_READ_COMMITTED_OK"; else ko "2.1 migración falló: $(tail -2 /tmp/mig1.txt)"; fi
espera_huellas "$H_CAM_NUEVO" "$H_RET_NUEVO" && ok "2.2 huellas nuevas = las declaradas en la migración" || ko "2.2 huellas tras aplicar: $(huellas)"
[ "$(acl)" = "$ACL0" ] && ok "2.3 ACL, DEFINER y search_path intactos" || ko "2.3 ACL cambió: $(acl)"
q "select count(*) from pg_proc p where p.proname in ('retirar_cuenta_cliente_autorizado','cambiar_cuenta_pago_contratos_autorizado') and obj_description(p.oid,'pg_proc') like '% Solo admite READ COMMITTED (0A000 en cualquier otro modo; $VER).'" | grep -qx 2 && ok "2.4 comentarios conservan su texto y añaden la frase" || ko "2.4 comentarios inesperados"
if psql "$DB_URL" -v ON_ERROR_STOP=1 -qAt -f "$MIG" >/tmp/mig2.txt 2>&1; then ko "2.5 la migración se aplicó dos veces"; else grep -q "no tiene el cuerpo esperado" /tmp/mig2.txt && espera_huellas "$H_CAM_NUEVO" "$H_RET_NUEVO" && ok "2.5 segunda aplicación se niega y nada cambia" || ko "2.5 segunda aplicación falló por otro motivo: $(tail -1 /tmp/mig2.txt)"; fi

echo "── 3 · pruebas ──"
if psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$AQUI/test-negativa.sql" >/tmp/neg-con.txt 2>&1 && grep -q "PASS" /tmp/neg-con.txt; then ok "3.1 prueba de la negativa PASS ($(grep -o 'PASS: [0-9]* casos' /tmp/neg-con.txt))"; else ko "3.1 prueba de la negativa: $(grep -E '✗|FALLOS|ERROR' /tmp/neg-con.txt | head -3)"; fi
for t in test-retirar-cuenta-cliente test-cambio-cuenta-pago; do
  if ( cd "$SUPA/scripts/cuentas-gloria" && psql "$DB_URL" -v ON_ERROR_STOP=1 -qAt -f "$t.sql" >/tmp/$t.txt 2>&1 ) && grep -qE "_OK$" /tmp/$t.txt; then ok "3.2 $t sigue PASS ($(grep -E '_OK$' /tmp/$t.txt | tail -1))"; else ko "3.2 $t: $(grep -E 'ERROR|FALLO' /tmp/$t.txt | head -2)"; fi
done

echo "── 4 · registrar ──"
psql "$DB_URL" -v ON_ERROR_STOP=1 -qAt -f "$AQUI/registrar.sql" >/tmp/reg1.txt 2>&1 && [ "$(registro)" = 1 ] && ok "4.1 registrar: fila $VER" || ko "4.1 registrar: $(tail -1 /tmp/reg1.txt)"
psql "$DB_URL" -v ON_ERROR_STOP=1 -qAt -f "$AQUI/registrar.sql" >/tmp/reg2.txt 2>&1 && [ "$(registro)" = 1 ] && ok "4.2 registrar otra vez: idempotente" || ko "4.2 registrar segunda vez: $(tail -1 /tmp/reg2.txt)"

echo "── 5 · reversa ──"
{ echo "begin isolation level repeatable read;"; sed '0,/^begin;$/{/^begin;$/d;}' "$AQUI/reversa.sql"; } > /tmp/rev-rr.sql
if psql "$DB_URL" -v ON_ERROR_STOP=1 -qAt -f /tmp/rev-rr.sql >/tmp/rev-rr.txt 2>&1; then ko "5.1 la reversa corrió en REPEATABLE READ"; else grep -q "debe ir en READ COMMITTED" /tmp/rev-rr.txt && ok "5.1 reversa en REPEATABLE READ: se niega" || ko "5.1 reversa en RR falló por otro motivo: $(tail -1 /tmp/rev-rr.txt)"; fi
espera_huellas "$H_CAM_NUEVO" "$H_RET_NUEVO" || ko "5.1b la reversa negada cambió algo"
if psql "$DB_URL" -v ON_ERROR_STOP=1 -qAt -f "$AQUI/reversa.sql" >/tmp/rev.txt 2>&1 && grep -q REVERTIDA_SOLO_READ_COMMITTED /tmp/rev.txt; then ok "5.2 reversa: REVERTIDA_SOLO_READ_COMMITTED"; else ko "5.2 reversa falló: $(tail -2 /tmp/rev.txt)"; fi
espera_huellas "$H_CAM_VIVO" "$H_RET_VIVO" && ok "5.3 huellas de antes repuestas" || ko "5.3 huellas tras la reversa: $(huellas)"
[ "$(registro)" = 0 ] && ok "5.4 registro borrado" || ko "5.4 el registro sigue"
[ "$(q "select string_agg(coalesce(obj_description(p.oid,'pg_proc'),''), ' | ' order by p.proname) from pg_proc p where p.proname in ('retirar_cuenta_cliente_autorizado','cambiar_cuenta_pago_contratos_autorizado')")" = "$COM0" ] && ok "5.5 comentarios como antes" || ko "5.5 comentarios no volvieron"
if psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$AQUI/test-negativa.sql" >/tmp/neg-rev.txt 2>&1; then ko "5.6 tras la reversa la prueba PASÓ (no detecta el mundo sin guarda)"; else ok "5.6 tras la reversa la prueba FALLA otra vez (mutante detectado)"; fi
psql "$DB_URL" -v ON_ERROR_STOP=1 -qAt -f "$MIG" >/tmp/mig3.txt 2>&1 && psql "$DB_URL" -v ON_ERROR_STOP=1 -qAt -f "$AQUI/registrar.sql" >/tmp/reg3.txt 2>&1 && espera_huellas "$H_CAM_NUEVO" "$H_RET_NUEVO" && [ "$(registro)" = 1 ] && ok "5.7 reaplicada y registrada" || ko "5.7 reaplicar/registrar: $(tail -1 /tmp/mig3.txt) $(tail -1 /tmp/reg3.txt)"
psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$AQUI/test-negativa.sql" >/tmp/neg-fin.txt 2>&1 && grep -q PASS /tmp/neg-fin.txt && ok "5.8 prueba de la negativa PASS al final" || ko "5.8 prueba final: $(grep -E '✗|ERROR' /tmp/neg-fin.txt | head -2)"

echo; echo "── Resumen ──"; printf '%s\n' "${RES[@]}"; echo "fallos: $FALLOS"; [ "$FALLOS" -eq 0 ]

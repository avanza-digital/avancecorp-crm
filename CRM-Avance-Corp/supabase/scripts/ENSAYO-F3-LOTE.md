# Ensayo del lote Contrato-F2 (la «F3» del plan) — runbook

**Objetivo:** probar, en un banco (branch efímero de Supabase), que el lote cumple los
5 invariantes de la meta **bajo concurrencia real, por las puertas**, que aterriza
**aditivo** (bandera apagada = idéntico a hoy) y que la reversa deja todo como estaba.
Nada de esto toca producción. El branch cuesta ~centavos/hora: se crea con
confirmación de costo de Miguel y se borra al terminar.

## 0. Antes del banco (gratis)
- `node --check CRM-Avance-Corp/supabase/scripts/test-rls.mjs` → OK (ya pasado).
- `bash -n CRM-Avance-Corp/supabase/scripts/oraculo-f3-concurrencia.sh` → OK (ya pasado).
- Revisiones: auditor-rls (210000/220000/240000/250000/260000) + Codex sobre el SET → sin
  bloqueantes abiertos.
- Si hay stack local (`supabase start`), aplicar el lote ahí primero como smoke de sintaxis
  (`psql <local> -v ON_ERROR_STOP=1 -f <migración>` en orden) — detecta typos sin costo.

## 1. Banco (con confirmación de costo)
**Atajo probado el 03/09:** `banco-f7` (ref `cwkiejoaqadcnaieghnf`, el banco a paridad del 01/09)
sigue vivo y limpio; llevarlo a paridad = replay solo de las versiones nuevas (`list_migrations`
de prod menos su registro). Evita el replay de 119 versiones de un branch nuevo.
1. Si no hay banco: crear branch (`get_cost` → `confirm_cost` → `create_branch`). Todo branch
   nuevo cae en `MIGRATIONS_FAILED` por diseño → **replay manual** (`scripts/banco/README.md`).
2. Credenciales: `npx supabase branches get <branch-id> --experimental -o json` (desde
   `CRM-Avance-Corp`) devuelve `POSTGRES_URL` (pooler, 6543) y las keys. Guardar en
   `$S/banco-pooler.txt` **cambiando el puerto a 5432** (modo sesión, receta) y las keys en
   `$S/banco.json` (para la suite). Nunca imprimir la contraseña.
3. Volcado de versiones faltantes: `$S/pendientes.txt` (`version|nombre|0`) + `volcar.py` (lee
   prod por la CLI enlazada; macOS no tiene `timeout`: no envolverlo) → `replay.py` →
   `reregistrar.py`. El volcado del 01/09 (110 versiones) sobrevive en el scratchpad de esa
   sesión y se puede copiar.
4. ⚠️ **Antes de aplicar el lote, comprobar si prod recibió migraciones ajenas** que redefinan
   las mismas funciones (el 03/09 fue P-058 `215149`, que cambió la autorización de las 4
   puertas de conversión vía `replace()+execute` dentro de un `DO` — invisible a un grep de
   `create`). Si las hay, **rebasar** las migraciones del lote y la reversa sobre ese texto.
3. Aplicar en orden, cada una con `psql "$PG" -v ON_ERROR_STOP=1 -f …`:
   - F1 `20260903160000`, backfill `20260903180000` (si la base fiel-parcial no los trae),
   - **el lote:** `190000` → `205000` → `210000` → `220000` → `230000` → `240000` → `250000` → `260000`.
   - (`200000` está SUPERADA: si el replay la aplica, `230000` la neutraliza; si no, da igual.)
   Cada migración imprime su `NOTICE … OK` de postflight; cualquier `ERROR` aborta el ensayo.
4. Postcondición de aterrizaje: `select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'`
   → **false**; `trg_leads_reconocer_identidad` → **ausente**.

## 2. Los 5 invariantes por las puertas (el arnés)
```
S=<scratchpad> CRM-Avance-Corp/supabase/scripts/oraculo-f3-concurrencia.sh   # siembra él mismo
```
El arnés siembra con un `RUN` de 4 dígitos (`RUN=NNNN` opcional; por defecto HHMM): leads,
perfil, documentos (`7RUN00x`), teléfonos (9 dígitos) y números de operación derivan de él.
**No se borra nada entre corridas:** `depositos_reclamados` y el ledger son append-only por
diseño (no se desmontan candados para ensayar); cada corrida vive en su espacio.
Resultado del 03/09: **VERDE 33/33.**
Debe terminar en **`ORÁCULO F3 (lote Contrato-F2): VERDE`**. El arnés enciende la bandera,
lanza DOS sesiones simultáneas (cada una en una sola transacción), y aserta: 1 identidad,
1 lead con puntero, 1 inversión preservada, titular, cierre con `inversionista_id`,
responsable; reintento idéntico → `reintento=true` sin duplicar; payload distinto → P0409;
«vuelve por Avance» → P0409; disponibilidad por documento → `ya_es_cliente`; no_contactar
por persona (marcar / rechazo directo / vendedor no levanta / gerencia sin motivo no /
gerencia con motivo sí / herencia al INSERT); y paridad con bandera APAGADA.

## 3. La suite RLS (permitido Y denegado por rol)
Con el seed determinista del banco (`seed-demo`) y `CRM_BANCO_PSQL_URL` exportada:
```
node CRM-Avance-Corp/supabase/scripts/test-rls.mjs
```
El bloque `testIdentidadMultiempresa` corre tras `testCierresExternos`. Debe pasar junto con
el resto de la suite (la línea base era 1274/1279 con 6 fallos ya documentados en
`banco/HALLAZGOS-SUITE.md` — que NO deben crecer).

## 4. Reversa
```
psql "$PG" -v ON_ERROR_STOP=1 -f CRM-Avance-Corp/supabase/scripts/rollback-f2-puertas.sql
```
→ `REVERSA F2 lote OK`. Comprobar: puertas y lecturas previas restauradas (hash de
`pg_get_functiondef` contra la versión previa — recordar que `md5(prosrc)` NO acredita una
recreación fiel: comparar el texto), sin RPC/triggers nuevos, bandera apagada. Aplicar el
lote **otra vez** después (reconstruíble) y repetir §2 en corto.

## 5. Cierre del ensayo
- Anotar resultados (verde/rojo, ajustes hechos) en `MIGRACIONES.md` (filas 190000–260000) y en
  el HTML del plan. Borrar el branch.
- Si todo verde → presentar a Miguel para el **`!`** (`db query --linked --file` por migración,
  en orden, y registrar cada una en `schema_migrations`) — con la bandera APAGADA.
- La **activación** (encender `resolver_en_puertas` + deploy del edge `crm-convertir-lead` +
  front llamando a `marcar/levantar_no_contactar`) es un paso aparte, con su propio visto.

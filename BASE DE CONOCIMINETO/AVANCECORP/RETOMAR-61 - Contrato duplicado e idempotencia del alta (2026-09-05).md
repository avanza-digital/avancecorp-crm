# RETOMAR-61 — Contrato duplicado del 05/09 e idempotencia del alta

**Para retomar en otra sesión: «retomemos RETOMAR-61».** Estado al cierre de la sesión `cc4f92ce` (05/09/2026, ~12:30 Lima). Nada aplicado en producción. Todo el trabajo vive en el árbol de trabajo (SIN commit) sobre `main`, y en el banco `banco-f7`.

## 1. Qué pasó (cerrado, con evidencia)

Ver [[Contrato duplicado - el alta sin PDF se leia como error (2026-09-05)]]. En corto: el front exigía una reserva de PDF `pendiente` en la respuesta del alta; los contratos firmados antes del 19/08 (régimen anterior) vuelven con `sin_reserva`/`job_id null`; el front decía error sobre un alta hecha; la analista cambió el número y duplicó (2026-01-000025 y 2026-01-000253, cliente `4e0c11bc…`). Sistémico desde el 21/08 (33 altas). `producto_condicion_id` distinto = normal (condición legacy por contrato). Codex NO pudo refutar la causa raíz.

## 2. Qué está hecho (en el árbol de trabajo, sin commit)

**Front (`CRM-Avance-Corp/app/`)**
- `src/data/crm-api.ts` · `crearContrato`: la prueba del alta es `id`+`numero_contrato`; `cuenta_bancaria_id` y `pdf` tolerantes con rastro; devuelve `idempotente`; manda `p_contrato.clave_idempotencia`. `aErrorApi` mapea `P0409` «ya creó el contrato» → `ALTA_YA_CREADA` y «fue eliminado después» → `ALTA_ELIMINADA`.
- `src/lib/idempotencia.ts` (+ `.test.ts`): `claveIdempotenciaPendiente(ambito)` / `liberarClaveIdempotencia(ambito)` con `localStorage` por ámbito (`alta_contrato:<clienteId>`) y memoria de proceso de respaldo.
- `src/components/app/contrato-nuevo.tsx`: usa la clave por cliente; la libera tras `setCreado`/callbacks; en `ALTA_YA_CREADA` y `ALTA_ELIMINADA` libera y explica; aviso visible si `cuenta_bancaria_id` vino null; toast «se recuperó el alta anterior» si `idempotente`.
- Pruebas: `crm-api-clientes-msw.test.ts` (bloque «un alta que el servidor confirmó NUNCA se lee como error», respuesta REAL de prod, roja contra el código viejo; bloque nuevo «rechazos de idempotencia» para el mapeo `P0409` → `ALTA_YA_CREADA`/`ALTA_ELIMINADA`), `contrato-nuevo.test.tsx` (bloque «idempotencia del alta»: doble clic, misma clave al reintentar, renovación tras éxito, aviso idempotente, régimen anterior sin archivar, desmontar en vuelo = misma clave, `ALTA_YA_CREADA`/`ALTA_ELIMINADA` liberan la clave, aviso de cuenta no confirmada), `lib/idempotencia.test.ts` (persistencia por ámbito). **ROJAS AHORA por el arnés, no por el código**: en el jsdom de vitest de este proyecto `globalThis.localStorage` es `undefined` (`TypeError: Cannot read properties of undefined (reading 'clear')`); la lib lo tolera (cae a la memoria de proceso), las pruebas no. Arreglo: en `beforeEach` de esos dos archivos `vi.stubGlobal('localStorage', <Map en memoria con getItem/setItem/removeItem/clear>)` y leer la clave por `claveIdempotenciaPendiente` en vez de `localStorage.getItem`; en `idempotencia.test.ts` quitar el pragma `@vitest-environment jsdom` (no aporta) y usar el mismo stub. Después: `npm run check` en `app/`.
- Verificado antes de la v2: typecheck OK, oxlint OK, vitest 194 archivos / 2819 verdes. **Repetir tras la v2 y el arreglo de las pruebas.**

**Servidor (solo banco)**
- `supabase/migrations/20260905190000_crm_alta_contrato_idempotente.sql` (v2), generada por `supabase/scripts/idempotencia/gen-alta-idempotente.py` desde el prosrc VIVO (`vivas/`, md5 prod `68cc6c91…`; nuevo `1876ea59…`). Reversa `scripts/rollback-alta-idempotente.sql`; registro `scripts/registrar-alta-idempotente.sql`.
- Semántica v2 (tras Codex): memoria `private.contrato_altas_idempotentes (actor_id, clave, contrato_id NULL=lápida SET NULL, huella md5 del payload, respuesta)`; replay solo con misma huella, pasando por `puede_registrar_ventas()` + `bloquear_fila_contrato_pdf` + `puede_leer_contrato_pdf_como`; misma clave + otros datos → `P0409` «ya creó el contrato N con otros datos»; borrado → `P0409` «eliminado». Sin tocar `crear_contrato_con_cuenta` ni `public.crear_contrato`.
- **Banco `banco-f7` (cwkiejoaqadcnaieghnf)**: v2 APLICADA (huella `1876ea59…`), reversa y reaplicación probadas. Cadena psql y credenciales de la suite: consultar exclusivamente el scratchpad privado de la sesión y sus archivos de entorno, fuera del repositorio. No usar esas credenciales contra producción.
- Oráculo `scripts/oraculo-alta-idempotente.sh` (RUN de 6 dígitos): con el texto vivo = mutante (15 rojos, reproduce el duplicado); con v2 (RUN 051204) = A–J e I verdes. Ya incorpora: cliente PB por RUN con asesor W (la reserva PDF exige cartera: comportamiento vivo), admin efímero ADM y la eliminación por la puerta oficial `crm.contrato_eliminacion_preparar/finalizar` (mismo camino que el SQL de remediación). **La corrida RUN 051205 dio 9 rojos que NO son de la migración** (logs en el scratchpad `oraculo-v2b.log`, `idem-h1.out`): H/J/L murieron con «42501 Cliente no encontrado o fuera de tu cartera» para V en `crm.crear_contrato_con_cuenta` línea 38 (= `puede_registrar_ventas()` false a mitad de corrida) → **contención con los oráculos de la otra sesión en el banco compartido**, que re-siembran/tocan a los actores F3 (V/SUP); repetir con el banco quieto. K: `update crm.equipo set activo=false where perfil_id=W` lo frena el trigger «El supervisor destino no existe, no esta activo o no tiene rol compatible» (SUP estaba inactivo en ese instante) → crear a W con `supervisor_id` NULL o revocarlo por la RPC oficial de offboarding, y volver a activarlo igual. Después de arreglar K, esperar A–L e I TODO VERDE.
- `scripts/test-rls.mjs`: bloque «IDEMPOTENTE por clave» (v2: otro número → P0409; mismos datos → replay; otro capital → P0409). Suite completa contra el banco con la v1: 1376/1390 (los 14 rojos son residuo del banco compartido: leads «IDENTIDAD … TRANSIENT», sonda de domicilio, tercer estado). **Repetir con la v2.**

**Remediación (NO ejecutar; Miguel decide)**: `supabase/scripts/remediacion-duplicado-2026-01-000253.sql` — diagnóstico, y un `DO` por la puerta oficial con comparación COMPLETA bajo lock (cabecera, autoría, cronograma cuota a cuota, cuenta, cotitulares), `request.jwt.claim.sub` fijado al actor para que la auditoría quede a su nombre, y postcondición `audit_log.usuario_id = actor`. Camino recomendado: botón «Eliminar contrato» de Gerencia. Por defecto se elimina 000253 (el reintento); si el papel firmado dice 000253, se elimina 000025.

**Docs**: `MIGRACIONES.md` (entrada `20260905190000`; **actualizar a v2**: huellas, semántica, hallazgos de Codex, orden de despliegue: ambos hacen falta para cerrar todas las ventanas —servidor primero recomendado, es inerte sin clave—), nota del vault del incidente, memoria `alta-confirmada-nunca-es-error`.

## 3. Revisión adversaria

- **Codex (sesión `01a07279-8c6e-7ad1-98be-8f1343666ca3`)**: 3 bloqueantes, 5 mayores, 4 menores; TODOS atendidos en la v2 salvo los menores aceptados (forense sin captura del cuerpo HTTP; condición legacy huérfana, precedente de 55). Pedirle una segunda pasada sobre la v2.
- **Workflow `revision-adversaria-duplicado` (run `wf_08e75cd9-dcc`)**: panel de refutación + revisores + verificación; al cierre de la sesión seguía corriendo. Leer su resultado (`~/.claude/projects/-Users-usuario-Desktop-DESARROLLO-DESARROLLO-AVANCECORP-desktop/cc4f92ce-3a51-4b8a-b6bb-4d4f6ffe0d3d/subagents/workflows/wf_08e75cd9-dcc/journal.jsonl`) y atender lo confirmado.

## 4. Siguiente paso, en orden

1. Arreglar K y L del oráculo (arriba) → oráculo TODO VERDE con la v2 → `test:rls` completo contra el banco.
2. Completar pruebas del front pendientes → `npm run check` en `app/` (typecheck + oxlint + vitest).
3. Leer el Workflow; segunda pasada de Codex sobre la v2; `auditor-rls` sobre el `.sql`.
4. Actualizar `MIGRACIONES.md`, la nota del incidente y la memoria a la v2. Commit en `main` (staging quirúrgico: el árbol lo comparten otras sesiones), `git push avancecorp main:tronco`.
5. Enseñar a Miguel el diff final y el SQL de remediación. Con su `!`: aplicar `20260905190000` en prod (`db query --linked --file`), correr `registrar-alta-idempotente.sql`, release del front (`/release-crm` con preflight), y remediar el duplicado por la puerta oficial.

Relacionadas: [[Contrato duplicado - el alta sin PDF se leia como error (2026-09-05)]] · [[RETOMAR-60 - F2.b E3 (b5) construida y ensayada, pendiente del ! (2026-09-05)]] · [[Ciclo de vida de contratos]] · [[Número de contrato]]

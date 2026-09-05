# RETOMAR-61 — Contrato duplicado del 05/09 e idempotencia del alta

**Para retomar en otra sesión: «retomemos RETOMAR-61».** Estado al 05/09/2026 ~13:35 Lima. La sesión original (`cc4f92ce`) se cortó por límite de uso a las 12:47 con la auditoría terminada y las correcciones a medias; la sesión `898b41ce` la retomó y cerró lo que sigue. **Nada aplicado en producción.** Todo está commiteado en `main` (los commits `e9cccb2`/`cb67bc8`, etiquetados como gerencia, barrieron el árbol entero: incluyen RETOMAR-61 y D-13) más el commit de documentación de esta sesión.

## 1. Qué pasó (cerrado, con evidencia)

Ver [[Contrato duplicado - el alta sin PDF se leia como error (2026-09-05)]]. En corto: el front exigía una reserva de PDF `pendiente`; los contratos firmados antes del 19/08 (régimen anterior) vuelven `sin_reserva`/`job_id null`; el front decía error sobre un alta hecha; la analista cambió el número y duplicó (2026-01-000025 y 2026-01-000253, cliente `4e0c11bc…`). Sistémico desde el 21/08 (33 altas; 16 eventos Sentry `crm.contrato.respuesta_invalida` desde el 31/08). **Segundo ciclo el mismo día** (leído en prod): 16:56:34Z alta de 000247 leída como error → 17:03:24Z eliminado por el botón de Gerencia (`audit_log.usuario_id` NULL: la edge borra con service role) → 17:06:04Z recreado con el mismo número para otro registro de cliente. Sin duplicado de ese ciclo; la consulta de vigilancia (§1.e de la remediación) devuelve UNA pareja: 000025/000253. Los dos ciclos del 04/09 fueron contratos distintos.

## 2. Qué está hecho

**Servidor (v2.1, generada por `scripts/idempotencia/gen-alta-idempotente.py`)**
- `migrations/20260905190000_crm_alta_contrato_idempotente.sql`: md5(prosrc) vivo `68cc6c91…` → nuevo `1876ea59…`; md5 del archivo `13b0a63e…`. Memoria `private.contrato_altas_idempotentes (actor_id, clave, contrato_id SET NULL = lápida, huella, respuesta)`; replay solo con misma huella y autorización vigente; misma clave + otros datos → P0409 con el número; borrado → P0409 «eliminado». Cambio v2 → v2.1: la comprobación de `search_path` en guardas y postflights es de IGUALDAD (`v_config <> array['search_path=""']`), no de inclusión (hallazgo del verificador del workflow).
- `scripts/rollback-alta-idempotente.sql` desregistra la versión de `schema_migrations`; `scripts/registrar-alta-idempotente.sql` se niega si la puerta no lleva `1876ea59…` o falta la tabla, y pinnea `13b0a63e…` (mutante «registrar antes de aplicar» rechazado en el banco).
- **Banco `banco-f7`**: ciclo completo el 05/09 13:05 — reversa OK → mutante de registro rechazado → v2.1 aplicada → registrada. Queda aplicada y registrada.
- `scripts/oraculo-alta-idempotente.sh`: **TODO VERDE (45 comprobaciones, RUN 051302)** con la v2.1. Arreglos: las banderas se restauran entre comillas (`activo='f'`, antes `activo=f` rompía); K revoca a W como lo hace la suite RLS (`revocarEquipoFueraDeBanda`: guard de jerarquía apagado en UNA transacción, porque prohíbe revocar a quien conserva cartera) y reactiva a SUP antes por si otro oráculo del banco lo dejó inactivo. Los 9 rojos de la corrida 051205 eran contención con los oráculos D-13 de la otra sesión (V y SUP quedaron inactivos en `crm.equipo`), no la migración.
- Suite RLS completa contra el banco (v2.1): 1515 aserciones; bloque «idempotencia» 8/8 verde. 20 rojos ajenos (residuo del banco compartido: leads «IDENTIDAD … TRANSIENT», sonda de domicilio, y tres familias de Gerencia —`ultimo_contacto_en`, `fuera_de_roster`, «11 claves»— que dependen de las migraciones de Gerencia que tenga el banco). Logs en el scratchpad de `898b41ce` (`test-rls-banco.log`, `oraculo-v21b.log`).

**Front (`CRM-Avance-Corp/app/`)**
- Sin cambios de código respecto a la nota anterior (`crm-api.ts`, `lib/idempotencia.ts`, `contrato-nuevo.tsx`). Arnés: Node ≥ 25 expone `globalThis.localStorage = undefined` sin `--localstorage-file` y tapa al de jsdom; `src/test/setup.ts` instala un almacenamiento en memoria cuando eso pasa; quitado el pragma jsdom de `lib/idempotencia.test.ts`. **`npm run check` verde: 194 archivos / 2831 pruebas, oxlint y typecheck OK.**

**Remediación (NO ejecutar; Miguel decide)**: `scripts/remediacion-duplicado-2026-01-000253.sql`. Cabecera corregida: el camino recomendado es la sección 3 (fija `request.jwt.claim.sub`), NO el botón de Gerencia, que deja el DELETE sin actor en `public.audit_log` (medido en prod). Se eliminó `2026-01-000253` por defecto; si el papel firmado dice 000253, se elimina 000025.

**Docs**: `MIGRACIONES.md` actualizado a v2.1 (huellas, semántica, revisión adversaria, segundo ciclo, orden de despliegue: ambos hacen falta, servidor primero). Nota del incidente actualizada. Memoria `alta-confirmada-nunca-es-error` (en `~/.claude/projects/…/memory/`) actualizada.

## 3. Revisión adversaria (cerrada)

- **Codex**: 3 bloqueantes, 5 mayores, 4 menores → todos atendidos en v2 (los menores aceptados: forense sin cuerpo HTTP; condición legacy huérfana).
- **Workflow `revision-adversaria-duplicado`** (`wf_08e75cd9-dcc`): 7 revisores, 39 hallazgos (3 mayores/12 menores/24 notas); 30 verificados, 30 reales (4 mayores). Mayores: reversa sin desregistrar (atendido), registro sin comprobar aplicación (atendido), dos eventos Sentry más el 05/09 (investigados: sin duplicado, ver §1), «el bug estaba en el cliente» incompleto (el servidor cambió el contrato de respuesta en `20260820190500` y su ledger declaró que el front no dependía; recogido en el ledger y la nota). Un verificador falló sin resultado; su borrador (tautología del check de `proconfig`) se atendió con la igualdad estricta.
- **`auditor-rls`** sobre la v2.1 (05/09 13:35, solo lectura): **sin bloqueantes; pasa al gate con condiciones.** Verificó: generación reproducible y huellas (`68cc6c91…`/`1876ea59…`/`13b0a63e…`), RLS forzada y cerrada en la tabla nueva, ACL de la puerta intacta, replay gateado con las mismas preguntas que el alta, sin lectura cruzada entre actores, lápida serializada con el finalizador oficial, sin toque a `public`. Ver sección 5.

## 5. Hallazgos del `auditor-rls` (v2.1) y qué falta de ellos

- **M1 (atendido en esta sesión):** el ledger describía la v1 (CASCADE, `079d047f…`, `f5a149c1…`). Ya reescrito a v2.1 con las tres huellas, la lápida y la evidencia del oráculo J/K/L.
- **M2 (pendiente):** el bloque «idempotencia» de `test-rls.mjs` (8 aserciones, todas con `vend1`) no cubre la seguridad del replay. Añadir al menos: (1) otro actor con la MISMA clave no obtiene el contrato de `vend1`; (2) actor revocado hace replay → 42501 y no recrea; (4) sonda de acceso a `private.contrato_altas_idempotentes` por la API para anon/authenticated/service_role (patrón de `capital_episodios`, ~l.11090). Opcionales: (3) lápida (declararla cubierta por el oráculo L en `scripts/LEEME.md` si el hard-delete no cabe en el gate); (5) carrera con la misma clave; (6) replay como coordinador y gerencia.
- **m1:** el hash `079d047f…` (v1 solo-banco) va incrustado sin nombre en las guardas → constante `H_V1_BANCO` comentada en el generador; retirar cuando el banco quede limpio.
- **m2:** la identidad de la puerta se fija por md5(prosrc)+owner+secdef+proconfig, no por `pg_get_functiondef` ni `proacl` exacto (E4 ya usó `md5(pg_get_functiondef(oid))`). Cambiarlo obliga a regenerar (cambian `H_NEW` y el md5 del archivo): **decisión de Miguel** (regenerar la misma migración, aún no aplicada en prod, o migración nueva).
- **m3:** el replay no pregunta `private.contrato_en_eliminacion` (el alta sí, vía `crear_job_contrato_pdf_base` → 55000): un contrato con eliminación PREPARADA y no finalizada se devolvería como «alta recuperada». Fix de una línea tras `bloquear_fila_contrato_pdf`; misma decisión que m2.
- **m4:** el registro tolera una fila previa con `statements` NULL → `coalesce(md5(statements[1]), '')`. Solo cambia el registrador (el md5 pinneado del archivo no cambia): regenerar es gratis.
- **Notas:** n1 la FK a `public.contratos` instala triggers RI sobre la tabla del portal (precedente `contrato_eliminaciones`; conviene una línea de OK explícito de Miguel en el ledger, como E4); n2 el postflight de BYPASSRLS mira al dueño de la tabla, exigir `relowner = postgres`; n3 `clave_idempotencia: null` no se quita del JSON (inocuo); n4 la `respuesta` guardada no tiene retención definida; n6 la reversa hace `drop table` de la memoria (si interesa el rastro forense, `rename`).

## 4. Siguiente paso, en orden

1. Decidir con Miguel m2/m3 (regenerar vs. dejar) y aplicar m4 + M2 (ampliar la matriz; recorrer el gate `test:rls` contra el banco). Después, segunda pasada de Codex sobre la versión final (esta sesión no tiene el plugin; pedirla desde una que lo tenga).
2. Enseñar a Miguel el diff final y el SQL de remediación. Con su `!`: aplicar `20260905190000` en prod (`db query --linked --file`), correr `registrar-alta-idempotente.sql`, release del front (`/release-crm` con preflight), y remediar el duplicado por la sección 3 del SQL.
3. Deuda anotada: el botón «Eliminar contrato» de Gerencia deja `audit_log.usuario_id` NULL (la edge llama a la puerta con service role); y `git push avancecorp main:tronco` (main va 3+ commits por delante de tronco).

Relacionadas: [[Contrato duplicado - el alta sin PDF se leia como error (2026-09-05)]] · [[RETOMAR-60 - F2.b E3 (b5) construida y ensayada, pendiente del ! (2026-09-05)]] · [[Ciclo de vida de contratos]] · [[Número de contrato]]

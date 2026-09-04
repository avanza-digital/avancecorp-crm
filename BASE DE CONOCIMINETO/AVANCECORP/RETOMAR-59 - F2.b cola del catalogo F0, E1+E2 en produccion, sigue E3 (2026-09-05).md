# RETOMAR-59 — F2.b «cola del catálogo F0»: E1 + E2 EN PRODUCCIÓN (apagadas), sigue E3

**Fecha del checkpoint:** 2026-09-05, madrugada. **Para retomar en otra sesión:** decir «retomemos RETOMAR-59».

Enlaza con: [[Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31)]] · [[Catalogo de puertas de escritura - identidad e inversiones (F0, 2026-09-03)]] · [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]] · [[Manifiesto productivo G0 multiempresa (2026-09-01)]].

## 1. Dónde estamos (verificado en producción, solo lectura)

| Entrega | Migraciones | Estado |
|---|---|---|
| Lote Contrato-F2 (F3) | `20260903190000` … `20260903260000` (8) | ✅ EN PROD 04/09 |
| F2.b **E1** = b1 (el alta reconoce a la persona) + b2 (veto de la persona en las mutaciones) | `20260904120000`, `20260904130000` | ✅ EN PROD 04/09, registradas con `registrar-f2b-e1.sql` |
| F2.b **E2** = b3 (alta de cliente con identidad + saga Auth↔Postgres) + b4 (conversión por persona) | `20260905100000`, `20260905110000` | ✅ EN PROD 05/09, registradas con `registrar-f2b-e2.sql` |
| F2.b **E3** = b5 (fusión, corrección documental, reasignación de responsable) | — | ⏭️ **LO QUE SIGUE** |

Banderas en producción: `resolver_en_puertas = false`, `inversiones_escritura = false`, `ficha_360_neutral = false`. **Todo aterrizó apagado**: con la bandera OFF cada puerta es byte a byte la de antes (paridad probada en los oráculos y en las reversas reales).

Git: `main` local = `avancecorp/tronco` (rama `feat/multiempresa-f2b-cola` fusionada en `d5ffe4c`; HTML del plan en `e1f8a5e`; este checkpoint encima). Worktree `../AVANCECORP-f3` sobre esa rama: al retomar, `git -C ../AVANCECORP-f3 merge --ff-only main`.

## 2. Qué es E3 (b5) — alcance acordado

Solo puertas de **Gerencia**, con previsualización, y alcance acotado hasta F5: **como máximo un lead y un perfil por lado**.

1. **Fusión de dos identidades** con matriz de colisiones explícita: dos perfiles, dos leads, cierres con `UNIQUE(lead_id)`, inversiones, meses sellados, y qué devuelve el resolver después de fusionar (puntos que Codex difirió a b5 el 04/09).
2. **Corrección de documento** que realinea identificador vigente + perfil + lead en la misma transacción (hoy el documento del cliente enlazado está protegido por b3).
3. **Reasignación del responsable de relación** (cierra el tramo abierto, abre otro con rastro).

Orden total de locks vigente (no romperlo): jerarquía (compartida, solo donde aplica) → documento advisory (`hashtext('inv_resolver:'||tipo||':'||norm)`) → identidad `FOR UPDATE` → perfil `FOR SHARE` → lead `FOR UPDATE` → reserva → claim → contactos (`bloquear_contactos_lead`) al final. Fusión: ids ascendentes.

## 3. El método (el mismo de E1 y E2, sin saltos)

1. Diseño concreto v1 de b5 en `CRM-Avance-Corp/supabase/DISEÑO-F2B-COLA-CATALOGO.md` (§b5 + §Prerrequisitos de ACTIVACIÓN).
2. Codex REFUTA (`codex:codex-rescue --fresh`, «refuta, no confirmes»). Siempre salió NO-GO en v1; v2/v3 aplica lo pertinente y difiere con números.
3. Implementar **desde el texto vivo** de producción: `supabase/scripts/f2b/vivas/` + un `gen-b5.py` con `rep()` anclado; guardas md5 de PRODUCCIÓN (`huellas14-prod.txt`, huella = archivo menos UN salto final); postflights; reversa byte a byte con postflight md5 y guardas de orden.
4. En banco-f7: migración → `oraculo-f2b-b5.sh` (dos sesiones psql reales, `run_as`, RUN de 6 dígitos) → reversa real ×2 + diff contra el texto vivo → re-aplicar → arnés viejo `oraculo-f3-concurrencia.sh` → `auditor-rls` → suite `test:rls` (ciclo en `scripts/f2b/LEEME.md`).
5. Codex sobre lo construido (GO técnico con lista de defectos ON → arreglar el mismo día).
6. Publicar SOLO con el `!` de Miguel: `cd CRM-Avance-Corp && npx supabase db query --linked --file supabase/migrations/<archivo>` y luego `registrar-f2b-e3.sql`. Nunca `db push` ni `merge_branch`.
7. Verificar prod en solo lectura → ledger `MIGRACIONES.md` «✅ PRODUCCIÓN» → fusionar a `main` y `git push avancecorp main:tronco` el mismo día → `PLAN-MAESTRO-MULTIEMPRESA.html` → memoria.

## 4. Decisiones que esperan a Miguel

1. **OK para tocar `public`** (regla del subproyecto): parche por ancla md5 de `public.crear_contrato` (llamar a `private.asegurar_identidad_perfil` antes de su `for share`) y trigger `BEFORE UPDATE OF dni, tipo_documento` en `public.perfiles`. Migración aparte, **NO escrita aún**.
2. **Colaboradores / registro del Portal fuera de la identidad** (por defecto: fuera).

## 5. Lo que NO se ha desplegado (se despliega al ACTIVAR, no antes)

Edges escritas y probadas en árbol, no vivas: `_supabase_functions/functions/{crear-cliente,importar-clientes,crm-convertir-lead,eliminar-cliente}/index.ts` + `_shared/saga-auth.mjs` (5 tests), copia viva del importador `CRM-Avance-Corp/supabase/functions/crm-importar-leads/`, front `app/src/lib/disponibilidad-lead.ts`. Prerrequisitos de activación listados en `MIGRACIONES.md` (entradas b3/b4): reserva/sellado de 1 argumento deben rechazar con ON, PATCH directo de asignación/reapertura, orden de locks de `marcar` por id, tareas/actividades por perfil, autorización propia del importador, casos b3/b4 en la suite, registro anti-pesca en `reclamar`.

## 6. Recursos

- **banco-f7** `cwkiejoaqadcnaieghnf`, vivo con E1+E2 (~US$0,32/día; borrarlo es decisión de Miguel). Sus credenciales estaban en el scratchpad de la sesión `3cb2f982-9883-4cfd-95e1-8a45421098f0` (`banco-pooler.txt`, `banco.json`; **nunca imprimirlas**); si ya no existe, volver a pedirlas por la CLI (`supabase branches get`).
- Herramientas versionadas: `CRM-Avance-Corp/supabase/scripts/f2b/` (generadores, huellas, `baja-historica.sql`, `vivas/`, `LEEME.md`).
- Oráculos: `supabase/scripts/oraculo-f2b-b{1,2,3,4}.sh`, reversas `rollback-f2b-b{1,2,3,4}.sql` (b1 se niega si b2 está; b3 si b4 está; b4 si hay reservas selladas vigentes).
- Memoria de Claude: `f3-implementa-el-contrato-f0.md`, `codigo-retomar-59.md`.

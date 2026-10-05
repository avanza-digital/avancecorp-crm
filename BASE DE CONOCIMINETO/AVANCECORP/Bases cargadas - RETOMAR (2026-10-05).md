# Bases cargadas — RETOMAR · serial `AVC-BASES-CARGADAS-20261005-R1`

Pedido de Miguel (03/10): el supervisor carga bases antiguas (archivo Excel/CSV o lote de descartados del CRM), las reparte
(«40 a uno, 30 a otro» o una por una) y ve si se trabajan. Es parte de [[Base para gestion del analista - F0 y decisiones (2026-10-01)]].
Decisiones E1–E14 y avance: `BASE PARA GESTION/BASES-CARGADAS.md`; contrato servidor ↔ pantalla:
`BASE PARA GESTION/BASES-CARGADAS-CONTRATO.md`; evidencias: `BASE PARA GESTION/revisiones/`.

## Estado al 05/10 (USABLE de punta a punta en producción)

| Pieza | Estado |
|---|---|
| B7 esquema `20261004160034` | ✅ prod, md5 `93e857c9` |
| B8 cargar/armar `20261004184501` | ✅ prod, md5 `ca81559b` |
| B9 repartir/recoger `20261004222602` | ✅ prod, md5 `8a169944` (`main` local `2dca81b0`) |
| B10 seguimiento + capital `20261004223253` | ✅ prod, md5 `92c5ee81` (`main` local `f9667515`) |
| Pantalla F5/F6 (pestaña «Bases», columna y selector «Base» del analista) | ✅ VIVO `27e6f248` (`build-20261005T023047087Z`), respaldo `rescue/bases-cargadas-f5-20261005` |
| GitHub | ✅ #186 (F5a), #188 (servidor B1b–B10), #189 (preflight en toda PR) fusionadas · ⏳ **#187 (F5/F6) abierta**, CI verde, solo falta la aprobación (Miguel la salta como admin) |

🔴 El próximo release del CRM debe contener `27e6f248` (el preflight lo exige).

## Pendientes, en orden

1. **Fusionar la #187.** Si GitHub pide «Update branch», el `preflight` ya arranca solo desde la #189.
2. **B11 · conversión de contactos de base:** el cierre cuenta ENTERO pero queda FUERA del divisor (decisión de Miguel,
   como la regla cerrada del registro manual). Toca el núcleo de conversión ⇒ plan corto y OK de Miguel
   ANTES de escribir (CLAUDE.md, «Autonomía»). Ciclo: banco Docker → auditor-rls → Codex (máx. 2) → rama con datos (borrarla)
   → `!` + registrador de Miguel → verificar `md5(prosrc)` → ledger → `main`. Ojo con el censo analítico (`count(` junto a
   `crm.leads`) y con «la anulación es la única puerta» de la conversión.
3. **Limpieza (con OK de Miguel):** bancos Docker parados con volúmenes `supabase_*_avancecorp-b6b-20261003` y
   `supabase_*_avancecorp-b10-20261004`; worktrees `AVANCECORP-desktop-worktrees/base-gestion-b6b-20261003` (rama
   `crm/bases-cargadas-b9`), `bases-cargadas-b10-20261004` (`crm/bases-cargadas-b10`) y `base-gestion-front-20261002`
   (`crm/bases-cargadas-f5`): todo ya está en producción y en GitHub.
4. **Textos desfasados (P3, sin urgencia):** en la próxima migración que toque esas piezas, corregir los comentarios «r1» de
   `reversa-b9.sql` y de `private.bases_carga_repartir_core/recoger_core`, y el comentario del CHECK
   `actividades_intento_base_forma` («la agenda se lee de crm.leads»: desde B9 el candado lee
   `metadata.proxima_llamada_en`). En la pantalla, el motivo defensivo `sin_estado` no tiene rótulo (hoy no ocurre).
5. **Deuda previa, decide Miguel:** la app del `main` LOCAL va por detrás de lo publicado (la carpeta compartida tiene trabajo
   sin commitear de otras sesiones). GitHub sí está al día.

## Cómo se trabaja aquí (lo que costó aprender)

- Antes de fijar una regla de estado, releer E1–E14: un encargo contradijo E1 (armados con analista anterior fuera del
  reparto) y hubo que rehacer B10.
- Anonimizar = agregar en UNA fila que NO se abre + rechazar el id ajeno con el mismo P0002 (Codex r2 de B10).
- Un script que registra un intento y reparte en el MISMO mensaje recibe 55P03 (la guarda usa `statement_timestamp()`).
- `db query --linked` (Management API) abre y cierra conexión por petición: un candado de sesión no queda colgado.
- El check `preflight` es obligatorio en `main` desde el 04/10 (ruleset `24459428`, sin bypass); lanzarlo a mano no cuenta.
- Commits SIN atribución de IA; al `main` local por índice temporal + `commit-tree` (la carpeta compartida tiene trabajo ajeno).

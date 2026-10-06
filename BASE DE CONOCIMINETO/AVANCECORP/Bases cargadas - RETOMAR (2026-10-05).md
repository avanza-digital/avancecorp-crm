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

1. ✅ **#187 fusionada** (05/10 14:51 UTC, `447208e1` en `avancecorp/main`).
2. **B11 · conversión de contactos de base — EN PAUSA (05/10), plan APROBADO, sin código escrito.** Ver «B11» abajo.

## B11 — dónde quedó (05/10)

**Medido en prod (solo lectura, 05/10):** el divisor (`private.conversion_episodios`) solo cuenta llegadas
`landing`/`formulario` sin alta manual ⇒ `base_cargada` YA está fuera, y el origen no se cambia tras el alta
(`leads_before_update`, P0409). El hueco es el numerador: `private.conversion_cierres` da 1 solo a landing/formulario ⇒ un
cierre de base suma **0**. 0 contactos de base, 0 cierres de base, `crm.periodos_cerrados` vacía, `conversion_politica`
activa ⇒ B11 no mueve ningún mes.

**Plan aprobado por Miguel (05/10):** ayudante único `private.conversion_origen_con_cierre(origen)` (landing, formulario,
referido, base_cargada) que reemplaza la lista copiada en: `conversion_cierres` (peso: 3.ª rama del `case` → 1; sus dos
ramas), `registrar_ajuste_si_mes_cerrado`, `conversion_mensual_por_vendedor`, `metricas_conversiones_equipo_fn`,
`metricas_conversiones_implementacion`, `metricas_distribucion_leads_v3_core` y la sonda de `conversion_mensual_sin_cartera_fn`.
El divisor (`conversion_episodios`) NO se toca. Tres de ellas están en el censo analítico (`conversion_mensual_sin_cartera_fn`,
`metricas_conversiones_implementacion`, `registrar_ajuste_si_mes_cerrado`): mover su huella en la misma fila + resellar
(patrón de `20261001212341`). Freno: abortar si ya existe algún cierre de base.
- Respuestas de Miguel: (1) los **armados desde el CRM** conservan su origen y su regla de siempre: B11 es solo para los
  cargados por archivo; (2) **«Resultados por origen» SIN fila «Base cargada»** (su contrato de origen es cerrado).

**🔴 Hallazgo que cambia el plan (pendiente del OK de Miguel):** «Divisor de coordinación» tiene un candado de paridad en el
front (`app/src/lib/conversion-coordinacion.ts:204`, `sumaDePartes` = formulario + landing + referido_aporte + upgrade +
renovacion_aporte = numerador bruto). `private.conversion_divisor_empresa` mete los cierres de base en `cierres_otros`
(«no pesan»): con B11 la suma no cuadra y la pantalla se niega a pintar. Propuesta: columna `cierres_base_cargada` en
`conversion_divisor_empresa` (drop + create: cambia RETURNS TABLE) y clave `base_cargada` en `cierres` de
`crm.conversion_divisor_coordinacion_fn`; front: clave opcional (0), sumada en `sumaDePartes` y pintada. **Pantalla
PRIMERO, servidor después.** Los demás candados del front (conversión mensual, Rendimiento, Inteligencia comercial) siguen
cuadrando con el ayudante único.

**Entorno (aislado):**
- Worktree `AVANCECORP-desktop-worktrees/bases-cargadas-b11-20261005`, rama `crm/bases-cargadas-b11` sobre `avancecorp/main`
  `b286b2bf` (limpio, sin cambios).
- Banco: stack Docker `avancecorp-b10-20261004` (volúmenes conservados, PARADO), puertos API 58221 / DB 58222. Se le
  aplicaron B10, `20260925170437` y `20261003225551` ⇒ **922/922 funciones `crm`+`private` idénticas a prod** (huella
  `md5(prosrc‖proconfig‖prosecdef)`, 05/10). Para levantarlo: un `config.toml` con `project_id = "avancecorp-b10-20261004"`,
  `[api] port = 58221`, `[db] port = 58222`, `shadow_port = 58220`, `[db.migrations] enabled = false`, realtime/studio/smtp/
  analytics apagados, y `supabase start --ignore-health-check`. Antes de usarlo, volver a comparar huellas con prod.

**Siguiente paso:** OK de Miguel al hallazgo → migración + suite SQL + mutantes en el banco → cambio de pantalla → auditor-rls
→ Codex (`scripts/codex-review-mcp`) → rama con datos (paridad antes/después de Rendimiento, Equipo, Distribución, Metas y
Divisor de coordinación de ago/sep/oct) → publicar pantalla → `!` de Miguel → md5 → ledger → `main`.
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

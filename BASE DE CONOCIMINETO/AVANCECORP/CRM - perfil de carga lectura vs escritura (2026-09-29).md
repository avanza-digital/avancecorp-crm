---
tags: [crm, rendimiento, refactor, servidor]
fecha: 2026-09-29
---

# CRM — perfil de carga: lectura vs escritura (2026-09-29)

**Conclusión:** el CRM es un sistema **de lectura**. Se escribe poco (≈3.200 filas al día) y se lee
muchísimo (paneles, métricas, colas, fichas). Base para priorizar el refactor módulo por módulo
(ver [[Mapa de capas del servidor CRM]]).

## Cómo se midió
Solo lectura en producción (`supabase db query --linked`) sobre `pg_stat_user_tables` y
`pg_stat_statements`. Ventana: desde el último arranque de Postgres, **25/09 20:50 UTC → 29/09
21:45 UTC (~97 h, incluye fin de semana)**. Los contadores se reinician con cada arranque: la
cifra válida es la de hoy, no esta.

## Cifras (esquema `crm`, ~97 h)
- Filas escritas: 8.694 insert + 4.277 update + 8 delete = **12.979**.
- Filas leídas: **13.143 millones** → ~1.000.000 : 1. Sin la anomalía de abajo, ~50.000 : 1.
- Peticiones a la API (PostgREST, un `set_config` por petición, incluye portal): ~203.000.
- RPC del CRM declaradas `STABLE` (solo leen): 169.914 llamadas. Declaradas `VOLATILE`: 19.316,
  pero la mayoría también son lecturas (`postventa_agenda_fn`, `cartera_inversionistas_*_fn`,
  `*_ficha_fn`). Escrituras reales visibles: `registrar_llamada_v4` 598, `importar_lead_fn` 455,
  `repartir_lead` 202, `solicitud_inversion_fn` 203, `cerrar_tarea_v2` 118.
- Tablas más escritas: `actividades`, `sla_operacion_recibos`, `leads`, `cartera_lecturas`, `tareas`.

## Puntos calientes (candidatos de refactor)
1. 🔴 **`crm.inversionistas`**: 22,6 M lecturas completas de la tabla (~551 filas cada una) =
   12.462 M filas, **el 95 % de todo lo que lee el CRM**.
   **Causa medida (29/09, bloques `DO` de solo lectura que terminan en `raise`):**
   `private.cartera_f5_fuentes()` hace un `cross join lateral` por contrato con
   `where i.perfil_id = c.cliente_id`. El único índice de `perfil_id` es **parcial**
   (`inversionistas_perfil_uidx … where perfil_id is not null and estado <> 'fusionado'`) y esa
   consulta no repite la condición, así que no lo puede usar → **679 recorridos completos por llamada**
   (uno por contrato; 679 contratos), ~90 ms. La alcanzan 11 puertas (postventa_agenda/estado/ficha,
   cartera_inversionistas_estado, inversionista_ficha/gestion/cuentas, contexto_conversion_inversion,
   solicitud_inversion, acceso_inversion, preparar_persona_lead_inversion): 14.252 llamadas en la ventana,
   ~2 llamadas a fuentes por puerta ≈ los 22,6 M. En vivo: 26.509 recorridos en 77 s (~39 llamadas).
   Descartadas con medición: `inversionista_canonica` (1 índice, 0 recorridos) y
   `leads_vetados_persona` (2 recorridos para los 2.582 leads).
   **✅ ARREGLADO EN PROD 29/09 ~17:25 Lima** (migración `20260929220021_crm_indice_inversionistas_perfil`,
   lanzada por Miguel con `!`): índice normal `crm.inversionistas (perfil_id)`, sin tocar ninguna función.
   Verificado: `cartera_f5_fuentes` seq 679 → **0**, 91 → 49 ms, 719 filas idénticas; en vivo
   **545 → 0,8 recorridos/s**. Advisors: 242 avisos, ninguno del índice. Codex CHANGES_REQUESTED (P2
   registrador con relectura, P3 comentarios) aplicado. Sirve también a otras 18 funciones con el mismo
   patrón (`citas_gerencia_consulta`, `citas_testigo_mes`…). Reversa: `drop index crm.inversionistas_perfil_idx`.
   Segundo foco, aparte: `private.postventa_tarea_json` compara `inversionista_canonica(i.id)` contra
   toda la tabla por cada tarea (1 recorrido + ~1.061 índices por tarea); ahí un índice no sirve, hay que reescribirla.
2. `solicitudes_tasa_fn`: 88.328 llamadas (~15 por minuto): huele a sondeo repetido.
3. Las más caras en tiempo: `avisos_sla_resumen_v2_fn` (2.922 s, 0,32 s cada una) y
   `cumplimiento_metas_fn` (1.861 s).
4. `equipo` (2,97 M) y `cierres_externos` (1,46 M) también se recorren enteras; son pequeñas.
5. Funciones que solo leen marcadas `VOLATILE`: PostgREST las trata como escritura. Revisar una por
   una antes de cambiarlas: `cartera_lecturas` recibe inserts (1.213), puede ser un registro de
   lecturas hecho a propósito.

## Evaluación del entorno tras el índice (29/09 ~18:00 Lima) — base del paso 2

Latencias REALES hoy, medidas como gerencia dentro de una transacción deshecha (dos pasadas):
`cartera_inversionistas_filtrada_fn` **2,3 s** (igual en pág. 1, pág. 2 o con texto) ·
`avisos_sla_resumen_v2_fn` 1,7–2,3 s · `metricas_conversiones_fn` 1,1–1,2 s · `inversionista_ficha_fn`
0,5–0,6 s · `postventa_agenda_fn` 0,5 s · `cumplimiento_metas_fn` 0,33 s · `cartera_filtrada_fn` 48 ms ·
`tareas_pendientes_fn` 18 ms · `solicitudes_tasa_fn` 5–7 ms.

**Causa medida de los 2,3 s de la cartera de inversionistas:** `private.cartera_f5_personas_visibles()`
calcula las 560 personas con 4 subconsultas laterales de presentación cada una (perfil, lead, cierre
externo, identificador) = **2.197 ms**, y `cartera_f5_listar` recorta DESPUÉS a la página de 25. Para una
sola persona (`personas_visibles(uuid)`) tarda 68 ms; `cartera_f5_fuentes` ya está en 49 ms. → Paso 2 del
refactor: paginar antes de presentar (mismas reglas de acceso, mismo JSON). La alcanzan 7 puertas
(`inversionista_ficha/gestion/cuentas/documento_fn`, `postventa_perfil/vencimientos_fn`, `cartera_f5_listar`).

**Sondeo de 15 s desde el front** (React Query `refetchInterval: 15_000`): `respuestas-tasa-provider.tsx`
(`solicitudes_tasa_fn`, 91.175 llamadas = 45 % de todas las RPC, también en segundo plano),
`postventa-queries.ts` (`postventa_estado_fn` + `postventa_agenda_fn` con `staleTime 0`: 7.900 llamadas de
0,5 s), `inversion-nueva.tsx` (2 consultas). El SLA usa intervalo dinámico (`intervaloReconsultaSla`).

**Puertas VOLATILE que solo leen (transitivo):** `postventa_agenda_fn`, `postventa_estado_fn`,
`postventa_ficha_fn`, `cartera_inversionistas_estado_fn`, `contexto_conversion_inversion_fn`,
`gestion_diaria_avisos_fn`, `bienvenida_inversion_estado_fn`. Las de cartera (`filtrada`, `ficha`,
`cuentas`, `documento`) escriben a propósito en `cartera_lecturas` (`private.cartera_f5_registrar`).

**Servidor sano:** caché 100 %, 41/90 conexiones (1 activa), PostgreSQL 17.6; tabla mayor
`public.audit_log` 128 MB (115 k filas). 15 índices sin uso (88–320 kB) y 30 FK sin índice (casi todas
`creado_por`): sin impacto a esta escala. `crm.solicitudes_tasa` figura con 0 filas vivas y tiene 90
(estadísticas desfasadas).

**Front:** `npm run check` PASS en worktree limpio (317 archivos, 4.923 tests). 115.615 líneas fuente +
78.625 de tests; bundle 3,5 MB JS (index 686 kB, echarts 476 kB). 20 `from('tabla')` directos (leads 4,
tareas 3, recordatorios 3, agenda_ics 3, perfiles 2, actividades 2, alertas 2, actividades_cliente 1):
el plan de cierre de saltos (`SERVIDOR-CRM/mapa-capas-2026-09-17/PLAN-CIERRE-SALTOS.md`) sigue sin
arrancar desde el 17/09. CodeGraph sin índice para esta carpeta (0 nodos).

**Entorno:** 56 rutas sin commitear de otra sesión en la carpeta compartida (cartera, leads, `crm-api.ts`,
`store.tsx`, migración `20260929201813`) bloquean integrar a `main` local (ya 3 PR detrás de GitHub).
`lefthook` no está en el PATH → los hooks de commit (lint+typecheck) NO corren desde esa terminal.
Edge espejo `crm-notificaciones-tasa`: código idéntico, el CRM tiene 2 tests extra. Docker corriendo.

## Paso 2 · Fase 1 — ✅ EN PROD 29/09 ~18:25 Lima (Miguel dio el «dale» ~18:10 y aplicó con `!`)

Verificado tras aplicar: huella nueva OK; `personas_visibles()` 561 filas en **90 ms** (antes 2.200–4.500);
listado de gerencia **189 ms** con y sin texto (antes 2.300–3.200; meta < 400). Advisors: 242, sin cambios.
PR #138 (apilada sobre #136). Apta para producción: sí. Comercialmente: la pantalla con la que gerencia y
supervisión revisan la cartera de inversionistas responde al instante; la ficha (0,5 s) queda para otro paso.
Sigue la **Fase 2** (front: quitar el sondeo de 15 s), pendiente del «dale».

El EXPLAIN ANALYZE cambió el diseño: no hacía falta «paginar antes de presentar». De los 2.384 ms del
listado, **2.283 ms eran UN lateral** (`ce`, el nombre del cierre externo): por cada una de las 560 personas
recorría `crm.cierres_externos` (41) y por cada fila la CTE `fuentes` (718) → 22.897 recorridos de la CTE.
Migración `20260929230336_crm_cartera_personas_visibles_cierre_sin_bucle`: ese lateral pasa a una CTE
`cierres_nombre` calculada una vez (`distinct on … order by inversionista_id, creado_en desc, id`) + `left
join … and not i.lector`. Nada más cambia. Oráculo en prod (deshecho): **46/46 idénticos** en 4 actores;
listado gerencia 2.357–3.216 → **181–232 ms**; prueba sintética 0/0 diferencias; ciclo migración →
idempotente → reversa → migración → registrador en verde; Codex 2 rondas (4 hallazgos aceptados, ver
`MIGRACIONES.md`). Hoy 0 personas toman su nombre del cierre externo (todas tienen perfil o lead).
Reversa: `supabase/scripts/cartera-personas-visibles/reversa.sql`.

## Paso 2 · Fase 2 — ✅ EN PROD 29/09 ~18:55 Lima (solo pantalla; Miguel publicó con `!`)

Build `build-20260929T235040143Z` (ZIP `crm-20260929T235041Z-6600af0a163a`, commits `6464f72e` + `6445c7cd`
de la PR #139; publicado desde la rama de rescate `rescue/sondeo-adaptativo-20260929` = lo vivo `b131ffbe` +
los dos commits, preflight OK). Cambios: `respuestas-tasa-provider.tsx` pregunta cada 15 s solo con una
solicitud propia pendiente (`estado_efectivo`) o con la última consulta fallida, y cada 2 min en reposo; sigue
en segundo plano (aviso de escritorio/sonido); `crm-queries.ts` deja una señal `storage`
(`ac-crm-solicitud-tasa-creada-v1`, solo la hora) al crear una solicitud para que las otras pestañas consulten
al instante; `postventa-queries.ts` 15 s → 60 s. Residual: desde otro dispositivo la pendiente se descubre en
≤ 2 min. Verificación: check 4.929, E2E Docker 18/18 (3 escenarios de `respuestas-tasa.spec.ts` ahora parten
de la solicitud pendiente), Codex LEVEL 2 CHANGES_REQUESTED → aplicado. Línea base de llamadas antes de
publicar (23:51 UTC): `solicitudes_tasa_fn` 94.537, `postventa_estado_fn` 2.934, `postventa_ficha_fn` 1.070;
la reducción se mide al día siguiente (los navegadores recargan el bundle poco a poco).
🔑 Trampas de esta fase: el ZIP de release exige los `.env` de `app/` (copiarlos al worktree); una prueba E2E
que salte de «sin solicitud» a «respondida» sin «pendiente» depende del sondeo fijo y ya no es realista.

## Paso 3 · Fase 1 — ✅ EN PROD 29/09 ~19:35 Lima (Miguel aplicó con `!`)

La lista de tareas (`tareas_pendientes_fn`, 22 ms) arrastra la agenda de postventa (`postventa_agenda_fn`) en cada
carga de Hoy/agenda de todos (~1.300 veces al día). De sus 509–532 ms, 320–338 eran `postventa_perfil_ids` en
`private.postventa_tarea_json`: por cada una de las 16 tareas se recorrían las 565 personas con
`inversionista_canonica()` dos veces por fila. Migración `20260930000550_crm_postventa_tarea_json_por_familia`:
las candidatas salen de la FAMILIA de la persona (CTE recursiva desde su raíz canónica, tope 16) y sobre ese puñado
se aplica el mismo predicado de antes (superconjunto → idéntico también con ciclos). Verificado: agenda 16 tareas en
**211 ms**; oráculo 13/13 idéntico (16 tareas fila a fila + 4 roles); prueba sintética 24/0; ciclo deshecho; Codex
APPROVE; auditor-rls PASS (riesgo aceptado: hoy ninguna persona tiene padre, la rama recursiva se demuestra
analítica y sintéticamente). PR #140 (apilada sobre #138). Reversa: `scripts/postventa-tarea-familia/reversa.sql`.
Queda de la agenda: ~0,2 s en dos llamadas a `postventa_estado_fn` (antes y después) + `postventa_visible` por tarea.
🔑 Trampa: la huella `md5(pg_get_functiondef)` incluye el salto de línea final que Postgres añade; calcularla en la
base (ensayo deshecho), no en local.

## Paso 4 · Fase 1 — ✅ EN PROD 29/09 ~20:05 Lima (Miguel aplicó con `!`)

El contador de avisos SLA (`crm.avisos_sla_resumen_v2_fn`) pedía al núcleo las 2.583 oportunidades activas y solo
contaba; 1.139 son terminales (descartadas/convertidas) y nunca avisan. Migración
`20260930002929_crm_sla_resumen_solo_operativos`: nuevo `private.sla_leads_operativos()` (ids activos en las 4
etapas comerciales; INVOKER, solo postgres) y el adaptador pasa esos ids al núcleo; el núcleo no cambia; la
migración y la reversa terminan con `assert_sla_avisos()`. Oráculo 15/15 idéntico (5 actores); Codex ×2 (r1
CHANGES_REQUESTED → r2 PASS); auditor-rls APPROVE. **Resultado: gerencia 1.735–1.792 → 1.256–1.289 ms (−27 %),
supervisor ~813 → ~620; meta de ≤ 1.200 NO alcanzada del todo** (la cartera operativa creció a 1.513 y hay
carga concurrente). Lo que queda son el bucle plpgsql del núcleo (~0,4 ms/oportunidad) y el armado del paquete:
Fase 2 (núcleo: tareas pre-agregadas, no recalcular `sla_hechos_actuales` en `sla_tareas_hechos`) y Fase 3 (a
decidir). Diferido: las dos puertas de Gestión Diaria que piden `(null,true)` (selladas por md5 en sus gates) y un
trinquete vivo del ayudante (auditor P2-2). PR #141 (apilada sobre #140).
🔑 Trampa: `$function$$def$` juntos forman `$$` y cierran un bloque `DO $$`: usar etiquetas distintas al anidar.

## Paso 4 · Gestión Diaria — ✅ EN PROD 30/09 ~10:25 Lima (Miguel aplicó con `!`)

`private.gestion_diaria_alertas_sla` y `private.gestion_diaria_equipo_pendientes` pasan al núcleo SLA solo las
oportunidades operativas (`sla_leads_operativos()`); sus dos guardianes resellados por huella; migración y reversa
pasan el paraguas `assert_gestion_diaria()`, `assert_sla_avisos()` y `assert_gestion_diaria_pulso()`. Migración
`20260930150852_crm_gestion_diaria_solo_operativos`, PR #142 (apilada sobre #141). Oráculo con la migración real
20/20 idéntico (gerencia + 4 supervisores × avisos/equipo/equipo propio/pulso); negativo del guardián (todo se
deshace); Codex APPROVE; auditor-rls PASS. **Resultado verificado: equipo de gerencia 1,80–1,85 → 1,35 s; avisos
del supervisor grande 1,00–1,03 → 0,86 s; supervisores pequeños sin cambio.** 🔑 En horario laboral el oráculo
puede dar diferencias por datos vivos entre las dos pasadas (READ COMMITTED obligatorio): repetir y mirar clave a
clave antes de concluir. Pendiente menor: caso «analista solo con leads terminales → (0,0)» en la suite local.

## Paso 4 · Vigilante del ayudante — ✅ EN PROD 30/09 ~10:57 Lima (Miguel aplicó con `!`)

El guardián `private.assert_sla_avisos()` (corre en cada migración del SLA y de Gestión Diaria a través del paraguas)
vigila desde ahora al ayudante `private.sla_leads_operativos()`: existe con su huella `8d478d78…`, dueño postgres,
INVOKER, STABLE, `search_path` vacío y ACL solo dueño; y **todas** las llamadas del contador `avisos_sla_resumen_v2_fn`
al núcleo van acotadas por el ayudante (`regexp_count` de la forma acotada = total de llamadas, y ≥ 1). Mismo texto de
OK; nada más cambia. Migración `20260930154341_crm_sla_vigilante_ayudante`, PR #143 (apilada sobre #142). Huellas del
guardián: viva `bf835965…` → nueva `9b9edc86…`. Ciclo ensayado en prod y deshecho con **cuatro negativos** (grant del
ayudante a `authenticated`, cuerpo del ayudante alterado, contador con `(null,true)`, contador con una llamada acotada
y otra amplia): los cuatro saltan. Codex CHANGES_REQUESTED → aceptado (exigir igualdad de llamadas, no presencia;
paraguas en la ruta idempotente); auditor-rls APPROVE (sin P0–P2). Verificado en vivo: guardián ampliado OK en 10 ms,
paraguas OK, advisors 242 sin clases nuevas. Cierra el P2-2 del auditor sobre `20260930002929`. Cualquier cambio
legítimo futuro del ayudante exige resellar aquí (patrón de la casa). Queda como ítem aparte: los cuatro negativos
viven solo en el ensayo manual (`scripts/sla-vigilante-ayudante/ensayo-ciclo.sql`); falta
`private.assert_sla_avisos_mutantes()` desde `test-rls.mjs`, como los otros trinquetes con mutantes.

## Paso 4 · Fase 2 — MEDIDA Y DESCARTADA tal como se planeó (29/09 ~20:20 Lima)

Con la cartera operativa (1.514 filas, gerencia): `sla_operacion_autorizada` 1.226 ms = núcleo `sla_operacion_leads`
835–999 ms + post-proceso 312 ms (+26 ms `proximo_cambio_en` releyendo el JSON, +15 ms del conteo del adaptador).
Dentro del núcleo, el SELECT del bucle es solo **133 ms** (`sla_hechos_actuales` 83, `sla_tareas_hechos` 84 que
recalcula hechos, lateral de tareas por lead barato); el prototipo «tareas pre-agregadas» salió MÁS LENTO (251 ms).
Las 3 sentencias SQL embebidas del bucle cuestan ~97 ms en total. **El coste real es el cuerpo plpgsql que arma
la ficha JSON de cada oportunidad (~0,5 ms × 1.514 ≈ 770 ms; 7,8 MB de JSON por llamada) y su copia en el
post-proceso (312 ms), para un contador que solo necesita 4 cifras.** La fase 2 «menos trabajo repetido en el
SELECT» no paga: descartada. Lo que sí pagaría es un «modo resumen» del núcleo (no armar `estado`/`presentacion`
cuando solo se cuenta): toca el motor sellado (`assert_sla_nucleo` referencia la firma exacta de
`sla_operacion_leads(uuid[],boolean,uuid[],timestamptz)`: no se puede añadir un parámetro sin resellar) y sus 9
puertas: es un mini-proyecto aparte (estimación: gerencia 1,27 → ~0,3–0,4 s). Alternativa no idéntica: caché del
resumen por actor 20–30 s (decisión de Miguel).

## Plan técnico original del paso 2 (superado por la medición de arriba; se conserva como historia)

- **Fase 1 (servidor, LEVEL 3):** `private.cartera_f5_personas_visibles(uuid)` y `private.cartera_f5_listar`:
  calcular para las 560 personas solo lo que filtra/ordena/cuenta (nombre, documento, teléfono, responsable,
  estado, empresa/moneda/mes de fuentes) y dejar los 4 laterales de presentación (perfil, lead, cierre
  externo, identificador) para las 25 de `pagina`. Reglas de acceso (`actor`, lector global, bandeja del
  supervisor, demos, canónicas) intactas. Migración nueva; reversa = restaurar los cuerpos actuales
  (huellas md5 vivas selladas en el preflight). Oráculo de igualdad en banco Docker a paridad: md5 del JSON de
  `cartera_inversionistas_filtrada_fn` (pág. 1–3 × sin filtro/texto/empresa/responsable/estado/por_vencer)
  y de `inversionista_ficha/cuentas/documento/gestion_fn` para 5 personas, con 3 roles (gerencia,
  supervisor con bandeja, analista) antes y después → idéntico. Medir tiempo. auditor-rls + Codex.
  Comprobar gates/huellas que sellen estas funciones antes de tocar (grep `personas_visibles|cartera_f5_listar`
  en migraciones y `supabase/scripts`). Meta: 2.306 ms → ≤ 400 ms por página.
- **Fase 2 (front, LEVEL 1–2):** `respuestas-tasa-provider.tsx` (15 s en segundo plano → Realtime si ya se usa
  en la app; si no, 60 s solo en primer plano + refetch al foco), `postventa-queries.ts` (staleTime 0 +
  15 s → invalidar tras escribir + refetch al foco), `inversion-nueva.tsx` (2 × 15 s → solo mientras el
  formulario está abierto y en primer plano). Meta: −45 % de llamadas RPC (hoy 91.175 de tasas en 4 días).
- **Diferido:** `avisos_sla_resumen_v2_fn` (1,7–2,3 s; plan SLA), `metricas_conversiones_fn` (1,1 s),
  `postventa_tarea_json` (recorrido por tarea), VOLATILE→STABLE en 7 puertas de lectura.

**Gates de producción (solo lectura, 29/09 ~18:05):** vigencia ✅ (5 puertas, tope 6) · analítica ✅ (37
candidatos, techo 14) · vigías ✅ (0 alertas abiertas, 50 cerradas) · **auditoría ❌**: 11 tablas sin
auditor completo (`cartera_lecturas`, `contratos_eliminados_auditoria`, `gestion_diaria_control_avisos`,
`gestion_diaria_entregas`, `inversion_ajustes_mes_cerrado`, `inversion_backfill_lotes`,
`inversion_cotitular_origenes`, `inversion_eventos`, `inversion_solicitud_correcciones`,
`inversion_solicitud_revisiones`, `politica_gestion_diaria`) — trabajos de otras sesiones; se arregla con un
auditor AFTER por fila o declarando la exención en `private.auditoria_exenciones`. `gate:realidad` NOT RUN
(exige credenciales que el hook no deja pasar en línea).

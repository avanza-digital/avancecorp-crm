---
tags: [crm, ux, supervisor, hoy, plan, seguimiento]
actualizado: 2026-09-27
estado: publicado-2026-09-27
---

# Hoy del supervisor - puesto de mando en una pantalla (plan 2026-09-27)

Relacionadas: [[Hoy del supervisor - reparto compacto]] · [[Fundamentos UX del CRM]] ·
[[Gestion Diaria - diseno VitaNova con colores del CRM, analisis y plan (2026-09-27)]].

Paquete del diseñador: `CRM-Avance-Corp/design_handoff_hoy_supervisor/` (README, prototipo
`.dc.html`, borrador `supervisor-mando.tsx`). Miguel: «así quiero que se le vea al supervisor».
El 27/09 pidió este plan **antes** que el del analista. Estado: **plan esperando OK; sin código.**

## El hallazgo que cambió el plan

Producción corre el seguimiento nuevo en modo **activo** desde el 07/09/2026
(`crm.sla_operacion_control.modo = 'activo'`, revisión 1). El borrador del diseñador se apoyaba
en la cola antigua (`cola_accion_fn`), que la pantalla solo consulta en modo legado (demo o
seguimiento apagado). Implementado tal cual, en producción «Decide primero» diría «Cargando…» para
siempre y la cola no existiría (hoy el supervisor solo ve una tarjeta «Seguimiento del equipo»).

La cola del diseño se construye sobre `crm.cola_accion_v2_fn` (la del módulo Seguimiento). Su
cuerpo VIVO (md5 `0a3ea253eef1be087d9121afc04499e5`) filtra por `p_analista_id` **antes** de
calcular `totales`, así que los conteos por analista vienen exactos del servidor.

## Plan para Miguel (por fases)

**Objetivo:** el supervisor abre «Hoy» y, sin bajar, sabe qué decidir, a quién de su equipo mirar
y qué casos atender, con los datos que producción usa de verdad.

- **F1 · Cola y equipo lado a lado.** Cola «Para atender ahora» (7 casos + «Ver todo en
  Seguimiento») con pestañas y un botón por analista; «Equipo hoy» con un punto de color por
  analista, que al tocarlo despliega sus señales y filtra la cola. Los números salen del servidor.
- **F2 · «Decide primero».** Hasta tres tarjetas arriba + «Esta semana». «Primera gestión
  pendiente» filtra la cola; «citas sin asistir» y «sin próxima acción» NO filtran la cola (no
  contiene esos casos): despliegan el detalle y llevan a «Mi equipo hoy»; «por repartir» lleva a
  Derivar leads.
- **F3 · Franja «Consulta» y «Detalle».** Cifras en una línea abajo; «Detalle» abre encima los 4
  indicadores, el cumplimiento del mes (con «Reintentar»), la agenda del equipo, «Por empresa», las
  tasas autorizadas y el pie «Ves solo a tu equipo». Sin «pipeline» ni textos técnicos.
- **F4 · Pruebas, revisión, publicación** solo con la orden de Miguel; la pantalla vieja queda de
  respaldo (volver atrás = un cambio de una línea).

Decisiones por defecto: tasas autorizadas dentro de «Detalle» (no se pierden); el enlace del
equipo va a «Mi equipo hoy»; desaparece la pestaña «Sin movimiento» (sin datos en modo activo).

## Anexo técnico (lo que Miguel no necesita leer)

- **Orquestador + dos adaptadores** (activo / legado) con una capa de presentación compartida;
  remontar al cambiar `modo` o `control_revision`. No mezclar ambos contratos en un componente.
  El demo es siempre legado: la aprobación visual del modo activo se hace con sesión real o con
  un fixture activo explícito.
- **Una sola consulta de página** (`useColaSlaPagina`) por pestaña/filtro: `totales` trae todos
  los conteos (pendientes, primera_atencion, tareas_vencidas…). «Todas» sin número hasta abrirla.
  Medir duración con tamaño típico/máximo y varios supervisores (cada consulta recalcula
  `private.sla_operacion_autorizada` y se refresca sola).
- **Fail-closed por consulta:** con error no se usa `data` retenida (TanStack la conserva tras un
  refetch fallido); validar `pagina.modo === 'activo'`; «Nada que decidir» solo si TODAS las
  fuentes de la banda 1 terminaron bien; el error de la agenda se ve en la superficie principal.
- **Primera gestión pendiente** (modelo 3): texto de supervisión («Revisa la primera gestión con el
  analista»). La severidad NO se infiere del primer ítem (`prioridad` 0 fija; orden por
  `referencia_en`, no por severidad): rojo solo con confirmación del servidor.
- **`lib/tres-cosas.ts`:** `candidatosDeHoy` sin recorte + `tresCosasDeHoy` = slice(0,3);
  `vendedorId?` en `CosaDeHoy`; entrada del seguimiento para el modo activo.
- **Semáforo del equipo:** una función pura con UNA severidad por analista (rojo prevalece; días,
  no-show, sin próxima acción, vencidas) que alimenta punto, cabecera y chips. `pct_completadas`
  se muestra como «% completadas», no «% cierres».
- **Filas:** unir por `lead_id` con el store; contacto y monto solo con lead completo (caché
  parcial); `referencia_en` null → «—»; apertura con estados «Abriendo…»/error como `ColaSlaPanel`;
  chips del roster con `activo && rol_crm === 'vendedor'`.
- **Pestañas:** primera atención como filtro removible anunciado, sin falsear `aria-selected`.
  Título «Para atender ahora» (la señal `pendientes` admite severidad baja: no llamarla «urgente»).
- **A11y:** tarjeta y CTA como hermanos (no anidados); filas del equipo con `aria-expanded` +
  `aria-controls`; «Detalle» con patrón completo (Esc desde cualquier descendiente, foco de vuelta
  al disparador); objetivos ≥36 px; nombre accesible de fila con dueño, motivo y antigüedad.
- **Publicación:** `main` local = `avancecorp/main`, build desde ese commit, preflight del CRM.

## Ejecución (27/09) — Miguel: «ejecuta todas las fases, siempre que Codex audite todo el código»

- **F1** `bc97b98d` · cola del seguimiento + Equipo hoy · `datos-supervisor.ts` compartido con la
  pantalla clásica · `lib/senal-equipo.ts` · `lib/cola-supervision.ts`.
- **F2** `40654da1` · «Decide primero» (`candidatosDeHoy`, primera gestión vencida roja por contrato
  del servidor: la señal solo existe con el plazo vencido y su aviso es `critica` fijo en
  `private.sla_operacion_leads`, verificado en el cuerpo vivo).
- **F3** `605ac085` · franja «Consulta» + diálogo «Detalle» + arreglos de la auditoría de la F1.
- **F4** · `hoy.tsx` enruta a `HoySupervisorMando` (modo legado/demo ⇒ pantalla clásica; rollback =
  una línea) · e2e `hoy-supervisor-mando.spec.ts` (teclado a 1440×900 y reflow a 375 px) ·
  `sla-operacion.spec.ts` actualizado (el Hoy del supervisor ya pide una vista previa de 7).
- **F4** `b862ac80` + cierre `4b54e495` (auditoría final de Codex: conversión con error anulada en
  todos los consumidores, `nombresCortos` por niveles, áreas de toque ≥36/40 px).
- **Auditorías:** Codex F1 (3 P1 + 2 P2) · Codex F2/F3 (1 P1 + 3 P2 + 1 P3) · `revisor-a11y`
  (1 P1 + 7 P2 + P3) · Codex final (1 P1 + 2 P2) · **Codex cierre: PASS** — todo aceptado salvo lo
  anotado abajo.
- **Verificación final:** `npm run check` PASS (4589/4589) · e2e Docker 17/17 PASS · gate de realidad
  NOT RUN (necesita la clave de servicio; supuestos de prod verificados por SQL de lectura). Encargos en
  `CRM-Avance-Corp/docs/encargos/2026-09-27-codex-supervisor-hoy-*.md`.
- **Decisiones tomadas por defecto:** tasas autorizadas dentro de «Detalle»; enlaces de equipo a
  «Mi equipo hoy»; «citas sin asistir» y «sin próxima acción» no filtran la cola.
- **Residuos aceptados (P3):** el error de apertura de ficha se anuncia dos veces (toast del store +
  aviso local, igual que el módulo Seguimiento); anillo de foco `ring/40` de toda la casa; el
  `Sheet` de la ficha no descarta `<body>` como origen de foco (el `Dialog` sí) — deuda aparte.
- **Todo número se abre** (regla de Miguel 27/09, «¿para qué quiero saber si no puedo verlo?»):
  `02e88946` + `1f5918bb` + `d301f693`; Codex PASS. Excepción: la conversión del mes (su lista,
  la vista Conversiones, es solo de gerencia).
- ✅ **PUBLICADO el 27/09 a las 15:10 Lima** por `/release-crm` de Miguel: artefacto
  `crm-20260927T200302Z-01d5ddc4b653`, build `build-20260927T200301496Z`, commit `01d5ddc4`.
  Rama de publicación `release/hoy-supervisor-20260927` = vivo anterior `8d4be227` + solo estos
  commits (cherry-pick), en worktree aparte: **se dejó fuera `3e6c3587` (Citas por equipo)
  porque su migración `20260927172931` NO está aplicada en producción** (verificado por SQL).
  Check PASS (4597) en esa rama, `ARTEFACTO_OK`, preflight OK contra `8d4be227`, configuración
  (Supabase, clave pública, Sentry) idéntica al build anterior. Humo: inicio 200, `version.json`
  nuevo, `index-DQc8V59y.js` = build, 105/117 byte a byte (11 PNG de la CDN + `.htaccess`), ZIP
  404. Rama fusionada en `main` (`491a90c4`) y borrada; manifiesto copiado a `releases/` del
  `main` (el preflight ya reconoce el vivo nuevo).
- **GitHub:** pendiente la PR de integración (el `main` local no se empuja: lleva lo de Gloria).

## Revisión de Codex del plan (27/09)

Encargo: `CRM-Avance-Corp/docs/encargos/2026-09-27-codex-plan-supervisor-hoy.md`. VERDICT
CHANGES_REQUESTED, confianza alta: 4 P1 + 6 P2, **todos aceptados** tras comprobarlos en el código
(`sla-operacion.tsx:75-76`, `sla-operacion.ts:78-90`, borrador `:379-383` y `:721`, migración
`20260907212612…:251`). Ya están incorporados arriba.

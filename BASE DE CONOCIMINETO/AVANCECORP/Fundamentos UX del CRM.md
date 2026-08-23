---
tags: [crm, ux, fundamentos, design-system]
actualizado: 2026-08-23
estado: vigente
---

# Fundamentos UX del CRM

Investigación aportada por Miguel (2026-08-23): 8 pilares y 47 conceptos de
UX/UI. Esta nota los aterriza al CRM — qué ya está cubierto, qué se integra a
las fases del rediseño del [[Hoy del supervisor - reparto compacto|Hoy del supervisor]]
y qué queda como trabajo propio con nombre.

Relacionadas: [[Hoy del supervisor - reparto compacto]] · [[Configuración operativa CRM 2026-08-07]].

## El sistema de diseño que YA existe (escrito, para que no viva solo en el código)

- **Color:** navy `#111e3d` (autoridad/ganado) · azul `#2563eb` (acción, en curso) ·
  ámbar `#d97706` (esta semana) · rojo `#dc2626` (intervención hoy) · violeta
  `#7c3aed` (categórico: reuniones/podios, nunca severidad) · gris `#64748b`
  (contexto). **Sin verde** (regla de la casa). Fuente única: `lib/semaforo.ts`.
- **Presupuesto de color por tarjeta:** 1 grupo rojo por tipo de decisión ·
  máx. 2 grupos ámbar visibles · el resto se agrupa o va tras expansión ·
  la severidad original nunca se rebaja: se agrupa y el grupo hereda la más alta.
- **Tipografía:** Plus Jakarta Sans; jerarquía por peso (800 cifras, 700
  títulos, 600 etiquetas) y `tabular-nums` en todo número comparable.
- **Espaciado:** escala Tailwind (4/8/12/16/24/32); tarjetas `rounded-xl`,
  divisores `border/60`.
- **Componentes:** Card + SectionHead · KpiCard · Badge (= severidad, nada
  más) · Progress · tablist (patrón de `ranking-vendedores`) · estados
  Panel{Cargando,Error,Vacio}.

## Los 8 pilares, mapeados

| Pilar | Estado en el CRM |
|---|---|
| 1 Psicología y percepción | ✅ En curso: Gestalt + color + carga cognitiva son la base del rediseño del Hoy del supervisor (F1–F3) |
| 2 Fundamentos visuales | ✅ Sistema de arriba; F2 aplica jerarquía (números gris salvo señal, tira de severidad) |
| 3 Arquitectura UX | 🟡 Role-Based UX ya existe (3 roles, 3 Hoy). **Falta**: mapa de user flows por tarea (lead→calificar→cerrar) y auditoría de arquitectura de información del sidebar |
| 4 Interacción | ✅ Estados y feedback ya son regla (toasts, degradación honesta con «—», skeletons); motion vive en el [[UI Playground (laboratorio de animaciones)|UI Playground]] |
| 5 Principios y leyes | ✅ Hick/Miller (franja ≤3, colapsos) · Jakob (campana=avisos, lupa=buscar) · **Fitts entra al checklist F2** (objetivos táctiles ≥40 px) · **Tesler como regla operativa** (ver abajo) |
| 6 Componentes profesionales | 🟡 Tablas y formularios tienen patrones; **falta** consolidarlos como catálogo (una nota por componente con sus estados) |
| 7 Accesibilidad | ✅ Es gate: subagente `revisor-a11y`, teclado en todo interactivo, color nunca solo. WAI-ARIA APG como referencia (panel vacío enfocable, 2026-08-23) |
| 8 Validación | 🟡 Existe la prueba visual de Miguel y hubo una prueba real (vendedora, domicilio legal, 96 s). **Falta formalizarla** → Fase 5 |

## Ley de Tesler — la regla operativa (2026-08-23)

La complejidad de un sistema no desaparece: **alguien la carga**. La regla del
CRM es que **toda complejidad que el sistema pueda calcular, la calcula el
sistema; al supervisor solo le llegan decisiones**.

Dónde ya se aplica (F1–F2):
- La campana **agrupa por decisión**: el sistema hace la deduplicación mental
  que antes hacía el supervisor con 27 avisos.
- «El más rezagado espera hace 4 días»: el sistema calcula el peor caso; el
  supervisor no barre la bandeja para encontrarlo.
- La cola **aterriza en la primera pestaña con filas**: el sistema decide dónde
  empezar; y ordena por severidad para que «cuál primero» no sea tarea humana.
- El motivo de cada fila viene **redactado** (`redactarMotivoCola`), no como
  datos crudos que el supervisor tendría que interpretar.

Dónde manda aplicarla a continuación:
- **F3 «Hoy, tres cosas» ES Tesler puro**: el sistema absorbe la priorización
  del día (qué mirar primero) en vez de dejar que el supervisor escanee cinco
  tarjetas. Es el argumento de esa fase.
- **F4 «reaparece si empeora»**: la vigilancia de una alerta reconocida la
  carga el sistema, no la memoria del supervisor.
- Candidato futuro: el reparto podría **proponer** la asignación (hoy el
  supervisor decide lead por lead en Derivaciones) — trasladarle al sistema el
  primer borrador de la decisión, nunca la decisión final.

Contra-regla (el límite de Tesler): la complejidad **de negocio** no se
esconde — el % de conversión, qué cuenta y qué no, las dos fechas de un
contrato. Ocultarla no la elimina: la traslada a un error futuro. Se absorbe
la complejidad *mecánica*, se explica la *de negocio*.

## Qué se integra a las fases del Hoy del supervisor

- **F2 gana un checklist de cierre** (además del presupuesto de color):
  1. Nielsen como auditoría: visibilidad de estado, prevención de error,
     reconocimiento sobre recuerdo, consistencia.
  2. Fitts: pestañas y filas con área clicable cómoda (≥40 px de alto táctil).
  3. Estados completos por componente nuevo: default/hover/focus/vacío/carga/error.
  4. Pasada de UX writing: todo vacío dice qué hacer («Reparte desde
     Derivaciones →»), ningún error sin salida.
- **F5 — Validación (nueva, tras F3):** prueba de usabilidad con UN supervisor
  real: 5 tareas sin explicar nada («encuentra al lead más urgente», «reparte
  la bandeja», «dime quién del equipo está atrasado»…), midiendo ¿completó? ·
  tiempo · clics · dónde se detuvo. Igual que la prueba de 96 s del domicilio
  legal: donde se detiene, ahí está la siguiente fase.

## Trabajo propio con nombre (no cabe en estas fases)

1. **Mapa de flujos por tarea** (pilar 3): dibujar lead→calificar→agendar→
   propuesta→cierre y contar clics por paso; optimizar transiciones, no pantallas.
2. **Catálogo de componentes** (pilar 6): una nota por componente con estados
   y ejemplos, para que pantallas nuevas no reinventen.
3. **Métricas UX en producto** (pilar 8): clics por tarea y tasa de término de
   las 3 tareas del supervisor — cuando exista F4 (reconocer) habrá datos.

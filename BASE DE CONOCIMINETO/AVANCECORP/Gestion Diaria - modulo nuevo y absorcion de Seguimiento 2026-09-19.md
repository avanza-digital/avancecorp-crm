---
tags: [crm, gestion-diaria, seguimiento, plan, decision]
estado: plan aprobado — Fase 0 en curso
fecha: 2026-09-19
---

# Gestión Diaria — módulo nuevo y absorción de Seguimiento (2026-09-19)

**Qué es.** Módulo nuevo del CRM que responde una sola pregunta: *¿qué está pasando hoy y qué hay que hacer ahora?* Tres vistas por rol (analista «Mi día», supervisor «Mi equipo hoy», gerencia «Toda la operación») y una pieza que lo desbloquea: **el resultado de llamada tipificado y obligatorio** (7 opciones), guardado en `crm.actividades.metadata` sin tocar el CHECK de `tipo`. Absorbe [[Seguimiento - modulo propio y vista por rol 2026-09-07]].

**Dónde vive el plan.** `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md` (aprobado por Miguel el 19/09), junto al planteamiento original `PLAN.md`, los seis mockups y el `UI-UX-playbook.pdf` (llegaron en `GESTION DIARIA/gestion-diaria-handoff.zip`).

## Decisiones de Miguel (19/09) — no re-preguntar

1. **«Hoy» se queda igual.** Gestión Diaria es un módulo DISTINTO en el menú (grupo Operación, en el sitio de Seguimiento). La pantalla de entrada de cada rol no cambia. Conviven dos presentaciones: Hoy = «las 3 cosas de ahora»; Gestión Diaria = la cola completa agrupada.
2. **Cola del analista: el lead nuevo sin primer intento va PRIMERO**, luego vencidas, luego las de hoy. Se conserva la regla de [[Hoy del vendedor - Ahora y Después]] (el mockup 4 ponía vencidas arriba: no).
3. **Plus Jakarta Sans sí, verde no.** El token `--font-sans` ya declaraba Jakarta pero nunca se cargó (el CRM pintaba la letra del sistema). Los estados «Bien» van en navy sobre fondo tenue; el azul se reserva a enlaces, selección y foco. Regla de [[Fundamentos UX del CRM]] intacta.
4. **«Contestó · no le interesa» descarta el lead en la misma operación**, con submotivo obligatorio y deshacer de 24 h. Ese deshacer NO existe hoy para el analista (el de coordinación exige lead sin dueño; `crm.reabrir_lead_fn` no tiene ventana y devuelve el lead a «nuevo»): se construye `crm.deshacer_resultado_llamada`.
5. **«Pide otro producto» también descarta** (`pide_credito` + submotivo agregable). Ambos descartes caen en el Centro de rescate (`crm.rescate_descartes_mes`), donde el supervisor o gerencia pueden reabrirlos. Esa carpeta excluye a propósito `datos_invalidos`.
6. **«Número errado» / «No es la persona»: el analista decide.** Con segundo número → tarea «llamar al segundo número» hoy. Sin segundo número → el panel ofrece «Descartar por datos inválidos» (deshacer 24 h) o «Mantener con reintento a 7 días». Cuentan como intento pero NO entran en la tasa de contacto.
7. **Tasa de contacto: el % se muestra siempre con el conteo** («100 % · 2 llamadas»). Chip y alerta solo con ≥ 5 llamadas útiles; esas filas van al final del orden por tasa.
8. **Llamadas por rango de horas**: supervisor y gerencia ven cuántas llamadas hace cada analista por franja horaria (barras 08–20 Lima), en la tabla de equipo.
9. **Submotivos aprobados**: no le interesa → sin fondos por ahora (motivo `sin_fondos`), ya invirtió con otro (`competencia`), desconfianza / no le interesa invertir / otro (`sin_interes`); pide otro producto → préstamo / crédito / otro (`pide_credito`). **Umbrales aprobados**: Bien ≥ 45 %, Atención 25–44 %, Bajo < 25 %; mínimo 5 llamadas útiles; «tasa muy baja» = 15 puntos bajo el equipo; «sin llamadas» desde las 11:00; «parado» = 2 h sin llamar entre 09:00 y 18:00.

## Qué deroga y qué NO

- **Deroga** la decisión del 07/09 de mantener Seguimiento como módulo propio: `#/seguimiento` pasará a alias de `gestion-diaria` en la última fase (cerrar → observar → derribar). `ColaSlaPanel` y `cola_accion_v2_fn` siguen vivos.
- **No deroga** el orden de prioridades del 25/08, la decisión «los avisos SLA nuevos no se reconocen» de [[Plan de avisos por accion y rol - 2026-09-07]] (solo `tarea_vencida` y `por_repartir` se reconocen), ni [[Terminologia de citas en el CRM]] («cita», nunca «reunión» en pantalla).
- La alerta «SLA de primer CONTACTO» está eliminada (§11 del planteamiento); la de «primer INTENTO» se conserva.

## Definiciones fijadas (una sola vez, en el servidor)

- **Llamada** = `tipo in ('llamada_realizada','llamada_no_contestada')`. **Contacto** = `llamada_realizada`. **Llamada útil** = llamada cuyo resultado no es número errado / no es la persona. **Tasa** = contactos / llamadas útiles. En pantalla se rotula «Llamadas», nunca «gestiones» ni «toques» (los 5 toques de Agenda son otro concepto; ver [[Contrato de la capa semantica - Leads y Citas (F6, 2026-08-30)]]).
- **Tarea vencida** = `estado='pendiente' and activo and vence_en < now()`.
- **Jerarquía** = `crm.equipo.supervisor_id` de hoy; roster activo = `activo` y rol vendedor.
- **Resultado tipificado**: `no_contesto` · `volver_a_llamar` · `agendo_reunion` · `no_interesado` · `numero_errado` · `no_es_la_persona` · `pide_otro_producto`, en `metadata` `{evento:'resultado_llamada', resultado, submotivo?, intento_n, etapa_anterior}`. Los tres primeros «no contactó» se graban como `llamada_no_contestada` (no avanzan etapa; sí sellan primera gestión).
- **Ventana legal** L–S 07:00–20:00 (`slotHabil`, ver [[Agenda comercial del CRM (plan v2)]]).

## Arquitectura (4 capas) y fases

Núcleo `private.gestion_diaria_llamadas(...)` (única definición de llamada/tasa, registrado como auxiliar auditado del censo analítico) · `private.llamada_registrar(...)` · `private.gestion_diaria_umbrales()`. Puertas: `crm.registro_actividad_fn` (F1) · `crm.registrar_llamada_v3` + `crm.deshacer_resultado_llamada` (F2, componen sobre `registrar_actividad_v2`/`cerrar_tarea_v2` selladas, patrón `cerrar_reunion_v3`) · `crm.gestion_diaria_analista_fn` (F3) · `crm.gestion_diaria_equipo_fn` (F4) · `crm.gestion_diaria_pulso_fn` (F5). Front: vista `gestion-diaria` con `screens/gestion-diaria/{analista,supervisor,gerencia}` y componentes compartidos `registro-actividad`, `registrar-resultado`, `tabla-equipo-diaria`, `alertas-del-dia`.

Fases: **F0** cimientos (medición, Jakarta, primitivas tabs/radio-group/exportar-csv, docs) → **F1** alta del módulo + registro crudo compartido (solo lectura; el supervisor lee HOY el texto de su equipo) → **F2** resultado tipificado → **F3** analista → **F4** supervisor → **F5** gerencia → **F6** absorber Seguimiento. SQL primero, front después, en cada fase; cada fase = 1 migración + 1 PR con merge commit.

## Hallazgos del código que corrigieron el planteamiento

`registrar_actividad_v2` no escribe metadata y está sellada → puerta v3 · en `cerrar_tarea_v2` el id de la actividad viaja en `respuesta->>'actividad_id'` · el UPDATE de metadata desde definer no está bloqueado (solo audita) · el censo analítico es un trinquete desbordado: las puertas no usan `count(` y el núcleo entra por `private.auxiliares_analitica_lc_auditados()` · `alerta_id` con regex cerrada en singular y uuid del ACTOR · `cola_accion_v2_fn` no está sellada por gate (md5 en preflight) · `DialogResultado` sirve también WhatsApp (solo se reemplaza la rama `tel`) · Sheet dentro de Sheet sin precedente → `Dialog` · «Omitir» se renombra «Cerrar sin registrar» (en móvil no hay Esc) · `parkeado` ≠ `leads_por_repartir`.

## Medición en producción (19/09, solo lectura)

SLA en modo `activo` desde el 07/09 · 18 analistas y 3 supervisores activos · 5 089 llamadas, **0** con metadata · vencidas canónicas **737** (662 por día Lima) · `politica_abandono`: 7 días, sin ningún consumidor hasta ahora · últimos 14 días: 2 638 llamadas, tasa global 46 %, equipo Carmen 33 % (1 425) vs equipo Jorge 62 % (1 207); analistas entre 6 % y 100 %; ratio llamadas/lead hasta 4,9 (dos analistas) · hora pico 10–12 y 15–17, casi nada después de las 18 · descartes vivos: sin_interes 210, pide_credito 191, datos_invalidos 130, otro 52, sin_fondos 51, no_responde 34, competencia 4 (todos con dueño) · en texto libre: «préstamo» 176, «crédito» 145, «no interesa» 107, «sin fondos» 70, «número errado» 53, «desconfianza» 8.

Fase 2 (resultado tipificado, 20/09): [[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]].

Relacionadas: [[Acceso y roles del CRM]] · [[Nucleo operativo SLA - arquitectura y consumidores 2026-09-06]] · [[Terminología comercial del CRM]] · [[Inicio]]

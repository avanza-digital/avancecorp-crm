---
tags: [crm, gerencia, citas, ux, propuesta-local]
fecha: 2026-09-08
estado: propuesta-local-con-datos-ficticios
---

# Citas Gerencia — adaptación al CRM y consultas por lead

Continuación de [[Retomar Citas Gerencia - propuesta local en pausa 2026-09-08]]. Contexto: [[Inicio]], [[Citas de Gerencia - correcciones comerciales y bases 2026-09-07]], [[Inventario de indicadores de Gerencia - Citas y operacion]] y [[Auditoria de Citas de Gerencia - frontend y contrato backend 2026-09-07]].

Miguel aceptó la dirección visual y pidió usar los recursos y componentes del CRM. La adaptación usa los componentes compartidos reales en una entrada local independiente: `http://127.0.0.1:4180/prototypes/citas-crm.html`. Los 40 registros son ficticios, con corte al 7 de septiembre de 2026, 13:00 Lima. No reemplaza todavía el módulo ni integra datos reales.

## Decisiones comerciales duraderas

- La consulta debe ocupar poco espacio. Filtros habituales visibles; filtros detallados desplegables.
- No repetir el número de citas en la franja superior y junto a la lista. La franja se usa para leads únicos con cita, citas por lead, leads con varias citas e inasistencias reprogramadas.
- El período solicitado es mes y cuatro semanas comerciales: 1–7, 8–14, 15–21 y 22–fin. La semana 4 incluye los días restantes; no son semanas ISO.
- Promedio por asesor = citas del conjunto filtrado / leads distintos con cita en ese conjunto. No incluye leads sin cita. El total se recalcula con ids únicos, sin promediar promedios ni sumar leads por asesor.
- «Por lead» permite comprobar cuántas citas tiene cada prospecto y abrirlas manteniendo el contexto.
- Para saber cuántas inasistencias se reprogramaron, conservar la cita original y seguir relaciones explícitas hacia la nueva cita. Otra cita con el mismo prospecto no prueba por sí sola una reprogramación.
- El seguimiento parte de las inasistencias filtradas y mira sus sucesoras hasta el corte, incluso fuera del mes/semana. Se diferencia nueva cita pendiente, asistencia posterior y ausencia de nueva cita.
- Cambiar de vista conserva los filtros. Los accesos desde una ficha a su Agenda o a las citas del asesor usan el mes de esa ficha y restablecen filtros incompatibles, con explicación en la guía.

## Implementación y límites

Reutiliza marca, tipografía, tokens, formatos, Button, Card, Input, Select, Badge y Sheet del CRM. La primera propuesta HTML y su modelo quedan intactos. El nuevo promedio atribuye la cita al analista del registro; no acredita que haya sido su creador.

La integración requiere filas de citas, ids de lead estables y relaciones fiables de reprogramación. No cruzar breakdowns agregados independientes para fabricar una lista de citas. Los contratos comerciales productivos vigentes no se cambiaron.

Guía, evidencia visual, revisión independiente evaluada y verificaciones: `UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/README.md`. Gate frontend ejecutado: lint, typecheck, 3.079 tests y build. Prueba táctil completa, lector de pantalla, backend y publicación no forman parte del resultado validado.

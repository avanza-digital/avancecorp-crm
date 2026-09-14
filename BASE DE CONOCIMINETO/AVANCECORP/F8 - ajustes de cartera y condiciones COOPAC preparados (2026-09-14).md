---
tags: [crm, multiempresa, f8, cartera, coopac]
fecha: 2026-09-14
estado: preparado-local-sql-pendiente-aprobacion
---

# F8 — ajustes de Cartera y condiciones COOPAC preparados

Miguel pidió corregir el timeout del caso real, volver a la organización de la
ficha anterior y registrar plazo/rentabilidad manual para COOPAC. Confirmó que
la rentabilidad se expresa como porcentaje anual: **12 significa 12 % anual**.
El plazo se registra en meses y el vencimiento se deriva por meses naturales,
ajustando fin de mes. Esto cubre cierre inicial e inversión adicional.

Preparado: núcleo de personas F5 más eficiente, Ficha 360 con los componentes
comerciales anteriores, continuidad/contactos/foco y conservación visual ante
fallos transitorios. El servidor conserva autoridad de datos y permisos;
revocar acceso retira la ficha. COOPAC no crea perfiles ficticios Avance.

Las condiciones se guardan en la fuente del cierre mediante los escritores
F3/F4 existentes. El cierre inicial deriva la fecha en el servidor de Lima y
no envía la previsualización del dispositivo, para que medianoche no rompa un
reintento. Las inversiones adicionales conservan la fecha comercial elegida.
Históricos y solicitudes anteriores no reciben tasas/plazos inventados.
Comisiones siguen externas. No se calcula un cronograma de pagos COOPAC.

PASS local: 3.579 tests, 15 E2E finales F5/F6, gates de scripts/Edge, paridad de
personas en siete contextos y siete variantes de enlaces demo/fusiones, altas,
correcciones, reintentos viejos/nuevos, ACL completa y replay en otra copia.
En volumen sintético parecido al real, lista+ficha pasan de timeout de 8 s a
menos de medio segundo; todavía no es una medición productiva.

Claude revisó por wrapper y devolvió observaciones P2/P3, sin P0/P1. Codex
corrigió fecha, accesibilidad, bloqueo de nuevas acciones y foco, verificó ACL
y documentó las decisiones. No se afirma un dictamen PASS de Claude.

**No instalado ni publicado.** Pendientes: aprobación del SQL concreto,
banco Supabase con coste aprobado, gates SQL/Auth/RLS/advisors, merge,
publicación del commit Main/remoto y nueva prueba real. G7-R01/G7 siguen abiertos;
F8 conserva el piloto nominal ya aprobado y F7 global sigue OFF. La edición del
plazo de contratos ya confirmados no se incluye; sí la corrección previa a confirmar.

Evidencia y SQL enlazados:
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/ajustes-2026-09-14/README.md`.

Antecedentes: [[F8 - primer caso real verificado (2026-09-14)]],
[[F8 - piloto nominal activado (2026-09-14)]],
[[Mejoras UX Ficha 360 2026-08-29]].
Plan: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

---
tags: [crm, f6, pruebas, accesibilidad, claude]
fecha: 2026-09-10
estado: pruebas-6-y-8-pass-lector-pendiente
---

# F6 — pruebas delegadas y ajustes de accesibilidad

Miguel autorizó todas las pruebas necesarias y pidió consultar siempre a Claude.
Esta preferencia explícita prevalece sobre la selección automática por nivel de
AGENTS.md: usar el wrapper `scripts/claude-review`, con Codex como PRIMARY y Claude
como revisor sin herramientas ni escritura. Se conservan el escritor único,
el límite de consultas y la prohibición de cadenas recursivas.

En el banco sintético se completaron retiro administrativo/permisos (punto 6)
y recuperación tras pérdida de respuesta (punto 8). Capital, inversiones y pagos
anteriores se conservaron. Punto 7 parcial: móvil, teclado y estabilidad comprobados;
lectura con VoiceOver pendiente de verificación. No trasladar el PASS de F5 a F6.

Se corrigió el retorno del foco en el Dialog común y el mensaje en inglés de
fallos de transporte. Son ajustes locales pendientes de publicación, junto al
selector de archivos aprobado por Miguel. No hay cambios SQL ni encendido productivo.

Se hicieron dos revisiones reales con Claude. Ambas entregaron CHANGES_REQUESTED:
la primera amplió casos negativos del ensayo; la segunda recomendó reforzar
el foco cuando el control sigue conectado pero no admite foco. Se incorporaron
las mejoras sustentadas y se documentaron los límites de Safari/VoiceOver.
Una opinión de Claude no reemplaza las pruebas ni equivale a autorización.

[Acta y evidencia](../../CRM-Avance-Corp/supabase/scripts/f6/REVISION-MANUAL-2026-09-10.md).
Continúa [[F6 - publicada y apagada (2026-09-10)]]. Gobierna
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

F7 (métricas), F8 (piloto) y F9 (activación y ciclo mensual) siguen pendientes.
Antes del encendido permanecen 15 fuentes con identidad sin resolver.
Las comisiones se calculan fuera del sistema.

Gate final `npm run check:all` PASS: 3.188 tests y 159 E2E; 26 E2E omitidas.
VoiceOver: NOT RUN como lectura efectiva; su estado final quedó apagado.

Arreglos de foco y mensajes: commit local `d586b66`. Selector de archivos: `513effa`.

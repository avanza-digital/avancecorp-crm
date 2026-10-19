---
tags: [crm, leads, conversion, capacitacion]
fecha: 2026-10-18
estado: validado localmente; NO instalado ni activado en producción
---

# Recorrido por asistencia y entrevista

Miguel definió la condición obligatoria de la primera conversión: el analista debe registrar que la persona asistió a su cita y tuvo una entrevista comercial con resultado. Ambos hechos deben corresponder a la misma cita del ciclo vigente. Gestión y contacto orientan al analista, pero no agregan una condición de bloqueo independiente.

Mover de etapa o agendar una cita no acredita asistencia. Reasignar conserva el ciclo y los hechos; reabrir un descartado inicia otro ciclo. Una visita sin cita crea la cita inmediata y registra asistencia/entrevista atómicamente, con el formulario y el motor de próxima acción existentes. No se permite fecha retrospectiva. La asistencia es una declaración del analista: el servidor comprueba registro, relaciones y ciclo, no presencia física.

La evaluación vive en el CRM y se vuelve a comprobar en las puertas de identidad/acceso/confirmación y en sus guardas de datos. Los reintentos conservan recibos y borradores; un borrador que pierde evidencia puede recuperarse, pero una primera conversión exigible no se confirma hasta corregirla. Las inversiones adicionales, renovaciones y upgrades mantienen el flujo de cliente actual.

Instalación inicial en observación. El corte de una activación futura es inmutable: ciclos anteriores no quedan retrobloqueados; una reapertura posterior sí pertenece al nuevo corte. La política histórica es propuesta, todavía sin autorización comercial para activar. No se inventa evidencia ni se aplica un backfill de asistencia. No hace falta n8n.

El Goal incluye PR/Main y ZIP, **sin publicación ni migración productiva**. Se verificó en un banco Supabase local y copias desechables: SQL/RLS, concurrencia, 79 comprobaciones Auth/PostgREST reales, seis E2E nuevos y regresión Docker. Los límites y gates hosted previos a una publicación futura están en el informe técnico.

- [Plan con barras, fases y subfases en FigJam](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=46-190).
- [Estado y evidencia](../../CRM-Avance-Corp/docs/plans/recorrido-lead-hechos/ESTADO.md).
- [Instalación, cohortes, activación y reversión](../../CRM-Avance-Corp/docs/plans/recorrido-lead-hechos/INSTALACION-Y-ACTIVACION.md).
- [Material para capacitar](../../CRM-Avance-Corp/docs/plans/recorrido-lead-hechos/CAPACITACION.md).

Relacionado: [[Conversion de lead con Nueva inversion - preparado 2026-09-19]] · [[Conversion - cliente antiguo usa su misma ficha y No insistir (2026-10-12)]] · [[Inicio]].

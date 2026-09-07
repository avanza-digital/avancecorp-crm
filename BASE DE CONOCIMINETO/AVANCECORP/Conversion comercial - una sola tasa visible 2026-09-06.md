# Conversión comercial: una sola tasa visible

Fecha: 2026-09-06

## Decisión

En **Gerencia → Conversiones**, la cifra principal responde una sola pregunta comercial: qué porcentaje de los prospectos recibidos en el período se convirtió.

- Fuente: `metricas_conversiones_fn → cohorte.conversion_contratos_pct`.
- Lectura visible: `prospectos convertidos / prospectos recibidos`.
- Ejemplo validado: 6 de 313 prospectos = 1.9%.
- El índice ponderado de 3.02% no se muestra en Conversiones. Se conserva en **Metas**, bajo el nombre **Índice para la meta mensual**, donde se compara con el objetivo de 15%.
- El encabezado ya no muestra la meta mensual ni una segunda tasa.

El cambio es únicamente de presentación en frontend. No modifica RPC, contratos, fórmulas ni el núcleo de conversión.

## Relación

- [[Conversion por analista - separar cohorte e indice mensual 2026-09-06]]
- [[Auditoria conversion CRM - nucleo unico (handoff 2026-08-26)]]

## Estado

Publicado y verificado en producción.

- Commit fuente: `97dbc1176ce69690fd400a84f9349583b337cfad`.
- Release: `crm-20260907T010701Z-97dbc1176ce6`.
- Build: `build-20260907T010617899Z`.
- SHA-256 del ZIP: `82b5a94d4eda11bbf3a2b4de8f0a87c7b6a657ec1610a882fd3a7790cec2c5c7`.
- Validación: 97 pruebas enfocadas y 2,845 pruebas del checkout limpio; el pre-push aprobó 2,877 pruebas del árbol de trabajo integrado. También aprobaron tipos, lint, configuración pública, build y guardas del bundle.
- Producción: 79 de 79 comprobaciones remotas correctas y tres lecturas estables de versión.
- Revisión visual autenticada: Conversiones muestra 1.9%, 6 de 313 prospectos, 313 recibidos y 6 convertidos; no muestra 3.02% ni 15% en el encabezado. Metas muestra `Índice para la meta mensual · 3.02% de 15%`.
- Rollback frontend conservado: `crm-20260907T004240Z-ff599df5ddcd`.

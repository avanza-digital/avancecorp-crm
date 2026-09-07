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

- Commit fuente final: `f9e1d1df7fbd482ad7e69129325593b98799c61b` (incluye la implementación `97dbc1176ce69690fd400a84f9349583b337cfad`).
- Release: `crm-20260907T011933Z-f9e1d1df7fbd`.
- Build: `build-20260907T011919854Z`.
- SHA-256 del ZIP: `ef49d25dcd5ecbb1cecf7049cea7f00a72ba0e3f0903f6a3da6c7b38fd0a7247`.
- Validación: 97 pruebas enfocadas para la implementación, 95 para la revisión final y 2,845 pruebas del checkout limpio; el pre-push aprobó 2,877 pruebas del árbol de trabajo integrado. También aprobaron tipos, lint, configuración pública, build y guardas del bundle.
- Producción: 79 de 79 comprobaciones remotas correctas y tres lecturas estables de versión.
- Revisión visual autenticada: Conversiones muestra 1.9%, 6 de 313 prospectos, 313 recibidos y 6 convertidos; no muestra 3.02% ni 15% en el encabezado. La cabecera explica que el origen filtra esa conversión. Metas muestra `Índice para la meta mensual · 3.02% de 15%`.
- Rollback frontend inmediato conservado: `crm-20260907T010701Z-97dbc1176ce6`. El release anterior a esta tarea también permanece disponible: `crm-20260907T004240Z-ff599df5ddcd`.

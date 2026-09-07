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

Implementado y validado localmente. Publicación pendiente.

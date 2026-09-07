# Conversión por analista: separar cohorte e índice mensual

Estado: publicado y verificado en producción.

## Decisión

La cifra principal del detalle de un analista muestra la conversión de sus prospectos:

- numerador: prospectos de su cohorte que ya cerraron;
- divisor: prospectos del período atribuidos al primer analista;
- fuente: `responsables[].conversion_pct`, servida por `crm.metricas_conversiones_fn`.

El índice mensual ponderado se conserva únicamente en el bloque de metas bajo el rótulo **Índice para la meta mensual**. No se presenta como la conversión de los prospectos del analista.

Ejemplo que motivó la corrección: 2 prospectos convertidos de 23 muestran 8.70%. El 14.29% de 3 cierres acreditados sobre una base automática de 21 pertenece al índice mensual ponderado y responde otra pregunta.

La corrección reutiliza los datos ya servidos. No agrega cálculos, funciones independientes ni cambios en los núcleos o contratos del servidor.

## Publicación

- Commit fuente: `ff599df5ddcdf9844c65de0ee6bc80f456c2103e`.
- Release: `crm-20260907T004240Z-ff599df5ddcd`.
- Build: `build-20260907T004227618Z`.
- SHA-256 del ZIP: `689f69c248831290adf34ba3b2f34fc77a083be37af284d49f75d93b7b75370b`.
- Reversa inmediata: `crm-20260907T001658Z-1a176cc32d75`.
- Verificación pública: 79 de 79 archivos correctos y tres lecturas consecutivas de `version.json` consistentes.
- Verificación visual real: ASTRID CENTENARO muestra `8.70%`, `2 de 23 prospectos cerraron`; el `14.29%` aparece únicamente como **Índice para la meta mensual**.
- El endpoint de purga de Hostinger devolvió una ruta inválida. No afectó la publicación: `version.json` se sirve con `no-store` y todos los archivos públicos coincidieron con el artefacto.

Pruebas: 43 pruebas focalizadas y 2,877 pruebas completas; tipado, lint, build productivo, configuración de release y guardia del bundle aprobados.

## Relacionado

- [[Inventario de indicadores de Gerencia - Comercial]]
- [[Conversion mensual - plan de implementacion]]
- [[Terminologia comercial - prospectos recibidos 2026-09-06]]

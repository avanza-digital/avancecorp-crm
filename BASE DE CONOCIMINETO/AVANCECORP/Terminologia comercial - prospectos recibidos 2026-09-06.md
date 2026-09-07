---
fecha: 2026-09-06
estado: publicado-verificado
tags: [crm, gerencia, conversiones, ux, terminologia]
---

# Terminología comercial — prospectos recibidos

Miguel indicó que «llegadas» no es un término comercial claro y aprobó sustituirlo en la interfaz del CRM.

Vocabulario visible acordado:

- «Llegadas únicas» → «Prospectos recibidos».
- «Llegadas del rango» → «Prospectos del período».
- «Semana de llegada» → «Semana de ingreso».

La actualización cubre indicadores, gráficos, descripciones, fórmulas visibles y textos accesibles de Gerencia. Los nombres internos del contrato (`llegada_unica`, `llegadas`, `LLEGADAS_UNICAS_PRIMER_ANALISTA` y campos relacionados) se conservan para no modificar cálculos, consultas ni compatibilidad con las RPC.

## Publicación verificada

Miguel autorizó publicar el cambio. Se desplegó únicamente el frontend del CRM en `https://crm.miavance.com`, desde un checkout limpio del commit `1a176cc32d75a53d3f053c4be2f51f258ddf86a4`; la modificación de vocabulario corresponde al commit `640dd8d6d3080b524414cf93cb5c3c4667ed4768`. Antes de construir se comprobó que Main local y `avancecorp/main` coincidían. Los demás cambios sin commit del directorio compartido no entraron al artefacto.

- Release: `crm-20260907T001658Z-1a176cc32d75`.
- Build activo: `build-20260907T001657426Z`.
- SHA-256 del ZIP: `27a42e00d8ddd3e07b7fc41f1bdf2ede69ec7a087a421dd687c81b7ec254e6b5`.
- Rollback conservado: `crm-20260906T234219Z-85d5bc76802d.zip`.

Validación: 230 pruebas relacionadas y las 2845 pruebas unitarias completas aprobadas; cinco pruebas de navegador de gráficos aprobadas; lint, TypeScript, cuatro pruebas de configuración de release, build y controles del paquete productivo aprobados. Tras desplegar y limpiar la caché, pasaron las 79 comprobaciones públicas y tres lecturas consecutivas de `version.json`.

Se verificó visualmente con la sesión real de Gerencia que Conversiones muestra «313 prospectos recibidos», «Prospectos con cita realizada», «Prospectos del período» y «Resultados por semana de ingreso». No se modificaron las métricas ni los datos; esta publicación no ejecutó cambios de base de datos ni alteró el portal.

Relacionadas: [[Conversiones - retiro de bloques explicativos 2026-09-06]], [[Inventario de indicadores de Gerencia - Comercial]], [[Decisiones UI UX Gerencia - 2026-09-06]].

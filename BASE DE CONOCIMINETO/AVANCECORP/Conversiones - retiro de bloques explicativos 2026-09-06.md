---
fecha: 2026-09-06
estado: publicado-verificado
tags: [crm, gerencia, conversiones, ux, decision]
---

# Conversiones — retiro de bloques explicativos

Miguel señaló que los bloques «Llegadas con cita realizada» y «Operaciones elegidas para conversión» de la captura no le resultan claros ni aportan valor comercial. Después de considerar gráficos y un detalle opcional, pidió eliminarlos.

Se retiraron ambos paneles de `inteligencia-comercial.tsx`, incluida la tabla de identificadores de operaciones. No se sustituyen por gráficos ni por otra sección. Se conserva el indicador compacto de citas ya existente, el detalle del analista y los cierres por semana.

El cambio es de presentación: se mantienen las consultas, los datos, las reglas de conversión, los pesos de renovaciones/upgrades y los otros consumidores del contrato. Las 43 pruebas de la pantalla, TypeScript y lint pasan.

## Publicación verificada

Miguel autorizó publicar. Se desplegó únicamente el CRM en `https://crm.miavance.com`, desde un checkout limpio del commit `85d5bc76802dcbc7c3e62a5de41d1bb14bcfd054`. Antes de construir se comprobó que ese commit coincidía con Main local y `avancecorp/main`, incluidos los cambios remotos. Los cambios de otros trabajos sin commit quedaron fuera del artefacto.

- Release: `crm-20260906T234219Z-85d5bc76802d`.
- Build en producción: `build-20260906T234219102Z`.
- SHA-256 del ZIP: `7f8e191e04528eace260d4c3ef6296c3b166686dac14fc46d89584fa97ab3628`.
- Artefacto, manifiesto y verificación pública conservados en `CRM-Avance-Corp/releases/`, fuera de la raíz pública.
- Rollback conservado: `crm-20260906T213102Z-7438e995f90d.zip`.

Validación: 2845 pruebas unitarias aprobadas; suite E2E completa con 121 aprobadas, 26 omitidas y cero fallos; cuatro pruebas de configuración de release; lint, TypeScript, build y verificaciones del paquete productivo aprobados. La ejecución detectó y corrigió una simulación E2E antigua de edición de teléfono: ahora simula la RPC que ya usa la aplicación. Ese arreglo afecta sólo las pruebas.

Tras publicar y limpiar la caché de Hostinger, pasaron las 79 comprobaciones públicas del artefacto y tres lecturas consecutivas de `version.json`. Se verificó visualmente Conversiones con la sesión real de Gerencia: desaparecieron ambos paneles, se conservan el porcentaje principal (3,02 % al comprobarlo), los cierres por semana y el indicador compacto de citas. El ZIP no está expuesto en CRM ni en el portal. No se modificaron datos, base de datos ni el portal.

Relacionadas: [[Deploy a Hostinger]], [[Decisiones UI UX Gerencia - 2026-09-06]], [[Contrato tecnico de ampliaciones N1-N4 de Gerencia - 2026-09-05]], [[Inventario de reutilizacion frontend - F0 UI UX 2 2026-09-06]].

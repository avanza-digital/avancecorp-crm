---
tags: [crm, configuracion, usuarios, productos, metas, sla]
actualizado: 2026-08-07
---

# Configuración operativa CRM 2026-08-07

Relacionado con [[Continuidad CRM 2026-08-06]] y
[[Meta de conversion predeterminada]].

## Decisiones duraderas

- Gerencia administra personas, activación, jerarquía, Productos, Metas y SLA.
- Solo Superadmin Portal asigna o cambia `rol_crm`. Sin una membresía efectiva
  de Gerencia, Superadmin queda limitado al directorio mínimo de Usuarios.
- Directorio real consulta Configuración en solo lectura.
- La autorización usa rol y estado vivos; nunca correo ni credenciales.
- Metas separa PEN/USD y declara fuentes distintas: contratos confirmados para
  capital/contratos, leads resueltos para conversión.
- El SLA es versionado por ciclo, asignación y etapa; Distribución ya no publica
  el umbral fijo de 24 horas como si fuera configuración vigente.
- Los contratos conservan snapshot legal y referencia a una condición de
  producto versionada; una publicación nueva no reescribe historia.

## Estado local

Las migraciones locales `20260807203740`, `20260807203751` y
`20260807203757`, las Edge Functions y las cuatro pantallas están implementadas
y pasaron replay limpio, cinco oráculos SQL, 1,403 pruebas unitarias, 73 E2E,
typecheck, lint, build y advisors sin hallazgos nuevos atribuibles. No se aplicó
ni desplegó nada en producción.

El detalle técnico y la evidencia viven en
[`docs/plans/2026-08-07-configuracion-operativa.md`](../../docs/plans/2026-08-07-configuracion-operativa.md).

## Gate pendiente

El repo hermano `public_html` todavía consume altas de contratos legacy. Hasta
migrar y desplegar esos callers no debe ejecutarse
`crm.cerrar_altas_legacy_productos(...)`; el bridge permanece abierto de forma
consciente y el cierre integral no se declara terminado.

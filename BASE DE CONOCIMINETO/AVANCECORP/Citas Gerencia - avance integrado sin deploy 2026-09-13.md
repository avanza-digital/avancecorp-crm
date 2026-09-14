---
fecha: 2026-09-13
estado: preparado-sin-deploy-con-pendientes
tags: [crm, citas, gerencia, metas, superadmin, release]
---

# Citas Gerencia — avance integrado sin deploy

Miguel aprobó la presentación y pidió preparar el deploy, **sin ejecutarlo**.
La propuesta de [[Citas Gerencia - reglas confirmadas y propuesta revisada 2026-09-13]]
ya está integrada al módulo real en local y a un banco propio. No se instaló ni
publicó este alcance en producción.

## Cambios implementados

Avance mensual por analista y recuperación horizontal, con componentes del CRM,
filtros compactos y detalle a demanda. Etiqueta «Entrevistas» y colores según el
resultado aprobados. Bandeja y Agenda permanecen disponibles.

La configuración inicial usa meta interna 1,25, objetivos 70/70, manuales
incluidos y una entrevista por cita atendida. Superadmin puede guardar borradores
y aplicar explícitamente una versión con vigencia e historial. No se reescriben
meses anteriores ni sellados. Un conflicto entre sesiones conserva la edición y
devuelve HTTP 409; guardar no aplica.

Las fuentes son el ledger de asignaciones, el núcleo de citas, la actividad real
de entrevista, la conversión nativa a perfil cliente y el núcleo de capital.
El ticket mensual enlaza contratos con el perfil cliente: `leads.contrato_id`
no se completa en el flujo actual y no sirve para recuperar ese importe.
Contratos nuevos del mismo cliente se suman; cada perfil cuenta una vez.
Se separan monedas y se muestran incidencias si falta capital o no concuerda
el analista. El dinero del lead estimado nunca sustituye capital confirmado.

Semana y filtros operativos afectan el seguimiento; las métricas mensuales
conservan su base. La proyección usa ritmo real, entrevistas y conversión
observadas, repetición de visitas y ticket; citas previstas para otro mes no
aceleran el cierre del mes actual.

## Pendientes que no deben suponerse aprobados

Siguen sin respuesta las tres preguntas enviadas durante esta preparación:
base del 70% de clientes (entrevistas o personas únicas), atribución de mes
(evento o primera asignación) y atribución de analista (evento u origen).
Ambas opciones están implementadas. Las claves correspondientes y el mes de
vigencia permanecen nulos hasta una decisión y aplicación explícita.
No se pidió otra vez confirmar 1,25, 70/70 ni manuales: esas reglas sí están claras.

La base inicial del avance de entrevistas es entrevistas / citas con resultado
(entrevista o no-show), identificada en la ayuda y configurable. Sin reglas
completas no se publican tasas dependientes ni proyección como definitivas.

## Evidencia y estado de cierre

`UX-UI-GERENCIA/citas-preparacion-2026-09-13/README.md` contiene inventario,
capturas del runtime, fórmulas, SQL, revisión independiente, preflight y reversión.

- Frontend final: 3.512 pruebas, lint, typecheck, cobertura y build PASS.
- E2E global: 178 PASS, 26 SKIP y una expectativa histórica antigua fallida.
  Se corrigió y se repitieron los 14 E2E de Citas, Superadmin y Gráficas: PASS.
- SQL mensual completo, configuración local y 48 comprobaciones Auth/HTTP: PASS.
- Revisión independiente: correcciones atendidas y PASS focalizado final.
- RLS general: **55/1.828 FAIL**. Coinciden los nombres normalizados con los 55
  de la corrida anterior; no es un A/B ni autoriza afirmar cero regresiones.
- Preflight productivo de solo lectura PASS: 279 migraciones, lector anterior
  conservado y configuración nueva ausente. SQL nuevo, deploy y smoke nuevo:
  **NOT RUN por instrucción de Miguel**.

El banco de pruebas es exclusivamente `citas-validacion-20260912`.
Los perfiles sintéticos quedaron inactivos y bloqueados; la aplicación de prueba
usa enero de 2099 y no afecta al mes actual. No se enviaron correos.

Antes de publicar: resolver las decisiones, diagnosticar el gate general,
confirmar SQL exacto y vigencia, integrar Main con `avancecorp/main` sin perder
Leads ni trabajos ajenos y construir el artefacto desde el mismo commit limpio.

Relacionado: [[Citas Gerencia - preparacion verificada 2026-09-13]],
[[Citas Gerencia - control de Superadmin en borrador 2026-09-11]],
[[Citas Gerencia - avance y proyeccion mensual por analista 2026-09-11]],
[[Fundamentos UX del CRM]], [[Main unico - sincronizacion y publicacion 2026-09-04]].

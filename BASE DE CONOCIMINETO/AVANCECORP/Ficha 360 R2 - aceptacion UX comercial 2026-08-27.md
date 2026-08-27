---
tipo: decision-ux
estado: candidata-estatica-captura-fresca-pendiente
fecha: 2026-08-27
serial: AVC-F41-360-20260825-R2
sha_evidencia: e6129674844ecca12b224690f43bedb436b06006
---

# Ficha 360 R2 — aceptación UX/comercial 2026-08-27

Relacionado: [[Ficha comercial 360 de clientes - plan]],
[[Ficha 360 - plan de reintegracion sobre nucleo unico (2026-08-27)]],
[[Rol Directorio]] y [[Fundamentos UX del CRM]].

## Decisión vigente

El `HEAD e6129674844ecca12b224690f43bedb436b06006` tiene GO
técnico-estático, pero la aceptación visual vigente está pendiente de una
captura fresca. Se corrigieron dos huecos de la reauditoría: el estado mensual
vacío ahora habla según Vendedor, equipo o empresa; y un cliente inactivo se
puede consultar sin conservar enlaces de llamada, WhatsApp o correo.

## Decisión histórica

Se acepta R2 como referencia UX/comercial para jerarquía, contenido, lenguaje,
flujo visible, móvil, foco, accesibilidad y diferencias por rol. La evidencia
estaba fijada en `49c9dc3b0502c5d483f956dbbaa624f042ee9d76`, dentro de
`artifacts/audits/ficha360-r2-20260827/README.md` y sus capturas antes/después.

Esta decisión **no** acepta el backend R2, sus migraciones, RLS, tipos, rama
completa ni producción. Tampoco autoriza despliegue.

## Requisitos que debe conservar la reintegración

- La ficha parte de continuidad comercial: capital vigente, próximo
  vencimiento y siguiente contacto; después inversiones, identidad, historial
  y banca según permiso.
- “Demo/Vista demo” y el alcance de la preview permanecen visibles antes de
  usar acciones.
- Vendedor lee “Mi cartera/Tus clientes”; Supervisor, su equipo; Gerencia y
  Directorio, la empresa.
- Directorio es auditoría de solo lectura: puede consultar ficha y contrato,
  pero no recibe enlaces de contacto, banca ni mutaciones.
- Vendedor/Supervisor/Gerencia pueden ver el flujo de nueva inversión; Agendar,
  Corregir, Aumentar y Renovar se rotulan como no validados mientras no exista
  una candidata integrada.
- `elegible_conversion` nunca se presenta como atribución final. La Ficha
  registra hechos; el [[Conversion mensual - definicion cerrada|núcleo mensual]]
  deduplica y atribuye.
- Navegación off-canvas hasta 767 px y también en teléfono horizontal
  hasta 950×500; tarjetas de 768 a 1199; tabla desde 1200.
- El menú cerrado sale del árbol accesible; abierto confina el foco. Navegar
  lleva el foco al título.
- Cerrar ficha restaura el disparador externo. Volver de una acción reemplazada
  restaura primero la sección/contrato lógico sin perder ese disparador para el
  cierre posterior.
- Nombres largos admiten dos líneas y los resúmenes no dependen de elipsis para
  comunicar su significado.

## Alcance expresamente no aceptado

- Éxito/error/cancelación reales de Agendar, Corregir, Aumentar y Renovar.
- Historial/tareas poblados, contratos vencidos, estados inactivos y matrices
  múltiples que el dataset demo no representa.
- RLS, banca, PDF, writers, carreras y datos reales.
- Contraste automatizado y aceptación autenticada por cada rol.

Estos casos son gates de la candidata nueva; no se heredan como supuestos del
prototipo.

## Verificación de la referencia

- Snapshot vigente R2: 176 archivos y 2372/2372 pruebas, typecheck, lint, build,
  bundle y duplicación verdes; remediación focal 142/142 y reauditoría del diff
  con GO material en `910bbd7`.
- La pasada visual anterior conserva sus capturas y resultados históricos como
  referencia comercial.
- No se ejecutó una nueva pasada Browser/Playwright sobre `e612967`. Por eso la
  comprobación visual autenticada por rol sigue siendo un gate de la candidata
  nueva y no una certificación de producción de R2.

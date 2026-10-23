---
tags: [auditoria, base-de-datos, integridad, crm, fase-0]
fecha: 2026-10-23
estado: preparacion verificada, decisiones pendientes
---

# Base de datos - fase 0 verificada y listas para decidir (2026-10-23)

Miguel autorizó sincronizar los commits de auditoría/plan y preparar las listas de
fase 0. Las consultas del 23/10, 10:57–10:59 Lima, fueron de solo lectura.
No se aplicaron cambios de datos, esquema, permisos ni publicación del CRM.

## Correcciones a la interpretación del 22/10

- Las **45 fuentes de contrato sin inversión** se dividen en **41 contratos
  existentes** (39 de septiembre acreditados e incluidos en el sello; 1 de marzo y
  1 de mayo fuera de plazo) y **4 fuentes de octubre eliminadas**. No cargar las 45
  como si fueran contratos activos.
- Los **dos leads sin acreditación** no son dos ventas inexistentes: uno ya tiene
  contrato activo e inversión vigente; el otro tiene perfil con nombre DEMO y no
  tiene contrato, inversión ni cierre externo. La clasificación como prueba queda
  pendiente de Miguel. No crear otra inversión para el primero.
- Los **11 contratos sin copia en la auditoría CRM sí tienen evento DELETE en la
  bitácora del portal**, con fecha y cuenta autora. Sus 12 filas del ledger se
  conservan. No se conoce el motivo comercial solo por ese evento.
- Se confirman **6 referencias de leads a contratos eliminados**, todas con copia
  CRM; cinco tienen algún contrato actual del mismo perfil y una no. Eso no prueba
  por sí solo que un contrato sea su reemplazo.
- SELECT de tabla para authenticated sigue efectivo en crm.leads, con lectura de
  DNI, fecha de nacimiento y género, sujeto al alcance por filas. Falta decidir
  roles y ámbito; no se ensayaron sesiones de cada rol.

La función viva private.conversion_sincronizar_lead requiere un vínculo explícito:
solicitud confirmada con primera conversión, contrato enlazado en el lead o cierre
externo inicial. No basta un contrato que comparta perfil. Su definición se leyó;
no se invocó para corregir datos.

## Entrega y decisiones

Detalle técnico y consultas reproducibles:
`CRM-Avance-Corp/docs/plans/base-de-datos-candados-2026-10-23/FASE-0.md`.

Listas nominales locales, fuera de Git:
`CRM-Avance-Corp/output/fase-0-candados-2026-10-23/LISTAS-PARA-MIGUEL.html`
y `evidencia.json`.

Miguel debe definir: incorporación a cartera de las 39 ventas de septiembre
(tratamiento separado de las 2 antiguas), atribución del caso con inversión,
clasificación del caso DEMO y roles que ven datos personales. El SQL de cada
corrección se preparará y probará antes de presentar su aplicación concreta.
La fase 0 no se declara cerrada por haber preparado las listas.

Relacionado: [[Auditoria de tablas - reglas basicas de Postgres en crm y private (2026-10-22)]]
· [[Reemplazar inversion - plan por fases (2026-10-17)]].

## Contraste adicional (11:12–11:13 Lima)

- De los 39 titulares de septiembre, 36 no tienen otras inversiones y 3 sí:
  una renovación, un upgrade y dos operaciones en Qorilazo. No prueba duplicidad;
  revisar esos tres casos antes de diseñar el lote. Las 41 fuentes existentes no
  tienen solicitudes por lead ni eliminaciones por fuente en las tablas consultadas.
- Los dos criterios (fecha del lead / resultado del episodio) dan los mismos 2 casos.
- Los 11 DELETE son del 07/09 al 14/09, anteriores a la instalación de la copia CRM
  del 15/09 a las 21:44 Lima (registro remoto 20260916024417, complemento 20260916024423).
- RLS activa, gate de actor RESTRICTIVE y selección de filas PERMISSIVE; anon sin
  USAGE ni SELECT. Exposición efectiva de esquemas por API y sesiones por rol no verificadas.
- La revisión secundaria pidió ampliar estos contrastes y se atendió con consultas
  reales. No se convirtió el dictamen CHANGES_REQUESTED en un PASS sin nueva revisión.

---
tags: [crm, formulario-3, origenes, coordinacion]
actualizado: 2026-10-15
---

# Formulario 3 — origen nativo preparado

**Implementado y probado en local; no aplicado ni publicado en producción.**
Miguel pidió que Formulario 3 fuera un origen real de backend, conectado como los
demás, y autorizó cambiar Repartir para que soporte más orígenes.

## Decisión de negocio

`formulario_3` vive en la misma tabla y columna `crm.leads.origen`, con las mismas
puertas de alta/importación, permisos, bandejas, analistas, tareas, inversión y
conversión. Conserva su identidad en ficha, filtros, agenda, reportes y ranking.
Comparte el turno operativo de Formulario y sus reglas de conversión; no se crea
un tercer turno. La ficha muestra una sola identificación «Formulario 3».

Repartir conserva dos turnos y presenta entregas en una tabla por origen y
supervisora, con filtros y cola paginada. Añadir un origen ya no requiere otro
panel de campaña. Recargas no descartan borradores ni pisan un reparto en curso.

## Datos que se preservan

No repetir la corrección de Excel: 76 responsables del archivo y un caso en la
bandeja de Carmen según decisión posterior de Miguel; 39 ajenos a los Excel
intactos. Conservar descartados, No contactar, historial y tareas.
Véase [[Formulario 3 - reparto corregido segun Excel (2026-10-15)]].

Producción se consultó solo en lectura. Se constató que uno de los 116 legados ya
se había convertido en cliente el 15/10, con contrato y acreditación abierta.
La migración se amplió para conservar íntegra esa inversión y cambiar únicamente
los orígenes de lead/acreditación, sin reconstruir la venta ni recalcular sus relojes.
Las pruebas usan datos ficticios; no se modificó ese cliente real.

n8n `BjI5m1PKVWhO0NDb` sigue activo cada cinco minutos. Mantiene el payload
FORMULARIO + campaña exacta, sus huellas y recibos; el servidor traduce al origen
nuevo después de activar B. No es necesario reconectar credenciales.

## Instalación y validación

Migraciones: A `20261015171407`, B `20261015173031`. A prepara compatibilidad;
después se publica frontend/Edge, el equipo termina borradores y renueva sus
pestañas; finalmente B activa y reclasifica. Durante A, las altas manuales F3
esperan la activación y la importación sigue en formato compatible.

Pruebas SQL: A/B y ROLLBACK, permisos/roles, filtros, dos turnos, reintentos,
conversión manual/automática y legado, convertido antes de B, foto sellada intacta,
rechazos por inconsistencia, escritor n8n concurrente y bloqueos financieros.
Claude revisó arquitectura e implementación; los agentes propios revisaron
consistencia y concurrencia. Se incorporaron correcciones y se ejecutaron pruebas.

El cierre local se registra en `supabase/scripts/formulario3-origen/LEEME.md` y
`REVISION.md`; el ledger conserva el estado **no aplicado**. Pendientes: rama
Supabase temporal autorizada, matriz RLS HTTP/advisors y publicación con invocación
humana de release. No afirmar que el origen productivo ya es nativo.

Figma: [plan de Formulario 3](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34).
Relacionado: [[Formulario 3 - fase 6 carga y activación (2026-10-15)]] ·
[[Formulario 3 - plan de integración en CRM y activación (2026-10-14)]].

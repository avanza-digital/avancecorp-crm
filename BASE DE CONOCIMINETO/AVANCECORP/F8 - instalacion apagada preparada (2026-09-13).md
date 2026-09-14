---
tags: [crm, cartera, multiempresa, f8, instalacion]
actualizado: 2026-09-13
---

# F8 — instalación apagada preparada

Continuación de [[F8 - exclusion demo preparada (2026-09-13)]] y
[[F8 - enlaces reales aplicados (2026-09-13)]]. El paquete de instalación combina
el control F8 ya ensayado y la exclusión demo. Ambas migraciones conservan sus
bytes; no se aplica de nuevo el lote de identidades reales.

Estado: **paquete para aprobación del SQL; instalación y piloto todavía OFF**.
No se creó una rama nueva, no se modificaron datos ni se publicó en esta
preparación. La consulta administrativa se ejecutó en una transacción de solo
lectura y terminó con rollback.

Lectura productiva revisada del 13/09 a las 23:25 Lima:

- 593 movimientos reales, cero brechas de identidad.
- Cinco fuentes demo, cuatro brechas exclusivamente demo.
- F3 ON; F4/F5/F6/F7 OFF. Control y miembros F8 ausentes.
- Las 14 definiciones, ACL y propietarios previos coinciden con lo esperado.
- Inventario de 15 categorías, incluidos permisos por defecto y protecciones.
- 279 migraciones en el padre; última `20260913213842`.

El procedimiento propuesto recupera el método ya usado en F5: copiar solo la
estructura vigente en una rama exclusiva, demostrar paridad de esquema y
permisos, y entonces registrar allí el historial exacto del padre. Mantiene las
FK hacia Auth y Storage, todas las Edge y el historial productivo. No reutiliza
la antigua rama F8 ni sus excepciones. **Falta probar esta reconstrucción para
el paquete actual**; el documento no declara una rama mergeable.

Paquete revisable:
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/INSTALACION-2026-09-13.md`.
Consulta conjunta reproducible: `verificar-base-instalacion.mjs --consulta` en
esa carpeta. El verificador rechaza capturas de más de 60 segundos, cambios de
esquema/permisos/historial, instalación parcial y brechas reales. Acepta ventas
nuevas coherentes. Pasó 24 pruebas offline y ocho pruebas SQL de catálogo;
cada mutación del ensayo termina con rollback. No autoriza un merge por sí solo.
También se prepararon comparación automática padre/rama y detalle de objetos;
la nueva rama real sigue sin crearse. La lectura viva de las 23:39, comprobada
a las 23:40 Lima, volvió a pasar las precondiciones del padre.
El acta G7
ahora distingue los diez enlaces reales resueltos de la exclusión demo pendiente
y de las pruebas remotas nuevas, que siguen NOT RUN.

Próximos pasos: aprobar el SQL exacto; ensayo en rama con paridad y matriz de
permisos; instalar apagado desde Main verificado; elegir Gerencia, supervisor y
dos vendedores; revisar su configuración/ventana y autorizar el encendido.
Los casos reales y firmas G7 siguen pendientes. Las pruebas locales aprobadas
y la conformidad G6 no reemplazan el piloto.

Plan: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

---
tags: [crm, ux, supervisor, leads, derivaciones, paginacion]
actualizado: 2026-08-24
estado: desplegado-produccion
---

# Derivar leads del supervisor - paginacion compacta

La bandeja **Derivar hoy** del módulo **Derivar leads** no debe crecer con todos
los leads asignados al supervisor. Esa lista larga convertía la pantalla en un
desplazamiento vertical aparentemente infinito.

## Comportamiento acordado

- Se muestran cinco leads por página, con navegación Anterior/Siguiente.
- La selección de asesor se conserva al cambiar de página.
- El resumen y el botón de guardado consideran el borrador completo, incluidas
  las selecciones que estén en otras páginas.
- Si la cantidad de leads disminuye, la página se ajusta a un rango válido y no
  queda una bandeja vacía por apuntar a una página que ya no existe.
- No se agrega un segundo contenedor con scroll interno.

## Cobertura

La prueba de `screens/derivaciones.test.tsx` verifica el límite de cinco filas,
la navegación a la segunda página y la persistencia del borrador al regresar.

## Despliegue

Publicado en `crm.miavance.com` el 2026-08-24 mediante el release
`crm-20260824T151110Z-d4a5416a5c0f`, construido desde el release vivo `b4060c7`
para no incorporar el trabajo paralelo del árbol compartido. En el smoke real,
la bandeja de 66 leads quedó dividida en 14 páginas; las páginas 1 y 2 mostraron
cinco filas y la navegación no produjo errores de consola.

### Regresión y restauración del mismo día

Un release paralelo posterior (`crm-20260824T155903Z-1dd89bffa9f2`) volvió a
publicar una base que no descendía de `d4a5416`, por lo que la paginación dejó de
existir realmente en el módulo vivo; no era caché ni una condición del usuario.
La restauración combinada `crm-20260824T175707Z-f924b91ad677` integra la
paginación, el teléfono alternativo, F4.3 del supervisor y la nueva portada del
vendedor. Quedó publicada aproximadamente a las 13:00 (hora de Lima), con
58/58 archivos no transformados idénticos al manifiesto; el chunk vivo contiene
`Paginación de leads por derivar hoy`. Los controles se ocultan correctamente
cuando hay cinco leads o menos y aparecen desde el sexto.

Relacionado: [[Hoy del supervisor - reparto compacto]] ·
[[Distribución de leads por capital y trazabilidad CRM]] ·
[[Acceso y roles del CRM]].

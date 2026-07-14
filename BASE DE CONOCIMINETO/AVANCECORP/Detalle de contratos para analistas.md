---
tags: [feature, negocio, contratos, analista, portal]
actualizado: 2026-07-14
---

# Detalle de contratos para analistas (solo lectura)

**Qué es (2026-07-14):** en el panel del analista (`/admin/analista.html`), cada contrato de "Mis contratos" tiene ahora un botón **"Ver detalle"** que abre una ficha de **solo lectura** con los términos del contrato + el **cronograma de cuotas** completo (el mismo timeline que ve el cliente en su portal).

## Por qué se hizo

El analista solo tenía el botón **"Corregir"**, que se **bloquea a las 5 horas** de creado el contrato (ventana de corrección). Pasada esa ventana no tenía **ninguna** forma de consultar el contrato ni su cronograma. "Ver detalle" llena ese hueco: es **solo lectura y siempre está disponible** (no depende de la ventana de 5 h).

## Qué ve el analista

- **Términos del contrato:** cliente, capital, moneda, tasa anual, tipo de interés, modalidad, fechas de inicio/vencimiento, estado, categoría y notas internas.
- **Cronograma de cuotas:** cada cuota con su estado (pagada ✓ / próxima / pendiente / vencida / trasladada), fechas y montos, más el resumen pagado / por pagar / progreso.

Solo puede ver los contratos de **su cartera** (clientes que tiene asignados como asesor, o sin asesor y creados por él). Es lo mismo que ya gobierna el resto de su pantalla.

## Cómo funciona (para no romperlo)

- **No cambió nada en la base de datos.** El permiso de lectura ya existía: las reglas de seguridad (RLS) del portal ya dejaban al analista leer los contratos de su cartera y su cronograma. Esto fue **solo pantalla** (frontend). Ver [[Acceso y roles del CRM]].
- Reutiliza el componente compartido del **cronograma** (el mismo del portal del cliente), así que si se cambia el diseño del timeline, cambia en ambos lados a la vez. Ver [[Ciclo de vida de contratos]] (ahí vive la fila "CAPITAL RENOVADO" y los estados de cuota).
- La seguridad real es la RLS, no el botón: aunque la pantalla lo oculte, un contrato ajeno devuelve **cero** filas. Verificado con prueba de suplantación en producción (contrato propio: 3 cuotas visibles; ajeno: 0).

## Estado

**EN PRODUCCIÓN y aprobado por Miguel (2026-07-14).** Detalle técnico y método de deploy → `public_html/CLAUDE.md` (changelog 2026-07-14 (b), §13: `analista v15`). Se desplegó sin tocar la sesión paralela de **conciliación** (quedó byte-idéntica; el service worker sigue en v98).

## Notas relacionadas
[[Acceso y roles del CRM]] · [[Ciclo de vida de contratos]] · [[Arquitectura del portal]] · [[Deploy a Hostinger]] · [[Inicio]]

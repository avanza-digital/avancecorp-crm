---
tags: [crm, leads, gestionado, publicacion]
fecha: 2026-10-03
---

# Gestionado - ficha y vistas coherentes (2026-10-03)

Publicado y comprobado en crm.miavance.com el 03/10/2026, después de la autorización
de Miguel «Sí, probar y publicar todo». Complementa [[Leads - filtro Gestionado (2026-10-03)]]
y [[Pipeline - columna Gestionado (2026-10-01)]].

Gestionado aparece en la cabecera y el recorrido de la ficha, la tabla de Leads,
la tarjeta, la búsqueda global y el cierre de tarea. Se calcula por contacto
vigente desde la asignación actual. Deshacer o reasignar actualiza la etiqueta.
No es una etapa editable. Si no se puede comprobar, muestra «Gestión sin verificar».

- Servidor: migración `20261003225551`, dos funciones de lectura INVOKER/RLS,
  lotes de 100. Publicada mediante merge del banco propio, después de
  **2.823 comprobaciones RLS**, SQL de seis roles y 22 escenarios HTTP.
- Pantalla: fuente `6b1c25382d9e`, build `build-20261004T025651347Z`.
  Conserva la ficha Base para gestión F2 publicada desde `3e248407`.
- Verificación: check **5.690 pruebas**, Docker **21/21**, HTTPS **98/98**.
  Sesión real de analista: 8 leads en el filtro y ficha con Gestionado como paso
  actual. Lectura productiva de tres roles: cero diferencias; ningún cliente
  ni actividad creada para verificar.
- Banco temporal retirado. ZIP y manifiesto publicado/anterior conservados.
- Integración pendiente: [PR #181](https://github.com/avanza-digital/avancecorp-crm/pull/181);
  la ficha Base F2 está en [PR #180](https://github.com/avanza-digital/avancecorp-crm/pull/180).
  GitHub exige una aprobación; no cambiar esa protección ni forzar Main.
- Limitaciones generales registradas: gate de realidad NOT RUN sin credencial
  de servicio productiva; gate analítico global tenía un fallo anterior ajeno
  a este cambio. Las comprobaciones específicas sí pasaron.

Acta completa: `CRM-Avance-Corp/docs/publicaciones/gestionado-ficha-2026-10-03.md`.
Fuente y huella del ZIP se mantienen aunque después se integren actas.

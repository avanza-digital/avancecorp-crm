# Continuidad CRM 2026-08-06

Relacionado con [[Meta de conversion predeterminada]].

## Estado confirmado

- Producción sirve `crm-20260806T192701Z-567cb1fd5e22` en
  `crm.miavance.com`.
- SHA-256 del release:
  `91c40e97d6897262f408beb8cefaad5e88f3318bebc7b05b51aa6af033fcec2c`.
- La bandeja de pendientes está distribuida por responsabilidad:
  Vendedor recibe sus casos, Supervisor excepciones escaladas de su equipo y
  Gerencia desviaciones estratégicas de conversión.
- La campana es el acceso canónico a `#/alertas`; no se duplica en el sidebar.
- No se añadió tabla, Realtime, RPC ni migración para estas señales.
- Producción se verificó byte a byte. El ZIP y manifiesto devuelven 404;
  `.env` y `.htaccess`, 403.
- Validación: 107 archivos de prueba, 1,298 pruebas aprobadas, lint sin
  advertencias, tipos y build correctos.
- No hubo navegador enlazado para una validación visual automatizada.

## Commits del cierre

- `772677c` — Inteligencia Gerencial y reuniones.
- `567cb1f` — Pendientes según responsabilidad.
- `a62f169` — Evidencia del despliegue.

## WIP separado para revisar mañana

El borrador `supabase/scripts/clean-crm-data.mjs`, su comando en
`package.json` y la documentación asociada se guardan solo para continuidad.
No deben ejecutarse todavía.

Pendientes de auditoría:

1. Rechazar cualquier opción desconocida que empiece por `--`.
2. Hacer que `--preserve-reference` conserve también cuentas bancarias y su
   relación con contratos, como promete la documentación.
3. Corregir el ejemplo de `--preflight`: hoy omite variables que el script
   exige.
4. Añadir pruebas automatizadas para bloqueos destructivos y modos de
   preservación antes de considerarlo operativo.

## Entorno local al cerrar

- El servidor Vite de `127.0.0.1:5173` quedó detenido.
- Para retomarlo: `npm --prefix app run dev -- --host 127.0.0.1`.
- Los documentos, el PDF, el contrato y `public_html` que aparecen fuera de
  este trabajo pertenecen a otros frentes y no deben incluirse automáticamente
  en commits del CRM.

## Continuidad posterior

- El siguiente ciclo quedó documentado en
  [[Configuración operativa CRM 2026-08-07]].

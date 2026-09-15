# Publicado: correo de acceso de clientes — 15/09/2026

**Activo en https://miavance.com/admin/clientes.html.** Recargar la página,
abrir Editar, corregir el correo, indicar motivo y guardar. Admin y superadmin
activos pueden hacerlo. El cliente usa el correo nuevo con la contraseña que
ya tenía; el correo anterior deja de servir para iniciar una nueva sesión.

## Evidencia

- SQL aprobado `20260915173423` instalado mediante merge de la rama propia;
  Supabase lo registró como `20260915181818_crm_correo_cliente_admin_atomico`.
- Antes del merge: 291 entradas del historial coincidentes; una única
  migración nueva y una única Edge nueva. Las 19 funciones existentes tenían
  los mismos bundles y configuración de JWT en padre y rama.
- Esquema reconstruido sin clientes reales. Paridad exacta de los objetos
  afectados: 34 columnas, 11 constraints, 13 funciones y 11 triggers.
  No se declara igualdad total de los catálogos de plataforma: la rama trae
  versiones/configuración administradas distintas y el dump renumera columnas
  que fueron eliminadas históricamente.
- PASS: los 9 grupos de integración contra Auth/Postgres remotos y un ensayo
  adicional de la Edge desplegada por HTTP con JWT admin y CORS del portal.
  Confirmados el login nuevo, la misma contraseña y el rechazo del correo viejo.
- Producción: RLS forzada, triggers activos, RPC ejecutable solo por el servicio
  y endpoint sin sesión devuelve 401. Fuentes de la Edge idénticas al ensayo.
- Portal: cuatro archivos publicados idénticos byte a byte. Preflight: 93
  archivos en el ZIP, 76 comparados, cero archivos vivos omitidos. Módulo
  Clientes v48 y service worker v117.
- El merge reempaquetó `crear-cliente` de v35 a v36; se compararon sus siete
  archivos entre la rama y producción y son idénticos. Las otras 18 Edge
  existentes conservaron sus bundles y configuración.
- Rama propia `correo-admin-20260915` eliminada y ausencia verificada. Los
  otros bancos de pruebas se conservaron. Ninguna cuenta real se modificó en
  las pruebas.

Artefacto del portal construido desde Main local y `avancecorp/main` iguales
en `5bde86f`, con submódulo del portal y `origin/main` iguales en `0e0d205`.
El ajuste de permisos del frontend CRM está guardado en Main; el sitio
publicado en esta operación es **miavance.com**.

## Límites de validación

Los checks locales y dos fallos preexistentes del banco global del portal
están detallados en [README.md](README.md). El wrapper de revisión independiente
no entregó un VERDICT válido y se registra NOT RUN. Los ensayos de login se
hicieron con usuarios sintéticos en la rama; no se cambió el correo de un
cliente real para probar en producción.

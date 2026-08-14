# Configuración operativa CRM 2026-08-07

Estado actualizado el 2026-08-08: Usuarios y jerarquía, Productos, Metas y SLA están desplegados en producción. Los contratos volvieron a ser de carga libre y la configuración visible quedó simplificada para operación.

## Base y Edge

- Migraciones remotas: `20260808160113` (usuarios), `20260808160129` (productos), `20260808160137` (metas/SLA), `20260808160148` (integración Portal) y `20260808190441` (atribución de contratos libres a metas).
- `crm-usuarios` v1: `ACTIVE`, `verify_jwt=true`; preflight CORS 204 y POST sin sesión 401.
- Productos históricos: 325 contratos preservados como snapshots legacy.
- Bridge: `permite_altas_legacy=true`, revisión 1. Sigue abierto deliberadamente: una condición de producto no es requisito visible para cargar contratos; el servidor conserva el snapshot técnico legacy.
- Condiciones comerciales no legacy seleccionables: 0.

## Frontends

- CRM: release `crm-20260808T185153Z-6d3bfb75d4d6`, SHA-256 `c01068853df7591b12df07467081f83be29e99a26e230a332fa98386951d0db0`.
- Producción sirve `index-yG0C8pp2.js`, `config-metas-C9BdWeJ8.js` y `config-sla-DDSk4PR_.js`; chunks comparados byte por byte.
- Portal `miavance.com`: contratos libres desplegados; service worker `avance-v108`.
- Los archivos vivos del Portal coincidieron byte por byte; ZIP, pruebas y `CLAUDE.md` responden 404.

## Decisiones operativas cerradas

- Metas: una sola meta mensual en soles por analista. La BD conserva seis dimensiones por compatibilidad, normalizadas en `nuevo/PEN`; conversión, cantidad de contratos y las otras dimensiones se publican en cero.
- Cumplimiento: un vendedor explícito enlazado al contrato manda si pertenece al snapshot mensual. Sin vendedor explícito se usa el autor inmutable del alta, también validado contra el snapshot. Vínculos inelegibles o con vendedores distintos quedan sin atribución; nunca caen silenciosamente a otro actor.
- Agosto, verificación posterior al merge: 65 contratos; 61 atribuibles a vendedores y 4 creados por supervisores fuera de metas individuales. No se reasignan a subordinados sin evidencia.
- Tiempos de atención: la UI usa horas y días con explicaciones humanas. La BD continúa guardando minutos enteros para no romper SLA históricos.
- Deuda durable: sellar una atribución comercial inmutable por contrato permitiría cubrir altas ejecutadas por supervisores en nombre de un vendedor. No inferirlas hoy desde el asesor actual porque el offboarding lo reasigna.

La identidad de [[Cuenta piloto CRM Miguel]] conserva perfil visible, membresía CRM activa, rol vendedor y supervisor **JORGE MARZANO**.

No cerrar el bridge de productos mientras el negocio quiera contratos libres. Publicar productos queda disponible como mejora comercial, no como bloqueo del alta.

Relacionado: [[Deploy a Hostinger]], [[Cuenta piloto CRM Miguel]] y [[Ciclo de vida de contratos]].

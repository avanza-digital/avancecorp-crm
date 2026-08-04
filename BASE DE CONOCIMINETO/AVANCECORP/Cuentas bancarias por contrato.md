# Cuentas bancarias por contrato

## Decisión de negocio

Un inversionista puede tener varias inversiones y cada contrato elige de forma explícita la cuenta donde Avance Corp depositará **todos los desembolsos de ese contrato**: intereses, devoluciones y retorno de capital.

- La cuenta no es una propiedad global del inversionista: es una instrucción fijada por contrato.
- Al crear un contrato, el analista puede reutilizar una cuenta guardada, tomar una fotografía de la cuenta vigente del perfil o añadir una nueva en el mismo formulario.
- No existe flujo de verificación bancaria. Una cuenta nueva queda disponible de inmediato después de validar que sus datos estén completos y bien formados.
- Cambiar posteriormente la cuenta del perfil no modifica contratos anteriores.
- El vínculo contractual es inmutable; una corrección excepcional exige conciliación explícita, no un cambio silencioso.

Relacionadas: [[Rol Analista]], [[Arquitectura del portal]], [[Notificaciones de pagos]], [[Ciclo de vida de contratos]] y [[Cuentas mancomunadas]]. Una cuenta mancomunada describe titulares del contrato; no reemplaza la instrucción bancaria de pago.

## Modelo técnico

- `crm.cuentas_bancarias`: historial reutilizable y versionado de cuentas. `activa` representa ciclo de vida, no verificación.
- `crm.contrato_cuentas_pago`: una sola cuenta por contrato.
- `crm.crear_contrato_con_cuenta`: crea contrato, cronograma, cuenta —si corresponde— y vínculo en una única transacción.
- La selección desde el perfil envía una fotografía de lo que vio el analista; si el perfil cambió antes de guardar, la operación se rechaza y se pide recargar.
- La selección de una cuenta guardada usa bloqueo compartido y validación de cliente, moneda y vigencia para cerrar carreras.
- Las sesiones humanas no leen ni escriben las tablas bancarias directamente; acceden mediante RPC con alcance de cartera y RLS deny-by-default.

## Pagos y compatibilidad

La Agenda de Pagos consulta la cuenta contractual antes de exportar Excel:

1. Si existe vínculo contractual, esa cuenta gana siempre.
2. Si el contrato es anterior y no tiene vínculo, se usa explícitamente la cuenta PEN/USD del perfil como `perfil_legacy`.
3. Si existe un vínculo incompleto o con moneda/cliente incoherente, Pagos se bloquea. Nunca cae silenciosamente al perfil.
4. Si falla la consulta de cuentas, se invalida la caché anterior y se bloquea la exportación.

No se hace backfill automático: una cuenta actual del perfil no demuestra cuál fue la instrucción histórica de cada contrato.

## Estado de implementación

Implementación y despliegue completados. La funcionalidad base corresponde a `20260803221622_crm_cuentas_bancarias_por_contrato.sql`; el endurecimiento posterior que extiende el gate de [[Offboarding seguro del CRM (P04)]] a toda la superficie bancaria `crm.*` corresponde a `20260804144555_crm_p04_gate_cuentas_bancarias.sql`.

## Despliegue 2026-08-03

- Migración fusionada a Supabase producción después de un gate RLS de 453/453 aserciones; la rama temporal fue eliminada.
- Portal `miavance.com` publicado desde el commit `eb536dc7ad67aa91f5e9d70a18badd31af3ff2f9`, con Service Worker `avance-v106` y caché de Hostinger purgada.
- Los archivos críticos de Pagos y Contratos devolvieron HTTP 200 y coincidieron byte por byte con el artefacto; el ZIP de despliegue devolvió HTTP 404.
- Frontend `crm.miavance.com` publicado mediante `/release-crm`: release `crm-20260803T223544Z-bb9ffc602eb7`, SHA-256 `d7ad3c383beb099bebf175da30bf1b12ddf5e5bf031b671f83b6b4571a61b80b`. El HTML y el bundle `assets/index-De_ut-kj.js` respondieron HTTP 200 y coincidieron byte por byte con el artefacto; el ZIP respondió HTTP 404.

Validado localmente con PostgreSQL 16 aislado (alta, versionado, historial, rollback, ACL y resolver), 1,097 pruebas unitarias/RTL/MSW, 68 E2E Playwright y 44 pruebas del portal.

El 2026-08-04 se desplegó el cierre P04 bancario: rama Supabase temporal `p04-bank-gate-20260804`, gate PostgREST **475/475**, advisors sin errores ni clases nuevas de seguridad, merge a producción y comprobación de hashes/ACL idénticos. Supabase registró la migración como `20260804154054`; la rama temporal fue eliminada.

El alta administrativa antigua de `public_html/admin/contratos` conserva temporalmente `public.crear_contrato` y, por compatibilidad, genera un contrato sin enlace. Pagos lo trata explícitamente como `perfil_legacy`. La garantía de cuenta fija se aplica a todo contrato nuevo creado por el flujo del analista en el CRM; será universal cuando se migre o retire esa alta administrativa.

## Riesgo residual aceptado mientras no se autorice tocar `public`

El wrapper nuevo impide cambiar la moneda de un contrato enlazado y Pagos detecta cualquier incoherencia antes de desembolsar. Sin embargo, una escritura privilegiada directa sobre `public.contratos` todavía podría almacenar temporalmente una combinación inválida; el consumo falla cerrado. Una guarda preventiva sobre `public.contratos` requiere autorización explícita por ser otra excepción a la frontera del portal.

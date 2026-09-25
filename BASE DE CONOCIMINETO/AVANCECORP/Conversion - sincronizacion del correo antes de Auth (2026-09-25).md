# Conversión: sincronización del correo antes de Auth

Relacionado: [[Inicio]], [[Conversion - correo de acceso reservado antes de Auth (2026-09-25)]].

## Decisión solicitada por Miguel

El correo editado en la ficha debe ser el del primer acceso Avance. Corregirlo desde
el formulario de acceso también debe ser posible antes de crear la cuenta. Una
reserva incompleta no vuelve inmutable el correo. Una cuenta Auth existente se
administra desde gestión de acceso; editar contacto no reasigna sus credenciales.

## Causa y arreglo preparado

La ficha y `inversion_solicitudes.datos.alta_portal` retenían valores distintos.
La RPC bloqueaba cualquier cambio si existía `auth_claim_id`, aunque Auth no existiese.
La migración `20260925170437_crm_correo_acceso_sincronizado.sql` sincroniza ambos
sentidos con revisión y auditoría, preserva claim/token/hash inicial y protege
contra peticiones tardías. GoTrue asigna app_metadata mediante UPDATE después del
INSERT; el guard cubre los dos dentro de la misma transacción.

Solo quien puede editar la ficha por RLS sincroniza su acceso pendiente. Importar
sin actor no crea un actor ficticio y obliga a revisar una diferencia antes de Auth.

## Estado

**Preparado, no desplegado.** Worktree autorizado `codex/correo-acceso-20260925`.
No confundir con el SQL puntual previamente aprobado/aplicado. Migración general
requiere aprobación, ensayo hospedado y merge. Frontend exige `$release-crm` humano.

Gates locales: 22 aserciones SQL, 21 HTTP Auth/PostgREST/Edge y roles, 4.426 tests
de frontend y 13 E2E Docker. Reversión operativa ensayada: vuelve a las RPC previas
pero conserva el guard contra altas tardías; nunca borra cuentas ni datos comerciales.
Detalles reproducibles y límites en `supabase/scripts/correo-acceso/README.md` del CRM.

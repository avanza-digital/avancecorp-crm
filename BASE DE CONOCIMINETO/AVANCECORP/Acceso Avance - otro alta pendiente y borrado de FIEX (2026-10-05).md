# Acceso Avance: «La persona tiene otro alta pendiente» y borrado de FIEX (05/10/2026)

## El síntoma
Al pulsar «Completar acceso Avance» para MARIA LUISA PANCICH ORDOÑEZ (persona, DNI) salía:
«La persona tiene otro alta pendiente; recupera ese proceso con sus datos originales».
Lo lanza `crm.acceso_inversion_fn`, paso `reclamar`.

## La causa
- El 07/09 (14:16 Lima) se intentó darle acceso con su DNI. Se creó su ficha y un **apartado**
  de acceso (`crm.multiempresa_idempotencia`, clave `auth_persona:<persona>`, estado `reclamado`).
- Ese acceso no se pudo terminar porque su correo **ya era la cuenta del portal de otra ficha**:
  la empresa FIEX DEL PERU S.A.C. (RUC guardado como «CE»), con el mismo correo de contacto.
- El apartado quedó colgado un mes, sin usuario, sin perfil y con el plazo vencido. Era el
  **único** apartado pendiente de todo el sistema.
- Una solicitud nueva calcula otra huella de datos. Si la persona tiene un apartado sin terminar
  con huella distinta, la base se niega a abrir otro. Ese es el mensaje.

🔑 **Cómo reconocerlo la próxima vez:** el mensaje sale cuando hay un apartado `reclamado` viejo
para la persona. Mira si su correo ya pertenece a otra cuenta del portal: casi seguro es la causa
de que el primer intento no terminara.

## Lo que se hizo (orden explícita de Miguel: «borrar de verdad», contra la regla general de soft-delete)
- Se borró FIEX completa en producción con un solo bloque `DO` atómico: ficha, inversión Prodelco
  US$ 4,000 (imputada 28/08, analista Linda Condori), cierre externo, depósito reclamado, eventos,
  titulares, 2 solicitudes, identificadores, responsables, gestiones, 77 lecturas de cartera,
  6 avisos, actividades, cuenta bancaria, perfil y **cuenta del portal** (auth.users + sesión).
- En el mismo bloque se borró el apartado colgado de María Luisa, exigiendo el estado comprobado
  y el plazo vencido.
- Antes: dos ensayos en producción terminados en `RAISE` (se revierten solos). En el segundo se
  simuló su «reclamar» después del borrado y **pasó**. Codex r1: CHANGES_REQUESTED (2 P1 + 1 P2),
  todos aceptados y corregidos (bloqueo de filas antes de comprobar, IDs exactos, nada ajeno
  colgando, `periodos_cerrados` bloqueada).
- Verificado desde fuera: 0 filas de FIEX, 0 cuentas con ese correo, candados en modo `O`,
  24 copias en `public.audit_log` (las tablas con `trg_audit`). Inversiones: 176 → 175.
- **Quedan a propósito:** 3 filas de `crm.ledger_rentabilidad` (append-only; sus lectores usan
  `left join` a perfiles), la idempotencia de un contrato ya eliminado y una bitácora de backfill.
- **Queda pendiente:** el archivo `f4-comprobantes/721b1f50…/09a16714…/comprobante.jpg`. Storage
  no deja borrarlo por SQL (`protect_objects_delete`): hay que borrarlo desde el panel de Supabase.

## Receta para borrar de verdad una ficha de inversionista (si vuelve a pedirse)
1. Cierre por llaves foráneas desde `crm.inversionistas`, `public.perfiles` y `auth.users`,
   recursivo hasta converger (en un `DO` que termina en `RAISE` con el informe).
2. Barrido de referencias SIN llave (columnas uuid de crm/public/private/storage).
3. Candados que bloquean el DELETE: `trg_cierres_externos_00_inmutables`,
   `trg_depositos_reclamados_00_append_only`, `trg_inversion_eventos_inmutables`. Se bajan POR
   NOMBRE y se suben en el mismo bloque. `audit_log` deja pasar sola la acción `SET NULL` de la FK.
4. Orden: depósitos → eventos → titulares → solicitudes → inversiones → cierres → tablas
   `inversionista_*`, lecturas, backfill → inversionista → avisos → perfil → auth.users.
5. Ensayo con `pg_stat_xact_user_tables` para ver EXACTAMENTE qué cae (incluidas las cascadas).

Relacionado: [[Eliminar contratos con pagos por administrador - preparado 2026-09-15]] ·
[[Acceso Avance - recuperacion del primer envio rechazado (2026-09-29)]] ·
[[Conversion - sincronizacion del correo antes de Auth (2026-09-25)]]

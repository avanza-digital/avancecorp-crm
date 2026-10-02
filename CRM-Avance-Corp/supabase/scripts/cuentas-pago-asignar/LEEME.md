# Asignar la cuenta de pago a un contrato que no tiene ninguna (02/10/2026)

Acompaña a la migración `20261002005004_crm_asignar_cuenta_pago.sql`.

## Para qué

22 contratos viejos no tienen cuenta de pago y por eso no se pueden marcar sus pagos (ver
`../cuentas-pago-rezago/LEEME.md`). No se pueden vincular solos: el cliente tiene dos cuentas, o
solo en la otra moneda, o ninguna. Hacía falta que una persona diga en cuál cobra, y no existía
ninguna operación para eso. Decisión de Miguel (01/10/2026): botón «Asignar cuenta» en Pagos.

## Qué permite

- Quién: solo admin y superadmin vigentes (la misma compuerta de «Cambiar cuenta de pago»).
- A qué contratos: abiertos (activo o vencido) y SIN cuenta de pago. Si ya tiene una, se cambia
  con «Cambiar cuenta de pago» y el correo del cliente, como siempre.
- Qué cuentas: vigentes, del mismo cliente y de la misma moneda del contrato. Si el cliente no
  tiene ninguna en esa moneda, primero se registra en Clientes → Cuentas.
- Con qué: motivo obligatorio (5 a 500 caracteres). Sin adjunto. No avisa al cliente.
- Qué deja: el vínculo (con quién lo creó), una constancia en
  `crm.contrato_cuenta_pago_asignaciones` (quién, cuándo, cuenta y motivo) y la bitácora.

No sella las cuotas que el contrato ya tenía pagadas, no registra cuentas y no toca el bloqueo de
pagos: solo completa la instrucción que al contrato le faltaba.

## Qué hay aquí

| Archivo | Para qué |
|---|---|
| `reversa.sql` | Sin asignaciones registradas (y con las piezas intactas), retira todo. En cualquier otro caso NO borra nada: solo cierra la puerta (retira el permiso de ejecutar). |
| `reabrir-puerta.sql` | Devuelve el permiso de ejecutar tras haber cerrado la puerta. Se niega si las piezas no son las de la migración. |
| `registrar.sql` | Anota la versión en `supabase_migrations.schema_migrations`. Se regenera si la migración cambia. |
| `siembra-extra.sql`, `test-asignar-cuenta-pago.sql`, `ciclo.sh` | Banco Docker propio: casos ficticios, pruebas y el ciclo completo. |

## Orden para publicar (lo lanza Miguel; nunca un revisor)

```bash
# desde CRM-Avance-Corp/ — el servidor ANTES que el portal (el botón llama a esta puerta)
supabase db query --linked --file supabase/migrations/20261002005004_crm_asignar_cuenta_pago.sql   # debe devolver ASIGNAR_CUENTA_PAGO_OK
supabase db query --linked --file supabase/scripts/cuentas-pago-asignar/registrar.sql
```

Es independiente de `20261001233019` (motivo del bloqueo y carga del rezago): pueden aplicarse en
cualquier orden.

## Si una asignación sale mal

Una asignación no se deshace desde pantalla ni se borra. Se corrige con «Cambiar cuenta de pago»
(queda el historial del cambio, con el correo del cliente).

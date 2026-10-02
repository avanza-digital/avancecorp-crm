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
| `generar-derivados.py` | Genera los dos archivos de abajo con UNA sola definición de «las piezas están enteras». `--verificar` falla si alguno quedó viejo. Ninguno se edita a mano. |
| `reversa.sql` | Generado. Sin asignaciones registradas y con las piezas enteras, retira todo y quita la versión del registro. En cualquier otro caso NO borra nada: solo cierra la puerta, quitándole el permiso de ejecutar a TODO el que lo tenga (aunque falte una pieza o alguna haya cambiado). |
| `reabrir-puerta.sql` | Generado. Devuelve el permiso de ejecutar tras haber cerrado la puerta. Se niega si las piezas no están enteras: cuerpos, permisos, candados, bitácora, reglas de la tabla y las piezas de «Cambiar cuenta de pago» de las que depende. |
| `registrar.sql` | Anota la versión en `supabase_migrations.schema_migrations`. Se regenera si la migración cambia. |
| `siembra-extra.sql`, `test-asignar-cuenta-pago.sql`, `prueba-concurrencia.sh`, `ciclo.sh` | Banco Docker propio: casos ficticios, pruebas, dos sesiones a la vez y el ciclo completo. |

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

## Cómo leer la última fila de cada guion

La migración, `reversa.sql` y `reabrir-puerta.sql` terminan con una fila que dice el ESTADO en que
está la base, no lo que hizo esa corrida. Si arriba hay un `ERROR`, la corrida no cambió nada y la
fila describe lo que ya había.

| Fila | Qué significa |
|---|---|
| `ASIGNAR_CUENTA_PAGO_OK` | Las piezas están puestas y la puerta abierta. |
| `PUERTA_CERRADA: …` | Las piezas siguen, pero nadie puede asignar. No se borró nada. |
| `PUERTA_REABIERTA` | Las piezas están enteras y se puede asignar otra vez. |
| `RETIRADA: …` | No queda ninguna pieza de la migración. |
| `RESTOS: …` | No quedan la puerta ni el núcleo, pero sí alguna otra pieza (alguien borró a mano). Se retira a mano antes de volver a aplicar la migración. |
| `SIN_CAMBIOS: …` | La puerta sigue abierta. |

## Límites conocidos

- La asignación solo corre en el modo de transacción normal (READ COMMITTED, el de la API). En
  otro modo se niega antes de mirar nada: con una fotografía fija podría ver vigente a un
  administrador ya revocado o no ver la asignación que acaba de hacer otro intento. La API ya
  trabaja en ese modo: trece puertas vivas del CRM (editar un lead, tomar un lead libre, reabrir
  un lead…) llevan la misma negativa, las ejecuta `authenticated` y funcionan a diario.
- Solo se asigna a contratos abiertos (activo o vencido). Hoy los 23 contratos sin cuenta están
  activos. Si algún día un contrato cerrado sin cuenta tuviera cuotas por pagar, la pantalla no
  ofrecerá el botón: es una decisión de negocio que se toma cuando aparezca.
- `reabrir-puerta.sql` no compara la definición del CHECK del motivo (sí que exista y esté
  validado); el núcleo valida el motivo por su cuenta.
- Riesgo que ya existía y NO es de esta migración: «Retirar cuenta» y «Cambiar cuenta de pago» no
  llevan esa misma negativa. Por la API siempre van en el modo normal; solo quien lance SQL a mano
  en otro modo podría retirar una cuenta recién asignada. Arreglo propuesto, aparte y con OK de
  Miguel: ponerles la misma negativa.
- Una asignación que ya había empezado cuando se lanza `reversa.sql` espera a que termine y luego
  se completa. Si el veredicto dice `PUERTA_CERRADA`, vuelve a contar las asignaciones un minuto después.

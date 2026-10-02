# «Retirar cuenta» y «Cambiar cuenta de pago» solo en READ COMMITTED (02/10/2026)

Acompaña a la migración `20261002163158_crm_retirar_y_cambiar_cuenta_solo_read_committed.sql`.

## Para qué

Los dos núcleos (`private.retirar_cuenta_cliente_autorizado`, F4 del 27/09, y
`private.cambiar_cuenta_pago_contratos_autorizado`, F3 del 26/09 corregida el 27/09) no llevaban la negativa de
modo de transacción que sí lleva «Asignar cuenta» (`20261002005004`). En el banco de «Asignar» se midió el
riesgo: en REPEATABLE READ o SERIALIZABLE, «Retirar cuenta» podía retirar una cuenta recién asignada que en
READ COMMITTED se niega a retirar, y «Cambiar» podía dar por vigente a un administrador ya revocado. Solo
alcanzable con SQL lanzado a mano: PostgREST siempre va en READ COMMITTED, así que ninguna pantalla cambia.
Decisión de Miguel (02/10/2026): sí, en migración aparte, después de entregar F6.

## Qué hace la migración

Reemplaza los dos cuerpos por el MISMO cuerpo (byte a byte, huella comprobada antes de tocar nada) con una
primera comprobación añadida: si `current_setting('transaction_isolation') <> 'read committed'`, error `0A000`
(«El retiro de cuenta / El cambio de cuenta de pago no admite este modo de transacción»). No toca puertas,
grants, triggers ni tablas; añade una frase al comentario de cada función. Se niega a aplicarse si los cuerpos
vivos no son los esperados (incluida una segunda aplicación).

| Archivo | Para qué |
|---|---|
| `generar-derivados.py` | Genera `registrar.sql` y `reversa.sql` desde la migración y `piezas-anteriores.json` (los cuerpos exactos de antes). `--verificar` falla si quedaron viejos. No se editan a mano. |
| `registrar.sql` | Anota la versión en `supabase_migrations.schema_migrations` (`db query` no registra). Se niega si la migración no está aplicada. Idempotente. |
| `reversa.sql` | Repone los cuerpos anteriores exactos, quita la frase del comentario y borra el registro. Se niega fuera de READ COMMITTED o si los cuerpos vivos no son los de la migración. |
| `test-negativa.sql` | Prueba de banco: en RR y SERIALIZABLE los núcleos y las puertas devuelven `0A000`; en READ COMMITTED pasan la negativa y caen en la comprobación siguiente (`42501` sin actor). Sin la migración, FALLA (es el mutante natural). |
| `ciclo.sh` | Ciclo completo en un banco Docker propio (esquema de producción sin datos): aplicar, reaplicar (se niega), prueba, pruebas existentes de `cuentas-gloria`, registrar ×2, reversa en RR (se niega), reversa, mutante, reaplicar. |

## Orden para publicar (lo lanza Miguel; nunca un revisor)

```bash
# desde CRM-Avance-Corp/
supabase db query --linked --file supabase/migrations/20261002163158_crm_retirar_y_cambiar_cuenta_solo_read_committed.sql   # debe devolver RETIRAR_CAMBIAR_SOLO_READ_COMMITTED_OK
supabase db query --linked --file supabase/scripts/cuentas-pago-negativa/registrar.sql
```

Si la primera dice «no tiene el cuerpo esperado», alguien cambió uno de los núcleos después del 02/10: no se
aplica; se regenera la migración sobre los cuerpos vivos.

## Verificación (banco `avancecorp-cuentas-negativa-20261002`, 02/10/2026)

`ciclo.sh`: 25 pasos, 24 ✓ (prueba de la negativa 14/14: núcleos y puertas en REPEATABLE READ, SERIALIZABLE y
READ UNCOMMITTED → `0A000`; en READ COMMITTED explícito → `42501` sin actor; sin la migración, 10 casos fallan).
Codex r1 (`docs/encargos/2026-10-02-codex-negativa-read-committed-r1*.md`): APPROVE_WITH_NITS; aplicados: READ COMMITTED
explícito en la prueba, puertas en todos los modos, postflight con `proconfig` exacto y sin LEAKPROOF, comentario sin
`rtrim` y reversa que quita solo el sufijo (NULL si no queda texto), atomicidad de `db query --file` documentada.
1 ✗ ajeno: `cuentas-gloria/test-cambio-cuenta-pago.sql` falla en su paso de `dry_run`
(«Solo el servicio de avisos reclama avisos») **igual sin la migración** (comprobado revirtiéndola): es del
banco sin datos, no de este cambio; hasta esa línea (551) los cambios reales de cuenta pasan en READ COMMITTED.
`test-retirar-cuenta-cliente.sql` PASS. Preparación propia del banco (solo banco): `storage.objects` mínimo,
`auth.uid()` que lee `request.jwt.claims` como producción y el catálogo `d0…02` que esas pruebas dan por sentado.

## Límites

- La negativa está en los núcleos; las puertas INVOKER la heredan (probado).
- No cubre otras funciones de cuentas (alta, historial): no escriben vínculos de pago.

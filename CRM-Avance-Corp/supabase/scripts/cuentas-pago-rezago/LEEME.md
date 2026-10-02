# Cuentas de pago: motivo del bloqueo y rezago de vínculos (01/10/2026)

Acompaña a la migración `20261001233019_crm_cuentas_pago_motivo_y_rezago.sql`.

## El problema

Una cuota solo pasa a «pagado» si su contrato tiene vínculo con una cuenta del mismo cliente y de
la misma moneda (`crm.contrato_cuentas_pago`). Quedaron 23 contratos viejos sin vínculo y el
bloqueo decía siempre lo mismo. Censo del 01/10/2026 (705 contratos):

| Caso | Qué significa | Contratos |
|---|---|---|
| `ok` | Se puede pagar | 682 |
| `una_cuenta` | Sin vínculo; el cliente tiene UNA cuenta activa en esa moneda | 1 |
| `varias_cuentas` | Sin vínculo; tiene dos o más: nadie sabe en cuál cobra | 7 |
| `otra_moneda` | Sin vínculo; solo tiene cuenta en la otra moneda | 12 |
| `sin_cuenta` | Sin vínculo; no tiene ninguna cuenta vigente | 3 |
| `cuenta_no_corresponde` | Hay vínculo, pero la cuenta es de otro cliente o moneda | 0 |

La carga vincula SOLO el caso `una_cuenta`. Los demás siguen bloqueados y son trabajo de
Operaciones: pedir la cuenta al cliente (o confirmar cuál) y registrarla. Cuando un contrato pase
a tener una sola cuenta posible, se lanza **`vincular-rezago.sql`** (la misma carga, sola) y lo
vincula. La migración NO se relanza para eso. Cuando hay que ELEGIR entre dos cuentas, elige
administración con «Asignar cuenta» en Pagos (migración `20261002005004`, ver
`../cuentas-pago-asignar/LEEME.md`); la carga nunca elige.

## Qué hay aquí

| Archivo | Para qué |
|---|---|
| `censo-sin-funciones.sql` | Solo lectura. Conteo por caso y detalle de los que no se pueden pagar (banco y origen de las cuentas candidatas, sin números). No usa funciones: sirve antes de la migración y tras revertirla. |
| `lista-operaciones.sql` | Solo lectura. La lista de trabajo de F6 para Operaciones: los contratos que no se pueden pagar, con cliente, teléfono y correo (PII: el resultado NO se versiona), vencidos, próxima cuota y cuentas candidatas (banco y origen, sin números). Misma clasificación que `censo-sin-funciones.sql`. De ahí sale el Excel de Gloria (02/10/2026). |
| `censo.sql` | Solo lectura. Lo mismo con la regla instalada (`private.cuenta_pago_diagnostico`), con el mensaje que ve quien registra el pago. |
| `generar-derivados.py` | Genera los cuatro archivos de abajo desde los textos fuente. `--verificar` falla si alguno quedó viejo. Ninguno se edita a mano. |
| `ensayo-prod-sin-escribir.sql` | Generado. Corre la migración en producción dentro de una transacción que termina SIEMPRE en error a propósito: no escribe nada. Devuelve el antes/después, el resultado de marcar una cuota real en un contrato de cada caso (comprobando que quedó pagada y sellada, no solo que no dio error) y qué texto recibe un gestor y un analista. Veredicto: `PASA`, `FALLA` o `INCOMPLETO`. |
| `vincular-rezago.sql` | Generado. La carga, sola y relanzable, con su propia marca por día. Se niega si el bloqueo o el diagnóstico vivos no son los de la migración. |
| `reversa.sql` | Generado. Borra solo los vínculos de la carga de la migración, repone el bloqueo anterior, quita las funciones y quita la versión del registro. Se niega si alguno de esos contratos ya registró un pago, un cambio de cuenta o un PDF. |
| `reversa-solo-codigo.sql` | Generado. Repone el bloqueo anterior, quita las funciones y quita la versión del registro SIN tocar vínculos. Es la que sirve cuando ya hubo pagos. |
| `registrar.sql` | Anota la versión en `supabase_migrations.schema_migrations` (lanzar la migración con `db query` no la registra). Se regenera si la migración cambia. |
| `siembra.sql`, `test-cuentas-pago-rezago.sql`, `ciclo.sh` | Banco Docker propio: casos ficticios, pruebas y el ciclo completo (aplicar, repetir, revertir, mutantes). |

## Orden para publicar (lo lanza Miguel; nunca un revisor)

```bash
# desde CRM-Avance-Corp/
supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/ensayo-prod-sin-escribir.sql   # debe fallar con ENSAYO_DESHECHO y "veredicto": "PASA"
supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/censo-sin-funciones.sql        # igual que antes del ensayo
supabase db query --linked --file supabase/migrations/20261001233019_crm_cuentas_pago_motivo_y_rezago.sql
supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/registrar.sql
supabase db query --linked --file supabase/scripts/cuentas-pago-rezago/censo.sql
```

Cómo leer el veredicto del ensayo:

- `PASA`: todo se probó y salió como dicta la regla. Se puede aplicar.
- `INCOMPLETO`: nada salió mal, pero algo no se pudo probar (está en `sin_probar`). Lo normal es
  que alguien estuviera registrando un pago justo en un contrato que el ensayo quería probar
  («otra sesión tenía ocupada la cuota»): se vuelve a lanzar. Si lo que falta es un caso sin
  ninguna cuota pendiente, se decide con esa lista a la vista.
- `FALLA`: algo salió distinto de la regla (está en `fallos`). NO se aplica.

El portal (Pagos) puede publicarse antes o después: si la lectura del motivo aún no existe,
muestra el texto genérico de siempre.

## Reglas que no se tocan

- El bloqueo no se relaja ni tiene atajos. Con dos o más cuentas posibles no se elige.
- No se inventan cuentas, no se convierte moneda y una cuenta inactiva nunca sirve para un vínculo nuevo.
- Los mensajes no llevan número de cuenta, CCI ni documentos, y el detalle solo se le dice a quien
  puede registrar pagos.
- La carga NO sella con esa cuenta las cuotas que el contrato ya tenía pagadas antes de su
  vínculo: se pagaron antes de que existiera y sería inventar un hecho. (Ojo, comportamiento que ya
  existía: si más adelante se corrige la FECHA de una de esas cuotas, el sello de pagos la marca
  como «inferido» en la cuenta vinculada, y desde ese momento `reversa.sql` se niega.)

## Límites conocidos

- Tras `reversa-solo-codigo.sql`, los vínculos de la carga siguen vivos; `reversa.sql` todavía
  puede borrarlos mientras no se hayan usado.
- Los vínculos creados después con `vincular-rezago.sql` llevan otra marca y `reversa.sql` no los
  toca: si uno resultara equivocado antes de usarse, se prepara su borrado aparte; si ya se usó,
  se corrige con «Cambiar cuenta de pago».
- `supabase/scripts/p0xx/rollback-s1-data.sql` (solo para ramas) no filtra por marca: no se usa
  en producción.

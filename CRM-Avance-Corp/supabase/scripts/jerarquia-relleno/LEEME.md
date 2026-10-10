# Facturación fase 5: relleno de jerarquía de Carmen Jaramillo y Jorge Marzano

**Estado (10/10/2026):** **APLICADA en producción y registrada** (~11:00 Lima, md5 del texto `00fb0e49…`) y comprobada
después. Aprobada por Miguel el 10/10 viendo el cambio mes a mes.

## Qué arregla

Facturación pone a cada venta el «supervisor de entonces» leyendo solo los eventos `jerarquia_actualizada`. El
29/08/2026 12:56:38 (Lima) el bloque `$normalizar_directorio$` de `20260828210351` movió a estos dos supervisores de
CARLOS VALLES a ADMINISTRADOR AVANCE CORP sin dejar evento, así que Facturación seguía atribuyendo a Carlos sus ventas
desde el 10/08. La migración `20261010150451_crm_jerarquia_relleno_carmen_jorge.sql` anota esos dos eventos con la
hora, el antes y el después que guarda `public.audit_log` (autor «sistema» de la fase 2, `via: 'relleno'`, id de la fila
de auditoría como prueba).

**Efecto aprobado:** Carmen, nada; Jorge, 9 ventas pasan de Carlos a Administrador (septiembre 4 × S/ 1,271,900 +
1 × US$ 27,000; octubre 3 × S/ 213,600 + 1 × US$ 20,000). Totales de la empresa, agosto (sellado) y lo que ve cada
supervisor: iguales. Solo Facturación lee estos eventos; la foto del sello no.

## Archivos

- `medir-relleno.sql`: medición de SOLO LECTURA (derivas, auditoría y simulación del cambio validada contra la función
  viva operación por operación). Sirve también para comprobar después de aplicar.
- `generar.py`: escribe `ensayo-produccion.sql` (la migración + una línea; acaba siempre en error) y `registrar.sql`
  (texto exacto de la migración). `--verificar` no escribe.
- `reversa.sql`: borra los dos eventos por su idempotencia fija; idempotente y se niega ante un estado distinto.
- `banco-prueba.py`: monta la misma situación con personas del banco y corre 14 casos, cada uno deshecho.

## Guardas de la migración

Se niega si cambió la lógica de Facturación (huellas), si el rastro de auditoría o la jerarquía de hoy ya no son los
medidos, o si hay un relleno a medias. Oráculo en la misma transacción (REPEATABLE READ): Facturación entera antes y
después; solo pueden cambiar ventas de los dos desde el día del cambio, de Carlos a Administrador, todas ellas, y lo
fechado antes del 10/10 tiene que ser exactamente lo aprobado. Una base sin estas personas ni su rastro no recibe nada.
Candados ANTES de la instantánea (Codex r1): `crm.equipo` en SHARE y `crm.usuario_eventos` en SHARE ROW EXCLUSIVE, así
que ningún cambio de jerarquía ni evento entra entre la validación y el commit. Una venta confirmada en esos ~250 ms
no se frena: sigue la misma regla (si es de ellos desde el 29/08, va con Administrador, lo correcto).

## Producción (Miguel con `!`, desde `CRM-Avance-Corp/`, con la ruta absoluta a este worktree)

1. `supabase db query --linked -f <worktree>/CRM-Avance-Corp/supabase/scripts/jerarquia-relleno/ensayo-produccion.sql`
   → el error «ENSAYO RELLENO PASS … SE DESHACE TODO» es el resultado correcto.
2. `supabase db query --linked -f <worktree>/CRM-Avance-Corp/supabase/migrations/20261010150451_crm_jerarquia_relleno_carmen_jorge.sql`
3. `supabase db query --linked -f <worktree>/CRM-Avance-Corp/supabase/scripts/jerarquia-relleno/registrar.sql`
4. Comprobación (solo lectura): `medir-relleno.sql` ya no lista a Carmen ni a Jorge.

Si algo corta entre el paso 2 y el 3: repetir la migración dice «ya aplicado» y `registrar.sql` se puede repetir.

## Verificación (10/10/2026, PRIMARY)

- Medición en producción 09:51: réplica 821/821 sin discrepancias; 0 ventas entre el 10/08 10:44 y el 29/08 12:56.
- Banco Docker (stack fact0c, huellas = producción): `banco-prueba.py` 14/14 PASS (bueno y repetición, ensayo, base
  vacía, seis negativas, reversa y dos negativas suyas, concurrencia con candados y su mutante sin candados).
- Codex r1 (`docs/encargos/2026-10-10-codex-relleno-jerarquia-fase5.md`): CHANGES_REQUESTED sin P0/P1. Aceptados los
  dos P2: la reversa valida TODOS los campos que deciden la atribución, bloquea las filas y comprueba que borra 2; la
  migración bloquea `crm.equipo` y `crm.usuario_eventos` antes de la instantánea. También el registro exige los dos
  eventos exactos y la guarda del oráculo usa `is not true` (un NULL no se cuela). La concurrencia de ventas se delimita
  (arriba) en vez de bloquear tablas del portal.
- Ensayo en producción con el texto final: «ENSAYO RELLENO PASS: 9 operaciones de 821 pasan de supervisor (aprobado:
  …); nuevas desde el 2026-10-10: 0; 226 ms — SE DESHACE TODO». Después, 0 eventos con `via = 'relleno'`.

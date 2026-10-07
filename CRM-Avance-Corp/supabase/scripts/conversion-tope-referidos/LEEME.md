# Tope de referidos (migración 20261007160937)

Regla: desde octubre de 2026 los referidos de un analista cuentan como máximo el 15 % (hacia arriba) de sus cierres de LEADS ASIGNADOS POR EL SISTEMA (origen landing o formulario, y que no sea registro manual: `alta_manual`) en el mes; el exceso, los más recientes, vale 0. La base no incluye referidos, renovaciones, upgrades, base cargada ni altas manuales (el alta manual sí suma entera al numerador: regla cerrada del registro manual); sin cierres asignados el tope es 0. Los orígenes de la base salen de `private.conversion_origen_base_tope(text)`.

Banco propio y todo lo que acredita la migración. Nunca contra producción.

| Archivo | Qué hace |
|---|---|
| `prueba-tope.sql` | El núcleo: 15 asignados + 5 referidos ⇒ cuentan 3, el ejemplo aprobado por Miguel (10 asignados + 4 referidos + 3 renovaciones + 2 upgrades + 1 de base cargada ⇒ tope 2), renovaciones, upgrades, base cargada, alta manual (sigue sumando 1) y referidos que NO suben el tope, base 0 ⇒ tope 0, ámbito {A,B} = {A}, cierres sin analista con un solo tope, septiembre sin tope e idéntico a la función anterior, redondeos y bordes, rango parcial y ámbito, anulaciones, divisor intacto. Termina en `rollback`. |
| `prueba-sello-deuda.sql` | El sello (`incluida_en_sello` solo para los referidos que cuentan) y la deuda (anular uno que contaba cobra 1; uno fuera del tope, nada; un mes sin tope, 0,15). |
| `mutantes.py <contenedor>` | 25 mutantes (núcleo, función de orígenes de la base y sello); cada uno debe romper una prueba (T3/T4 los rechaza la base misma, con una restricción). M8a/M8b sobreviven a propósito (defensa duplicada); el doble cae. Un mutante con SQL inválido aborta la corrida. |
| `anterior-episodios.sql` | La función ANTERIOR (texto vivo del 07/10/2026) como `pg_temp`: la vara de la igualdad. |
| `medir-costo.sql` | Costo con 6.000 cierres, función anterior contra la nueva. |
| `reversa.sql` | Revierte la migración (se niega si un mes sellado guarda un tope). |
| `mundo-fase-b.sql` · `snapshot-fase-b.sql` | FASE B (migración 20261007203000): un mundo sintético determinista y la instantánea de lo que publican las seis funciones; se corre antes y después y se comparan (septiembre idéntico). |
| `prueba-origen.sql` · `anterior-origen.sql` | FASE B: origen, foto en vivo, cifra oficial abierta y sellada (con `crm.cerrar_periodo` real), fuera de roster. |
| `mutantes-fase-b.py <contenedor>` | 17 mutantes de las funciones de la Fase B; todos deben caer. |
| `medir-costo-origen.sql` | Costo del ranking por origen, antes y después. |
| `reversa-fase-b.sql` | Revierte SOLO la Fase B (se niega si una foto sellada ya guarda `aporte` o un tope). |

```bash
# 1 · volcado de solo esquema de producción (sin datos), desde CRM-Avance-Corp/
supabase db dump --linked --schema public,crm,private --keep-comments -f /ruta/esquema.sql
# 2 · banco propio (supabase/scripts/potencial-lead/banco/montar-banco.sh), y sembrar la CONFIGURACIÓN de producción:
#     las tres tablas del censo analítico, crm.conversion_pesos (1 fila) y crm.conversion_politica (1 fila).
# 3 · aplicar y probar
psql -v ON_ERROR_STOP=1 -f ../../migrations/20261007160937_crm_conversion_tope_referidos.sql   # SIEMPRE con ON_ERROR_STOP (o por `db query --file`, que va en un mensaje)
psql -v ON_ERROR_STOP=1 -f prueba-tope.sql ; psql -v ON_ERROR_STOP=1 -f prueba-sello-deuda.sql ; python3 -I mutantes.py <contenedor>
```

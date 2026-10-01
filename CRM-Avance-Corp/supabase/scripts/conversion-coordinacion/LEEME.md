# Conversión por analista para Coordinación — oráculo y orden de aplicación

Pieza: migración `20260930185623_crm_conversion_divisor_coordinacion` (núcleos
`private.conversion_divisor_empresa(date)` y `private.conversion_divisor_empresa_totales(date)`
+ puerta `crm.conversion_divisor_coordinacion_fn(date)`, que no lee tablas), pestaña
«Conversiones» de `#/repartir`.

## Por qué existe

La coordinadora veía en «Supervisión → analistas» el reporte de ENTREGAS
(`crm.reporte_derivaciones_coordinacion_fn`), que cuenta por fecha de entrega y deja
de sumar, a propósito, la entrega devuelta a la misma bandeja antes de gestionar (el
lead queda en quien lo recibió después). Ese número no es el divisor de conversión:
el núcleo cuenta una llegada por lead, por su alta original en Lima, en el PRIMER
analista asignado, y no se la resta al reasignar. Setiembre 2026: Astrid 62 en el
reporte contra 65 del núcleo por tres leads parqueados y re-entregados.

Decisión de Miguel (30/09/2026): el reporte de entregas no cambia; Coordinación lee
el divisor real del núcleo por una puerta nueva, con ámbito de toda la empresa.

## Qué prueba `oraculo-divisor-coordinacion.sql`

Transaccional (termina en `rollback`), con un mundo sintético que siembra aquí mismo:
estructura y ACL, candado de dispersión (ninguna de las dos funciones lee `crm.leads`
ni `crm.lead_asignaciones`), autorización por rol (coordinador y gerencia entran;
vendedor, supervisor, directorio, coordinador inactivo y anónimo → 42501 antes que
22023), período (futuro y día distinto del 1 → 22023), la regla del divisor recorriendo
las puertas REALES del reparto (turno → repartir → derivar → devolver → derivar: A→B y
A→B→A cuentan una vez en A y no suben a B; alta manual 0; referido 0; sin asignar cuenta
en la empresa; alta a las 23:30 del último día del mes anterior queda en ese mes),
paridad fila a fila con `private.conversion_neta_por_vendedor`, gerencia recibe el
mismo payload, contraste con el reporte de entregas (allí B suma), mes sellado (foto,
desglose por origen en null, el núcleo vivo rechaza recalcular) y huellas md5 del núcleo
y de los conteos operativos al 30/09/2026.

Mutantes cazados el 30/09 (original restaurado después): contar por dueño actual (E01d),
atribuir al último receptor (E01d), duplicar formulario (E04c), numerador +1 (E05a).
E07 cubre además `fuera_ranking` poblado, una foto con `conversion_sin_analista: null` y (E07f)
que la empresa sellada coincide con el `total` de la puerta mensual oficial bajo gerencia.

## Cómo correrlo (banco Docker con el esquema de prod, nunca producción)

```bash
# banco: dump de prod cargado + configuración (crm.conversion_pesos, políticas SLA, meta_periodos)
docker exec -i <banco> psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q \
  -c "$(cat supabase/migrations/20260930185623_crm_conversion_divisor_coordinacion.sql)"
docker exec -i <banco> psql -U postgres -d postgres -v ON_ERROR_STOP=1 -q \
  -f - < supabase/scripts/conversion-coordinacion/oraculo-divisor-coordinacion.sql
# esperado: ORACULO-DIVISOR-COORDINACION-OK y cero filas c0000000-/c1000000- después
```

El lead «de borde» se siembra con el guard de tenencia apagado para UNA sentencia
(el servidor sella `creado_en` con su reloj; no hay otra forma de tener un alta del
mes anterior). Solo en banco.

## Orden de aplicación en producción (lo lanza Miguel con `!`)

1. `supabase db query --linked --file supabase/migrations/20260930185623_crm_conversion_divisor_coordinacion.sql`
   (un solo mensaje; trae preflight, funciones y postflight de paridad con el núcleo).
2. `supabase db query --linked --file supabase/scripts/registrar-20260930185623.sql`
   → `REGISTRO_CONVERSION_DIVISOR_COORDINACION_OK` con las dos huellas.
3. Advisors de seguridad/rendimiento: el único aviso esperado es el SECURITY DEFINER
   ejecutable por `authenticated`, protegido por el gate dentro de la puerta (mismo
   patrón que el reporte de Coordinación).
4. Publicar el front (`/release-crm`): la pestaña «Conversiones» llama a la puerta y,
   mientras no exista en prod, muestra el error de la RPC con reintento (no rompe el resto).

Reversa: `drop function crm.conversion_divisor_coordinacion_fn(date); drop function
private.conversion_divisor_empresa_totales(date); drop function private.conversion_divisor_empresa(date);`
y borrar la versión del registro.

## v2 (30/09/2026 tarde): desglose de cierres y rango de fechas — `20260930221500`

Miguel pidió, ya con la v1 publicada, (a) ver de dónde salen los cierres y (b) consultar
por rango de fechas. La migración `20260930221500_crm_conversion_coordinacion_desglose_cierres`
acredita por md5 los tres cuerpos vivos de la v1 y los redefine (DROP + CREATE: cambian
firma y tipo de retorno) con un cuarto núcleo pequeño:

- `private.conversion_divisor_base(desde, hasta)`: elige la pieza del núcleo según el modo
  (mes exacto → `conversion_neta_por_vendedor`, con ajuste; rango → `conversion_mensual_por_vendedor`
  en vivo, peso del referido del mes de `hasta`, como la puerta de Gerencia).
- `private.conversion_divisor_empresa(desde, hasta)`: fila por analista con llegadas por origen y,
  nuevo, cierres por origen (formulario, landing, referido con aporte, oficina sin peso) y cartera
  (upgrade, renovación con aporte), bruto y ajuste. Mes sellado → foto (`origenes_ranking.filas` y
  `cartera` con los pesos sellados; bruto/ajuste en null; `desglose_disponible` dice si la foto lo trae).
- `private.conversion_divisor_empresa_totales(desde, hasta)`: totales de la empresa y sin analista.
- `crm.conversion_divisor_coordinacion_fn(p_periodo, p_desde, p_hasta)`: sin argumentos = mes vigente;
  `p_periodo` = ese mes; `p_desde` + `p_hasta` = rango inclusivo (Lima), ≤ 366 días, sin futuro; un mes
  calendario exacto se trata como mes; mes y rango a la vez → 22023.

Invariantes que exige el postflight sobre datos reales: partes (formulario + landing + referido×peso +
upgrade + renovación×peso) = numerador bruto; neto = `conversion_con_ajuste(bruto, ajuste)`; conteos
iguales a los del núcleo; y el rango «1 → hoy» reproduce el mes vigente. El oráculo añade E05f/g y E09
(rango exacto = mes, 1 → hoy, rango que termina ayer, mes sellado por rango, 22023 para rangos
inválidos, 42501 para un vendedor en modo rango).

Orden de aplicación (Miguel con `!`): `db query --linked --file` de `20260930221500…sql` →
`scripts/registrar-20260930221500.sql` (→ `REGISTRO_CONVERSION_DESGLOSE_OK` con cuatro huellas) →
advisors → front por `/release-crm` (el front v2 exige las claves nuevas; publicar SQL antes que front).

Reversa: `drop` de las cuatro funciones nuevas, volver a aplicar los tres `create function` de
`20260930185623` y borrar la versión `20260930221500` del registro.

### v2b (tras las revisiones del 30/09 noche)

- El oráculo ya no depende del día: E09a usa el mes ANTERIOR como rango exacto; E09b compara el
  bruto y exige ajuste 0 solo cuando de verdad es rango; E09b2 (15 del mes anterior → hoy) afirma la
  invariante en un rango REAL y la aditividad del divisor; E09b3 declara el cruce con un mes sellado.
- E07 siembra la foto sellada CON desglose (`origenes_ranking.disponible = true`, `cartera` con
  `operaciones_* ≠ conversiones_*`) para cazar la confusión de claves; la siembra apaga el trigger
  `trg_cierre_mes_vendedor_10_ranking_origen` solo durante ese `insert` (recalcularía sobre datos
  vivos que no existen).
- El registrador acredita las cuatro huellas vivas (`md5(prosrc)`) contra las del artefacto probado
  en el banco antes de registrar: puerta `b881b83ca8d4dd2f0f081d736828c8c5`, base
  `0a43b0f3b56026bd2c5bfa4a9d8942d9`, empresa `5700d2770d1796440aa0184b035d623a`, totales
  `e97995f5ffd9109fce87f2e5dafb11a6`. Si en prod difieren, NO registra: averiguar por qué antes.
- E09 exige el mes vigente y el anterior ABIERTOS en el banco (lo comprueba por el payload y
  aborta con mensaje claro): el oráculo es un mundo de fixtures; si el banco trae un mes real
  sellado, rehacerlo desde el dump de esquema.
- Payload: `cierres.otros`, `periodo.cruza_meses_sellados`, `fuente.modo`. La rama sellada lee
  `cartera.conversiones_*` (nunca `operaciones_*`).


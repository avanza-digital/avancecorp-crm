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

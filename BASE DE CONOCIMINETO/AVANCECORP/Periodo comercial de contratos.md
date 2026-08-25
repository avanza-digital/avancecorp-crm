---
tags: [crm, contratos, capital, cierre-comercial, produccion]
actualizado: 2026-08-24
estado: implementado-en-produccion
---

# Periodo comercial de contratos

## Problema

Durante la carga inicial del CRM se registraron en agosto contratos cerrados
comercialmente en meses anteriores. El servidor usaba `creado_en`, la fecha
técnica de carga, y por eso acreditaba esos contratos al mes equivocado.

## Decisión comercial

El contrato pertenece al mes de su cierre comercial, no necesariamente al mes
en que fue registrado en el CRM. La regla es universal para cualquier mes; no
es una excepción para julio.

`creado_en` se conserva como auditoría técnica y `fecha_inicio` sigue siendo el
inicio del plazo contractual. Ninguna de las dos columnas fue reescrita.

## Implementación vigente desde el 2026-08-24

- `public.contratos.fecha_cierre_comercial date not null` decide el período.
- `fuente_cierre_comercial` distingue `migracion_inferida`,
  `fecha_inicio_inferida`, `registro` y `correccion_manual`.
- El histórico se inicializó con la mejor evidencia disponible del sistema
  nuevo: `least(fecha_inicio, día de registro en America/Lima)`. La fuente
  `migracion_inferida` deja claro que no es una firma histórica reconstruida.
- En un alta nueva, el servidor usa `fecha_inicio` si la carga llegó tarde; en
  caso contrario usa el día de registro en Lima. El cliente no puede imponer
  una fecha comercial durante el INSERT.
- Una corrección posterior solo puede hacerla Gerencia con
  `crm.corregir_fecha_cierre_comercial(contrato, fecha, motivo)`. Exige motivo,
  rechaza fechas futuras y deja auditoría antes/después.
- No se puede insertar ni mover un contrato hacia o desde un mes ya sellado.
  Altas, correcciones y [[Cierre de mes]] comparten candados para evitar
  carreras.

## Consumidores del dato

Usan `fecha_cierre_comercial`:

- `private.produccion_mes_por_vendedor`, fuente de cumplimiento de metas y del
  sello mensual.
- `crm.metricas_capital_mes_fn`.
- Las ventanas de capital/contratos de
  `private.metricas_conversiones_implementacion`.
- `public.metricas_directorio`.
- `crm.contratos_por_periodo_comercial_fn(periodo)`, reporte de Gerencia y
  Directorio que funciona incluso si el mes no tiene metas publicadas.

No cambiaron el cronograma, PDF, plazo, `cerrado_en`, cierres externos,
causalidad de anulaciones ni la cohorte de conversión de leads. La RPC mensual
global tampoco inventa un vendedor cuando no existe un snapshot de metas.

## Resultado productivo verificado

Después del despliegue hay 438 contratos y los 438 históricos están marcados
como `migracion_inferida`; cero incumplen la fórmula de backfill. En total, 142
contratos cambiaron de mes frente a su fecha técnica de registro.

| Período | Contratos | Movidos desde registro | Capital PEN | Capital USD |
|---|---:|---:|---:|---:|
| 2026-01 | 3 | 3 | 120,000.00 | 0.00 |
| 2026-02 | 6 | 6 | 231,600.00 | 0.00 |
| 2026-03 | 8 | 8 | 496,400.00 | 0.00 |
| 2026-04 | 11 | 11 | 385,000.00 | 1,000.00 |
| 2026-05 | 21 | 20 | 774,450.00 | 38,867.00 |
| 2026-06 | 108 | 40 | 6,507,494.40 | 107,933.00 |
| 2026-07 | 182 | 54 | 5,042,473.72 | 390,400.00 |
| 2026-08 | 99 | 0 | 3,377,095.00 | 398,310.00 |

Julio tiene cero revisiones de metas y, aun así, la RPC devuelve sus 182
contratos y totales. No había meses sellados al migrar.

Durante la ventana de despliegue se eliminó mediante el flujo normal un
contrato de USD 20,000. `audit_log` registró el DELETE a las 17:38:28 UTC; por
eso el total vivo bajó de 439 a 438 y agosto de 100 a 99. No fue efecto de la
migración, que no contiene borrados.

## Validación y operación

- Migración local: `20260824170630_crm_periodo_comercial_contratos.sql`.
- Versión registrada en producción: `20260824174020`.
- Gate productivo: `PERIODO_COMERCIAL_CONTRATOS_OK`.
- Advisors posteriores: cero errores. Las dos RPC aparecen en el aviso estándar
  de funciones `SECURITY DEFINER` para usuarios autenticados; `anon` está
  revocado y los gates internos de rol fueron ejecutados.

El histórico inferido queda listo para revisión comercial. Si Gerencia conoce
una fecha más precisa, debe usar la RPC con motivo; no debe editar la columna de
forma directa.

Relacionado: [[Cierre de mes]] · [[Conversion mensual - definicion cerrada]] ·
[[Configuración operativa CRM 2026-08-07]] · [[Ciclo de vida de contratos]].

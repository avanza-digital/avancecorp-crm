# Conversión · recuperar cinco ventas perdidas al borrar y recargar el contrato (2026-10-18)

**Decisión de Miguel (17/10/2026):** las ventas que dejaron de contar porque alguien borró el contrato y lo volvió a cargar
**sí deben contar**: «esas ventas precisas hay que arreglar», «ármalo con los cinco». Es una excepción autorizada, por fila
exacta, a [[Conversión - la anulación es la única puerta]]: la anulación no se borra, queda **rehabilitada**.

## Los cinco
| Lead | Analista | Mes | Qué pasó | Qué hace la corrección |
|---|---|---|---|---|
| Julio César Núñez | Astrid | oct | contrato borrado y recargado (001560) | re-apuntar la venta al contrato vivo (referido) |
| Nancy Atuncar | Nayra | oct | recargado 001510 con fecha 30/09 | fecha comercial al 01/10 y re-apuntar (referido) |
| María Aurora Ccance | Vladimir Jurado | oct | «Eliminar inversión» la anuló | rehabilitar la anulación y re-apuntar |
| Víctor Arango | Adelayda | oct | anulada; estaba como upgrade | pasado a «nuevo» (17/10); rehabilitar y re-apuntar |
| José Pedro Mejía | Linda | **sep** | recargado 001536 con fecha 06/10, como upgrade | pasado a «nuevo»; fecha al 30/09 y re-apuntar. **Plazo: 22/10 00:00** |

## Cómo (migración `20261018032400`, v3)
- Tabla `crm.conversion_ventas_recuperadas`: una fila por venta, solo inserción, sin API, con el respaldo.
- Cuatro funciones dejan de tratar ESA anulación como vigente: `cierre_anulado` (métrica), `cierres_estado_fn` (chip
  «CIERRE ANULADO»), `altas_nuevas_por_analista_fn` («Altas nuevas») y `anular_cierre_avance` (no se vuelve a anular:
  «Esta venta se anuló y después se recuperó…»). Si la inversión de esas dos cambia, se usa «Reemplazar inversión».
- Las fechas comerciales de Nancy y José Pedro cambian en `public.contratos` (OK de Miguel): 10 000 PEN pasan de
  septiembre a octubre y 353 000 PEN de octubre a septiembre.

## Lo que se aprendió
- **El tope de referidos reparte, no suma.** Desde octubre un referido pesa 1 y el tope es 15 %: la métrica reparte
  n × 15 % entre los n referidos del analista en orden de fecha. Recuperar un referido mueve el aporte individual de los
  otros y el suyo puede quedar en 0; lo que sube exactamente una cuota (0,15) es la **suma del analista**. Toda
  comprobación «nada más cambió» debe comparar la suma, no el aporte por lead (hallazgo de Codex, 18/10).
- La nota en la línea de tiempo del lead exige correr **sin sesión de usuario** (`db query --linked`), por el trigger de
  atribución de `crm.actividades`.
- Una venta que vuelve a septiembre queda antes de la política de valoración del capital (01/10): conserva su
  valoración histórica y el capital del mes se mueve igual.

Estado: **EN PRODUCCIÓN desde la noche del 17/10/2026** (Miguel la aplicó con «!»; comprobación `APTA`). Probada antes en el banco (58 bloques, 50 mutantes) y revisada por Codex. Efecto: Astrid y Nayra +0,15 en octubre (el reparto individual de sus referidos se movió por el tope), Jurado y Adelayda +1 en octubre, Linda +1 en septiembre. Kit en
`CRM-Avance-Corp/supabase/scripts/recuperar-ventas-recargadas/` (LEEME). Relacionado: [[Reemplazar inversion - plan por fases (2026-10-17)]].

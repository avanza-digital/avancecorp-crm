# Unificar las 12 puertas de la conversión

**Estado:** pendiente · **Fecha límite:** antes de sellar un mes · **Escrito:** 21/09/2026

---

## El problema, en una frase

La tabla es una. El núcleo es uno. **Las puertas son doce**, y cada una le
pregunta al núcleo a su manera.

```
TABLA      crm.lead_asignaciones + crm.leads + crm.operaciones_cartera   ✅ una
NÚCLEO     private.conversion_episodios                                  ✅ uno
PUERTA     ❌ DOCE, cada una con su propia aritmética encima
PANTALLA   consume esas doce
```

Hoy todas dan el mismo número **por casualidad**: no hay ningún mes sellado ni
deuda de anulación viajando entre meses. El día que selles, la mensual servirá la
foto y el rango seguirá recalculando en vivo. Dos porcentajes del mismo mes, uno
encima del otro, sin que nada diga cuál manda.

## Lo que ya funciona: el patrón a copiar

**Dos puertas ya lo hacen bien y están en producción:**

- `crm.metricas_vendedores_fn` → llama a `crm.conversion_mensual_fn` y **reenvía**
- `crm.cierre_mes_estado_fn` → igual

No recalculan nada. Por eso la conversión de un analista sale idéntica en las dos
pantallas que la publican. **Unificar no es inventar: es extender a las otras diez
lo que estas dos ya hacen.**

## Inventario de las doce

| # | Puerta | Qué sirve | Hoy | Ola |
|---|---|---|---|---|
| 1 | `crm.conversion_mensual_fn` | **LA definición** (foto si sellado, neto de ajustes) | ✅ es la fuente | — |
| 2 | `crm.metricas_vendedores_fn` | Gestión de equipo, Directorio | ✅ delega | — |
| 3 | `crm.cierre_mes_estado_fn` | Estado del cierre | ✅ delega | — |
| 4 | `crm.metricas_conversiones_fn` | **Resumen y Conversiones** (el número grande) | ❌ recalcula | **1** |
| 5 | `crm.metricas_distribucion_leads_v3_fn` | Distribución / Rendimiento inferior | ❌ recalcula | **1** |
| 6 | `crm.metricas_conversiones_equipo_fn` | Ranking · pestaña Cosecha | ❌ recalcula | **1** |
| 7 | `crm.cumplimiento_metas_fn` | Metas | ❌ recalcula | 2 |
| 8 | `crm.cumplimiento_metas_sin_cartera_fn` | Metas (variante) | ❌ recalcula | 2 |
| 9 | `crm.series_comerciales_fn` | Series del histórico | ❌ recalcula | 2 |
| 10 | `crm.metricas_multiempresa_fn` | Multiempresa | ❌ recalcula | 3 |
| 11 | `crm.resumen_cartera_fn` | Resumen de cartera | ❌ recalcula | 3 |
| 12 | `crm.cerrar_periodo` | El motor del sello | ❌ recalcula | 3 |

## La regla que decidió Miguel (21/09)

> **Mes completo = la cifra oficial. Rango parcial, calculado y rotulado.**

- Rango = mes calendario completo **y sin filtro de fuente** → el bloque del
  núcleo se pide a `crm.conversion_mensual_fn`. Misma cifra que Ranking y Metas,
  con foto sellada y el descuento por anulaciones ya aplicado.
- Cualquier otro caso (rango parcial, varios meses, filtro de fuente activo) →
  sigue calculando en vivo, y el paquete lo **declara**.

Para el mes vigente, «mes completo» significa del día 1 a hoy — que es
exactamente lo que ya hace `periodoMesCalendario` en el front.

## Contrato nuevo del paquete

Cada puerta unificada añade a su bloque de núcleo:

| Clave | Tipo | Significado |
|---|---|---|
| `es_mes_calendario` | bool | el rango coincide con un mes completo |
| `fuente` | `'mensual'` \| `'rango_vivo'` | de dónde salió la cifra |
| `sellado` | bool \| null | el mes está sellado (null si no se delegó) |
| `ajuste_aplicado` | bool | se restó la deuda por anulaciones |

Y a sus sondas:

| Clave | Significado |
|---|---|
| `mensual_comparada` | se contrastó contra la mensual |
| `paridad_mensual` | numerador vivo − numerador mensual |

**Son claves NUEVAS en la respuesta** ⇒ por la regla de la casa, **el front va
primero** (tolerando su ausencia), y el servidor después.

## Dónde se interviene

**En los envoltorios cortos, NO en la implementación de 38 KB.**

- `crm.metricas_conversiones_fn` es de 473 bytes: valida el rol y delega en
  `private.metricas_conversiones_implementacion`. Ahí se intercala la decisión.
- `crm.metricas_distribucion_leads_v3_fn` es de 3 269 bytes: recorta claves de
  SLA. Mismo sitio.

Eso reduce el riesgo a una fracción: el motor no se toca.

⚠️ **Las tres funciones de distribución las posee `crm_metricas_bridge`, no
`postgres`.** Cualquier `create or replace` debe conservar ese propietario, y el
postflight tiene que exigirlo.

---

## Ola 1 — lo que ve gerencia (la que tiene fecha límite)

**Puertas 4, 5 y 6.** Son las que publican el número grande y las únicas que hoy
pueden discrepar de Ranking y Metas.

### Paso 1 · Foto de referencia
`supabase/scripts/conversion/foto.sql` contra producción. Guardar divisor,
numerador, pct por los cuatro caminos y las filas de analistas.

### Paso 2 · Front primero
Tolerar las seis claves nuevas como opcionales en:
`lib/metricas-conversiones.ts`, `lib/metricas-distribucion.ts`,
`lib/metricas-conversiones-equipo.ts`. Tests: con las claves y sin ellas, el
mapeo no cambia. **Publicar y comprobar el `buildId` vivo.**

### Paso 3 · Servidor
Una migración por puerta, cada una con:
- Preflight con la huella del cuerpo vivo (`f6e43674…` para la 4,
  `ddfc3648…` para la 5).
- La rama de delegación + las seis claves.
- Postflight: huella candidata, propietario, ACL, y que las claves viajen.
- Declaración en el trinquete refrescada si la función está censada.

### Paso 4 · Rótulos
El número grande dice qué es: «Índice comercial de septiembre» cuando delega,
«Recálculo del 1 al 21 — no es la cifra del mes» cuando no.

### Paso 5 · Gates
- Banco Docker (receta en `MIGRACIONES.md`): las tres aplican en verde.
- **`gate:conversion` antes y después: ni un número movido.**
- **`crm.alarma_conversion_fn` sigue en `cuadra: true`.**
- Mutante: forzar `es_mes_calendario` a false con rango = mes y comprobar que la
  alarma lo caza.
- `auditor-rls` sobre cada migración.
- `npm run check` + advisors.

**Riesgo:** alto (toca lo que ve gerencia). **Valor:** una sola definición del
mes en todo el CRM, y el día del sello ya no aparecen dos verdades.

---

## Ola 2 — metas y series

**Puertas 7, 8 y 9.** Mismo patrón. Menor riesgo: Metas ya bebe de la mensual por
transitividad; lo que falta es que lo **declare** en su paquete.

Cuidado con `series_comerciales_fn`: publica a propósito **dos** cifras —
`conversion_mensual_pct` (del núcleo) y `conversion_cohorte_pct` (el bruto por mes
de entrada, decisión de Miguel del 27/08). **No se unifican: se rotulan.**

---

## Ola 3 — el resto

**Puertas 10, 11 y 12.**

- `metricas_multiempresa_fn` y `resumen_cartera_fn`: consumen el núcleo para otras
  preguntas. Probablemente solo necesitan declarar su fuente.
- **`crm.cerrar_periodo` es el caso delicado:** es quien ESCRIBE la foto. Aquí se
  arreglan de paso dos hallazgos confirmados de la auditoría del 21/09:
  - **C6:** la foto escribe `cierres_sin_episodio: 0` como literal en vez de la
    medida real → un mes puede sellarse con la sonda en rojo y salir en verde
    para siempre.
  - **C3 (cierre):** al sellar no se guarda la sonda. Debería guardar el veredicto
    de `crm.alarma_conversion_fn` junto a la foto.

**Ojo:** hoy `crm.periodos_cerrados` está VACÍO y nunca se ha escrito una foto.
Se puede arreglar **antes** de que exista la primera. Es la mejor ventana y no
se repite.

---

## Qué NO entra en este plan

- **Los pesos y las reglas de negocio no se tocan.** Referido 0,15, cartera 1,
  oficina 0, y el registro manual sumando arriba sin sumar abajo: todo decidido
  por Miguel y **cerrado**.
- Los rótulos y ceros fabricados del portal admin: trabajo aparte.
- Citas: ya tiene su testigo desde el 21/09.

## Cómo se sabrá que está hecho

1. `crm.alarma_conversion_fn` sigue en `cuadra: true` después de cada ola.
2. Con un mes sellado, Resumen y Conversiones sirven **la foto**, no un recálculo.
3. Ninguna pantalla divide.
4. `gate:conversion` en VERDE y sin un solo número movido.

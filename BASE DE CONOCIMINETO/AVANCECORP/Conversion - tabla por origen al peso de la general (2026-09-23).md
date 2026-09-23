---
tags: [crm, conversion, gerencia, origenes, capas, produccion]
fecha: 2026-09-23
estado: servidor en produccion; pantalla al publicar el front
---

# Conversión: la tabla por origen pesa como la general

**✅ SERVIDOR EN PRODUCCIÓN desde el 23/09/2026.** Migración
`20260923185001_crm_origenes_conversion_ponderada`, aplicada por Miguel con `!`.
**Pantalla:** PR #81 fusionada (`9a2c3504`); se ve cuando se publique el front con `/release-crm`.

## La decisión (Miguel, 23/09)

«Poner en la tabla la cifra al 15 %» y «el servidor siempre que haga todo». La tabla
«Resultados por origen» de gerencia mostraba contratos ÷ leads en bruto. Un cierre por referido
cuenta ×0,15 en la conversión general, así que las dos cifras no se podían comparar.

## Qué cambia en pantalla

| Origen | Antes | Ahora |
|---|---|---|
| Formulario | 3,1 % | 3,1 % (peso 1) |
| Landing | 1,6 % | 1,6 % (peso 1) |
| Referido | 72,7 % | **10,9 %** (peso 0,15) |

Cifras de septiembre medidas en producción tras aplicar. Referido no «cayó»: ahora cada cierre
pesa lo mismo que en la conversión general. El rótulo lo explica («cada cierre cuenta ×0,15, como en
la conversión general»).

## Cómo quedaron las capas (tabla → núcleo → puerta → pantalla)

| Capa | Qué hay |
|---|---|
| Tabla | Nada nuevo. El peso sale de `crm.conversion_pesos`, como en la general. |
| Núcleo | `private.metricas_conversiones_implementacion` añade `conversion_ponderada_pct` a cada fila de `origenes`: `100 × contratos × peso ÷ leads`, redondeado a 1 decimal. Queda vacía si el origen no tiene leads. |
| Puerta | Firma y permisos sin cambios. El paquete trae **una clave más**: se añade y no sustituye nada (`conversion_contratos_pct` sigue igual). |
| Pantalla | `resumen-gerencia.tsx` muestra la cifra tal como llega. Si un servidor viejo no manda la clave, vuelve a la cifra de siempre con el rótulo «No es la conversión ponderada». |

## Cómo se probó

- Ensayo en producción: un solo bloque `DO` que termina en `raise`, en REPEATABLE READ. Se
  compararon 112 respuestas por caso, rol e identidad, y la única diferencia fue la clave nueva. En
  READ COMMITTED dio una falsa diferencia por la actividad real del momento.
- Después de aplicar: trinquete `OK`, `metas-vs-oficial.sql` PASS y ningún aviso nuevo en los
  advisors de seguridad.
- Huellas vigentes: función `6e4fedb3d6f9ba485ece9afeb322b491`, censo `315549aa87482ba7ecc9148d53b78f1f`.
  **Quien vuelva a tocar la función parte de ahí.**
- Reversa: `supabase/scripts/conversion/reversa-origenes-ponderada.sql`. Restaura el cuerpo
  `1af7e330`, el de las dos migraciones de peso de renovación sobre el que se generó esta.

## Del mismo lote (PR #80, fusionada)

- La pastilla «Solo cierres de arrastre» del ranking pasa a llamarse **«Cerró sin base del mes»**:
  no tenía base (0) y aun así cerró. No dice «sin leads asignados» porque un alta manual también
  es un lead asignado.
- Los tipos del front se regeneraron desde producción.

Relacionado: [[Conversion - una sola pieza para Metas y la oficial (2026-09-23)]] ·
[[Auditoria de conversiones - capas backend a frontend (2026-09-21)]]

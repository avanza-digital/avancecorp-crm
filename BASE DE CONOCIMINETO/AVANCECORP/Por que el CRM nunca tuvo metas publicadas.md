---
tags: [crm, metas, bug, regla-de-negocio]
actualizado: 2026-08-10
---

# Por qué el CRM nunca tuvo metas publicadas

**Miguel, 2026-08-10:** «quiero establecer metas, pero por algún motivo no se
guardan».

No era un fallo intermitente ni un problema de su cuenta. **Publicar metas era
imposible**, y lo fue desde que existe la pantalla: `crm.meta_periodos` llevaba
**0 filas** en producción. Todo lo que dependía de las metas —el cumplimiento
del asesor, los rankings, las metas de equipo— llevaba meses enseñando el
estado vacío porque no había forma humana de salir de él.

## La causa

Dos funciones decidían sobre el mismo conjunto —«a quién se le fija meta este
mes»— con **dos definiciones distintas**:

| Función | A quién considera | En producción |
|---|---|---|
| `crm.configuracion_metas_fn` (el editor) | vendedores activos **con supervisor activo** | **16** |
| `crm.publicar_metas_vendedores` (guardar) | **todos** los vendedores activos | **17** |

Y antes incluso de contar, el publicador abortaba con `23514` si algún vendedor
no tenía supervisor.

Bastaba **una** persona sin supervisor para bloquear el mes entero. Esa persona
existía: **IVETT TEEVIN**, vendedora activa sin supervisor asignado. El editor
ofrecía 16 metas, el servidor exigía 17, y el error que volvía —«Todos los
vendedores activos deben tener supervisor activo»— no decía **a quién**, con lo
cual era inaccionable con 17 analistas en pantalla.

Reproducido en producción dentro de una transacción con rollback: sin supervisor
→ `23514`; asignándoselo en la misma transacción → publica `revisión 1`. El
defecto era exactamente ese y nada más.

## Por qué ningún test lo cazó

Porque **el fixture siembra a todos los vendedores con supervisor**. El mundo de
las pruebas no tenía huérfanos; el real, sí. Es el mismo patrón que motivó el
[[gate de realidad|Configuración operativa CRM 2026-08-07]] y que ya había
costado tres incidentes en dos días.

Y había un agujero peor, que encontró el auditor: `test-rls.mjs` solo tenía
casos **negativos** de publicación —quién NO puede publicar—, ni uno solo que
comprobara que publicar **funciona**. El gate daba 732/732 sobre una acción que
estaba rota de raíz. *Una suite sin un caso positivo de la acción principal no
prueba que la acción funcione, por muchos negativos que acumule.*

## La decisión

Un vendedor sin supervisor **no cabe** en `crm.metas_vendedor`: la columna
`supervisor_id` es `NOT NULL` con clave foránea. Exigir su meta era pedir algo
que la base no puede guardar.

Así que el roster de metas —«vendedor activo con supervisor activo»— se define
**una sola vez** (`private.roster_metas_vendedores()`) y lo comparten el editor
y el publicador. **Lo que la pantalla ofrece es exactamente lo que el servidor
acepta.** Quien queda fuera ya no bloquea a los demás.

Pero **no en silencio**: la pantalla de Metas ahora nombra a los excluidos, dice
el motivo y advierte la consecuencia real. Esconder la exclusión habría
cambiado un bug ruidoso por uno mudo — alguien sin meta y nadie enterado hasta
fin de mes.

## Tres motivos, tres arreglos

Quedar fuera del roster no es una sola cosa, y la pantalla los distingue:

| Motivo | Qué pasó | Dónde se arregla |
|---|---|---|
| `sin_supervisor` | no tiene supervisor asignado | Usuarios → asignar supervisor |
| `supervisor_inactivo` | lo tiene, pero está dado de baja | Usuarios → reactivar o reasignar |
| `supervisor_no_es_supervisor` | quien figura como jefe ya no tiene ese rol | Usuarios → corregir rol o reasignar |

Agrupar los tres bajo «sin supervisor» mandaría a gerencia a asignarle jefe a
alguien que en pantalla ya tiene uno: el mismo error de usar un predicado como
proxy de varias preguntas que costó el incidente P04.

## La decisión de Miguel sobre IVETT

Planteado el 2026-08-10: **IVETT TEEVIN** es vendedora activa sin supervisor, y
asignarle uno era decisión de negocio (JORGE MARZANO y CARMEN JARAMILLO llevan 8
analistas cada uno — empate sin default defendible).

**Miguel, 2026-08-10, textual: «ivette dejala asi fuera».**

Así que se queda fuera del roster de metas **a propósito**. Es exactamente el
caso que el arreglo contempla: los otros 16 llevan su meta, la publicación no se
detiene, y la pantalla de Metas la nombra con el motivo `sin_supervisor` para
que la exclusión sea una decisión visible y no un olvido.

⚠️ **Consecuencia que hay que tener presente**: mientras siga así, IVETT no
aparece en el cumplimiento del mes y **sus contratos no se atribuyen a nadie**
(ver la deuda abajo). Si empieza a cerrar operaciones, esto deja de ser
inofensivo.

## Deuda que este arreglo NO cierra

`crm.cumplimiento_metas_fn` construye su universo desde `crm.metas_vendedor`, así
que un analista fuera del roster **no aparece en el cumplimiento del mes y sus
contratos no se atribuyen a nadie**. Antes lo tapaba el `23514` abortando la
publicación entera — pero como publicar era imposible, esa garantía nunca llegó
a ejercerse. Queda documentado y la pantalla lo advierte; cerrarlo en la RPC de
cumplimiento es trabajo aparte.

## Efecto colateral bueno

El publicador hacía `lock table public.perfiles in share mode`: **cada
publicación de metas del CRM congelaba las altas y ediciones de perfil del
portal en producción**. Se estrechó a las 21 filas del equipo comercial. Ver
[[CRM y portal separados|crm-portal-separados]].

Relacionado: [[Metas del asesor van en soles]],
[[Plan de escalabilidad del CRM a data gigante]], [[Acceso y roles del CRM]].

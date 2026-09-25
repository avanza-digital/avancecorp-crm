# F6 — Historial previo a la publicación de la UX

> **Estado superado:** F6 quedó autorizada, publicada y verificada el 25/09
> a las 05:14 Lima. [Acta vigente](PUBLICACION-2026-09-25.md). El contenido
> siguiente conserva el preflight y los bloqueos anteriores, ya resueltos.

**25/09/2026. Paquete preparado; despliegue de la UX NOT RUN.**
El [PR #101](https://github.com/avanza-digital/avancecorp-crm/pull/101) fue
integrado por `miguejbs98` a las **05:39:45 UTC / 00:39:45 Lima** en
`f9196dba908fab4a28048e43ceab2c1284156cee`, sin revisión APPROVED registrada.
No se atribuye aprobación a esa integración. El goal exige revisión normal;
la excepción antes concedida para F5 no autoriza por sí sola publicar F6.

## Fuente, paquete y pruebas

Main local/remoto estaban alineados en `f9196dba`, con árbol limpio. El árbol
completo coincide con `81930a59`, head del PR, y la app es idéntica a `4a4cb1ec`
probada. Los controles del PR y los tres de Main dieron PASS. [Recibo](pr101-integracion-y-ci-main.json).
Se reutiliza la evidencia del mismo código: 4.421 pruebas / 298 archivos,
Chromium Docker 270/0/26 y WebKit 10/0; dos revisiones independientes concluidas.

`release:crm` y `release:crm:verify`: **PASS**. Artefacto:
`crm-20260925T054322Z-f9196dba908f.zip`, 2.320.539 bytes, 117 archivos.
SHA-256: `e6c17b3b8084c154137160aef01c0f0ed49c93d1984261f3e2986e90f3f4ffeb`.
Destino: `crm.miavance.com`. [Resumen y huellas](prepublicacion-resumen.json).
El ZIP/manifiesto y los logs completos permanecen en el checkpoint local de F6;
no se incluyen credenciales ni paquetes binarios en esta acta.

La diferencia con la versión servida es la UX/UI gerencial del PR #101. No
hay SQL, Edge ni cambios de permisos que promover. Antes de subir se debe
reconfirmar Main/remoto y reconstruir si avanzaron; esta acta no publica el ZIP.

## Producción y recuperación actuales

Otra tarea publicó `3027028d`, con build `build-20260925T041520137Z`.
Los **79 HTML/JS/CSS** del manifiesto coinciden byte a byte con HTTPS. Esto
acredita que la cola F6 del PR #97 y el Resumen de Gerencia del PR #100 ya
están servidos; la UX nueva del PR #101 sigue sin publicar.
[Archivos y hashes](produccion-3027028d-verificada.json).

El respaldo vigente es `crm-20260925T041520Z-3027028d7c97.zip`:
SHA-256 `b07b1379ea590face22d905517c4493c3a949d107722a0744c332b0f804a0421`.
ZIP y manifiesto fueron verificados y conservados juntos. El primer cotejo
contra el F5 anterior `b402a7f1` dejó de coincidir porque había sido sustituido;
se identificó la versión actual antes de proponer otro despliegue.

## Lectura productiva y límites

[Conciliación del 25/09](produccion-sonda-20260925.json): **11/11 PASS** en un
snapshot READ ONLY. Originales y RPC coinciden: 0 llamadas del nuevo día,
19 analistas y 756 tareas vencidas. Es un control puntual; no acredita otro día
completo ni sustituye hábitos, permisos negativos o navegación.

El comando general `gate:realidad` salió con código 2 por variables de servicio
ausentes: medición CLI **NOT RUN**. Al trasladar sus nueve supuestos a SQL se
encontró además que el script apuntaba a `crm.perfiles`, relación inexistente.
La tabla productiva es `public.perfiles`; esta continuación corrige una sola
consulta con `.schema('public')`, igual que el otro lector de perfiles del
mismo script. Es un control del operador y no forma parte del bundle del CRM.

La [medición SQL de solo lectura](realidad-sql-20260925.sql) obtuvo
[ocho coincidencias y una divergencia](realidad-sql-20260925.json): 290 clientes
activos sin domicilio. La regresión de contratación ya cubre la captura del
domicilio faltante; esta adaptación visual no presupone que todos lo tengan.
No se atribuye PASS al CLI productivo. La sintaxis y `npm run check:scripts`
de la corrección dieron **PASS**; el frontend no cambia.
[Validación del control y huella del log](VALIDACION-CONTROL-REALIDAD.json).

## Lo necesario para publicar y cerrar

La comprobación del acceso Hostinger devolvió **HTTP 401 Unauthenticated** en
dos lecturas con la credencial guardada. El MCP oficial dispone de la operación
estática; requiere renovar el acceso. [Resultado saneado](hostinger-acceso.json).
Se preguntó a Miguel por autorización F6 con el merge manual como aprobación
y por renovación del acceso. Las respuestas siguen pendientes; el silencio
no autoriza el despliegue. No repetir confirmaciones ya dadas para F5 o para
el recorrido de negocio.

El [mismo Figma](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L) distingue
la cola publicada de la UX integrada pero todavía pendiente de publicación.
[Actualización](figma-integracion-pendiente.json) y [captura](figma-integracion-pendiente.png).
La casilla de la entrega permanece abierta hasta completar su publicación.

T0 F5 permanece **24/09 a las 21:57:11 Lima**. El control adicional no cuenta
como un día completo. La retirada final exige siete días reales estables:
**no antes del 01/10 a las 21:57:11 Lima**. El corte del sábado 26/09 a las
11:30 sigue pendiente; no hay vigilancia programada garantizada.

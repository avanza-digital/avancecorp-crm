# Contrato duplicado: el alta sin PDF se leía como error (2026-09-05)

**Estado: arreglo construido y ensayado en el banco; pendiente del `!` de Miguel para producción y de la remediación manual del duplicado.**

## El problema, en idioma de negocio

Una analista registró el contrato de una clienta (S/ 20 000, 15 %, firmado el 11/03/2026) y la pantalla le dijo «El servidor no confirmó completamente el contrato y su cuenta de pago». El contrato **sí** se había creado. Reintentó con el mismo número y el sistema, con razón, dijo «ese número ya existe». Cambió el número, reintentó, y quedó **un segundo contrato idéntico** (2026-01-000025 y 2026-01-000253, a 61 segundos). Los dos figuran activos, con cronograma y cuenta de pago; ninguno tiene pagos ni documento.

## Por qué pasó

- Los contratos **firmados antes del 19/08/2026** no llevan el documento que emite el sistema (decisión de Miguel del 20/08: ya tienen su contrato en el formato anterior). Para ellos el servidor responde «sin reserva de PDF».
- El CRM, al crear un contrato, exigía que la respuesta trajera **una reserva de PDF en curso**. Como para estos contratos no la hay, el navegador rechazaba la respuesta y pintaba un error **sobre un alta que ya estaba hecha**.
- El servidor no tenía culpa: la cadena de creación es una sola transacción y respondió bien las dos veces. El error vivía en cómo el navegador leía la respuesta.
- **No fue un caso aislado**: desde el 21/08, **33 altas** de contratos antiguos pasaron por ese error falso. El 04/09 hubo dos ciclos iguales. Solo hoy hubo duplicado porque la analista cambió el número; hasta ahora el chequeo de «número repetido» había frenado los reintentos por casualidad.
- Que los dos contratos tengan «condición de producto» distinta es normal: el registro de condiciones acuña una entrada por contrato (ver [[Auditoria servidor Supabase - duplicacion y deuda (2026-08-28)]]: el «catálogo» es el registro de condiciones de cada contrato).

## Qué se arregló

1. **El navegador ya no convierte un alta hecha en error.** La prueba de que el contrato existe son su identificador y su número; lo demás (cuenta, estado del documento) se lee con tolerancia y, si no encaja, se anota como rastro técnico sin asustar a la analista. El estado real del documento lo manda siempre el servidor cuando se consulta después.
2. **El alta es idempotente.** Cada intento del formulario lleva una clave única; si la analista reintenta (por red, por timeout o por un error falso), el servidor devuelve **el mismo contrato** en vez de crear otro, y la pantalla avisa «se recuperó el alta anterior». Dos envíos simultáneos con la misma clave también producen un solo contrato (ensayado en el banco). Sin clave, todo sigue exactamente como hoy. No se tocó el núcleo de creación (`crear_contrato`), solo la puerta del CRM.
3. **Reproducido antes de arreglar**: la respuesta real de producción hacía fallar el código viejo (prueba roja → verde). En el banco, el ensayo con el texto vivo reprodujo el duplicado (misma clave, número cambiado → 2 contratos) y con el arreglo dio 1.

## Qué falta (decisiones de Miguel)

- **Aplicar en producción** la migración `20260905190000_crm_alta_contrato_idempotente` (`db query --linked --file`) y registrarla; después, **publicar el front**. El orden no importa aquí: la clave viaja dentro del JSON y el servidor viejo la ignora; el front nuevo tolera «sin reserva» con o sin migración.
- **Resolver el duplicado**: eliminar uno de los dos por la puerta oficial (botón «Eliminar contrato» de Gerencia o el SQL `scripts/remediacion-duplicado-2026-01-000253.sql`, revisado y no ejecutado). Por defecto se elimina el reintento (000253); **si el contrato físico firmado dice 000253, se elimina 000025**. Los dos son idénticos en todo salvo el número.
- Avisar al equipo: las 33 altas antiguas están bien creadas; el error que vieron era falso.

## Lecciones

- **Después de una escritura irreversible no se falla cerrado.** Rechazar la respuesta de un alta ya hecha no protege nada: fabrica duplicados. Ya había pasado el 19/08 con la plantilla v5.
- **Una defensa accidental no es una defensa.** El chequeo de número repetido frenaba los reintentos sin querer; en cuanto alguien cambió el número, se acabó.
- **Toda escritura que un humano puede reintentar lleva clave de idempotencia.** Es la única forma de que «reintentar» sea seguro.

Relacionadas: [[Ciclo de vida de contratos]] · [[Número de contrato]] · [[Cuentas bancarias por contrato]] · [[PDF de contrato (generador) — plan]] · [[Bug de plazo contractual en PDF por fin de mes (2026-09-01)]]

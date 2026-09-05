# Contrato duplicado: el alta sin PDF se leía como error (2026-09-05)

**Estado (05/09, 13:30): arreglo v2.1 construido, revisado de forma adversaria (Codex + 7 revisores, 39 hallazgos, todo lo mayor atendido) y ensayado en el banco (oráculo TODO VERDE, suite RLS del bloque 8/8, front `npm run check` verde); **duplicado remediado en producción el 05/09 17:12 Lima** (se conservó 000253, el número del contrato físico); **migración aplicada en producción el 05/09 17:20 Lima**; pendiente solo publicar el front con `/release-crm`.** Retomado en [[RETOMAR-61 - Contrato duplicado e idempotencia del alta (2026-09-05)]].

## El problema, en idioma de negocio

Una analista registró el contrato de una clienta (S/ 20 000, 15 %, firmado el 11/03/2026) y la pantalla le dijo «El servidor no confirmó completamente el contrato y su cuenta de pago». El contrato **sí** se había creado. Reintentó con el mismo número y el sistema, con razón, dijo «ese número ya existe». Cambió el número, reintentó, y quedó **un segundo contrato idéntico** (2026-01-000025 y 2026-01-000253, a 61 segundos). Los dos figuran activos, con cronograma y cuenta de pago; ninguno tiene pagos ni documento.

## Por qué pasó

- Los contratos **firmados antes del 19/08/2026** no llevan el documento que emite el sistema (decisión de Miguel del 20/08: ya tienen su contrato en el formato anterior). Para ellos el servidor responde «sin reserva de PDF».
- El CRM, al crear un contrato, exigía que la respuesta trajera **una reserva de PDF en curso**. Como para estos contratos no la hay, el navegador rechazaba la respuesta y pintaba un error **sobre un alta que ya estaba hecha**.
- El servidor creó bien las dos veces: la cadena de creación es una sola transacción. El error vivía en cómo el navegador leía la respuesta. **Matiz** (revisión adversaria): la forma de esa respuesta la cambió el propio servidor el 20/08 (los contratos antiguos pasaron a responder «sin reserva») y su registro de cambios afirmó que el navegador no dependía de ella; nadie actualizó el navegador. El arreglo es del navegador y de la puerta, pero la lección es del registro: no se declara «el front no depende» sin una prueba.
- **No fue un caso aislado**: desde el 21/08, **33 altas** de contratos antiguos pasaron por ese error falso (16 avisos en Sentry desde el 31/08). El 04/09 hubo dos ciclos iguales (contratos distintos del mismo cliente: no duplicaron). Solo hoy hubo duplicado porque la analista cambió el número; hasta ahora el chequeo de «número repetido» había frenado los reintentos por casualidad.
- **Hubo un segundo ciclo el mismo día**, por otro analista: a las 11:56 (hora Lima) creó el contrato 2026-01-000247 (10 000 USD, firmado el 10/03/2026) y la pantalla dijo error; a las 12:03 alguien lo eliminó con el botón de Gerencia (la auditoría quedó **sin actor**: ese botón borra con la cuenta de servicio); a las 12:06 lo volvió a crear con el mismo número para otro registro de cliente y la pantalla volvió a decir error. De ese ciclo no queda duplicado; la búsqueda de parejas sospechosas en producción devuelve hoy una sola: 000025/000253.
- Que los dos contratos tengan «condición de producto» distinta es normal: el registro de condiciones acuña una entrada por contrato (ver [[Auditoria servidor Supabase - duplicacion y deuda (2026-08-28)]]: el «catálogo» es el registro de condiciones de cada contrato).

## Qué se arregló

1. **El navegador ya no convierte un alta hecha en error.** La prueba de que el contrato existe son su identificador y su número; lo demás (cuenta, estado del documento) se lee con tolerancia y, si no encaja, se anota como rastro técnico sin asustar a la analista. El estado real del documento lo manda siempre el servidor cuando se consulta después.
2. **El alta es idempotente.** Cada intento del formulario lleva una clave única; si la analista reintenta (por red, por timeout o por un error falso), el servidor devuelve **el mismo contrato** en vez de crear otro, y la pantalla avisa «se recuperó el alta anterior». Dos envíos simultáneos con la misma clave también producen un solo contrato (ensayado en el banco). Sin clave, todo sigue exactamente como hoy. No se tocó el núcleo de creación (`crear_contrato`), solo la puerta del CRM.
3. **Reproducido antes de arreglar**: la respuesta real de producción hacía fallar el código viejo (prueba roja → verde). En el banco, el ensayo con el texto vivo reprodujo el duplicado (misma clave, número cambiado → 2 contratos) y con el arreglo dio 1.
4. **El mismo peligro entre dos pestañas, cerrado** (revisión de Codex, 05/09): la clave de un intento se comparte por cliente entre pestañas; se corrigió para que la pestaña que reintenta conserve su clave aunque otra confirme y limpie el almacenamiento, y para que una respuesta tardía no borre la clave de un intento posterior.

## Qué falta (decisiones de Miguel)

- ~~Aplicar en producción la migración~~ **HECHO (05/09 17:20 Lima)**: aplicada y registrada, verificada. Falta **publicar el front** con `/release-crm`: es lo que hace que la pantalla deje de leer como error el alta antigua y que empiece a viajar la clave. Hasta entonces el servidor se comporta exactamente como antes.
- ~~Resolver el duplicado~~ **HECHO (05/09 17:12 Lima)**: se eliminó 000025 y se conservó 000253, que es el número del contrato físico firmado. Por la puerta oficial, con el SQL §3, comparando los dos contratos completos bajo candado; el borrado quedó auditado a nombre del administrador (lo que el botón de Gerencia no consigue). La clienta tiene ahora un solo contrato.
- **Segunda pasada de Codex** sobre la versión final (v2.1) antes de aplicar: la sesión que la pidió se cortó por límite de uso.
- Avisar al equipo: las 33 altas antiguas están bien creadas; el error que vieron era falso.

## Lecciones

- **Después de una escritura irreversible no se falla cerrado.** Rechazar la respuesta de un alta ya hecha no protege nada: fabrica duplicados. Ya había pasado el 19/08 con la plantilla v5.
- **Una defensa accidental no es una defensa.** El chequeo de número repetido frenaba los reintentos sin querer; en cuanto alguien cambió el número, se acabó.
- **Toda escritura que un humano puede reintentar lleva clave de idempotencia.** Es la única forma de que «reintentar» sea seguro.
- **Cuando el servidor cambia la forma de una respuesta, el navegador cambia en el mismo commit**, y el registro de cambios no afirma «el front no depende» sin una prueba que lo demuestre.
- **Un borrado desde un botón debe quedar a nombre de quien lo pulsó.** El de Gerencia hoy no lo hace (auditoría sin actor); queda anotado como deuda.

Relacionadas: [[Ciclo de vida de contratos]] · [[Número de contrato]] · [[Cuentas bancarias por contrato]] · [[PDF de contrato (generador) — plan]] · [[Bug de plazo contractual en PDF por fin de mes (2026-09-01)]]

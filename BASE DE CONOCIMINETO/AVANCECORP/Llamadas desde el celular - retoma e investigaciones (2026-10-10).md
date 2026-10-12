# Retoma de llamadas — 10/10/2026

Relacionado: [[Llamadas desde el celular - revision PR 251 (2026-10-10)]] · [[Llamadas desde el celular - revision conjunta PR 232 y 249 (2026-10-10)]] · [[Llamadas desde el celular - instalacion y publicacion (2026-10-07)]].

## PR #251

Miguel autorizó revisar `41f0edbb..cbfce23d`, fusionar y publicar. Correcciones revisadas: los dos P2 y cuatro P3 previos están resueltos. Aprobación: https://github.com/avanza-digital/avancecorp-crm/pull/251#pullrequestreview-5481042899.

PASS propios en `cbfce23d`: lint, typecheck, gate `npm run check` completo (6622 tests/410 archivos, cobertura, configuración release, push-tasa, build, bundle y duplicación); focalizados 128/128; E2E Docker local 2/2; diffcheck. Wrapper Claude: exit 1, sin VERDICT, no se cuenta como dictamen. No se repitió P1–P15.

Se actualizó la rama con main por la protección de GitHub (`0d5b75d9`); app idéntica al SHA probado, CI `verify`, `app-check`, `preflight`, `cambios` PASS. Fusión normal por squash el 10/10 a las 17:41 Lima: **`7b0d0716e491d35842b48109c3aa134c18c862b2`**. No se usó `--admin`.

Release vivo detectado: `build-20261010T144534615Z`, fuente `1b2dc5c806379b0502190f6e60695f07378f813b`. La memoria anterior estaba atrasada. Su árbol es idéntico al squash #247 `426499c3`, pero el commit vivo no era ancestro de main. El preflight de `7b0d0716` rechazó por ello. Procedimiento de rescate aplicado en la copia aislada: rama desde el vivo e integración de main, conflicto de ledger resuelto conservando main (incluye #248). **`9e2c9af88cf7c43f8bb905ce55d3d9fb6ac62439`**, árbol completo idéntico a `7b0d0716`; ambas ascendencias comprobadas. Se reutiliza el gate por igualdad de contenido. ZIP `crm-20261010T224358Z-9e2c9af88cf7.zip`, SHA256 `7e5816203275e8f2220bc5b7c47bb5c15c1faf31a39bc0e7e424543782ca3034`; release verify y preflight con ruta absoluta PASS. Publicación solicitada; ver cierre al pie antes de afirmar que está viva.

## Investigación retomada

Se usan los cuatro puntos del #251; no se ha recibido la enumeración completa del relevo «Noche del 10/10», por lo que su correspondencia I-1…I-4 es provisional. I-5 no se inventa.

- **Nuevo dueño (punto 1): confirmado en SQL local.** Banco reducido sintético con base del repositorio y las 12 migraciones reales. Tras reasignar el lead de A1 a A2, A2 une la llamada de A1 al resultado creado por A1. Se conservan evento.analista_id=A1 y actividad.creado_por=A1; enlace.enlazado_por=A2. Tercero A3 fuera de ámbito rechazado. Recomendación: conservar unión manual explícita dentro del ámbito actual; aclarar la distinción con v5 exacta (`celular_ajeno`). No cambiar autor histórico ni ampliar permisos. Es comportamiento existente, no una migración nueva.
- **Reloj (punto 2): confirmado en SQL y UI.** Ingesta admite el aviso sintético con reloj +20 min y lo marca; unión manual al resultado creado a la hora real falla con 22023 y no crea enlace. La UI filtra ese resultado y muestra lista vacía; control sin desfase sí lo ofrece. Corregir la guía: fecha/hora automática evita futuros casos, pero no corrige el timestamp inmutable ya capturado. No recomendar registrar otro resultado para resolver el enlace ni manipular fechas. La unión exacta por ID es un camino distinto. Cualquier cambio al margen SQL requiere diseño separado.
- **Supervisor/fila ajena (punto 3): confirmado.** SQL local permite al supervisor B1 unir una llamada de su equipo. `screens/gestion-diaria.tsx:64–73` elige otra pantalla para supervisor, sin pestaña Celular. Prueba de componente con `es_propia:false` muestra botón, autor del resultado y ejecuta onUnir. No implica permitir resultados exactos v5 de otro celular. Mantener el alcance actual hasta acordar interfaz para supervisor con F4-e.
- **Exportación (punto 4 / I-4): pendiente física de Jhosep.** Primero prueba con macro/variables sintéticas en C1 5.67: menú y formato de exportación, globals/locales, diccionarios y variable segura; inspección local del archivo antes de compartirlo. No enviar exportaciones reales, números ni credenciales al chat/PR. Para usar A, cola y errores resueltos, datos saneados y restauración/verificación de C1; si no puede acreditarse, usar B de ACTIVAR-C2. No borrar avisos pendientes para facilitar exportación.
- **I-5: pendiente recibir definición.** `_DEV_NO_SUBIR/HANDOFF-2026-10-10.md` no está en proyecto/copia limpia. Solicitado a Jhosep en comentario 6102862849; usuario contestó «sí» al pedido de adjunto, pero no adjuntó contenido.

Evidencia: `/private/tmp/avancecorp-pr251-review-20261010/investigacion.sql`, `investigar-local.py`, `investigacion-sql.log`, `investigacion-ui.test.tsx`, `investigacion-ui.log`. SQL: tres escenarios PASS, incluye control negativo fuera de ámbito. UI: dos pruebas PASS. Banco PostgreSQL temporal detenido; transacción ROLLBACK. Auth/v4 son dobles declarados del banco reducido; no es aceptación en producción ni matriz RLS completa. La prueba UI temporal se retiró del checkout tras conservarla como evidencia.

## Aviso de tratamiento

El borrador corrige las afirmaciones técnicas de retiro, credencial y llamadas personales. **No está aprobado para firma todavía.** Antes de entregarlo, completar responsable/razón social y domicilio, banco de datos y canal para derechos, destinatarios/encargados y transferencias, consecuencias y base aplicable al tratamiento de datos del analista y de terceros. No inventar estos datos ni deducir que la firma del analista autoriza tratar teléfonos ajenos.

Referencia revisada: artículo 18 de la Ley 29733, información previa sobre finalidad, destinatarios, banco y titular, transferencias, plazos y ejercicio de derechos: https://www3.congreso.gob.pe/Docs/DGP/DIDP/files/ley_29733.pdf. Reglamento oficial identificado: https://www.gob.pe/institucion/anpd/normas-legales/6554453-n-016-2024-jus. La revisión identifica lo faltante; no certifica cumplimiento ni selecciona una base legal sin datos de la empresa.

## Jhosep, C1/C2/C3 y vigilante

Miguel aclaró que **Jhosep tiene los celulares**. Instrucciones enviadas: https://github.com/avanza-digital/avancecorp-crm/pull/251#issuecomment-6102862849.

1. Renovar MacroDroid gratis en C1 **lunes 12/10/2026 antes de ~15:50 Lima**, comprobando vencimiento en la app. Recordatorio comunicado; no confundir con una alarma programada. Pro corporativo para 2–3 equipos hasta S/57 sigue autorizado.
2. Antes de activar C2: aviso revisado y firmado; cuenta activa y lead sintético propio con consentimiento; una SIM, sin internacionales. I-4 antes si camino A; B disponible.
3. ACTIVAR-C2: alta en Configuración/Celulares, permisos Teléfono/Registro, aparecer encima, batería sin restricciones, Chrome y PWA con vínculos, hora automática; 9 variables y 3 macros, etiqueta C2, clave antes de encender y ultimo_latido=0. Control de latido y llamada real con encuesta/unión; registrar evidencias saneadas. C3 después, individualmente.
4. F4.2.4: tras publicación, un caso C1 guardar desde ficha/PC → unir → un resultado/una unión → sale de Pendientes. Mantener 47/102 hasta aceptación; luego 48/102. No repetir P1–P15.
5. Vigilante: pendiente conocer el anterior (objetivo, frecuencia, dónde corre). No hay herramienta general de cron/automatizaciones expuesta ni configuración local encontrada; no se afirma rearmado. Pedido a Jhosep junto al relevo.
6. H-P5/H-P10 continúan abiertos. F4-e §9 conserva su requisito de OK explícito; no se ha escrito SQL nuevo. Jev OFF.

## Tablero y preservación

FigJam: https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY/ · actualizado por hitos de revisión, fusión e investigación: **47/102; 2/8 fases**. Conteos F0=1/12, F1=12/12, F2=13/13, F3=11/13, F4=8/13, F5=0/15, F6=0/12, F7=2/12. Captura de bloque de estado revisada. Ninguna aceptación física nueva marcada.

Checkout compartido preservado. Trabajo y build en `/private/tmp/avancecorp-pr190-correcciones-20261006`. No hay otro PR abierto de Jhosep al corte posterior a fusionar #251; #185 sigue borrador ajeno, sin tocar.

## Cierre verificado — 10/10/2026, 20:26 Lima

**Publicado y comprobado:** `build-20261010T224357802Z`, fuente `9e2c9af88cf7c43f8bb905ce55d3d9fb6ac62439`. Hostinger aceptó el despliegue y la web devuelve ese build. Smoke: 159 archivos públicos HTTP correctos; 147 hashes iguales al manifiesto. Los 12 PNG restantes difieren: siete conservan exactamente los píxeles y cinco tienen dimensiones distintas. Ningún PNG cambió entre el manifiesto anterior y este; no se presenta como igualdad binaria total ni se atribuye una causa no comprobada. `.htaccess` no se pidió por HTTP. Evidencia `smoke.json`, `png-inspection.json` y logs en la carpeta de revisión.

Mientras se cerraba la publicación entró #252 de Facturación en main `dbb36ce77ca0b27e469d0e397eddc0b7e8a82a13`. Se integró entero en el rescate sin conflictos: `76d4b4c6`, árbol idéntico a `dbb36ce7`. El push normal fue rechazado por GH013 (historial lineal/PR/checks). Se abrió **#253**, cero archivos cambiados, y pasaron `verify`, `app-check`, `cambios` y `preflight` (Supabase Preview omitido). **Miguel autorizó expresamente la fusión administrativa del #253** en esta conversación; se ejecutó `--merge --admin --match-head-commit 76d4b4c6...` y quedó fusionado a las 20:26 Lima. No se modificaron reglas ni se usó force.

**main final: `3f81c40f0ad9407659282dbd592fac661f9d47aa`**, coincidente local/remoto en la copia limpia. Ambas ascendencias (release `9e2c9af8` y #252 `dbb36ce7`) PASS, árbol idéntico al main previo `dbb36ce7`, checkout limpio. No se republicó #252 desde esta sesión; no confundir el SHA del frontend vivo con el nuevo tip main. El checkout compartido no se cambió de rama ni se integró: se preserva su trabajo ajeno. Se copiaron con `cp -n` ZIP y manifiesto vivos a `CRM-Avance-Corp/releases/` del proyecto compartido para los próximos preflights.

Informe completo a Jhosep: https://github.com/avanza-digital/avancecorp-crm/pull/251#issuecomment-6104173210 (actualizado con la fusión de #253). Tablero actualizado tras cada hito y captura revisada; permanece **47/102, 2/8 fases**. C1/aviso/I-4 físicos pendientes de Jhosep, I-5 y vigilante pendientes de recibir el relevo/configuración. Recordatorio comunicado para lunes 12/10 antes de ~15:50, no alarma programada. Jev OFF.

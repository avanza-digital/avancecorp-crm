# Publicar cierres de clientes sin esperar a llamadas del celular

## Decisión y alcance

Miguel indicó que #190 tardará y pidió avanzar con el cierre de tareas de clientes.
El «deploy» de #207 sigue autorizado. Sus dos migraciones ya están instaladas:
postflight productivo PASS a las `2026-10-07T00:43:32.969586Z`.

Se conserva todo Main, incluidas #190 y #207, y se añade un interruptor de publicación
para la integración de eventos del celular. No se revierte la PR ni se publica una
rama antigua. Este ajuste no modifica SQL, Edge, permisos ni datos.

## Comportamiento mientras #190 sigue pendiente

- `LLAMADAS_CELULAR_APROBADAS = false` en `app/src/lib/config.ts`.
- En sesiones reales no aparece la pestaña Celular y no se consultan sus dos RPC.
- El enlace F1 con teléfono sigue abriendo el resultado manual. El identificador
  opcional de un evento del celular no se incorpora mientras la integración está cerrada.
- El diálogo y la tarjeta Ahora comparten el mismo control: no envían ese identificador
  ni anuncian un enlace automático. Los resultados manuales siguen usando v4.
- El store rechaza cualquier envío explícito con evento de celular antes de escribir
  o cambiar el estado optimista. No hay fallback después de un error de servidor.
- La demostración local conserva #190 en memoria. La entrega productiva sigue sin
  permitir el acceso demo.
- Cerrar tarea de clientes, sus resultados y la supervisión de #207 permanecen activos.

## Verificación

- Pruebas específicas: **229/229 PASS**.
- `npm run check`: **PASS, 391 archivos / 6.267 pruebas**, lint, tipos, build,
  configuración de release, bundle y duplicación 0,44 %.
- Las pruebas con la configuración real exigen pestaña ausente, cero consultas,
  F1 manual, formulario sin origen y rechazo preventivo del store. También se
  conservan pruebas de v4, demo y futura activación de v5.
- E2E Docker: en ejecución sobre siete especificaciones del recorrido afectado.
  Un primer intento con dos workers sufrió demoras de arranque bajo carga de otros
  contenedores y se interrumpió. Se repite con un worker sin cambiar aserciones ni
  tiempos. El Main anterior ya tenía la suite completa PASS: 368/26 omitidas.

## Revisión de Claude y decisión del PRIMARY

Revisión acotada de este nuevo interruptor: **CHANGES_REQUESTED**, sin P0/P1.
Las recomendaciones sobre #207 ya estaban resueltas en su acta anterior.

- **P2 hipotético, Deshacer:** descartado con evidencia. La API de Deshacer no cambió
  entre el build vivo `4e6ee7ee` y Main. Producción ya tiene
  `crm.deshacer_resultado_llamada(uuid)` (MD5 del cuerpo
  `bfcb417bd4b5b447722f0d4f65b16c68`) y `crm.registrar_llamada_v4`
  (`5a7262fd493b6b3df331cae3a489c257`). No dependen del SQL de #190 pendiente.
- **P3, tarjeta y otros consumidores:** inspeccionados. Diálogo y tarjeta llaman a
  `useRegistroResultado`, cuyo origen está condicionado. Las tres funciones de la
  API de celular solo se consumen en `useLlamadasCelular`; su único montaje está en
  la pantalla del analista. No hay otro polling ni consumidor real sin condicionar.
- **P3, nombre local repetido:** scopes diferentes, lint PASS; no produce un defecto
  y no se añade un cambio cosmético a la entrega comprobada.
- **Canario y demo:** las pruebas negativas con la configuración real fallarían si
  se abriera el interruptor. La prueba de la pestaña demo se conserva. No hace falta
  un test adicional que repita literalmente el valor de la constante.

El PRIMARY resuelve las observaciones con esos hechos; no atribuir un PASS posterior
a Claude. Evidencia saneada: `app/artifacts/gestiones-clientes-independiente-review.txt`.

## Activación posterior de #190

El agente de llamadas debe verificar su SQL, Edge y comportamiento con SLA activo,
abrir `LLAMADAS_CELULAR_APROBADAS` y ajustar las pruebas que fijan el estado cerrado.
La apertura requiere construir y publicar otra entrega desde Main verificado.
El interruptor controla disponibilidad del cliente; la autorización de datos sigue
siendo responsabilidad del servidor.

No existen reintentos productivos de v5 previos a esta entrega: su frontend y su
backend no se han publicado. Si en el futuro se cierra el interruptor después de
activar #190, habrá que tratar explícitamente los recibos pendientes; este ajuste
no define una reversa para aquel escenario.

## Publicación

Pendientes la integración del ajuste en Main, el artefacto desde ese commit,
preflight Hostinger y comprobación HTTP posterior. La revisión visual la realiza
Miguel en Cartera → ficha de cliente → Seguimiento → Cerrar tarea.

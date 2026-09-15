# Ficha individual publicada y verificada — 15/09/2026

La ficha de Gerencia pasó de **2674,505 a 723,414 ms (−73 %)**; Supervisor, de 1674,235 a 813,641 ms; Analista, de 786,208 a 718,032 ms. La meta de menos de un segundo queda acreditada para la consulta SQL medida. Misma persona con dos inversiones y JSON completo idéntico en los tres roles; una muestra de calentamiento y tres medidas por grupo, rol SQL authenticated, READ COMMITTED y ROLLBACK. No representa el tiempo completo del navegador, excluido por Miguel del ensayo.

## Publicación comprobada

- SQL fuente aprobado: `20260915170237_crm_ficha_lectura_individual.sql`, intacto desde `8f3dd99`. Artefacto leído del commit `2c16afdffad00172bebbf3ed11dd44d962cb5a6c`, con Main local y avancecorp/main iguales. Sin publicación de frontend.
- Merge de la rama propia como **20260915185535**. En el banco había un bloque; el merge lo separó en **nueve sentencias**, cuyos segmentos coinciden literalmente con el archivo aprobado. Las 294 entradas anteriores del historial se conservan completas; total 295.
- 649 funciones y 275 triggers coinciden con el banco. Se mantienen las seis diferencias de catálogo administradas/revisadas del entorno temporal. 20 bundles Edge y su configuración JWT/import map conservados.
- Preservados los cambios concurrentes de correo atómico y ticket de Citas, incluidos el trigger Auth, el cuerpo de Citas y sus declaraciones/sello de arquitectura. El control de Citas pasa en producción: 34 candidatos, 30 sujetos al techo 30 y cuatro auxiliares verificados.
- No se modificaron las banderas globales ni el piloto productivo. F8/G7 conserva sus pendientes; publicar esta mejora no habilita automáticamente a los 18 analistas.

## Evidencia

[Medición productiva](evidencias/rendimiento-produccion.json), [recibo e historial](evidencias/recibo-produccion.json), [catálogo](evidencias/catalogo-produccion.json), [premerge](evidencias/premerge.json), [Edge](evidencias/edge-premerge.json).

PASS local y remoto: 640 fichas y 328 resultados de núcleo iguales, ocho huellas conservadas y 15 controles de seguridad/reversa. El banco remoto con 490 personas y 7093 cuotas no mostró regresión relevante; su CPU/plan difiere de producción y sus tiempos no se usaron para atribuir la meta productiva.

PASS Auth/API: 15 sesiones, 62 comparaciones antes/después en piloto y 92 en modo general. Se mantuvieron los rechazos de cliente, anónimo, tabla/esquema privado y ficha ajena. Seis peticiones en oleadas de 1/2/3 conservaron respuestas completas; acredita solapamiento de solicitudes HTTP, no intervalos SQL internos. Los tipos públicos/crm regenerados son idénticos.

Advisors: ninguna advertencia nueva de funciones/RLS/permisos. El aviso de contraseñas filtradas que apareció en el banco ya existía en producción; no se cambió Auth. 16 avisos INFO de índices sin uso desaparecieron al ejercitarlos. [Comparación](evidencias/advisors-remotos.json).

La matriz RLS general heredada y E2E visuales no se ejecutaron en esta tarea; sí la matriz específica descrita. Frontend sin cambios. Claude emitió CHANGES_REQUESTED, sin P0/P1: Codex evaluó y resolvió los puntos aplicables y acreditó finalmente el rendimiento en producción. No se cambia retrospectivamente el dictamen del reviewer.

## Banco y retoma

Banco `tufxjboalbtekbszckcf` eliminado y ausencia confirmada el 15/09 a las 19:33:48 UTC. Coste estimado **US$0,021**, dentro del límite de US$1; no es una factura. `banco-f7` se conserva intacto.

La siguiente tarea es concretar la apertura general solicitada por Miguel: revisar evidencia real y pendientes de [G7](../multiempresa-f8/ACTA-G7.md), comprobar alcance por rol y preparar el encendido/reversa. [Orden de trabajo](ESTADO.md). Las pruebas sintéticas no firman conformidades financieras ni completan automáticamente los recorridos reales del piloto.

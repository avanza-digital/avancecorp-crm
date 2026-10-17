# Evaluación PRIMARY de la revisión final

Claude emitió CHANGES_REQUESTED, sin hallazgos P0/P1, y consideró entregable la candidata.
No se solicitó otra revisión: se resolvieron los puntos con código y pruebas.

- Orden de publicación (P2): aceptado y documentado en RESULTADO, pasos 2/4/5: TC si corresponde → migración de fecha comercial → frontend. Reversa operativa: frontend anterior primero; conservar SQL aditivo. La nueva pantalla falla explícitamente contra un servidor anterior por diseño; nunca mezcla criterios.
- Ambigüedad/visibilidad (P3): aceptado. Unicidad global antes del ámbito en ambos lectores. El gestor conserva sus filas anteriores y añade una fecha nula cuando no hay un único cierre válido. Prueba con episodio histórico de un equipo y acreditación de otro: Gerencia y Supervisión no reciben una fecha arbitraria.
- Dos fuentes de fecha (P3): confirmado que la gestión procede de `private.conversion_cierres`. Se agregó la misma condición de tipo/unicidad y se verificaron raíz y gestión para una fuente convertida en renovación. El payload instalado también pasa por el parser y el cálculo real del frontend.
- Marca `cierre_posterior` (P3, hipótesis del reviewer): el cuerpo vivo compara únicamente `coalesce(c.ultimo_cierre>=t.vence_en,false)`, con cierre canónico no anulado. La marca se conserva para clientes anteriores. La pantalla nueva compara por día comercial y usa la asistencia real cuando existe; la raíz ya exige conversión activa, perfil cliente, registro conocido y ausencia de anulación. Comentario y pruebas explicitan la diferencia intradía.
- Censo (P3): aceptado `EXCEPT ALL` en ambos sentidos. No se alteran los 11 hallazgos globales previos.
- Orden de movimientos bancarios (P3): aceptado; preserva hora antes de desempatar por ID. Regresión probada con IDs en orden inverso a los instantes.
- Formato de fecha: `FechaSchema = v.pipe(v.string(), v.isoDate())`. Tres pruebas adicionales rechazan fecha sin ceros, formato local e instante con hora. La fecha de SQL es `date`.
- CSV: prueba fortalecida para comprobar mes, clientes vinculados, porcentaje, clientes comerciales y columna final en la fila exacta del analista.
- Latencia: veinte muestras del fixture sintético real: mediana anterior 5,44 ms y comercial 7,44 ms. Es una medición local pequeña; no acredita latencia productiva a escala.
- Configuración: 16 combinaciones de mes/analista/base/manuales concilian servidor y pantalla, con manual propio y atribución diferente.

Los gates remotos no ejecutados y el censo global previo siguen declarados en
RESULTADO; no se convierten en PASS por el dictamen ni por estos ajustes.

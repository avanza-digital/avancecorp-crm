# H5 — revisión independiente y resolución

Una consulta mediante `scripts/claude-review`, con Codex PRIMARY y Claude
SECONDARY_REVIEWER aislado y sin herramientas. CodeGraph se intentó primero:
la copia aislada no tiene índice y la herramienta indicó continuar con lecturas
puntuales. No se creó un índice ni se cambió configuración durante la revisión.

Dictamen original: **CHANGES_REQUESTED / MEDIUM**, sin P0/P1. Se conserva
[íntegro](evidencias-h5-2026-09-24/review-claude.md), junto con
[la evidencia enviada](evidencias-h5-2026-09-24/review-pedido.txt).
No se atribuye un PASS de Claude ni se pide otra opinión para cambiar el dictamen.

| Hallazgo | Decisión y evidencia del PRIMARY |
|---|---|
| P2: sesión demo/sin avisos mostraba un fallo y reintento inútil | Aceptado. `AlertasDelDia` distingue indisponibilidad, carga y error. Dos casos nuevos fallaron antes y pasan después; el error real conserva el reintento. |
| P2: medición limitada a tres RPC | Aceptado. El E2E registra todas las peticiones `/rest/v1/` por método/ruta y compara equipos de 1 y 32 analistas dentro del mismo test, en contextos separados y con reloj fijo. |
| P3: aserciones negativas inmediatas | Aceptado. Se comprueba la UI y se espera la finalización de peticiones antes de cada medición; se comprueba también el refresco explícito. |
| P3: aserciones dentro del handler | Aceptado. El handler guarda el cuerpo y responde; la aserción se ejecuta después. Los nuevos IDs son UUID válidos. |
| P3: supuesto doble fetch en registro del equipo paginado | No reproducido. El nuevo E2E mantiene en vuelo la respuesta, pagina a 26, refresca desde cabecera y observa **una** primera página con filtro Llamadas conservado. Pasó antes de cualquier arreglo de este código; no se modificó el hook ni el componente Registro. |
| P3: contador y lista con distinto significado | Aceptado. La franja dice «Otros sin reconocer»; el listado conserva los reconocidos y su explicación. Pruebas existentes del contador actualizadas. |
| Observación: referencias mutadas durante render | Diferida. No se demostró una regresión observable. Se mantienen los guards y pruebas de aislamiento; no se hace un refactor de concurrencia dentro de este cierre. |
| Warning del linter en Contacto | Revisado con salida exacta: `jsx-a11y(control-has-associated-label)`, `tabla-equipo-diaria.tsx:48:17`. La celda tiene texto alternativo `sr-only`; el árbol accesible nativo expone numerador, denominador y mínimo. No se deshabilitó ninguna regla ni se añadió un nombre redundante. |

La primera comparación de todos los endpoints detectó una diferencia **solo
intermedia** en `postventa_agenda_fn`: su refresco paralelo terminó después de
la foto del error, pero antes de la recuperación. Los conteos iniciales, los
cambios de pestaña y el ciclo terminado eran iguales. Se conservan ambas
mediciones; se compara cada etapa estable y la recuperación completa, sin
excluir ningún endpoint del contador.

Resultados de la corrección: **50 pruebas / 3 archivos PASS** y **14 E2E
dirigidos PASS**, Docker local, cero retries. La verificación integral final
se registra en [el acta H5](SUPERVISOR-HORIZONTAL-H5-EVIDENCIA-2026-09-24.md).

La primera suite completa detectó además una carrera del test del popup:
`loginReal` esperaba el menú cuando Radix ya lo había ocultado del árbol
accesible por el diálogo modal. La captura de error mostraba el popup correcto.
Solo ese escenario deja que el test espere directamente el popup; no cambia
el login del producto ni el helper compartido. El recorrido dirigido pasó.

El typecheck detectó `unknown` usado como hijo condicional de React en el
arreglo inicial. Se convirtió explícitamente a booleano; typecheck PASS.
Se interrumpió la suite en curso para volver a verificar una fuente estable.
Los intentos previos se conservan; no se contabilizan como PASS finales.

Límites: reloj del cliente y portal Radix conservan sus decisiones documentadas
en H4; no se afirma ensayo humano de medianoche, VoiceOver/NVDA o Safari.
H6 requiere backend compatible, flujo de publicación autorizado y aceptación
real. La revisión no sustituye estos pasos.

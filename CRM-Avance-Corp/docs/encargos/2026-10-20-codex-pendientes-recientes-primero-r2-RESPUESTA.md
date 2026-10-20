**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** C3, C4 y C5 quedan cerrados. Acepto los rechazos de C2 y C6, y retirar la clasificación P1 de C1 manteniendo su riesgo operativo documentado. Encuentro una regresión concreta de cobertura en el arnés actualizado; no un nuevo defecto demostrado de autorización o paginación.

Los siguientes estados califican la disposición del PRIMARY:

- **C1 — ACEPTADO el rechazo como P1.** El aviso y la espera no garantizan retirar todos los consumidores: dejar una pestaña v3 sin recargar, ejecutar la reversa al día siguiente y pulsar «Cargar más» sigue produciendo `PGRST202`. Esto refuta que el plazo garantice compatibilidad, pero reproduce precisamente la limitación que ahora reconoce la cabecera. No lo presento como riesgo nuevo ni exijo conservar v3 indefinidamente.

- **C2 — ACEPTADO el rechazo.** Con la evidencia del contrato y del funcionamiento de la cola, retiro la exigencia de versionarla. La repetición u omisión durante un recorrido por páginas sigue siendo posible, pero ese recorrido ya admite cambios entre peticiones. No se demuestra una incompatibilidad adicional del consumidor antiguo.

- **C3 — ACEPTADO; cerrado.** La página de 16 vencidas corta efectivamente el empate: cursor en 25 y segunda página exactamente `[24]`. La aserción detecta el mutante que omite el ID; su fallo está informado por el PRIMARY.

- **C4 — ACEPTADO; cerrado.** El preflight fija ambos comentarios anteriores y el postflight de la reversa comprueba su restitución. Esto cubre el caso que originó el hallazgo.

- **C5 — ACEPTADO; cerrado.** La fecha nueva queda por debajo del cursor descendente. El test ahora representa una reaparición posible y comprueba que prevalece la versión posterior de la tarea.

- **C6 — ACEPTADO el rechazo.** Con el mismo ayudante y bloqueos `FOR SHARE`, no hay conflicto entre esos lectores que sostenga el interbloqueo v2/v3 planteado. No tengo un caso concreto que demuestre un riesgo nuevo.

- **A8 — ACEPTADO para resumen y corte.** Ambos proceden ahora de la misma primera respuesta, mientras `hayMas` continúa usando `consulta.hasNextPage`. La explicación del comentario necesita una precisión, indicada abajo.

**Nuevo hallazgo [P3]: el test de «Siguiente entre páginas» ya no cruza una página.**

Evidencia: bloque `salto` de [gestion-diaria-cola/prueba.sql](/Users/usuario/dev/avancecorp-crm-orden-pendientes-20261020/CRM-Avance-Corp/supabase/scripts/gestion-diaria-cola/prueba.sql).

Después de gestionar los registros 530 y 529 quedan 528 pendientes, ordenados `528…1`. Con límite 8 y páginas desde cero:

- `n=10` ocupa la posición 518, página 64.
- `n=9` ocupa la posición 519, también página 64.

La nueva aserción `10 → 9` comprueba sucesión, pero perdió la cobertura del cruce que tenía el test anterior. Puede pasar aunque exista una regresión específica al atravesar el límite.

**Corrección concreta:** usar `9 → 8` y comprobar también que el anclaje pasa de la página 64 a la 65.

**RIESGOS:**

- El comentario de A8 afirma que todas las páginas posteriores quedan antes del corte inicial. Eso solo está garantizado en «Vencidas». En «Todas», puede haber más de 25 tareas futuras y la segunda página también contener fechas posteriores al corte. Esto no invalida usar el corte inicial para clasificar; sí requiere acotar la explicación.
- No se aporta una prueba del hook que compruebe conjuntamente resumen/corte iniciales y finalización de la paginación. Las pruebas de `unirPaginasPendientes` no verifican ese comportamiento.
- Ciclo de reversa y mutantes: **PASS informado**. Ejecución independiente: **NOT RUN**, conforme al encargo. No hay resultados finales nuevos de `check`, E2E, matriz RLS modificada ni estado actualizado de H3.

**NEXT ACTIONS:**

1. Restaurar el cruce real de página en el arnés.
2. Precisar el comentario de A8 y verificar el comportamiento del hook con dos páginas.
3. Adjuntar los checks pendientes, incluyendo la matriz con `CRM_RLS_EXIGE_GESTION_DIARIA=1`.

**CONFIDENCE: MEDIUM.** Alta para los cierres y el cálculo del arnés; limitada a la evidencia transcrita para ejecución e integración.

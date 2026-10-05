**VERDICT: BLOCK**

**SUMMARY.** La recepción persistente cierra los ataques de reenvío descritos, pero el diseño todavía no permite afirmar que los fallos estén resueltos. Faltan cambios esenciales en el contrato Edge–RPC, una identidad de evento segura durante toda la vida del dispositivo, reglas completas de bloqueo y una barrera de activación del despliegue. El SHA-256 propuesto tampoco elimina la conservación recuperable de teléfonos.

Revisión exclusivamente estática: **pruebas NOT RUN**. Conservo las abreviaturas **D, N, I, E y H** de la revisión anterior; **X** corresponde a `supabase/functions/crm-llamadas-ingesta/index.ts`. El plan no está numerado: lo cito por sección.

**RESPUESTA P1 — Sí para los ataques enumerados; no basta para afirmar que solo queda el tiempo.**

Reservar atómicamente una recepción para **todo origen válido nuevo**, antes de consultar leads, y consumir cupo también en los duplicados elimina la diferencia entre `E:141–149` y `E:187–190`. Con confirmación uniforme de cupo y salud, cierra también los observables de `I:278–282`. El ataque «ignorado → mismo origen con lead propio» deja de crear un evento, incluso después de purgar.

Condiciones necesarias:

- Recepción y evento deben confirmar conjuntamente cuando corresponde guardar el evento. No capturar un fallo de inserción y confirmar únicamente la recepción con 202: el reintento quedaría descartado para siempre.
- Los duplicados deben actualizar cupo y `ultimo_envio_en` antes de cualquier retorno.
- Los errores dependientes del procesamiento del lead requieren análisis: un bloqueo que termine en 503 puede convertir una diferencia temporal en una diferencia de respuesta. Es un riesgo pendiente, no un oráculo nuevo demostrado aquí.

**Etiqueta: sí para rotar; no como identidad permanente sin más contrato.** Rotar conserva la etiqueta (`N:601–605`), pero también puede reutilizarse después de cerrar (`N:529–536`). Con ids locales reutilizables, una llamada nueva recibiría 202 y se perdería por colisión con una recepción antigua. Hace falta una identidad estable del dispositivo o de su instalación, independiente de la credencial, y un id aleatorio generado una sola vez por llamada y conservado en todos sus reintentos.

**RESPUESTA P2 — Sí frente a cerrar/rotar, con límites que deben quedar explícitos.**

Asignación `FOR SHARE` → estado `FOR UPDATE` establece un orden compatible con cerrar y rotar, que toman `FOR UPDATE` sobre la asignación y no bloquean el estado en los cuerpos transcritos (`N:559–571`, `N:591–605`). No aparece un ciclo entre esas rutas.

Si gana el cierre, la petición debe revalidar y responder 401 antes del cupo. Si gana la petición, el cierre espera su finalización. Esto garantiza orden de confirmación en la base; no garantiza que la respuesta HTTP del latido llegue antes que la del cierre.

La hora debe capturarse **después del bloqueo del estado**, no solamente después del bloqueo de la asignación. Reiniciar únicamente al avanzar la ventana corrige `I:150–177`; también deben calcularse correctamente los `Retry-After` cuando el reloj retrocede.

Dos límites:

- Bloquear la asignación no bloquea por sí mismo una baja en `crm.equipo` o `public.perfiles`, consultadas por `private.rol_crm` (`E:129–132` y definición viva aportada). La coordinación de esa revocación sigue sin acreditarse.
- Debe aclararse si los timestamps de salud usan la misma hora capturada: actualmente emplean `now()` (`I:220`, `I:315`) y pueden retroceder por el orden de inicio de las transacciones.

**RESPUESTA P3 — Sí: devolver un resultado normal permite conservar el consumo; `EXCEPTION` no está desaconsejado en general.**

Una excepción que sale de la RPC revierte el consumo anterior (`I:308–314`). Para errores esperados de validación, la RPC puede confirmar normalmente un resultado discriminado y la Edge convertirlo en HTTP 400.

También es correcto consumir **fuera** de un bloque interior `EXCEPTION` que capture únicamente errores esperados de validación. La subtransacción revierte lo hecho dentro, no el consumo anterior. Tiene coste, pero no justifica prohibirla; evitaría `WHEN OTHERS` para disfrazar errores inesperados de problemas del cliente.

**El plan no cierra todavía el circuito completo:**

- La Edge devuelve 400/413 antes de llamar a la base (`H:112–122`): esos inválidos seguirían sin gastar cupo.
- La Edge ignora el resultado normal de las RPC (`H:127–132`), y `X:14–16` solo lanza ante errores de PostgREST. Un resultado normal «inválido» acabaría respondiendo 202/200 si no cambia este contrato.

Debe definirse cómo se autentican y contabilizan los cuerpos inválidos, incluidos JSON mal formado y sobres inválidos, manteniendo el límite de lectura. Las excepciones de transporte —tamaño, método, tipo de contenido— también necesitan un alcance explícito para la promesa de 401 uniforme.

**RESPUESTA P4 — Sí, elimina la consulta histórica por estas puertas; eso no justifica conservar el bypass de gerencia.**

Exigir actividad del lead en el predicado compartido es correcto para alinear estas operaciones con `leads_select` y cerrar `N:137–142`. Una necesidad de auditoría histórica requeriría una capacidad específica de lectura, sin conceder mediante ella descartar, asociar o enlazar.

**Ocultar no equivale a caducar.** La baja lógica no ejecuta la cascada de `D:270`, y la purga actual no incluye identificadas registradas (`D:528–544`). Por tanto, incluso con los 30 días propuestos para pendientes, quedarían llamadas registradas de leads inactivos conservadas indefinidamente.

Recomiendo distinguir:

- Pendientes identificadas sin enlace: plazo explícito desde `recibido_en`.
- Descartadas: conservar su plazo desde `descartado_en`.
- Registradas, incluidas las de leads dados de baja: aplicar una política de archivo/retención acordada para el historial del lead.

No hay evidencia para imponer automáticamente 30 días a estas últimas. Esa decisión falta en la tabla.

**RESPUESTA P5 — Sí, si se filtra por ámbito, no por elegibilidad completa.**

Consultar únicamente candidatos activos del ámbito del dueño, bajo su identidad temporal, elimina tanto la ambigüedad global como la diferencia provocada por `guardar_sin_identificar` (`N:102–113`, `E:180–190`, `N:140–141`). Cero candidatos propios debe producir exactamente el mismo tratamiento, existan o no candidatos ajenos.

**No usar directamente `llamada_celular_elegible_dueno` como filtro de candidatos.** Su regla también excluye etapas terminales y `no_contactar` (`N:123–126`, `E:51–52`). Esos leads propios deben seguir identificándose y quedar `por_revisar`. Se reutiliza el mecanismo de identidad, no ese predicado completo.

Se pierden dos comportamientos legítimos:

1. La llamada a un lead ajeno deja de llegar al equipo de ese lead, contradiciendo el criterio anteriormente aceptado (`N:34–35`).
2. Un teléfono compartido por un lead propio y otro ajeno pasa de ambiguo a identificado con el propio. La identificación significa «coincidencia única en esta cartera», no identidad global demostrada.

Miguel debe aceptar ambos efectos. El respaldo de Jhosep no sustituye esa decisión.

**RESPUESTA P6 — Sí para una entrante correctamente declarada; no para garantizar que toda llamada almacenada sea saliente.**

Con tablas vacías, `entrantes_activas NOT NULL` (`D:107`), un `CHECK` que la mantenga falsa y rechazo explícito en la puerta impiden activar la ruta defectuosa. La ingesta ya ignora `direccion='entrante'` cuando está apagada (`E:154–156`).

Pero `direccion='desconocida'` continúa el procesamiento y puede terminar en `requiere_resultado` (`E:158–159`, `E:174–179`). Debe decidirse si eso es válido para el piloto «solo salientes» o si corresponde `por_revisar`/ignorado.

Además, la base no puede detectar una entrante que la macro etiquete falsamente como saliente. El arreglo del estado `en_saliente` necesita pruebas reales; el código de la macro no está transcrito. El bloqueo de política no sustituye esa validación.

**RESPUESTA P7 — A: sí, recomendada con condiciones. B: no garantiza recuperación exacta posterior.**

F1 recibe actualmente una URL con el número, sin identidad de evento (`H:63–67`). Si hay varias llamadas y encuestas del mismo lead, la coincidencia por número y tiempo no permite recuperar inequívocamente la relación uno a uno exigida por `D:405–408`. «Limpiar después» puede producir enlaces falsos, pendientes falsos o pérdida definitiva al caducar.

La opción B solo sería aceptable reconociendo expresamente que parte del histórico puede quedar sin reconciliar; no debe prometer reconstrucción automática exacta.

**Treinta días es una propuesta razonable, no una regla ya ratificada para identificadas.** Debe aplicarse a estados pendientes sin enlace, desde `recibido_en` del servidor (`D:608`), excluyendo registradas y descartadas. Deshacer un resultado no convierte su llamada en «sin resultado» a efectos de purga: el enlace permanece por contrato (`D:21–24`).

A también tiene un hueco: una hora del celular adelantada más de diez minutos puede impedir enlazar una encuesta real (`N:423–425`). La ingesta acepta fechas hasta 2100 y solo marca el adelanto (`E:124–125`, `E:161–162`). El id exacto no corrige esa incompatibilidad. Falta revisar el contrato de F4-a, no transcrito.

**RESPUESTA P8 — No: “pequeña frente a la red” no demuestra que el canal sea aceptable.**

El ruido de red puede reducirse mediante observaciones repetidas. Comparar únicamente p50/p95 no mide la capacidad de distinguir casos. Los límites ralentizan la adquisición de muestras, pero no la eliminan (`I:74–77`).

Una medición útil debe:

- Intercalar aleatoriamente solicitudes equivalentes con ids nuevos: lead propio, ajeno, varios ajenos y ningún lead.
- Mantener iguales tamaño, formato, credencial y condiciones de conexión.
- Separar primeras recepciones de duplicados y cubrir caché fría/caliente y carga.
- Medir el recorrido completo Edge–PostgREST–base; usar tiempos internos solo para diagnóstico.
- Estimar intervalos de confianza y capacidad de clasificación con el número de muestras alcanzable por un atacante, incluyendo errores y timeouts.

Si #12 conserva su alcance estricto, hace falta desacoplar la respuesta del procesamiento dependiente del lead **o justificar una garantía equivalente**. Medir y aceptar riesgo exige una modificación explícita del alcance, no declarar el canal cerrado.

El desacoplamiento tampoco resuelve todo automáticamente: una cola durable con el teléfono sigue guardándolo; un 202 previo a procesamiento sin respaldo durable puede perder llamadas. Esa tensión con F2 debe resolverse expresamente.

**RESPUESTA P9 — No: SHA-256 sin secreto no es suficiente para el objetivo declarado.**

El alfabeto permitido admite teléfonos completos (`D:237–239`, `E:99–101`, `H:28`). Si el id es un teléfono, su SHA-256 puede comprobarse contra un diccionario de números. El propio proyecto reconoce ese problema para `hash_payload` (`D:396–400`). Sacarlo de la auditoría elimina una copia, pero la recepción permanente conserva otra representación recuperable.

Recomiendo ids aleatorios opacos, generados una sola vez por la macro y persistidos con el evento. Restringir el formato evita errores comunes; **una expresión regular no garantiza entropía ni independencia del teléfono**.

Si se mantiene la aceptación de ids controlables por el cliente, considerar HMAC con secreto protegido separadamente del almacén de recepciones. Su rotación debe conservar la deduplicación histórica; cambiar la clave sin estrategia puede volver a admitir eventos antiguos.

El evento puede referenciar la recepción por su UUID: no necesita otra copia del hash. Tampoco debe describirse la recepción como anónima o «sin datos personales» sin analizar su vinculación con dispositivo e historial.

**RESPUESTA P10 — Sí frente a un `UPDATE` de la misma fila; no puedo acreditar todas las rutas reales de reasignación.**

Un `UPDATE crm.leads` toma un bloqueo de fila incompatible con `FOR SHARE`, normalmente `FOR NO KEY UPDATE` si no cambia una clave relevante. `FOR KEY SHARE` sería insuficiente para proteger cambios ordinarios de propietario.

Sin embargo, las funciones y triggers reales de reasignación no están transcritos. Las policies aportadas no prueban su orden de bloqueo.

El diseño necesita además:

- **Asociar:** proteger el lead anterior y el destino. La autorización depende de ambos (`N:358–375`).
- **Enlazar:** coordinar la lectura de la actividad con Deshacer. Hoy se lee sin bloqueo (`N:415`, `D:470`); añadir solamente una condición sobre `deshecho_en` no demuestra serialización.
- **Orden global:** si se conserva evento → lead, puede chocar con un borrado físico que tome lead → evento mediante la cascada de `D:270`. Debe fijarse un orden compatible y revalidar las referencias tras obtener los candados.

Los cambios de jerarquía en `crm.equipo` tampoco quedan protegidos únicamente bloqueando el lead.

**RESPUESTA P11 — Sí: hay cambios de contrato y huecos fuera de las seis decisiones.**

La decisión 3 sustituye una conducta aceptada (`N:34–35`); necesita ratificación expresa. La retención de identificadas es una ampliación, no parte de los 30 días ratificados. Y el encargo declara #12 aceptada: el plan no puede tratarla simultáneamente como pendiente ni rebajarla por una diferencia temporal aparentemente pequeña.

Sobre los criterios finales de Claude:

- **Etiqueta:** aceptable para rotación, insuficiente sin contrato de reutilización e identidad.
- **Hash del origen:** insuficiente frente a ids de baja entropía.
- **Recepciones permanentes:** coherentes mientras cualquier origen antiguo pueda volver a aceptarse. No son la única solución posible; podrían retirarse al cerrar irrevocablemente un espacio de identidades. Requieren presupuesto de crecimiento y una política explícita.
- **Una quinta migración:** correcto; «mismo despliegue» no establece atomicidad ni cierre seguro ante fallo.

Otros puntos omitidos:

- El límite sigue siendo **por asignación**, por lo que rotar reinicia el cupo (`I:83–84`, `I:157–159`, `N:603–605`).
- Los latidos no tienen `evento_origen_id` (`I:189`, `H:31`). El «mismo orden» no puede incluir literalmente la recepción idempotente sin cambiar su contrato.
- Una recepción en `crm` sin auditoría necesita resolver la regla de rastro; la excepción técnica existente se justifica por estar en `private` (`I:9–13`).
- F4 debe localizar por la identidad completa, no únicamente por hash.
- La reversa posterior al inicio del tráfico debe conservar recepciones y hechos, cerrar las puertas necesarias y evitar reinstalar las fugas. No puede reconstruir ids originales a partir de hashes.

**FINDINGS P0–P3 nuevos**

No identifico P0 ni P1 con la evidencia disponible. Los siguientes son hallazgos del diseño; no afirmaciones sobre una quinta migración todavía inexistente.

1. **P2 — La corrección de consumo de inválidos queda desconectada de la Edge.**  
   Los retornos anticipados evitan el contador (`H:112–122`), y un error devuelto normalmente por la RPC sería ignorado (`H:127–132`, `X:14–16`). El plan §5 debe incluir el nuevo contrato de admisión y resultados, además de fecha y eliminación del 409.

2. **P2 — La recepción permanente puede conservar teléfonos recuperables.**  
   El origen admite un teléfono (`D:237–239`); convertirlo en SHA-256 no elimina su baja entropía, problema ya reconocido en `D:396–400`. La permanencia propuesta amplía el impacto de ese error.

3. **P2 — Reutilizar etiqueta e id puede descartar silenciosamente una llamada nueva.**  
   Se permiten nuevas asignaciones de una etiqueta cerrada (`N:529–536`) y no hay garantía de ids globalmente irrepetibles (`D:237–239`). Con la nueva unicidad permanente, una colisión legítima recibe éxito sin crear evento. F4 tampoco puede buscar inequívocamente usando solo el hash.

4. **P2 — El diseño de candados no cubre todas las dependencias de autorización y enlace.**  
   Asociar depende del lead anterior y del destino (`N:358–375`); enlazar depende de una actividad leída sin bloqueo (`N:415`). El plan no fija ese conjunto ni su orden. Los intercalados descritos en P10 deben cerrarse o refutarse con las rutas reales; no están reproducidos en esta revisión.

5. **P2 — El enlace exacto puede seguir rechazando llamadas por un reloj adelantado.**  
   Un evento con fecha futura válida se acepta y se marca (`E:124–125`, `E:161–162`), pero su encuesta queda rechazada por `N:423–425`. La opción A necesita resolver esta regla, no únicamente transportar el id.

6. **P2 — Falta una barrera verificable ante fallo de la quinta migración.**  
   Las cuatro anteriores confirman separadamente (`D:748`, `N:1044`, `I:529`, `E:265`) y conceden acceso a puertas (`N:900–908`, `I:388–396`). Si la quinta falla, su precondición no revierte esas concesiones. La publicación necesita impedir activación y entrega de credenciales hasta verificar la quinta, y dejar una salida segura ante fallo.

7. **P3 — Rotar conserva la deduplicación propuesta, pero reinicia el límite por celular.**  
   El estado sigue vinculado a la asignación (`I:83–84`) y la rotación crea otra (`N:603–605`). No es un bypass autónomo del analista —requiere gerencia—, pero contradice la continuidad implícita del límite por dispositivo. Debe conservarse el contador o documentarse expresamente esa excepción.

**RIESGOS y test gaps.** Todo lo siguiente permanece **NOT RUN** en esta revisión:

- Recorrido completo Edge–RPC para inválidos, duplicados, revocados y cupo agotado, comprobando qué transacciones confirman.
- Reintentos después de rotación, sustitución del dispositivo, reutilización de etiqueta, purga y pérdida de la respuesta HTTP.
- Barreras de concurrencia con las rutas reales de reasignación, baja de usuario, Deshacer, enlace y purga; incluir origen y destino de asociación.
- Leads propios terminales o con `no_contactar`, teléfonos compartidos entre ámbitos y ambos valores de `guardar_sin_identificar`.
- Retención sin adelantar la caducidad de descartadas ni eliminar registradas por haber deshecho su resultado.
- Enlace F4 con reloj adelantado, entrega tardía, origen sin evento y evento caducado.
- Fallo deliberado de la quinta migración, comprobación de vacío bajo bloqueo y reversa con datos existentes.
- Restauración de identidad y auditoría en éxito y error tras ampliar la consulta bajo identidad temporal.

**NEXT ACTIONS.**

1. Completar el diseño de identidad, privacidad del origen y contrato Edge–RPC antes de escribir la quinta.
2. Fijar el conjunto y orden de bloqueos, adjuntando las rutas reales de reasignación y Deshacer.
3. Resolver con Miguel ámbito, alcance temporal de #12 y retención completa; recomendar A sin prometer recuperación exacta mediante B.
4. Añadir el contrato de F4-a y la barrera de activación/reversa.
5. Reservar la ronda 2 para el diff y los resultados reales de los casos anteriores.

**CONFIDENCE.** Alta en los problemas de Edge, hash recuperable, reutilización de identidad, reloj y commits separados. Media en la concurrencia del sistema completo: faltan las implementaciones de reasignación, baja, Deshacer y F4-a.

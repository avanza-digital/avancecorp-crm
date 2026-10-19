**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** No identifico una fuga concreta en el filtro por autor mostrado. Sí encuentro cuatro problemas accionables: el postflight puede ocultar una ACL indebida del ayudante, el legado diverge del Registro al apagar postventa, las contestadas por hora incluyen llamadas sin resultado y la reversa puede confirmar dejando sellos incompatibles.

El ensayo acredita el recorrido nominal reportado. La composición con `20261016211001` real en ambos órdenes sigue sin demostrarse. Ejecución independiente por este reviewer: **NOT RUN**.

**RESPUESTAS P1–P6**

1. **P1 — Acceso indebido: no encuentro un camino demostrado en los predicados transcritos.** Se exige sesión, acceso al CRM, rol permitido, exclusión del lector global y habilitación; después se intersectan los autores solicitados con los visibles ([migración:163](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:163), [migración:176](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:176)). La autorización histórica por autor corresponde a la decisión declarada.

   **¿Puede lanzar en solo lectura? Sí.** La llamada de [migración:166](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:166) llega a `resolver_en_puertas_bajo_candado()`, que lanza `0A000` con aislamiento distinto de `READ COMMITTED`, incluso dentro de una transacción `READ ONLY`. Esto no contradice el ensayo reportado bajo `READ COMMITTED`. El cuerpo mostrado usa un candado advisory, sin el `SELECT FOR SHARE` problemático. Los cuerpos de `puede_acceder_crm`, `rol_crm`, `es_lector_global` y `piloto_f8_actor_activo` no están incluidos; no puedo certificar todas sus rutas internas.

2. **P2 — No hay equivalencia completa.** Para cierres de postventa coinciden el tipo, el estado efectivo y la clasificación; `tipo = 'llamada_realizada' AND util` coincide con `contacto` del Registro (`private.gestiones_clientes_eventos:21`, `:41`, `:65`). El Registro no expone una columna `util` para comparar literalmente.

   La divergencia adicional comprobable es el **legado con postventa apagada**, descrita en F2. Además, el ayudante fuerza el estado legado a `completada` ([migración:192](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:192)), mientras el Registro conserva `coalesce(t.estado,'completada')` y calcula `operativa` con él (`Registro:32`, `:64`). Sin el cuerpo de `gestiones_resumen_fn` no atribuyo a esta última diferencia un efecto probado sobre sus totales.

3. **P3 — Sí funcionan los reemplazos sobre el gate numerado mostrado; no está acreditada la composición completa en ambos órdenes.** El preflight exige una aparición de cada ancla, y los reemplazos modifican los sellos del lector y agregador correspondientes ([migración:99](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:99), [migración:331](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:331)). No veo un resellado ajeno accidental en ese cuerpo ni placeholders que sobrevivan al postflight nominal.

   Esto compone con **un reemplazo independiente del sello del roster**. Sin embargo, `ensayar.mjs` instala primero esta migración y después simula ese reemplazo ([ensayar.mjs:90](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/scripts/gestion-diaria-llamadas-clientes/ensayar.mjs:90), [ensayar.mjs:102](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/scripts/gestion-diaria-llamadas-clientes/ensayar.mjs:102)). No se incluye ni ejecuta aquí la migración `211001` real.

4. **P4 — Sí puede aceptar un fallo propio; no demuestra que únicamente permanezcan los rojos conocidos.** El error del roster interrumpe el gate antes de alcanzar la nueva sección 2b. El postflight tolera esa excepción y su comprobación independiente de ACL es incompleta ([migración:465](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:465), [migración:495](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:495)). Véase F1.

5. **P5 — No está garantizada la restauración exacta en ambos órdenes.** El ensayo reportado sí comprueba los cuerpos originales después de deshacer sus simulaciones ([ensayar.mjs:143](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/scripts/gestion-diaria-llamadas-clientes/ensayar.mjs:143)). Existe, además, un caso en que la reversa confirma con sellos incorrectos: F4.

   **La regex funciona para el bloque insertado mostrado.** Si cambia su separador, puede no encontrarlo y abortar de forma segura. Si se añade otra sección entre 2b y 3, puede eliminarla también: el límite es el siguiente comentario de sección 3, sin verificar el contenido retirado ([reversa.sql:26](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/scripts/gestion-diaria-llamadas-clientes/reversa.sql:26)). Este segundo caso es un riesgo condicionado a una edición posterior, no un fallo observado en el ensayo.

6. **P6 — Sí faltan negativos; los mutantes evitan la vacuidad por gate previamente rojo, pero algunos no aíslan lo anunciado.** El requisito de verde inicial está correctamente implementado ([migración:415](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:415)). Sin embargo:
   - El mutante 8 elimina tanto la bandera como la llamada al resolver; cualquiera de esas ausencias satisface la misma comprobación estructural ([migración:428](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:428)).
   - El 11 sustituye todo el agregador y devuelve ceros en otras métricas. Su rechazo por huella no demuestra específicamente la protección del filtro de NULL ([migración:431](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:431)).
   - El manejador cuenta cualquier excepción del gate como detección, sin verificar qué contrato falló ([migración:441](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:441)).

**FINDINGS**

**[P1] F1. El rojo conocido del roster puede ocultar una ACL indebida del ayudante**

**Evidencia:** `private.assert_gestion_diaria_analista:57` comprueba el roster dentro del bloque 2; la sección nueva se inserta después de ese bloque, en [migración:334](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:334). El postflight solo comprueba EXECUTE para `authenticated` y ausencia para `anon`.

**Contraejemplo:** una ACL por defecto concede EXECUTE sobre nuevas funciones a un tercer rol. El `REVOKE` de [migración:214](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:214) no elimina ese permiso. El chequeo independiente pasa, el gate lanza primero por el roster y la migración acepta la excepción. La comprobación exacta de ACL de 2b nunca se ejecuta.

**Impacto:** puede confirmarse una instalación que incumple su propio contrato de permisos. Esto no demuestra por sí solo una fuga de filas.

Además, la tolerancia usa el prefijo del error del roster sin fijar su huella conocida. La excepción del censo admite cualquier lista sin los nombres excluidos, no únicamente las diez piezas conocidas ([migración:507](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:507)).

**Recomendación:** ejecutar las comprobaciones propias completas aunque exista el rojo ajeno, y delimitar las excepciones mediante la huella y el conjunto de discrepancias conocidos.

**[P2] F2. Apagar postventa retira un legado que el Registro conserva**

**Evidencia:** el ayudante aplica las banderas al conjunto común de autores, antes de ambas fuentes ([migración:167](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:167)). En `private.gestiones_clientes_eventos`, `v_f6` condiciona la rama de postventa en la línea 27; la rama legado de la línea 34 carece de esa condición.

**Contraejemplo:** A1, llamada realizada del autor visible, sin tarea ni espejo, con postventa apagada y sin piloto. La rama legado del Registro la conserva; el ayudante devuelve cero. Es una divergencia adicional a F5.

El oráculo consolida esa diferencia al esperar únicamente leads después de apagar postventa ([oráculo:315](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/scripts/gestion-diaria-llamadas-clientes/test-gestion-diaria-llamadas-clientes.sql:315)).

**Recomendación:** separar la habilitación de postventa de la selección del legado y comprobar paridad también con la bandera apagada.

**[P2] F3. Una llamada sin resultado incrementa las contestadas por hora**

**Evidencia:** el agregado principal exige `tipo = 'llamada_realizada' AND util` ([migración:260](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:260)); el agregado horario exige únicamente el tipo ([migración:284](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql:284)).

**Contraejemplo:** T11 produce `llamada_realizada`, `sin_resultado`, `util=false`. Por sí sola entrega `contestadas=0` en el total y `contestadas=1` en su hora. La nueva fuente vuelve normal esta discrepancia.

El oráculo permite expresamente ese exceso mediante una desigualdad ([oráculo:198](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/scripts/gestion-diaria-llamadas-clientes/test-gestion-diaria-llamadas-clientes.sql:198)).

**Recomendación:** aplicar la misma definición de contestada al desglose horario y exigir que su suma coincida con el total.

**[P2] F4. La reversa puede confirmar dejando huellas nuevas contra cuerpos antiguos**

**Evidencia:** obtiene las huellas actuales y las usa como texto que debe sustituirse, sin comprobar que los reemplazos hayan ocurrido ([reversa.sql:21](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/scripts/gestion-diaria-llamadas-clientes/reversa.sql:21), [reversa.sql:31](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/scripts/gestion-diaria-llamadas-clientes/reversa.sql:31)). Su postflight verifica únicamente los cuerpos restaurados del lector y agregador ([reversa.sql:159](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/scripts/gestion-diaria-llamadas-clientes/reversa.sql:159)).

**Contraejemplo:** después de instalar, cambiar el lector a `VOLATILE`. Su huella actual cambia, pero los gates siguen sellando `a209…`. La reversa busca la nueva huella, no encuentra coincidencias, restaura correctamente el lector original y confirma. Los gates del analista y Pulso conservan `a209…` frente al cuerpo restaurado `27d256…`.

**Recomendación:** validar el estado admitido antes de revertir, exigir reemplazos únicos y verificar los sellos restaurados de los tres gates preservando los cambios independientes.

**RIESGOS Y TEST GAPS**

- Falta ensayar `211001` **real** antes y después, incluyendo reversa. La referencia transcrita de Pulso contiene sellos nuevos y el censo neutralizado; no representa el estado previo anunciado.
- Faltan los negativos concretos de F1 y F4, y las comprobaciones funcionales de F2 y F3.
- Falta cobertura de actor sin acceso al CRM, lector global, rol excluido y combinaciones de piloto/banderas.
- Faltan metadatos ausentes o contradictorios con la tarea y un evento exactamente en `p_fin`.
- Varias aserciones usan `<>` sobre campos JSON potencialmente ausentes: un NULL puede dejar la condición sin disparar. Conviene usar `IS DISTINCT FROM` para los valores obligatorios ([oráculo:187](/Users/usuario/dev/avancecorp-crm-llamadas-clientes/supabase/scripts/gestion-diaria-llamadas-clientes/test-gestion-diaria-llamadas-clientes.sql:187)).
- La ejecución en `READ ONLY` consta como PASS reportado en el resumen, pero no está incorporada al ensayo transcrito.

**NEXT ACTIONS**

1. Corregir F1–F4.
2. Añadir sus contraejemplos al ensayo y hacer específicos los mutantes 8 y 11.
3. Ejecutar ambos órdenes con `211001` real y registrar separadamente los resultados nominales, los negativos y la cadena en solo lectura.

**CONFIDENCE: MEDIUM.** Los contraejemplos señalados se desprenden del código. La evaluación completa de dependencias de autorización y compatibilidad entre migraciones queda limitada por los cuerpos no incluidos.

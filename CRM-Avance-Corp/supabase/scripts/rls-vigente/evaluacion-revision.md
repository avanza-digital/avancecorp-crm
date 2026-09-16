# Evaluación del PRIMARY — reparación de la matriz RLS

Dos consultas, ambas mediante `scripts/claude-review`, sin herramientas ni
escritura del reviewer. Dictámenes **CHANGES_REQUESTED**, no PASS. El primer
informe detectó la lectura F3 sin candado; el segundo revisó la primera candidata.
Esta evaluación y las pruebas son la decisión del PRIMARY, no otro dictamen.

## Hallazgos aceptados y corregidos

- **P1: inversión de candados.** Aceptado. BEFORE ROW ya retiene la fila de
  control. La versión final usa `pg_try_advisory_xact_lock_shared` para F3 y
  `pg_try_advisory_xact_lock` para F8 antes de continuar. Si otro escritor tiene
  un candado incompatible, la activación aborta con P0409 y se puede reintentar.
  No espera reteniendo la fila/F3 y no necesita ampliar triggers a otras tablas.
  Ocho casos cubren los escritores aislados y F4→F3 / F3→F8 en una transacción.
  Un apagado F3 posterior sigue esperando una activación ya aceptada y cierra
  las tres puertas económicas. Se verifica que F8 conserva su estado.
- **P2: atributos de la función.** El preflight fija ahora la definición completa
  obtenida con `pg_get_functiondef`, no solo prosrc. El postflight fija exactamente
  GUC, volatilidad, paralelismo, coste, owner, atributos y privilegios de API.
  Se prueba el rechazo de una configuración inesperada y la reversa literal.
- **P2/P3: NULL y NEW en DELETE.** `v_f3` empieza en false; la guarda usa
  `is not true`. DELETE se rechaza antes de leer NEW y UPDATE se anida. Se fija
  el trigger BEFORE DELETE OR UPDATE, habilitado y vinculado a la función.
- **P2: reserva legacy D-10.** Se conserva la prueba de comportamiento OFF/ON
  y se restaura la huella completa vigente (`d408a22334cf70e5cb805d1e3b83b749`),
  contrastada con producción de solo lectura.
- **P3: candado observado.** La espera de la prueba identifica classid/objid/
  objsubid del candado F3 y conserva el primer resultado, sin volver a medir.
- **P3: comentario NaN.** Ahora describe el lead todavía no convertido y la
  validación del monto; no atribuye al caso un orden que ya no ejercita.
- **Registro del gate.** `test:rls:f8` ejecuta ambas suites; `check:scripts`
  comprueba sintaxis. El banco vacío requerido es intencional, no un skip.

## Hallazgos contrastados o límites documentados

- **Correo: confirmación/detector.** Las dos RPC eran parte de una propuesta
  nunca instalada, supersedida por `20260915173423`. El cierre vigente es el
  trigger diferido `private.sincronizar_correo_cliente_auth`, que valida actor,
  identidad y marca y confirma perfil/auditoría en la misma transacción Auth.
  No existe una RPC pública separada para cerrar el acuse. La prueba actual mide
  la frontera vigente y la inmutabilidad de Auth/perfil/identidades. La suite
  positiva completa vive en `../correo-admin/`; no se afirma haberla reejecutado.
- **Restauración de fixture.** `ejecutarFueraDeBanda` envía explícitamente
  `begin; ... commit;` mediante un único psql. Error, cierre o muerte de la
  conexión revierte el cambio transaccional de estado del trigger. Se añade
  comprobación de `tgenabled='O'` después. Se conserva este setup exclusivo de
  banco para restaurar la fila original sin efectos comerciales de reapertura.
  Todas las aserciones se ejecutan con los controles habilitados.
- **Expiración F8.** `private.piloto_f8_control_activo()` comprueba inicia_en y
  vence_en en cada lectura bajo candado; la hipótesis de piloto vencido no aplica.
- **Métricas.** El total.analistas mide filas del roster; los analistas fuera del
  roster se cotejan separadamente en cobertura, conservando deltas exactas de
  divisor/numerador. Las filas de vend1 se comparan campo a campo como Gerencia,
  Supervisor, Directorio y el propio analista. No se amplía la visibilidad.
- **DNI nulo.** BANK_CLIENT.dni es obligatorio y `verifySeed` lo comprueba. El
  estado nulo señalado por el reviewer no cumple las precondiciones del banco.
- **Timestamp SQL.** El archivo lo creó Supabase CLI en UTC. 16/09 04:04 UTC es
  15/09 23:04 Lima; no es una migración con fecha futura inventada.
- **Funciones de catálogo sin prefijo.** search_path vacío mantiene pg_catalog
  implícito; no hay explotación. Se conserva el estilo del cuerpo original;
  las nuevas llamadas try-lock sí están calificadas.
- **Mes NULL de facturación.** Se coteja con el mes corriente de Lima; si ambos
  están vacíos no prueba la diferencia frente a una implementación que siempre
  devuelve vacío. No se presenta como cobertura positiva de ese caso.
- **Meses cerrados.** El banco no contiene cierres históricos; la rama de metas
  retroactivas está expresamente no ejercitada. No se falsea ese resultado.

## Hallazgo adicional del ensayo remoto

La elección de analista para «solo referidos» podía seleccionar vend1 según el
orden de sus UUID. El mismo bloque asigna a vend1 una llegada automática y un
referido, contaminando ambos escenarios y provocando ocho errores. La selección
excluye ahora explícitamente a vend1. Se conservan las ocho expectativas exactas;
no cambia código de negocio ni la fórmula de conversión.

## Repetición sin reconstrucción: precondición corregida

Se ejecutó explícitamente la matriz por segunda vez sin restaurar el banco:
21 fallos por historial/fixtures retenidos, incluido el cliente que ya tenía
identidad canónica y flags alterados por la primera corrida. El protocolo
`LEEME-seed.md` exige limpiar/resembrar entre intentos; no autoriza reinterpretar
el estado final como fixture inicial. Se conserva ese contrato y se añade una
precondición de censo activo que aborta inmediatamente con instrucciones de
reconstrucción. No se relajan las expectativas ni se borran ledgers para forzar
un reintento verde. Los ensayos finales usan reconstrucción + seed, tanto local
como remoto. También se actualiza la allowlist exacta de origenes a los 17
campos vigentes (incluye citas_realizadas y leads_con_cita_real).

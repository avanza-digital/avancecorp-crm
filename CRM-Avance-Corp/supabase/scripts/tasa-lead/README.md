# Solicitud de tasa antes de convertir el lead

Estado al 9 de septiembre de 2026: **implementación validada localmente; banco remoto en curso**.
Miguel aprobó el SQL concreto y el costo de US$0,01344/hora de la rama temporal
con «hazlo». La rama `tasa-lead-publicacion-20260909` (`ehzftpvxuwuzinvkyhzz`)
se creó bajo `dctqcbznekcyxhjujuci`. Esa aprobación comprende completar la publicación.

Revisión recibida, evaluada y correcciones comprobadas: `REVISION.md`.
La actualización de Mi cartera de `avancecorp/main` hasta `e60d631` está integrada.
Revalidación integrada: 3.140 pruebas de frontend PASS; Playwright completo:
152 PASS y 26 SKIP (incluye escritorio y móvil para la tasa en el lead).

## Comportamiento

La ficha del lead muestra «Condiciones de inversión» y el recuadro existente de
solicitud de tasa. La política, la aprobación de Gerencia y la aceptación de un
tope son las mismas que para clientes. Pedir aprobación no crea un cliente ni
una cuenta. Una solicitud pendiente bloquea la conversión a Avance incluso si
se intenta volver a la tasa base; el cierre externo conserva su propio flujo.

El servidor comprueba permisos, identidad, vigencia y condiciones exactas antes
de reservar y antes de iniciar efectos. Al convertir, enlaza la misma solicitud
al cliente y conserva el lead de origen. La aprobación se consume al crear el
contrato, una sola vez. Capital, moneda, fechas, modalidad, interés, categoría,
producto y contrato origen forman parte de la intención autorizada.

Se exige completar el DNI del lead antes de enviar una solicitud especial.
Los cambios de condiciones invalidan el uso de la autorización para esa propuesta.
Una contraoferta superior a la base exige aceptación del solicitante. Las
solicitudes rechazadas o vencidas permiten utilizar la base si no hay otra
petición pendiente. Los borradores no enviados permanecen en el formulario;
las solicitudes enviadas se conservan en el servidor.

## Archivos y alcance SQL

- Migración: `../../migrations/20260909042103_crm_solicitud_tasa_lead_preconversion.sql`.
- Pruebas transaccionales: `../test-tasa-lead.sql`.
- `base-viva-huellas.json`: firmas, propietarios y ACL de las diez funciones
  consultadas en producción antes de preparar la migración.
- `base-viva-funciones.sql`: esas definiciones para reproducir el banco local.
  **No es una migración y no debe aplicarse a producción.**
- `revertir-antes-del-primer-uso.sql`: reversión condicionada, descrita abajo.

Se admite `cliente_id` nulo únicamente cuando existe `lead_id` en una solicitud.
Se añaden origen, huella previa y documento del lead, y las condiciones validadas
a la reserva de conversión. Se amplían las RPC de solicitud, lectura y conversión
sin retirar sus firmas anteriores. Se conserva RLS y se revoca el acceso directo
a los helpers internos. No hay DDL sobre `public`, cambios de banderas ni
aplicación automática de otras migraciones locales pendientes.

La migración abre una transacción, limita la espera de candados a cinco segundos
y rechaza cambios en las diez definiciones de partida, dos dependencias de
conversión/respuesta y la política RLS reemplazada. La lectura de
producción tras reanudar confirmó nuevamente las diez huellas. Si cambian antes
de publicar, hay que reconciliar y repetir las verificaciones pertinentes.

## Verificación ejecutada por el PRIMARY

| Verificación | Resultado y límite |
| --- | --- |
| `app/npm run check` | PASS: 222 archivos, 3.136 pruebas; incluye análisis estático, tipos y build. Cuatro avisos de lint existentes en coverflow. |
| Componentes afectados | PASS: 38 pruebas enfocadas, incluidos carga/error, bloqueo pendiente, traslado de tasa y bandeja con lead sin cliente. |
| `npm run test:edge-preflight` | PASS: 67 pruebas Node y 5 Deno; errores de tasa/documento frenan ambas variantes antes de Auth/perfil/correo. |
| `npm run check:scripts` | PASS; incluye 46 mutantes detectados. |
| `seed:preflight` / `test:rls:preflight` | PASS sin conexiones. No equivale al gate RLS remoto. |
| `test-tasa-lead.sql` | PASS: quince grupos, PG 17 aislado, cambios y datos de prueba revertidos. |
| `test-concurrencia-local.py` | PASS: dos sesiones reales; espera del candado y rechazo de conversión sin reserva parcial. |
| Política cambiada antes de migrar | PASS: rechazo por preflight, rollback y posterior aplicación correcta. |
| Reversa sin uso → comparación de huellas → reaplicación | PASS en banco local. |
| Recorrido nuevo Playwright | PASS a 1.440 y 390 px; solicitud, bloqueo, reapertura y aprobación. |
| Suite Playwright general | Primera ejecución: 144 PASS, 5 FAIL, 26 SKIP. Se corrigieron tres selectores ambiguos y el entorno local de fuentes. Revalidación posterior: 34/34 PASS, incluidos los cinco fallos. No se presenta como una segunda ejecución integral. |
| Revisión independiente de implementación | CHANGES_REQUESTED recibido; hallazgos evaluados/corregidos y comprobados por el PRIMARY. Ver `REVISION.md`. |
| SQL remoto específico | PASS: quince grupos con rollback en `ehzftpvxuwuzinvkyhzz`. |
| HTTP remoto | PASS: sesión real de analista/Gerencia; solicitud, contraoferta, aceptación, equipo ajeno, pendiente/base/omisión/documento en ambas banderas, sin efectos parciales. |
| Tipos desde esquema remoto | Generados con CLI; once bloques del alcance comparados e incorporados sin retirar los tipos F5 pendientes. Typecheck PASS. |
| Advisors | Tres nuevas RPC authenticated previstas; una función existente cambia a wrapper SQL. Los avisos de DEFINER se evalúan junto con la matriz de permisos. Sin nuevos avisos de rendimiento. |
| Matriz RLS completa | Referencia antes de migrar: 1.775 PASS / 41 FAIL de 1.816; comparación posterior en curso. |
| Aplicación, Edge y frontend productivos | NOT RUN. |

El banco parte de la estructura de pruebas vigente, con los actores sintéticos
de `siembra-banco-f3.sql -v run=910908`. Para reproducir las definiciones vivas
se instala `base-viva-funciones.sql` únicamente en ese banco, luego la migración
y `test-tasa-lead.sql`, con `ON_ERROR_STOP=1`. Los bancos locales usados fueron
`tasa_lead_20260909`, `tasa_lead_replay_20260909` y `tasa_lead_final_20260909`.
La prueba específica cubre RLS por ámbito, ACL, identidad ausente y
autoaprobación; no sustituye la matriz completa de offboarding del proyecto.

## Orden de publicación y cierre

1. Cerrar la revisión independiente y cualquier corrección necesaria. Mostrar
   el SQL exacto y confirmar el costo de la rama temporal antes de crearla.
2. Crear una rama Supabase del proyecto vigente; reproducir el esquema real,
   sembrar datos ficticios y aplicar únicamente esta migración candidata.
3. Ejecutar el banco específico, el gate RLS del proyecto y advisors. Registrar
   resultados y distinguir fallos anteriores de regresiones con evidencia.
4. Integrar los cambios remotos sin sobrescribirlos; verificar `main` y
   `avancecorp/main` en el mismo commit. El commit debe incluir lo ya publicado.
5. Construir el ZIP desde ese commit limpio mediante `npm run release:crm` y
   verificar su manifiesto. Conservar el release anterior fuera del web root.
6. Publicar en orden **base de datos → Edge `crm-convertir-lead` → frontend**.
   La nueva Edge exige las guardias SQL. El frontend admite solicitudes sin
   cliente; no se deben enviar solicitudes de lead desde una UI antigua.
7. Comprobar funciones, permisos, lectura de solicitudes, artefacto servido y
   acceso del CRM. Registrar commit, huellas y resultado. Eliminar únicamente
   la rama temporal de esta tarea cuando termine el ensayo/publicación.

## Reversión

Antes del primer uso, retirar el frontend y la Edge nuevos coordinadamente y
aplicar `revertir-antes-del-primer-uso.sql` mediante el ciclo autorizado. Toma
candados y se niega a ejecutarse si existe una solicitud con lead o una reserva
con condiciones: no borra historial para lograr una reversión. Restaura las diez
funciones, políticas y columnas de partida; la igualdad de huellas fue ensayada.

Si ya hay solicitudes de lead o reservas con condiciones, se conserva el modelo
y se corrige hacia delante. Una UI antigua que exige `cliente_id` no nulo no es
una reversión compatible con esos datos. No borrar solicitudes, reservas,
identidades ni contratos para volver a un estado anterior.

## Hallazgos del banco remoto

El fixture específico fijaba su política una hora antes. Tras la matriz RLS,
otra revisión de observación más reciente prevalecía. Se corrigió el fixture
para publicar su política en el instante actual; los quince grupos pasaron.
No se cambió el SQL aprobado por ese ajuste.

`testRentabilidadR1` intentaba limpiar con `estado='vencida'`, que no es un estado
persistido, y ocultaba el error con `tolerante`. La segunda matriz quedó bloqueada
por una solicitud dejada por la primera. La limpieza ahora modifica las fechas
bajo el GUC de prueba y exige éxito; conserva historia y no rebaja permisos.

La prueba HTTP encontró que P0410/P0411 de la reserva con identidad devolvían
500 pese a bloquear correctamente. La Edge devuelve 409 en esos casos. Los
tests exigen el estado exacto (409; 503 si falta RPC); gate Edge 67 Node + 5 Deno
y HTTP real con ambas banderas PASS. La migración aprobada conserva SHA-256
`113a436ec25f13105d7321f527bbeb583d74c09feffb408ab3a8616ea418ca55`.

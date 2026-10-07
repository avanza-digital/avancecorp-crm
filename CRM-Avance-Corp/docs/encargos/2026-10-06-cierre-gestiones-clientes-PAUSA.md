# Pausa segura — cierre de gestiones de clientes

> **Historial de pausa, ya retomada el 6 de octubre de 2026 por «sigue».** La implementación local y la evaluación final de Claude están terminadas; [estado vigente y verificaciones](2026-10-06-cierre-gestiones-clientes.md). El respaldo de esta pausa se conserva intacto como fotografía anterior.

## Identificador de continuación

**Serial: `CRM-CLIENTES-CIERRE-20261006-01`**

Para continuar: **«Retoma CRM-CLIENTES-CIERRE-20261006-01»**.

Fecha: 6 de octubre de 2026, zona America/Lima. Pausado expresamente por el usuario. No continuar implementando hasta que solicite retomar.

## Petición y límites vigentes

- Permitir al analista **Cerrar tarea** desde Cartera → ficha del cliente → Seguimiento, como en leads, manteniendo también Agenda.
- Registrar resultados de llamadas, WhatsApp y citas. Una cita programada o confirmada no es una entrevista; debe registrarse la asistencia.
- Conectar historial, siguiente tarea, Registro, Gestión Diaria, resumen de gerencia y Citas con la atribución correcta al autor y permisos de supervisión.
- El usuario aprobó el diseño local y la implementación, y pidió revisión de Claude.
- **La comprobación visual la hace el usuario.** No repetirla automáticamente.
- No se autorizaron cambios productivos ni publicación. Ninguna migración de esta tarea se aplicó a producción. No hubo commits, push ni deploy realizados por esta tarea.

## Punto seguro alcanzado

La implementación y las evidencias están guardadas en disco. Finalizaron las pruebas y la revisión de Claude; no queda una operación de escritura de esta tarea a medio ejecutar. La última consulta de catálogo terminó correctamente y era solo de lectura. Se conservan los servidores de vista local con datos sintéticos.

**La tarea está incompleta:** falta evaluar los hallazgos finales de Claude, aplicar únicamente los ajustes respaldados por evidencia y verificar los últimos cambios.

Documento funcional y técnico: [cierre de gestiones de clientes](2026-10-06-cierre-gestiones-clientes.md).

## Repositorio compartido: preservar otros trabajos

- Raíz Git real: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop`.
- Directorio de trabajo: `CRM-Avance-Corp` dentro de esa raíz.
- Rama al pausar: `main`.
- HEAD observado al comenzar el guardado: `1d4134e6476f007ac14cbb38df42b84e22fe862f`.
- HEAD observado al generar el respaldo: `376ac0dce16db7838c204347ccb70850965dd8c1`. El repositorio siguió avanzando por trabajo externo incluso durante el guardado; el manifiesto registra el instante del respaldo, no una promesa de que HEAD permanezca fijo.
- Referencia observada al inicio de este trabajo: `b286b2bf`. HEAD avanzó por trabajo externo mientras se desarrollaba esta tarea.
- Hay numerosos cambios ajenos y copias ` 2.*`, incluidos archivos compartidos con esta implementación. **No restaurar, borrar, hacer stash ni sobrescribir globalmente. No asumir que todo el diff es de esta tarea.**
- Main debe seguir `avancecorp/main`, no `origin/main` ni `avancecorp/tronco`.
- La copia de seguridad guarda el contenido de los archivos relacionados al momento de pausar; algunos incluyen modificaciones de otras tareas. No restaurarla ciegamente sobre un HEAD posterior.

## Implementación guardada

### Escritura y ficha

- Botones **Cerrar tarea** en el Seguimiento de las fichas de perfil y cliente neutral.
- Diálogo común de cierre con resultados tipados y compromiso siguiente cuando corresponde.
- Writer F6 con payload versión 2, compatibilidad de cierres anteriores, idempotencia, control de revisión y cierre/historial/siguiente tarea atómicos.
- Registro separado del autor de la gestión y del responsable de la tarea.
- Migración: `supabase/migrations/20261005224214_crm_resultados_cliente_postventa.sql`.
- La migración comprueba la huella MD5 del writer anterior: `4fe2e158e6d359fcc25c64bc6624d2e5`.

### Lectores y supervisión

- Migración: `supabase/migrations/20261006012208_crm_gestiones_clientes_supervision.sql`.
- Cinco RPC: `registro_actividad_v2_fn`, `gestiones_resumen_fn`, `citas_clientes_fn`, `gestion_diaria_citas_v2_fn`, `gestion_diaria_pendientes_v2_fn`.
- Registro unificado con cartera, identidad explícita, resultados y cursor compuesto; CSV coherente.
- Resumen operativo por autor, separado de los indicadores de captación sellados.
- Citas de clientes por fecha programada; pendientes y citas agendadas conservan sus contratos originales y añaden navegación a la ficha correcta.
- Leads conservan INVOKER/RLS; lectores privados de clientes comprueban sesión, rol, banderas y jerarquía. Sin nuevos permisos SELECT sobre el historial F6.
- Tras reasignación, se conserva el conteo del autor; se retiran identidad, detalles privados y enlaces cuando ya no tiene acceso al cliente.
- Invalidación de cachés conectada tanto con postventa como con Agenda heredada.
- Tipos de las cinco RPC generados desde el banco migrado e integrados, preservando los demás contratos.

### Último cambio realizado

Se corrigió la exclusión de citas **sin responsable**: gerencia puede verlas sin filtro de analista; supervisor no. Se ajustó SQL, contrato nullable de `vendedor_id` y validación de coherencia, y se añadió la prueba de roles.

Los tres grupos SQL pasaron tras ese cambio. **Falta ejecutar typecheck y las pruebas frontend relevantes sobre este último ajuste**, que ocurrió después del check general y del paquete de evidencia enviado a Claude.

## Banco local y vista previa

- Contenedor existente: `supabase_db_crm-avance-corp-local`.
- Banco propio: `gestiones_clientes_20261006`.
- Sello obligatorio: `BANCO SINTETICO gestiones clientes 20261006 / sin produccion`.
- Las dos migraciones están instaladas en este banco. No ejecutar de nuevo `instalar` ni usar `ensayar` como si fuera una base sin migrar.
- Para pruebas en el banco ya instalado: `node supabase/scripts/gestiones-clientes/banco.mjs probar`.
- Prueba concurrente: `node supabase/scripts/gestiones-clientes/concurrencia.mjs`.
- Instrucciones y recreación: `supabase/scripts/gestiones-clientes/README.md`.
- Las pruebas transaccionales revierten sus datos; la prueba concurrente conserva dos cierres sintéticos. Los conteos de prueba ya contemplan esa base.
- Snapshot de esquema usado, sin datos de clientes: `/private/tmp/avancecorp-gestionado-ficha-20261003/esquema-productivo.sql`. Puede desaparecer al limpiar temporales; no depender de que sobreviva indefinidamente.

Vista local: `http://127.0.0.1:5197/#/mi-cartera/inversionista/22222222-2222-4222-8222-222222222222`.

La vista usa datos de ejemplo en memoria; no está conectada a producción ni al banco SQL de pruebas. Backend de ejemplo en `127.0.0.1:59999`; archivos `app/artifacts/postventa-local-backend.mjs` y `postventa-local-fixture.ts`. Sesiones de servidor observadas: Vite `92458`, backend `61296`; los números pueden dejar de ser válidos al reiniciar la sesión. Si mañana no responde, reconstruir la vista usando esos archivos y su configuración local, sin cambiar el CRM productivo.

## Verificación efectivamente realizada

| Comprobación | Resultado al pausar |
| --- | --- |
| SQL: cierres, resultados, replay, siguiente tarea, confirmación frente a asistencia | PASS |
| SQL: actor/responsable, autorización, reasignación, redacción, banderas, perfiles y estados | PASS |
| SQL: paginación, cursor entre fuentes, G4b/pendientes v2, espejos, medianoche Lima, citas sin responsable | PASS |
| Concurrencia real con dos conexiones | PASS; mismo recibo con misma clave, un cierre y conflicto con claves diferentes |
| Generación e integración de tipos de cinco RPC | PASS |
| Check general: lint, typecheck, 381 archivos y 6.130 pruebas, release-config, push-tasa | PASS en el estado previo al último ajuste nullable |
| Build y verificación del bundle | PASS en ese mismo estado |
| `npm run check` completo | FAIL exclusivamente en duplicación: 1,1 %, umbral 0,8 %, con copias preexistentes ` 2.*` |
| Mismo análisis excluyendo solo esas copias | PASS: 0,43 %; no se cambió el umbral ni se borraron copias |
| E2E Docker local, siete especificaciones | 44 sin fallos finales: 41 al primer intento y 3 con retry bajo carga simultánea |
| Repetición F6 sin suite masiva en paralelo | PASS: 13/13 sin retry |
| Typecheck posterior a la integración de tipos | PASS, anterior al último cambio nullable |
| Verificación frontend del último cambio nullable | NOT RUN; pendiente al retomar |
| `gate:realidad`, advisors y ensayo remoto | NOT RUN; sin destino/credenciales remotos autorizados para esta tarea |
| Validación visual | A cargo del usuario |

Logs principales en `app/artifacts/`: `gestiones-clientes-sql-instalado.log`, `gestiones-clientes-sql.log`, `gestiones-clientes-concurrencia.log`, `gestiones-clientes-check-final.log`, `gestiones-clientes-typecheck-final.log`, `gestiones-clientes-e2e-final.log`, `gestiones-clientes-e2e-f6-final.log`, `gestiones-clientes-dup-sin-copias.log`.

EXPLAIN ANALYZE del banco pequeño: Registro 28,622 ms, resumen 9,957 ms, Citas 4,872 ms. **No acredita rendimiento con volumen productivo.**

## Claude: respuesta y evaluación pendiente

Se usó exclusivamente el wrapper autorizado `../scripts/claude-review`, con Claude como SECONDARY_REVIEWER sin herramientas ni escrituras. Codex conserva la decisión e implementación.

1. Arquitectura: `app/artifacts/review-gestiones-clientes-arquitectura-respuesta.txt`. CHANGES_REQUESTED; decisiones relevantes ya incorporadas.
2. Implementación final: primer envío no produjo VERDICT válido; el wrapper lo rechazó. Se hizo un reintento técnico con evidencia acotada, no una consulta para obtener aprobación.
3. Respuesta válida final: `app/artifacts/review-gestiones-clientes-final-respuesta.txt`. **CHANGES_REQUESTED**, confianza MEDIUM. No P0 ni fuga de PII identificada. Solicitud/evidencia: `review-gestiones-clientes-final-acotado.txt`.

**No iniciar otra ronda automática de review.** Evaluar esta respuesta con código, contratos y pruebas, y documentar recomendaciones aceptadas o descartadas.

### Puntos prioritarios para retomar

- Rendimiento: el helper PL/pgSQL materializa el rango antes de paginar; el resumen paga resolución de identidad/detalles que no utiliza. La función de identidades también consulta F5 para `[]`. Evaluar retorno temprano autorizado para lista vacía y separación de conteos respecto de datos de presentación. La solución aún no está implementada.
- Verificar el tratamiento de nombres vacíos: `leads.nombre_completo` es NOT NULL, pero la consulta de catálogo no encontró CHECK de contenido no vacío. No inventar datos ni esconder corrupción sin entender el contrato.
- Evaluar deduplicación de legado cuando las banderas F6 están apagadas; decidir a partir del contrato y verificarlo.
- Evaluar el guardado de resultado_origen para acciones administrativas, helper escalar de identidad usado en pruebas, posible reapertura heredada, autores vacíos en Citas y el toast al recuperar una operación.
- Registrar la decisión de privacidad/UX del Registro: al enfocar o tras 60 s se retiran páginas acumuladas de clientes y se recarga la primera. Revisar solo si existe un riesgo concreto.
- Antes de producción, revisar volumen, plan de consultas e índices; CREATE INDEX no concurrente puede bloquear escrituras durante instalación.

### Evidencia que ya responde a hipótesis del reviewer

La última consulta solo de lectura terminó al pausar:

```text
crm.actividades.metadata NOT NULL
crm.actividades_cliente.cliente_id NOT NULL
crm.actividades_cliente.tipo NOT NULL
crm.leads.nombre_completo NOT NULL
crm.tareas CHECK num_nonnulls(lead_id, perfil_id, inversionista_id) = 1
crm.actividades_cliente.tipo CHECK IN (
  llamada_realizada, llamada_no_contestada, whatsapp_enviado,
  whatsapp_recibido, reunion_realizada, nota, reasignacion
)
```

- La hipótesis de que `NOT (metadata ? 'postventa_gestion_id')` omita filas por metadata NULL no se reproduce con la restricción actual NOT NULL. Puede hacerse defensivo si existe una razón, sin presentarlo como bug comprobado.
- Tipos heredados arbitrarios quedan restringidos por CHECK; comparar esa lista con `TIPOS_ACT` antes de aceptar la hipótesis de fallo por tipos desconocidos.
- El writer original asigna `v_detalle := nullif(btrim(p_datos->>'detalle'),'')` en línea 24 del cuerpo; línea 30 exige detalle de 3–2000 caracteres para toda acción distinta de confirmar; la inserción de escritura comienza en línea 35. La hipótesis de cerrar con detalle NULL, o insertar el parche antes de inicializar detalle, no corresponde al writer guardado por huella. No eliminar esa validación.
- `private.vendedor_ids_visibles` incluye al propio actor: gerencia obtiene el equipo, supervisor el subárbol incluyéndose, vendedor a sí mismo. No añadir un filtro que elimine gestiones propias del supervisor.
- Índices encontrados en `inversionista_gestiones`: PK id; `(inversionista_id, creado_en DESC, id)`; y nuevo `(creado_por, creado_en, id) WHERE tipo='cierre'`. No se encontró índice por tarea en esa consulta.

## Copia de seguridad de esta pausa

Directorio: `app/artifacts/pausa-CRM-CLIENTES-CIERRE-20261006-01/`.

Respaldo creado: `archivos-guardados.tar.gz`, con **92 archivos relacionados**, manifiesto SHA-256, patch de cambios rastreados y estado Git. Se verificó que todos los archivos del tar coinciden con sus hashes. No incluye `.env`, credenciales, dependencias ni una copia indiscriminada de otros artifacts. El manifiesto es la lista exacta del respaldo. El código original permanece en su lugar.

## Orden para continuar mañana

1. Leer este punto de pausa y las reglas del proyecto/vault; comprobar HEAD y cambios externos sin sobrescribirlos.
2. Leer la respuesta final de Claude y evaluar sus hallazgos usando la evidencia anterior.
3. Implementar los ajustes necesarios y comprobar el contrato nullable de citas sin responsable.
4. Ejecutar los checks relevantes y los gates exigidos; reportar PASS/FAIL/NOT RUN de forma explícita. Mantener E2E en Docker local.
5. Actualizar el documento de implementación y la memoria duradera del tema. La comprobación visual sigue con el usuario.
6. Entregar el estado final para revisión. Producción requiere el SQL exacto aprobado y el flujo de publicación autorizado; no está autorizada por este serial.

# Núcleo operativo SLA — N1

Estado: **implementado en código, con pruebas locales de PostgreSQL 16**. La migración no está aplicada en Supabase. N1 es el núcleo de lectura y decisión; el proyecto SLA-R2 completo sigue pendiente de integración y de ajustes guiados por el usuario.

## Entrega

La migración `20260907001024_crm_sla_nucleo_operativo_lectura.sql` incorpora cuatro tablas de entradas del dominio, siete funciones privadas de hechos/cálculo/autorización, un guard de integridad y un gate de arquitectura. Añade las consultas `crm.estado_sla_leads_v2_fn(uuid[])` y `crm.cola_accion_v2_fn(integer)`. La consulta v1 conserva firma, propietario, permisos y payload; ahora usa la misma proyección de hechos.

No se publica ninguna política ni se reconstruye stock. El único registro inicial es el control en `legado`, revisión 0, sin primera activación ni política de adopción. Los valores 1/3/3/5 días y demás propuestas de R2 aparecen únicamente en fixtures de prueba. Las aprobaciones para la futura configuración y las decisiones aún pendientes se mantienen en el [plan vigente](<../../../PROPUESTA DE SLA PARA ETAPAS/PLAN-FINAL-SLA-2026-09-06.md>); los ajustes se revisan con el usuario por bloques.

## Manifiesto de responsabilidades

| Objeto privado | Responsabilidad y consumidores |
|---|---|
| `sla_hechos_actuales` | Fotografías originales, ciclo, asignación, episodio y ámbito resuelto. Alimenta v1 a través de la ventana, el núcleo operativo y los hechos de tareas. No interpreta roles. |
| `sla_tareas_hechos` | Pendientes de agenda con contexto causal y motivos de inconsistencia. Alimenta el núcleo; no redefine estadísticas de citas. |
| `sla_etapa_hechos` | Presupuesto ya consumido y entradas en esa etapa/ciclo, sobre el ledger de etapas. Alimenta el núcleo. |
| `sla_politica_operativa` | Versión vigente solo cuando dispone de las cuatro reglas. La usan núcleo y ventana. Reutiliza `sla_politica_vigente`. |
| `sla_evaluar_prorroga` | Regla pura de elegibilidad y ganancia. Queda lista para el futuro writer del dominio; N1 no tiene ningún llamador de escritura. No es una RPC pública. |
| `sla_operacion_leads` | Seguimiento, selección de compromiso, cobertura, techos y decisiones de atención/supervisión con un instante explícito. Usa `persona_vetada` y los hechos anteriores. |
| `sla_operacion_autorizada` | Ventana común: actor, rol y ámbito mediante los helpers existentes, más un único reloj por consulta. Selecciona la perspectiva permitida y sirve los tres adaptadores públicos. |
| `trg_sla_nucleo_entrada_guard` | Entradas inmutables, correspondencia de tareas y actividades, adopción fija, revisión consecutiva y prohibición de anexar reglas a una política con episodios. |
| `assert_sla_nucleo` | Comprueba dependencias, propiedades de las funciones, privacidad de los helpers, RLS y auditoría de las cuatro tablas. |

Las tablas son `sla_politica_etapas_operacion`, `lead_sla_etapa_ajustes`, `tarea_sla_contexto` y `sla_operacion_control`. Todas tienen RLS, auditoría de los tres verbos y cero privilegios de acceso directo para PUBLIC, anon, authenticated y service_role. No se crea una tabla de resultados calculados. Los núcleos de capital, conversión, citas y métricas SLA históricas conservan sus definiciones y permisos.

## Contrato y casos difíciles

- Estado v2 acepta hasta 200 IDs sin NULL. Duplicados no multiplican filas; vacío devuelve ninguna. IDs ajenos o inexistentes no revelan datos. Un inactivo solicitado explícitamente devuelve `no_aplica`; la cola y v1 siguen limitados a activos.
- La cola recibe decisiones del núcleo, cuenta señales sobre todo el ámbito y después limita la lista. Las señales pueden solaparse. El reloj y las filas coinciden con estado v2 dentro del mismo statement.
- Una nota, actividad futura o gestión anterior al ciclo/asignación no reinicia seguimiento. Los cinco tipos de gestión se centralizan; un supervisor puede atender un lead sin que eso atribuya productividad al analista.
- Se examinan todas las tareas comerciales pendientes. Una tarea ambigua o de otro ciclo impide conceder cobertura; no se salta una vencida buscando otra futura. Las administrativas siguen siendo agenda y no conceden cobertura.
- La tercera reprogramación no cubre. El margen deja de cubrir exactamente al vencer y el límite operativo calculado no retrocede por ese cambio de estado temporal.
- El techo de un episodio usa su propia política; un episodio histórico sin anexo usa la adopción fija. Cambiar la política vigente no modifica esos techos.
- `null` significa no evaluable; no se convierte en cumplimiento. Un techo ya agotado sí permite afirmar que se necesita revisión aun con un compromiso ambiguo.
- Se detectan fotos ausentes y discordancias de asignación/etapa. Los motivos técnicos adicionales son `sin_episodio_etapa`, `asignacion_sla_incoherente`, `etapa_sla_incoherente`, `referencia_gestion_invalida` y `operacion_no_activada`.
- La regla de prórroga exige conversación humana, mismo episodio, modo activo y ventana `[límite−24 h, límite)`. Respeta presupuesto, eventos ya ajustados y ganancia parcial. El futuro writer debe resolver estos argumentos desde los hechos, revalidar bajo locks y persistirlos atómicamente; no puede recibirlos como decisiones del navegador.

## Verificación reproducible

Desde `CRM-Avance-Corp`:

```sh
npm run test:sla:nucleo
```

Requiere PostgreSQL 16 nativo. En otra instalación, `SLA_PG_BIN` señala su carpeta de ejecutables. El runner crea un cluster privado con socket Unix, sin escucha TCP, sin URL externa ni credenciales de Supabase. Cada caso clona una base plantilla aislada y el servidor se detiene al terminar. La ruta del JSON de evidencia aparece al final.

Se aplica **el SQL real completo de N1**, incluida su guarda de deriva de v1. El banco incorpora el cuerpo real de v1 y el censo real de contadores. Los helpers de identidad, ámbito y veto son dobles explícitos; las tablas existentes son un esquema reducido de sus contratos. Las pruebas acreditan cálculo, delegación del ámbito, payloads, límites, permisos nuevos, auditoría y reversa. **No equivalen a `test:rls`, advisors, carga ni a todos los triggers de una copia completa de producción.**

Hay mutantes que desconectan la cola del núcleo, alteran cobertura y su frontera temporal, y añaden un contador crudo. Los oráculos normales detectan las alteraciones. No se añade ninguna exención al censo existente ni se eleva su tope.

Tras instalar N1 en un banco completo, `npm run gate:sla` consulta el gate instalado usando el mismo canal que los gates existentes. El postflight de la migración ejecuta también los gates de analítica, auditoría, vigencia y F7 cuando están presentes. Antes de publicar faltan el ensayo en ese banco completo, esos gates, `test:rls` pertinente y advisors sobre el cambio.

## Contraste de cartera real

El [contraste con cartera real](<../../../PROPUESTA DE SLA PARA ETAPAS/CONTRASTE-CARTERA-2026-09-06.md>) añade evidencia sobre una foto de 1.157 leads, con 827 abiertos: [agregados](contraste-cartera-2026-09-07.json) y [18.698 comparaciones independientes](paridad-cartera-2026-09-07.json). La suite del núcleo actual pasa [44/44](resultados-2026-09-07.json). Se conservó la evidencia anterior de 42 casos como historial de otro hash.

Para repetir el contraste, ejecutar `extraer-contraste-cartera.sql` como lectura autorizada y guardar su objeto `snapshot` fuera del repositorio, en un temporal privado. El simulador usa PostgreSQL 17, nunca una URL externa:

```sh
python3 supabase/scripts/contrastar-sla-cartera-local.py --snapshot /private/tmp/FOTO.json --output-dir /private/tmp/RESULTADO-NUEVO
python3 supabase/tests/sla-nucleo/oraculo-cartera.py /private/tmp/FOTO.json --comparar /private/tmp/RESULTADO-NUEVO/estricto-estados.json --paridad /private/tmp/PARIDAD.json
```

Las fotos completas y resultados individuales no se versionan. La huella de foto vincula la evidencia al corte exacto. El oráculo es una prueba independiente; los consumidores del producto siguen calculando únicamente mediante el núcleo SQL. Este contraste no reemplaza las pruebas de integración completa de Supabase.

## Reversa

`supabase/scripts/rollback-sla-nucleo-lectura.sql` restaura el cuerpo anterior de v1 al byte y revoca las dos RPC v2. Es repetible, preserva tablas/hechos/auditoría y exige `legado` sin primera activación. Rechaza una deriva del cuerpo v1. Se prueba dos veces en el banco.

Es una reversa de exposición de lecturas, no un borrado del esquema ni una desactivación de un módulo ya operativo. Tras ella el gate SLA queda deliberadamente rojo porque v1 deja de delegar. Reponer la lectura requiere reaplicar la definición del adaptador y sus grants mediante una migración nueva; no se repite la migración creadora de tablas.

## Siguiente trabajo, guiado por el usuario

1. Ajustar plazos, márgenes y expectativas operativas por bloques. Luego crear publicación/configuración versionada y transición de modos; N1 no ofrece estas puertas.
2. Completar captura del contexto causal de tareas y diagnóstico/reconstrucción del stock. La falta de contexto queda visible hasta resolverla.
3. Implementar el writer de prórrogas, locks ordenados, recibos/idempotencia y confirmación del guardado. N1 solo evalúa y no elimina esas deudas de los writers actuales.
4. Integrar agenda, estado/cola, validadores y pantallas; mantener la protección de contacto y el historial bruto. No se modificó frontend en N1.
5. Contrastar primero contra la cartera real y ensayar la integración completa. El usuario prefiere activación conjunta si la evidencia es correcta; observación queda opcional, sin una jornada obligatoria.

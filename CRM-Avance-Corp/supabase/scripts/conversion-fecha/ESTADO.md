# Conversión por fecha comercial — candidata F2/F3, F4 en curso

**No publicar hasta completar el ensayo.** Miguel aprobó el SQL exacto y
`release-crm`, condicionados a los gates. La rama remota está creada y autorizada;
el estado vigente del ensayo está en `ENSAYO-REMOTO.md`. Los pendientes de
autorización anteriores en esta acta son históricos. Producción permanece intacta.

## Decisiones de negocio cerradas

- Mes de cierre comercial; operación confirmada y vínculo acreditado antes de
  las 00:00 del día 11 siguiente, extremo excluido, America/Lima.
- Desde septiembre de 2026, recalculando septiembre y conservando agosto/previos.
  No trasladar crédito de una carga tardía, aunque Cron esté apagado.
- Caso ambiguo resuelto expresamente: solo el contrato de septiembre acredita
  septiembre, no el de mayo. No inferir upgrade ni eliminar ninguno.
- Cuatro reemplazos nominales autorizados, una conversión por caso. Los UUID
  y nombres reales se conservan únicamente en el manifiesto privado del operador.
- Caso sin inversión probada: pendiente sin crédito hasta acreditarla.
- No prohibir contratos anteriores al lead; los enlaces atípicos siguen permitidos.

## Estado del ensayo remoto

Ya se instalaron exclusivamente en la rama autorizada las versiones nativas
`20260927073637` y `20260927080006`. Baseline y candidata inactiva: 2267/0 cada
una; escritores HTTP 15/15, estados/plazo 5/5, tipos integrales, check frontend,
advisors sin nuevas advertencias y reversa remota PASS. Matriz activa final en
curso. Producción todavía intacta; publicación/PR pendientes. Detalle y límites
en `ENSAYO-REMOTO.md`; los pendientes remotos del historial inferior ya no son
el estado vigente.

## Implementado

Migración creada mediante CLI 2.117.0:
`20260927035114_crm_conversion_fecha_comercial_plazo.sql`, conciliada con la
versión nativa `20260927073637` sin cambiar sus bytes.

1. `private.conversion_plazo_hasta`: frontera única del día 11 de Lima.
2. `private.conversion_decidir_plazo`: decisión pura, sin reloj de lectura.
3. `private.conversion_instante_servidor`: reloj interno no controlable por cliente.
4. `crm.conversion_acreditaciones`: fuente exacta, analista del episodio,
   origen, reloj de confirmación/vínculo, decisión, versión y auditoría.
   RLS ON; acceso directo revocado a clientes y service_role; sin policy DELETE.
5. `private.conversion_acreditar_fuente`: escritor interno invoker, fuente
   explícita y concordante con el lead, candados mensuales ordenados, revalidación
   después de espera e idempotencia. No escoge cualquier contrato del perfil.
6. `private.conversion_cierres`: conserva la rama anterior a septiembre y usa
   acreditaciones por fecha comercial desde septiembre. Firma/payload intactos.
7. `private.cierre_mes_ventana_desde` delega en la frontera común; no activa Cron.
8. Triggers **solo crm** alimentan el registro desde episodio, enlace explícito,
   confirmación de solicitud y corrección de cooperativa. El resolver no usa
   cualquier contrato del perfil: conserva la fuente ya elegida o exige un
   único vínculo explícito. `leads_before_update` restaura contrato/perfil ante
   UPDATE directo de authenticated; se verificó con el rol real.
9. La puerta existente `crm.corregir_fecha_cierre_comercial` reevalúa el crédito
   bajo los candados de ambos meses. No modifica importes ni el espejo financiero.
10. `private.registrar_ajuste_si_mes_cerrado` usa el mes comercial acreditado,
    revalida tras esperar el candado y no inventa deuda por pendiente/tardío.
    Conserva peso de referido de la foto, capital cero e idempotencia por lead.
11. RPC nueva `crm.conversion_estado_lead_v1`, wrapper invoker y lector privado
    autorizado: mismo ámbito de leads, denegación a revocados/anónimos/ajenos.
    No agrega claves a los payloads estrictos de Ranking o Metas.
12. Ficha real del lead presenta mensaje/fecha del servidor, carga y error con
    reintento. Demo no consulta esa RPC. No calcula elegibilidad en frontend.
    Caché bajo el prefijo de estado del cierre para invalidarse al anular.
13. Instalación y activación separadas: `crm.conversion_politica` comienza
    inactiva. El lector conserva el resultado anterior hasta que el activador
    privado valide y concilie TODO el manifiesto en la misma transacción.
    Un cambio, omisión o vencimiento aborta el lote completo. Recepción real,
    sin antedatar; reintento del mismo manifiesto no duplica escrituras.
14. `conversion_exclusion_fuente` centraliza la elegibilidad viva (retirada,
    demo y cartera). Un trigger **crm**, al insertar el sello bajo el candado
    mensual, conserva `sellado_en` e `incluida_en_sello` por acreditación.
    La deuda exige esa prueba, no sólo el estado de admisión; no depende de
    si la fuente desaparece antes o después del cierre. No se modifica public.
15. Corregir el día dentro del mismo mes conserva el vínculo recibido a tiempo;
    cambiar de mes revalida el plazo con recepción actual. Un cambio operativo
    de origen después del sello conserva la atribución congelada sin bloquearlo.
16. La retirada por `crm.contrato_eliminar_auditado` toma el mismo candado mensual
    mediante un trigger en `crm.contratos_eliminados_auditoria`, antes de borrar
    la fuente. Bloquea el lead con NOWAIT para evitar un ciclo con operaciones
    que ya lo poseen; conflicto explícito PT409, sin borrado parcial. Funciona
    aunque el vínculo legado del lead no sea la fuente elegida al conciliar.
    No modifica la puerta de borrado ni añade objetos en public.

## Verificación parcial real

Banco exclusivo Docker `supabase_db_crm-avance-corp-local`, base
`conversion_fecha_20260927`, copiada de `ranking_cartera_20260926` sin conexiones
activas al origen. Fixtures: 6 episodios y 7 contratos sintéticos. No es un
bootstrap independiente ni una copia de datos de clientes de producción.

Ejecutar desde la raíz del clon:

```sh
node CRM-Avance-Corp/supabase/scripts/conversion-fecha/verificar-plazo.mjs
```

- PASS calendario: límites 9/10/11, microsegundos, enero cargado en septiembre,
  ambas fuentes del ejemplo mayo/septiembre, pendiente, vínculo tardío, sello y fecha futura.
- PASS registro: fuente exacta, identidad, atribución, reloj del servidor,
  auditoría, núcleo comercial, ámbito visible y fuentes originales intactas.
- PASS reintento al avanzar el reloj interno a 2030: mismo hecho completo,
  sin rejuvenecer la fecha ni agregar otra escritura de auditoría.
- PASS denegaciones SQL reales para authenticated/anon; no equivale al gate
  HTTP/Auth/RLS completo del producto, que sigue pendiente.
- PASS cinco mutantes, todos fallan por su aserción específica (no un error genérico).
- PASS integración de enlace, corrección de fecha, sello no vacío y anulación.
  La prueba fuerza un registro administrativo en octubre y crédito comercial
  septiembre: deuda en septiembre, una sola vez, capital cero, fotos intactas.
- PASS escritores oficiales compartidos: reutiliza `conversion-inversion/test-conversion.sql`,
  con dos leads libres (la suite usa dos) y correo del firmante sintético completo.
  Cooperativa Prodelco USD y Avance con saga Auth/perfil, aprobación de tasa,
  comprobante, cuenta/cronograma y reintentos. Solicitud preparada no acredita;
  confirmada acredita la fuente exacta una sola vez. No se desactivaron guards.
- PASS estado/RLS SQL: analista propio, supervisor, gerencia, lead ajeno,
  inexistente, miembro revocado y anónimo. El dump sintético no traía ACL;
  el test repone únicamente los grants usados, contrastados en producción.
- PASS paridad abierta por la alarma de cinco caminos. Tras sello/anulación,
  lectura mensual, rango y distribución coinciden con la foto congelada.
  La alarma de bruto vivo - deuda NO es el oráculo de una foto sellada: usarla
  así dio rojo por diseño y no se cambió el producto para falsear esa comparación.
- PASS once carreras con dos sesiones reales y espera advisory observada:
  acreditar→sellar, sellar→acreditar tarde y doble intento→reintento estable;
  corregir/sellar, anular/sellar, corregir/anular y retirar/sellar, cada pareja
  en ambos órdenes. Se comprueban conflictos reintentables, foto, pertenencia
  individual al sello y deuda única, no sólo que terminen las sesiones.
  Comando: `node CRM-Avance-Corp/supabase/scripts/conversion-fecha/verificar-concurrencia.mjs`.
  Los bancos efímeros propios se eliminan; la plantilla permanece intacta.
- PASS `npm run check`: lint/typecheck, 301 archivos y 4468 tests, cobertura,
  release-config, service-worker, build, bundle y duplicación. Cinco advertencias
  a11y preexistentes fuera del diff; no se silenciaron.
- E2E Docker completo: **275 passed, 26 skipped, 1 flaky**, salida 0, 10.7 min.
  Intermitente: `gestion-diaria-pulso.spec.ts:136`, ancho esperado 959 al cambiar
  viewport; pasó al reintentar. No atribuirlo a este cambio sin reproducción.
- PASS `check:scripts` y `test:edge-preflight`. El primero falló inicialmente
  por EPERM de servidor localhost; pasó al repetir con autorización.
- `seed:preflight` y `test:rls:preflight`: FAIL de configuración (SUPABASE_URL
  ausente). La matriz HTTP/Auth integral sigue NOT RUN, no sustituida por SQL.
- Gate de realidad CLI: no corrió por falta de entorno. Equivalente de sus
  consultas ejecutado por MCP de solo lectura 26/09 23:42 Lima: 21 metas,
  2406 leads activos, 16606 actividades, 1326 tareas, 29 comerciales, 0 huérfanos,
  0 metas bajo sello; cinco caminos 98.15/1423 = 6.90 %. Divergencia preexistente:
  288 clientes sin domicilio legal. El test del nuevo bloque cubre pendiente/error.
- Tipos generados con CLI 2.117.0 desde `conversion_tipos_20260927` local; se
  incorporan literalmente tabla/RPC nuevas, conservando el resto de tipos del
  commit publicado. Regeneración integral contra rama remota: pendiente.
- PASS sintaxis Node y `git diff --check`.
- Segunda ejecución completa de `npm run check`: PASS, mismos 4468 tests.
  Después se regeneraron los dos campos de pertenencia al sello: typecheck PASS.
- E2E focal de Gestión diaria: 11/11 PASS, sin reintentos; no se alteró el spec.
- PASS regresiones: contratos distintos de la misma persona (mayo tardío,
  cartera excluida, septiembre elegido sin volver a seleccionar por antigüedad),
  identidad canónica duplicada, exclusión demo por su puerta oficial y agosto
  no vacío idéntico. Sólo la siembra del histórico sintético anterior a la
  candidata exceptúa temporalmente dos guards de inmutabilidad; quedan ON
  antes de todas las pruebas. El código de producto nunca los desactiva.
- PASS instalación inactiva, activación atómica, fallos parciales, plazo vencido
  e idempotencia del manifiesto. PASS reversa exacta con huellas, sin borrar hechos.
- PASS corrección del día después del día 10 antes de sellar: conserva crédito.
  Demo anterior al sello y anulación posterior: no genera deuda fantasma; estado
  visible correcto. Crédito sí incluido: genera deuda, la lectura del mes siguiente
  la recibe y el saldo la cobra una vez, capital cero.
- PASS Metas con roster nominal y cuotas sintéticas publicadas, además de su
  rama fuera_ranking, frente a la oficial por analista. Se crea una revisión
  nueva sobre el periodo existente mediante las validaciones y auditoría reales;
  no se desactivan guards. Ranking por origen recibe los cierres acreditados.
- PASS retiro por la puerta auditada oficial antes y después del sello:
  conserva hechos/auditoría, sólo la fuente incluida al sellar genera deuda
  posterior, una vez y capital cero. No se sustituye la puerta por un DELETE
  directo que omita la limpieza de vínculos.
- Reejecución final local después del candado de retirada: las diez suites SQL
  y los cinco mutantes PASS, incluida la reversa del trigger nuevo.
- Revisión Claude de implementación: CHANGES_REQUESTED. P1 aceptados/corregidos
  y probados por PRIMARY; evaluación en `REVISION.md`. No atribuir un segundo
  PASS a Claude: no se repitió la consulta después de las correcciones.
- Límite de infraestructura: el rechazo de EXECUTE bajo authenticated provoca
  SIGSEGV en la imagen local Supabase 17.6.1.105, reproducido y alineado con
  https://github.com/supabase/supautils/issues/214. ACL efectiva comprobada
  con has_function_privilege; ese rechazo en ejecución queda NOT RUN en banco
  compatible. No se relajó ningún permiso ni se cambió configuración/versiones.
  Producción reporta la misma versión: NO reproducir allí la caída.
- Las diez suites SQL y sus mutantes terminan con ROLLBACK; los fallos cierran
  la conexión. Las carreras sí hacen COMMIT en sus bases efímeras exclusivas,
  eliminadas al terminar; nunca lo hacen en la plantilla ni en producción.
- Un primer intento falló por acceso al socket Docker: se repitió con permiso.
  Un terminador SQL ausente fue corregido y el banco completo pasó después.

## Próximo trabajo obligatorio (no declarar F2 completo)

1. **Instalación inactiva y conciliación atómica implementadas/probadas.**
   Instalar el esquema YA NO vacía septiembre: conserva la política anterior
   hasta el COMMIT del activador. No activar sin ensayo y aprobación del SQL.
   Manifiesto privado en `/private/tmp/conversion-fecha-f0.ANVNe4/conciliacion-propuesta.json`:
   108 episodios, 106 fuentes exactas (97 septiembre, 9 anteriores), 2 pendientes,
   ninguna fuente repetida. Incluye las cinco selecciones expresas de Miguel.
   Revalidado en vivo 27/09 00:40 Lima: cero divergencias lead/episodio/fuente,
   cero identidades canónicas repetidas, cero episodios nuevos, septiembre abierto.
   SQL y resultado de solo lectura están junto al JSON. Revalidar inmediatamente
   antes de aplicar; reversa y huellas ya preparadas. Ejecutar TODO atómicamente.
   La recepción usa reloj real al conciliar: nunca antedatar. Si se llega a
   octubre 11 sin instalar, no adjudicar septiembre por este manifiesto viejo.
2. Ensayo remoto: matriz HTTP/Auth/RLS integral y advisors; tipos completos.
   Los tipos nuevos se generaron literalmente desde `conversion_tipos_v3_20260927`.
   Se conservan tipos ajenos existentes: la regeneración integral remota sigue pendiente.
3. Retiro de fuente, carreras corregir/anular/sellar/retirar y roster con cuotas
   ya probados localmente. Repetir la matriz pertinente en el banco remoto
   autorizado: SQL local no equivale a Auth/PostgREST real.
4. Revalidar manifiesto y proyección privada antes de activar. Las cifras son
   simulación, no resultados publicados; ninguna reparación real aplicada.
5. Verificar gate final contra el commit integrado. La revisión de diseño y
   de implementación consumieron las dos consultas previstas; PRIMARY conserva
   responsabilidad sobre correcciones y pruebas, sin consultas para forzar PASS.
6. Ensayo remoto/coste/SQL exacto/release y verificaciones productivas pendientes
   de sus aprobaciones. Main=avancecorp/main al publicar. No activar Cron ni
   sellar históricos. Nunca instalar directo en producción.

## Documentación técnica consultada

- Guías Supabase y Supabase Postgres Best Practices: invoker, permisos mínimos,
  candados consistentes y transacciones cortas.
- Context7 `/supabase/supabase`, funciones y permisos; documentación oficial:
  https://supabase.com/docs/guides/database/functions
- Changelog revisado 26/09: upgrade 15.19/17.11 anunciado para 28/09. No se
  cambiaron versiones, extensiones, operadores ni infraestructura como parte
  del trabajo. El ensayo remoto debe registrar su versión real de Postgres.

El árbol raíz contiene cambios ajenos y no se toca código allí. Clon existente:
`/private/tmp/ranking-cartera.AfQUSa`, rama `codex/conversion-fecha-comercial`.
Los cambios previos propios del acta de Ranking en MIGRACIONES/PRODUCCION-VERIFICADA
se preservaron. No se creó un worktree ni se realizó commit/push/publicación.

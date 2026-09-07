# Núcleo escritor SLA N2

Implementación en `../../migrations/20260907024903_crm_sla_nucleo_operativo_escritura.sql`.
No publica políticas, reconstruye stock ni activa al instalarse. Requiere N1 y
las puertas de gobernanza reales en verde. Comprueba huellas de los tres cuerpos
que reemplaza, por lo que cualquier drift obliga a reconciliar el SQL.

## Prueba reproducible

`../../scripts/test-sla-operacion-local.py` requiere el template del banco integral
PG17 preparado por `test-sla-integracion-local.py`, con N1, política base v1 y los
actores sintéticos documentados por ese banco. Acepta solo socket local bajo
`/private/tmp/sla-integracion-*`, puerto 55485. Clona el template; cada prueba usa
otro clon y al finalizar solo borra sus propias bases. No recibe URL de producción.

```sh
python3 CRM-Avance-Corp/supabase/scripts/test-sla-operacion-local.py \
  --socket /private/tmp/sla-integracion-7q2czdop --template sla_integracion \
  --output /private/tmp/sla-n2-resultados-20260907.json
```

Resultado del 07/09/2026 UTC: **23/23**, 7,145 segundos de casos. Se usaron las
funciones, RLS y gates CRM reales, no versiones simplificadas. Las tablas de
metadatos de cron del banco no ejecutan un scheduler; cada clon adapta únicamente
`cron.job.database` a su nombre, conservando horario, comando y estado.

Se verificaron autoridad Gerencia; publicación atómica v2 y herencia del anexo por
v1; CAS con `P0409`; inicialización aprobada que preserva primera atención y rechaza
políticas futuras/reinicios; dos inicializaciones simultáneas; adopción inmutable;
captura humana/interna; reconstrucción humana idempotente y rechazo de alta interna
sin prueba humana; retiro del helper; concesión por mismo episodio, ventana y tope;
dos gestiones simultáneas sin duplicar presupuesto; apagado que espera una gestión
admitida; sello de fecha servidor; falta de concesión en avances, intentos,
episodios históricos y modos de lectura; cierre de ACL; contingencia repetible que
conserva historia/avance/locks y bloquea reactivación.

Los casos de gesto compuesto y recibos están en `test-sla-comandos-local.py` (N3).
Estos resultados locales no acreditan todavía instalación ni uso en producción.

## Configuración gobernada

`crm.configuracion_sla_v2_fn()` devuelve vigente, última publicada, revisión de
modo y `inicializacion_aprobada`. Esta contiene `{disponible,motivo,config}`. Motivos:
`politica_futura`, `ya_publicadas`, `sin_permiso` o null. El documento `config` viene
del proveedor privado único `private.sla_config_inicial_aprobada(uuid)`.

Gerencia inicializa con `crm.publicar_reglas_sla_aprobadas_v2(p_expected_version)`.
Esta puerta solo sirve cuando la última política vigente carece de anexo. Comparte
lock y publicador con v1/v2. Devuelve `{version:2,politica:{base,operacion},expected_version}`.
Publica los plazos aprobados y conserva primera gestión/contacto vigentes. No cambia
el modo. Una política posterior se edita con `crm.publicar_politica_sla_v2`; v1
mantiene su firma e incorpora el anexo anterior al publicar su nueva versión.

`crm.cambiar_modo_sla_operacion(p_expected_revision,p_modo)` admite legado,
observacion y activo. Primera activación y adopción se fijan solo una vez. Un CAS
obsoleto usa **P0409**, no 40001, para evitar los reintentos largos de PostgREST.
La interfaz debe releer y pedir revisión humana, sin repetir automáticamente la
mutación con una revisión nueva. El modo requiere los hooks completos para entrar
en observación/activo.

## Reconstrucción y cierre

Después de N2/N3, todavía en legado, el propietario ejecuta lotes de hasta 200
leads. Cada lote debe tener una transacción independiente:

```sql
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
select * from private.sla_reconstruir_contextos_lote(:lead_ids::uuid[]);
commit;
```

`:lead_ids` es un parámetro enlazado por el operador, nunca SQL interpolado desde
el cliente. El timeout de sentencia se establece fuera de la función para que
gobierne toda la llamada. Un timeout revierte ese lote; conservar legado y revisar
la contención. No ampliar los límites sin evidencia.

La función bloquea todos los leads por ID, después sus tareas pendientes por ID,
y el control al final. Relee ciclo, tenencia y auditoría tras bloquear. Exige ciclo
actual no aproximado/finito, fecha de creación dentro del ciclo, tenencia coherente,
cadena causal válida y auditoría de INSERT humana con autor/fecha/lead coincidentes
y sello dentro de 60 segundos. No interpreta `vence_en` como creación. Cierre,
inactivación o abandono total de tenencia posteriores impiden reconstruir.

Devuelve reconstruido/existente o un motivo explícito: conflicto_contexto,
ciclo_no_demostrable, lead_no_abierto, creacion_fuera_ciclo, tenencia_incoherente,
cadena_no_demostrable, alta_humana_no_demostrable o barrera_de_cancelacion. No cambia
la tarea ni sus fechas, autor, dueño o estado. Los ambiguos siguen en agenda sin
cobertura. Guardar el resultado real fuera del repositorio y comparar su cobertura
contra el contraste previo; las 831 tareas de la foto anterior no son una promesa
de cardinalidad para una cartera que sigue cambiando.

Solo después de guardar y revisar los resultados, aplicar
`20260907031450_crm_sla_cierre_reconstruccion_contextos.sql`. Retira los dos helpers
transitorios; conserva contextos/captura y comprueba el gate. No debe aplicarse
automáticamente junto con N2 antes de reconstruir.

## Recuperación

La primera medida es pasar a legado por RPC y, si corresponde, volver al artefacto
frontend previo. El cambio de modo espera los ajustes ya admitidos; una vez
confirmado no hay ajustes nuevos hasta una reactivación expresa. Conserva primera
activación, adopción, políticas, contextos, ajustes y recibos.

Si un fallo estructural en los hooks persiste, existe
`../../scripts/rollback-sla-operacion-hooks.sql`, ensayado y repetible. Exige legado,
obtiene locks acotados y retira únicamente captura y adjudicación, conservando
avance automático, clocks, autorización, locks fuertes y firmas consumidas por
N3/v1. No borra tablas ni registros y no modifica recibos. Ante contención falla
íntegramente en cinco segundos. Deja el gate normal en rojo por hooks ausentes, de
forma que no se puede reactivar por accidente. Registrar cuándo se interrumpió la
captura. Recuperar exige una nueva migración revisada y reconstrucción/verificación
del intervalo; no volver a ejecutar N2 a ciegas (sus huellas impiden hacerlo sobre
un estado distinto) ni relajar el gate para que pase.

`fuentes-previas.json` conserva las seis definiciones originales leídas y sus
huellas, sin datos de cartera, para revisión de contingencia y drift.

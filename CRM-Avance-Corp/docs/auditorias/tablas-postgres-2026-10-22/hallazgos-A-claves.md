# Frente A — Claves e integridad referencial
VERDICT: ATENCIÓN

SUMMARY: Las claves del CRM están bien armadas. Las 151 tablas tienen clave primaria, salvo 3 respaldos o catálogos. Las 281 llaves foráneas están validadas. Los tres 1:1 que pide el negocio (un titular principal por inversión, una acreditación por lead y una cuenta de pago por contrato) los garantiza la base con UNIQUE. Ninguna columna `*_id` sin FK es un hueco real: todas tienen motivo, casi siempre escrito. Lo que queda abierto: un lead convertido puede quedarse sin contrato vivo (ya pasó, con 7 leads diferidos desde el 06/10); el borrado de un perfil de cliente arrastraría sus cuentas bancarias, porque no hay candado; y varias copias de datos (analista acreditado, lead del episodio, titular principal) solo se mantienen por código, no por llave.

Rutas de evidencia relativas a `scratchpad/auditoria-tablas/` (`catalogo-estructura.sql` = DDL de prod; `esquema-prod-20261022.sql` = volcado con cuerpos de funciones). Migraciones en `CRM-Avance-Corp/supabase/migrations/`.

## FINDINGS

### [P1] A-1 · Un lead «convertido» puede quedarse sin venta viva, y la base no lo impide
- Tabla/columna/constraint: `crm.leads.contrato_id` → `public.contratos` `ON DELETE SET NULL` (`leads_contrato_id_fkey`); índice `idx_leads_contrato` NO único.
- Evidencia:
  - `catalogo-estructura.sql:6426`: `FOREIGN KEY (contrato_id) REFERENCES public.contratos(id) ON DELETE SET NULL`.
  - Ninguno de los 20 CHECK de `crm.leads` ata `etapa='convertido'` a un vínculo. El único que mira la etapa es `descartado_requiere_motivo`.
  - `idx_leads_contrato USING btree (contrato_id) WHERE contrato_id IS NOT NULL` no es UNIQUE (`catalogo-estructura.sql:4710`): dos leads pueden apuntar al mismo contrato.
  - La puerta `crm.contrato_eliminar_auditado` permite ese SET NULL de forma explícita (`esquema-prod-20261022.sql:8231-8237`, lista blanca `'crm.leads'::regclass`). Solo guarda `leads_referencias` en la copia (`:8336`) y no revincula el lead si el contrato se recarga.
  - Ya pasó en producción: la nota del vault «Reemplazar inversion - plan por fases (2026-10-17)» deja como diferidos «los 7 leads con contrato colgante del 06/10». La memoria `diagnostico-conversion-setiembre-2026` registra además un lead convertido sin `contrato_id` que nunca acredita.
- Por qué importa: el lead sigue contando como convertido para el embudo, pero su venta desapareció o quedó en otro contrato. Conversión, ranking y «Mis ventas» pueden no cuadrar con los contratos reales.
- Qué haría falta: escribir la regla «convertido ⇒ fuente viva (contrato o cierre externo inicial)» en la base, con un constraint trigger diferido o pasando la FK a RESTRICT para que el borrado obligue a anular o reemplazar la venta. Decidir también si `leads.contrato_id` debe ser UNIQUE.
- SQL de comprobación (solo lectura):
```sql
select
  count(*) filter (where l.etapa='convertido' and l.contrato_id is null
    and not exists (select 1 from crm.cierres_externos ce
                    where ce.lead_id=l.id and ce.es_cierre_inicial and ce.anulado_en is null)) as convertidos_sin_venta_viva,
  count(*) filter (where l.contrato_id is not null
    and not exists (select 1 from public.contratos c where c.id=l.contrato_id))             as contrato_inexistente,
  (select count(*) from (select contrato_id from crm.leads where contrato_id is not null
                         group by contrato_id having count(*)>1) d)                         as contratos_con_2_o_mas_leads
from crm.leads l;
```

### [P2] A-2 · CASCADE desde `public.perfiles` borraría datos de pago y el historial postventa del cliente, sin candado
- Tabla/columna/constraint:
  - `crm.cuentas_bancarias.cliente_id` (`cuentas_bancarias_cliente_id_fkey`, CASCADE, `catalogo-estructura.sql:6126`).
  - `crm.actividades_cliente.cliente_id` (CASCADE, `:5943`).
  - `crm.tareas.perfil_id` (CASCADE, `:6693`).
- Evidencia:
  - De los 4 CASCADE hacia `public.perfiles`, solo `crm.equipo.perfil_id` (`:6159`) tiene un candado: `trg_equipo_no_borrar` (`:5592`) lanza una excepción salvo en la purga declarada.
  - `cuentas_bancarias` solo tiene triggers de UPDATE (`trg_cuentas_bancarias_version_inmutable`, `:5572`) y de auditoría. `actividades_cliente` y `tareas` no tienen ningún candado de DELETE.
  - Las constancias que apuntan a esas cuentas no tienen FK y sobreviven a propósito: `cuotas_cuenta_pagada` (1408 filas), `cuentas_bancarias_retiros` y `contrato_cuenta_pago_cambios`. Quedarían apuntando a cuentas borradas.
  - Solo protege a la cuenta vigente de cada contrato: `contrato_cuentas_pago.cuenta_bancaria_id` RESTRICT. Las versiones anteriores de la cuenta no tienen esa protección.
- Por qué importa: si el portal o Auth borra el perfil de un cliente que no tiene ficha ni contrato que lo bloquee, se pierden sin aviso sus cuentas bancarias (66 filas en total) y su timeline postventa. Solo quedaría el rastro de `log_audit_crm`. HIPÓTESIS: no consta que el portal borre perfiles, y la acción de `public.contratos.cliente_id` y la de `public.perfiles` → `auth.users` no están en el volcado.
- Qué haría falta: cambiar esos 3 CASCADE a RESTRICT, o ponerles un trigger «no borrar» como el de `crm.equipo`.
- SQL de comprobación (filas que hoy no anclan ni una ficha `crm.inversionistas` ni un contrato, es decir, las que un borrado de perfil se llevaría):
```sql
select 'cuentas_bancarias' as tabla, count(*) as filas_expuestas from crm.cuentas_bancarias x
 where not exists (select 1 from crm.inversionistas i where i.perfil_id=x.cliente_id)
   and not exists (select 1 from public.contratos c where c.cliente_id=x.cliente_id)
union all
select 'actividades_cliente', count(*) from crm.actividades_cliente x
 where not exists (select 1 from crm.inversionistas i where i.perfil_id=x.cliente_id)
   and not exists (select 1 from public.contratos c where c.cliente_id=x.cliente_id)
union all
select 'tareas.perfil_id', count(*) from crm.tareas x
 where x.perfil_id is not null
   and not exists (select 1 from crm.inversionistas i where i.perfil_id=x.perfil_id)
   and not exists (select 1 from public.contratos c where c.cliente_id=x.perfil_id);
```

### [P2] A-3 · Copias de datos que solo cuida el código: ninguna llave las ata a su original
- Tabla/columna/constraint:
  - `crm.conversion_acreditaciones` (306 filas): `episodio_id` (FK a `lead_asignaciones`) y `lead_id` (FK a `leads`) son FK independientes; nada exige que el episodio sea de ese mismo lead. `analista_id` no tiene FK (`catalogo-estructura.sql:1150`).
  - `crm.actividad_ciclo_contexto.lead_id` frente a `crm.actividades.lead_id`.
  - `crm.inversion_titulares` (rol `principal`) frente a `crm.inversiones.inversionista_id`.
  - `crm.leads.inversionista_id` frente a `crm.inversionista_leads`.
- Evidencia:
  - El alta copia `v_episodio.analista_id` en la acreditación (`esquema-prod-20261022.sql:42769`). Luego la acreditación se actualiza sin tocar `episodio_id` ni `analista_id` (`:42783`). La tabla no tiene ningún trigger que impida cambiar esas columnas (solo `trg_audit_conversion_acreditaciones`, `catalogo-estructura.sql:5302`).
  - `actividad_ciclo_contexto` la llena un trigger desde `new.lead_id` (migración `20261019001500_crm_recorrido_evaluacion.sql:117`), pero su FK a `leads` es aparte de la FK a `actividades`.
  - `private.inversion_titular_coherente` (`catalogo-estructura.sql:5616`) solo vigila el lado `inversion_titulares`. Si cambia `inversiones.inversionista_id`, nadie revisa el titular principal; hoy lo cuida a mano la fusión (`esquema-prod-20261022.sql:16298-16310`).
  - `leads.inversionista_id` es UNIQUE (`leads_inversionista_uidx`, `:4924`) e `inversionista_leads.lead_id` también (`:4844`), pero no hay ninguna llave que obligue a que digan lo mismo.
- Por qué importa: la conversión por analista, la atribución de la venta y la cartera por persona leen estas copias. Un desajuste no da error: el número sale mal en silencio.
- Qué haría falta: agregar FK compuestas sobre UNIQUE baratos en el padre. Por ejemplo, `UNIQUE (id, lead_id, analista_id)` en `lead_asignaciones` y luego `FOREIGN KEY (episodio_id, lead_id, analista_id)`; lo mismo `(actividad_id, lead_id)` → `actividades(id, lead_id)`. En los demás casos, un trigger del lado padre.
- SQL de comprobación (todo debería dar 0):
```sql
select 'acreditacion: episodio de otro lead' as chequeo, count(*) from crm.conversion_acreditaciones ca
  join crm.lead_asignaciones la on la.id=ca.episodio_id where la.lead_id<>ca.lead_id
union all select 'acreditacion: analista distinto del episodio', count(*) from crm.conversion_acreditaciones ca
  join crm.lead_asignaciones la on la.id=ca.episodio_id where ca.analista_id is distinct from la.analista_id
union all select 'acreditacion: analista fuera de crm.equipo', count(*) from crm.conversion_acreditaciones ca
  where ca.analista_id is not null and not exists (select 1 from crm.equipo e where e.perfil_id=ca.analista_id)
union all select 'contexto: lead distinto de su actividad', count(*) from crm.actividad_ciclo_contexto x
  join crm.actividades a on a.id=x.actividad_id where a.lead_id is distinct from x.lead_id
union all select 'titular principal distinto de la inversion', count(*) from crm.inversion_titulares t
  join crm.inversiones i on i.id=t.inversion_id where t.rol='principal' and t.inversionista_id<>i.inversionista_id
union all select 'inversion sin titular principal', count(*) from crm.inversiones i
  where not exists (select 1 from crm.inversion_titulares t where t.inversion_id=i.id and t.rol='principal')
union all select 'lead sin su par en inversionista_leads', count(*) from crm.leads l
  where l.inversionista_id is not null and not exists
    (select 1 from crm.inversionista_leads il where il.lead_id=l.id and il.inversionista_id=l.inversionista_id);
```

### [P3] A-4 · Cuatro `*_id` sin FK y sin una justificación escrita (clase b)
- Tabla/columna/constraint:
  - `crm.solicitudes_tasa.producto_condicion_id` (`catalogo-estructura.sql:3069`).
  - `crm.producto_condiciones.legacy_contrato_id` (1085 filas, `:2762`, índice `:5014`).
  - `crm.cambio_cuenta_avisos.solicitud_id` (`:781`).
  - `crm.origenes_capital_confirmados.contrato_id` y `.cierre_externo_id` (`:2590`).
- Evidencia:
  - Ninguna lleva `COMMENT` que diga «sin FK a propósito», a diferencia de las otras 30 de la lista.
  - `producto_condicion_id` llega del navegador y solo entra en la huella (migración `20260918210543_crm_modo_rentabilidad_integral.sql:169`). Su tabla destino es inmutable, así que una FK no estorbaría.
  - `cambio_cuenta_avisos.solicitud_id` no admite FK porque en `contrato_cuenta_pago_cambios` la clave única es `(solicitud_id, contrato_id)` (`:3948`).
  - `origenes_capital_confirmados` valida la fuente solo al insertar (`private.origen_capital_confirmado_guardar`).
- Por qué importa: hoy el impacto es bajo (solicitudes y orígenes casi vacíos; las condiciones legado no se ofrecen), pero alguien que lea el DDL no sabe si falta la FK por descuido o a propósito.
- Qué haría falta: agregar la FK a `producto_condiciones`, que es inmutable, y documentar con `COMMENT ON COLUMN` el porqué de las otras tres.
- SQL de comprobación (huérfanos actuales):
```sql
select 'solicitudes_tasa.producto_condicion_id' as columna, count(*) from crm.solicitudes_tasa s
  where s.producto_condicion_id is not null and not exists (select 1 from crm.producto_condiciones p where p.id=s.producto_condicion_id)
union all select 'producto_condiciones.legacy_contrato_id', count(*) from crm.producto_condiciones p
  where p.legacy_contrato_id is not null and not exists (select 1 from public.contratos c where c.id=p.legacy_contrato_id)
union all select 'cambio_cuenta_avisos.solicitud_id', count(*) from crm.cambio_cuenta_avisos a
  where not exists (select 1 from crm.contrato_cuenta_pago_cambios c where c.solicitud_id=a.solicitud_id)
union all select 'origenes_capital_confirmados (activos)', count(*) from crm.origenes_capital_confirmados o
  where o.activo and ((o.contrato_id is not null and not exists (select 1 from public.contratos c where c.id=o.contrato_id))
     or (o.cierre_externo_id is not null and not exists (select 1 from crm.cierres_externos e where e.id=o.cierre_externo_id)));
```

### [P3] A-5 · Tres tablas sin PRIMARY KEY; un respaldo vivo podría tener filas duplicadas
- Tabla/columna/constraint:
  - `private.respaldo_cierre_septiembre_2026` (169 filas, `catalogo-estructura.sql:3799`).
  - `private.respaldo_cierre_agosto_2026` (0 filas, sin RLS y sin grants, `:3791`).
  - `private.pares_autoridad` (`:3782`).
- Evidencia:
  - Los respaldos tienen solo `(tabla text, fila jsonb, guardado_en)`, sin constraints ni índices.
  - `pares_autoridad` usa `CONSTRAINT par_unico UNIQUE NULLS NOT DISTINCT (rol_portal, rol_crm)` (`:4524`) como clave natural. Es correcto, pero sin PK la tabla no puede entrar en una publicación lógica para UPDATE/DELETE.
- Por qué importa: si el respaldo de septiembre se guardó dos veces, `03-restaurar.sql` reinsertaría filas repetidas al restaurar (HIPÓTESIS: no leí ese script). El de agosto está vacío, así que restaurar agosto ya no es posible con él.
- Qué haría falta: confirmar que no hay duplicados antes de que se selle septiembre (22/10). Darle a `pares_autoridad` una PK `(rol_portal, rol_crm)` o un `id`. Ver A-8 para los respaldos.
- SQL de comprobación:
```sql
select tabla, count(*) as filas, count(distinct fila) as distintas
from private.respaldo_cierre_septiembre_2026 group by tabla order by tabla;
```

### [P3] A-6 · FK sin índice: ninguna duele hoy
- Tabla/columna/constraint: es la lista de `hechos-produccion.md`, unas 40 FK. 25 son `creado_por`/`*_por`/`actualizado_por` hacia `public.perfiles`. Las únicas con miles de filas son `crm.lead_sla_etapas.politica_id` (9356) y `crm.lead_sla_ciclos.politica_id` (4617), ambas hacia `crm.sla_politicas`.
- Evidencia:
  - `catalogo-estructura.sql:6420` y `:6402` (RESTRICT, sin índice).
  - Las tablas padre de esas FK nunca se borran: `sla_politicas`, `politica_rentabilidad` y `solicitudes_tasa` son versionadas o inmutables, y a `public.perfiles` la frenan decenas de RESTRICT y el candado de `crm.equipo`.
  - Los dos caminos de borrado que sí existen tienen todas sus FK hijas indexadas: borrar un lead por error de carga y borrar un contrato (en `hechos-produccion.md` no aparece ninguna FK hacia `crm.leads` ni hacia `public.contratos` sin índice).
- Por qué importa: solo afecta al rendimiento de un borrado del padre o de un join filtrado por esa columna. Ninguno de los dos se hace en el uso diario.
- Qué haría falta: nada urgente. Indexar `politica_id` en las tablas de SLA solo si alguna lectura filtra por política.
- SQL de comprobación (¿se recorren enteras esas tablas?):
```sql
select relname, seq_scan, seq_tup_read, idx_scan, n_live_tup
from pg_stat_user_tables
where schemaname='crm' and relname in ('lead_sla_etapas','lead_sla_ciclos','ledger_rentabilidad','postventa_operaciones','inversionistas')
order by seq_tup_read desc;
```

### [P3] A-7 · ON DELETE declarado que no se ejecuta nunca, y SET NULL en columnas de autoría
- Tabla/columna/constraint:
  - `crm.equipo.perfil_id` CASCADE (`catalogo-estructura.sql:6159`): lo anula `trg_equipo_no_borrar`.
  - `crm.leads.vendedor_id` y `crm.leads.asignado_supervisor_id`, `crm.tareas.vendedor_id` y `crm.equipo.supervisor_id`: SET NULL hacia `crm.equipo`, que no se borra salvo por la purga.
  - SET NULL en columnas de autoría: `crm.actividades.creado_por` (`:5955`), `crm.tareas.creado_por` (`:6684`), `crm.leads.creado_por`, `crm.leads.descartado_por` (`:6432`), `crm.leads.perfil_id` (`:6438`) y `crm.actividades_cliente.creado_por`.
- Evidencia: el propio esquema rechaza ese patrón en `crm.tareas.cancelada_por_id` (`catalogo-estructura.sql:166`): «Sin FK a public.perfiles a propósito: con on delete set null, dar de baja a un supervisor reescribiría hacia atrás el % de sus vendedores». La misma razón vale para `actividades.creado_por`, que es la columna con la que Gestión Diaria cuenta las llamadas por autor.
- Por qué importa: en la práctica nadie llega ahí. Un miembro con historial no se puede purgar, porque `lead_asignaciones` y el resto de RESTRICT hacia `crm.equipo` lo impiden. Pero el DDL promete un comportamiento que no existe y, si un día se abre la purga, la atribución histórica se borraría sin aviso. HIPÓTESIS: no leí `private.trg_devolucion_equipo_solo_rpc` (`:5662`), que probablemente también frena el SET NULL en `leads`.
- Qué haría falta: pasar a RESTRICT/NO ACTION las FK de autoría y las CASCADE neutralizadas, para que el DDL diga lo que de verdad pasa. Otra opción es documentarlas.
- SQL de comprobación (¿ya se perdió autoría en el historial de llamadas?):
```sql
select tipo, count(*) as sin_autor from crm.actividades where creado_por is null group by tipo order by 2 desc limit 10;
```

### [P3] A-8 · Tablas que parecen residuales, candidatas a limpieza (no borrar sin decisión de Miguel)
- Tabla/columna/constraint:
  - Archivo legado: `crm.objetivos_legacy_archivo` y `crm.objetivos_vendedores_legacy_archivo`. Esta última tiene FK a `auth.users` (`catalogo-estructura.sql:6507`) y a `crm.equipo`.
  - Backfills: `crm.backfill_multiempresa_mapa`, `crm.inversion_backfill_lotes`, `private.backfill_cuentas_p0xx` y `private.conciliacion_cuentas_p0xx`. Las dos últimas no tienen comentario.
  - Piloto: `crm.piloto_f8_control` y `crm.piloto_f8_miembros`.
  - Respaldo: `private.respaldo_cierre_agosto_2026`.
  - `private.respaldo_cierre_septiembre_2026` se conserva hasta comprobar el sello del 22/10.
- Evidencia: todas tienen `n_live_tup = 0` en `hechos-produccion.md`. Ese número es una estimación: `crm.empresas` también sale con 0 y no puede estar vacía, porque las 388 `crm.inversiones` la referencian con FK NOT NULL.
- Por qué importa: las tablas vacías con FK siguen frenando borrados y siguen sumando superficie de permisos. Los comentarios de `backfill_multiempresa_mapa` («Fuente de la reversa») y de `respaldo_cierre_agosto_2026` («Se restaura con 03-restaurar.sql») hacen promesas que no se cumplen si de verdad están vacías.
- Qué haría falta: contar las filas exactas y, con las que estén vacías y su fase cerrada, aplicar CERRAR → OBSERVAR → DERRIBAR.
- SQL de comprobación:
```sql
select 'objetivos_legacy_archivo' t, count(*) from crm.objetivos_legacy_archivo
union all select 'objetivos_vendedores_legacy_archivo', count(*) from crm.objetivos_vendedores_legacy_archivo
union all select 'backfill_multiempresa_mapa', count(*) from crm.backfill_multiempresa_mapa
union all select 'inversion_backfill_lotes', count(*) from crm.inversion_backfill_lotes
union all select 'piloto_f8_control', count(*) from crm.piloto_f8_control
union all select 'piloto_f8_miembros', count(*) from crm.piloto_f8_miembros
union all select 'backfill_cuentas_p0xx', count(*) from private.backfill_cuentas_p0xx
union all select 'conciliacion_cuentas_p0xx', count(*) from private.conciliacion_cuentas_p0xx
union all select 'respaldo_cierre_agosto_2026', count(*) from private.respaldo_cierre_agosto_2026
union all select 'empresas (control: no puede ser 0)', count(*) from crm.empresas;
```

### [P3] A-9 · Comprobar una vez que ninguna FK quedó saltada (0 huérfanos, 0 triggers de FK apagados)
- Tabla/columna/constraint: las 281 FK de `crm` y `private`.
- Evidencia:
  - La memoria `diagnostico-conversion-setiembre-2026` describe los 7 leads como «`leads.contrato_id` COLGANTE pese a FK ON DELETE SET NULL validada y activa». Una FK validada no puede dejar un id colgante, salvo que sus triggers estén apagados.
  - En producción `session_replication_role` no se puede fijar (migración `20260811190310_crm_ledger_cierres_integros.sql:449-456`).
  - Las migraciones apagan triggers siempre por su nombre y los vuelven a encender (por ejemplo `20260807203757:747-764` y `20260725012707:72-82`).
  - Lo más probable es que «colgante» significara `NULL` o «apunta al contrato equivocado», no un id inexistente. Sin embargo, el volcado no muestra `tgenabled`, así que no lo puedo descartar.
- Por qué importa: si un trigger de FK (RI) estuviera apagado, todas las conclusiones de este frente sobre «la base lo garantiza» serían falsas para esa tabla.
- Qué haría falta: correr una vez el barrido de abajo. Debe dar 0 en todas las filas.
- SQL de comprobación (FK de una sola columna, más los triggers de FK deshabilitados; solo lectura, unos segundos):
```sql
select c.conrelid::regclass::text as tabla, c.conname::text as fk,
  (xpath('/row/n/text()', query_to_xml(format(
     'select count(*) as n from %s h where h.%I is not null and not exists (select 1 from %s p where p.%I = h.%I)',
     c.conrelid::regclass, a.attname, c.confrelid::regclass, af.attname, a.attname), false, true, '')))[1]::text::bigint as huerfanos
from pg_constraint c
join pg_attribute a  on a.attrelid=c.conrelid  and a.attnum=c.conkey[1]
join pg_attribute af on af.attrelid=c.confrelid and af.attnum=c.confkey[1]
where c.contype='f' and cardinality(c.conkey)=1
  and c.connamespace in ('crm'::regnamespace,'private'::regnamespace)
union all
select 'pg_trigger', 'triggers RI deshabilitados', count(*)
from pg_trigger t join pg_class r on r.oid=t.tgrelid
where t.tgisinternal and t.tgconstraint<>0 and t.tgenabled='D'
  and r.relnamespace in ('crm'::regnamespace,'private'::regnamespace)
order by 3 desc limit 15;
```

## CLASIFICACIÓN de columnas *_id sin FK

| Columna | Clase | Motivo |
|---|---|---|
| crm.actividad_ciclo_contexto.gesto_oficina_id | a | Es el `operacion_id` de idempotencia del gesto de oficina. La clave de `multiempresa_idempotencia` es texto, así que no admite FK. Un CHECK lo ata a `oficina_tarea_id`, que sí tiene FK. |
| crm.alertas_reconocimientos.alerta_id (text) · .solicitud_corte_id | a | Id de grupo del front, que un trigger valida contra el actor, e idempotencia (único por `perfil_id`). |
| crm.backfill_multiempresa_mapa.fila_id | a | Origen polimórfico (perfil, cierre o lead) de un backfill. Ver A-8. |
| crm.base_carga_operaciones.operacion_id · crm.bases_carga.operacion_id | a | Idempotencia del front (único). |
| crm.cambio_cuenta_avisos.solicitud_id | b | La clave única del destino es compuesta, así que no admite FK, y no hay COMMENT. Ver A-4. |
| crm.capital_valoraciones.fuente_id | a | Polimórfico (contrato o cierre externo). Foto inmutable, única por `(fuente, fuente_id, revision)`. |
| crm.contrato_cuenta_pago_asignaciones (cliente_id, contrato_id, cuenta_bancaria_id, solicitud_id, vinculo_id) | a | COMMENT: «Sin claves foráneas a propósito: sobrevive…». Inmutable y no se borra. |
| crm.contrato_cuenta_pago_cambios (cliente_id, contrato_id, cuenta_anterior_id, cuenta_nueva_id, solicitud_id) | a | Igual: historial inmutable que sobrevive a contratos, clientes y cuentas. |
| crm.contratos_eliminados_auditoria.contrato_id | a | Copia de lo eliminado. UNIQUE `contrato_id`. |
| crm.conversion_acreditaciones.analista_id | b | Copia de `lead_asignaciones.analista_id`, sin FK a `crm.equipo` (que nunca se borra) y sin amarre al episodio. Manda en la conversión por analista. Ver A-3. |
| crm.conversion_acreditaciones.fuente_id | a | Polimórfico. Las lecturas derivan `fuente_retirada` cuando la fuente ya no existe (`esquema-prod-20261022.sql:43860-43863`). |
| crm.conversion_reservas.claim_id | a | Claim de la saga de Auth (`multiempresa_idempotencia`, con clave texto). |
| crm.conversion_ventas_recuperadas (acreditacion_id, contrato_vigente_id, fuente_borrada_id, lead_id) | a | COMMENT: sin FK a propósito. Un trigger valida al insertar. Inmutable. |
| crm.correcciones_categoria_contrato (actor_id, contrato_id) | a | Migración `20261015212939:8`: «Sin FK: … sobreviven a una eliminación auditada». Falta el COMMENT ON. |
| crm.correcciones_correo_acceso.cliente_id | a (hipótesis) | Bitácora de correcciones de acceso. No tiene comentario de columna. |
| crm.cuentas_bancarias_retiros (cliente_id, cuenta_id, solicitud_id) | a | COMMENT: sin FK a propósito. UNIQUE `cuenta_id` y UNIQUE `solicitud_id`. |
| crm.cuotas_cuenta_pagada (contrato_id, cuenta_bancaria_id, cuota_id) — 1408 | a | COMMENT: sin FK a propósito. Solo la escribe `private.sellar_cuenta_cuota_pagada` desde `public.cronograma_pagos`, así que es coherente por construcción (migración `20260926204051:287`). UNIQUE `cuota_id`. No se borra. |
| crm.dispositivos_push_tasa.sesion_id | a | Id de sesión de Auth, efímero. |
| crm.gestion_diaria_entregas (alerta_id text, solicitud_id) | a | Clave del front e idempotencia (UNIQUE por perfil). |
| crm.inversion_solicitudes.auth_claim_id | a | Claim de la saga de Auth. Un CHECK lo ata a `auth_contexto`. |
| crm.inversiones_eliminadas (fuente_id, inversion_id, inversionista_id, lead_id) | a | COMMENT: copia inmutable de lo eliminado. |
| crm.leads_eliminados.lead_id | a | COMMENT: «sin llave foránea a propósito». |
| crm.ledger_rentabilidad (actor_id, cliente_id, contrato_id, contrato_origen_id) — 1004 | a | COMMENT: «Sin FK a public.contratos a propósito». Append-only. |
| crm.llamadas_celular_eventos.evento_origen_id · private.llamadas_celular_intenciones/recepciones.evento_origen_id (text) | a | Id externo que genera la macro del celular (único). |
| crm.origenes_capital_confirmados (cierre_externo_id, contrato_id) | b | El trigger valida al insertar, pero no hay COMMENT. 0 filas. Ver A-4. |
| crm.postventa_escrituras.tarea_id | a (hipótesis) | Marcador por transacción (PK `(transaccion, tarea_id)`). No tiene comentario. |
| crm.producto_condiciones.legacy_contrato_id — 1085 | b | Sin COMMENT. Condición congelada de un contrato legado; si se elimina el contrato queda huérfana (inofensivo). Ver A-4. |
| crm.sla_operacion_recibos (operacion_id, sujeto_id) — 15218 | a | `operacion_id` = idempotencia (PK `actor_id, operacion_id`). `sujeto_id` es polimórfico: tarea o reunión, según el comando. La tabla no tiene COMMENT ON TABLE. |
| crm.solicitudes_tasa (contrato_id, contrato_origen_id) | a | COMMENT: sin FK a propósito, para no bloquear la eliminación del contrato. |
| crm.solicitudes_tasa.producto_condicion_id | b | Sin COMMENT. Llega del navegador y el destino es inmutable. Ver A-4. |
| crm.tareas.cancelada_por_id — 13780 | a | COMMENT: sin FK a propósito (un SET NULL reescribiría el % hacia atrás). Lo acota el CHECK `tareas_cancelada_por_id_valida`. |
| crm.usuario_eventos (actor_id, objetivo_id) | a | Auditoría append-only. |
| private.ayuda_consultas.usuario_id | a | Bitácora de la ayuda (1 fila). |
| private.backfill_cuentas_p0xx (cliente_id, contrato_id, fila_id) · private.conciliacion_cuentas_p0xx (cliente_id, contrato_id) | a | Tablas de trabajo de un backfill ya hecho, vacías. Ver A-8. |
| private.contrato_altas_idempotentes.actor_id | a | Idempotencia (PK `actor_id, clave`). |
| private.contrato_pdf_anexo_emisiones (actor_id, contrato_id, pdf_id) | a | COMMENT: sin FK, sobrevive a la eliminación auditada y al borrado de perfiles. |
| private.membresias_purgadas.perfil_id | a | Lápida de una membresía purgada. |

No hay ninguna de clase (c) (hueco real que deje huérfanos en una tabla viva). Las de clase (b) están en A-3 y A-4.

## LO QUE ESTÁ BIEN (breve, para no repetir trabajo)
- **Restricciones:** ninguna está NOT VALID. Hay 281 FK. Las únicas FK diferidas son las 2 de `sla_operacion_recibos`, y lo son a propósito. Ninguna tiene ON UPDATE (los ids no cambian).
- **Claves primarias:** 148 de 151 tablas tienen PK. Hay 59 cuya PK no es `id uuid default gen_random_uuid()`: 39 usan otra columna o una clave compuesta, 6 un `id boolean`, 8 un `bigint` IDENTITY y 6 un `uuid` sin default. Todas tienen motivo:
  - Tablas de una sola fila (`id boolean`, `singleton`, `unica`).
  - Extensiones 1:1 (`actividad_ciclo_contexto`, `tarea_sla_contexto`, `inversion_solicitud_origenes`, `inversionista_datos_contacto`, `equipo`, `agenda_ics`…).
  - Idempotencia (`multiempresa_idempotencia`, `postventa_operaciones`, `sla_operacion_recibos`, `contrato_altas_idempotentes`).
  - Claves naturales (`tipo_cambio_diario`, `periodos_cerrados`, `cierre_mes_vendedor`).
  - Las 6 con `uuid` sin default reciben el id de la puerta como llave de idempotencia (`inversion_solicitudes`, `contrato_pdf_jobs`…).
  - Las de `bigint` usan IDENTITY.
- **Los 1:1 y 1:N del negocio están en la base:**
  - Un titular principal por inversión (`inversion_titulares_principal_uidx`) y una inversión por fuente (`inversiones_contrato_uidx`, `inversiones_cierre_uidx`, CHECK `inversiones_una_fuente`).
  - Una acreditación por lead, por episodio y por fuente (3 UNIQUE) y una cuenta de pago por contrato (`contrato_cuentas_pago_contrato_id_key`).
  - Una asignación abierta y una sola conversión por lead, más un EXCLUDE sin solapes. Un ciclo y una etapa abierta por lead.
  - Un responsable abierto por inversionista, un documento vigente por persona y una ficha por perfil.
  - Una publicación y un borrador por producto. Una solicitud de tasa viva por huella. Un retiro por cuenta.
- **Borrado de contrato (`crm.contrato_eliminar_auditado`):** recorre `pg_constraint` y se niega si aparece una dependencia CASCADE o SET NULL nueva (`esquema-prod-20261022.sql:8226-8241`). Copia todo antes de borrar. Además, las migraciones crean candados de DELETE sobre `public.contratos` (`trg_contratos_00_documental_congelado` en `20260818014534:1029` y `trg_contratos_05_restaurar_operacion` en `20260824231133:532`); no los pude verificar en prod porque `public` no está en el volcado. Así, el CASCADE hacia `contrato_cuentas_pago` es deliberado y queda auditado.
- **Borrado de lead:** el CASCADE desde `crm.leads` hacia actividades, tareas y llamadas lo cubren 8 candados (`private.borrado_lead_error_autoriza`). Solo abren dentro de la transacción que copia en `leads_eliminados`.
- **RESTRICT de ledgers y de ventas:** los que van hacia `leads`, `equipo`, `cierres_externos` y `contratos` protegen a propósito. «Eliminar inversión» los revisa antes, con mensajes claros (`private.inversion_motivo_no_eliminable`, que incluye reasignaciones y operaciones de cartera).
- **`cuentas_bancarias.creado_por`:** el SET NULL está previsto y tiene su excepción escrita en el trigger de inmutabilidad.
- **FK a `storage.objects`** desde `cierres_externos.comprobante_objeto_id`: protege el comprobante para que no se borre.
- **FK compuestas:** `actividad_ciclo_contexto` → `lead_sla_ciclos(lead_id, ciclo_n)`, `capital_valoraciones` → `tipo_cambio_diario` (con CHECK de ambos nulos o ambos llenos) y `plazos_carga_mes` → `reaperturas_mes(id, periodo)` están bien formadas.

## CONFIDENCE: media-alta
- Lo que la sostiene: el DDL y los cuerpos de funciones son de producción del 22/10 y leí los triggers y las puertas que cuidan cada caso.
- Lo que la baja:
  - No ejecuté ningún SQL contra producción, así que las cifras de exposición (A-1, A-2, A-3, A-9) quedan pendientes de las consultas de arriba.
  - El esquema `public` no está en el volcado: desconozco la acción ON DELETE de `public.contratos.cliente_id` y de `public.perfiles` → `auth.users`, y si existen candados en `public.perfiles`. Por eso A-2 es una hipótesis.
  - Los conteos de filas son estimados (`n_live_tup`).

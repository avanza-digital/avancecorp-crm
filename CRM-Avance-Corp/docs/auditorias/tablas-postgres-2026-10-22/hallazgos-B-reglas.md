# Frente B — Unicidad y reglas de negocio
VERDICT: ATENCIÓN

SUMMARY: La base está bien armada en lo grueso. Las claves naturales que importan para el dinero tienen su UNIQUE o su PK: mes cerrado, cierre por vendedor y mes, metas, tipo de cambio, acreditación por lead, cuenta de pago por contrato y un tramo abierto por persona. No hay `float`, `money` ni `timestamp` sin zona, y casi todos los ledgers rechazan UPDATE/DELETE con un trigger. El hueco más serio es `crm.conversion_acreditaciones`: es la tabla que decide qué venta cuenta y para quién, y es el único eslabón de la cadena de conversión sin candado en la base. Le siguen siete bitácoras e historiales sin trigger de inmutabilidad, varios códigos `text` sin CHECK (entre ellos `cierre_mes_vendedor.estado`) y el teléfono del lead, que la base no valida al insertar. Ninguno de estos huecos se ha visto roto en los datos: todo depende de que el código no se equivoque. Cada hallazgo trae su consulta de comprobación.

Fuente: `resumen-tablas.json` y `catalogo-estructura.sql` (DDL), y los cuerpos de función de `esquema-prod-20261022.sql` (volcado de producción del 22/10). No se ejecutó nada contra producción. Los conteos de filas son `n_live_tup` (estimados).

## FINDINGS

### [P1] B-1 · `crm.conversion_acreditaciones`: el ledger que acredita la venta no tiene candado en la base
- Tabla/columna/constraint: `crm.conversion_acreditaciones` (306 filas). Sus únicos triggers son `trg_audit_conversion_acreditaciones AFTER INSERT OR DELETE OR UPDATE … log_audit_crm()`. No tiene ningún `BEFORE UPDATE/DELETE`, y nada la referencia por FK (`conversion_ventas_recuperadas.acreditacion_id` no tiene FK, según los hechos).
- Evidencia: las tablas vecinas de la misma cadena sí lo tienen: `lead_asignaciones` (`trg_lead_asignaciones_00_inmutables`), `cierre_mes_vendedor` y `periodos_cerrados` (`trg_cierre_mes_append_only`), `cierres_avance_anulados` (`…_append_only`) y `conversion_ventas_recuperadas` (`proteger_venta_recuperada`). Cinco funciones la actualizan: `private.conversion_acreditar_fuente`, que reescribe `fuente_tipo`, `fuente_id`, `fecha_comercial` y `periodo_comercial`; `conversion_fijar_sello_trg`; `conversion_reevaluar_plazo`; `reabrir_mes`, que borra `sellado_en`; y `sincronizar_conversion_categoria`. Ninguna regla de la base impide, por ejemplo, cambiar `analista_id`, `lead_id` o `fuente_id` en una fila ya sellada, ni borrar una fila. `analista_id` además admite NULL.
- Por qué importa: aquí se decide qué venta se acredita y a quién (conversión mensual y cierre de mes). Un UPDATE manual (en este proyecto se corre SQL a mano en prod) o un error en una ruta DEFINER movería el crédito sin que la base proteste, y lo único que quedaría es el rastro en audit_log.
- Qué haría falta: un trigger `BEFORE UPDATE OR DELETE` que congele la identidad (`id`, `lead_id`, `episodio_id`, `analista_id`, `creado_en`), que impida cualquier cambio con `sellado_en` no nulo salvo la vía de `reabrir_mes` (`private.reapertura_autoriza`, el mismo patrón de `trg_cierre_mes_append_only`) y que rechace el DELETE.
- SQL de comprobación: `select count(*) filter (where sellado_en is not null) as selladas, count(*) filter (where sellado_en is not null and actualizado_en > sellado_en) as tocadas_despues_del_sello, count(*) filter (where analista_id is null) as sin_analista from crm.conversion_acreditaciones;` (lo esperado es 0 en la segunda y la tercera, salvo meses reabiertos).

### [P2] B-2 · Siete bitácoras y tres historiales de vigencia sin trigger de inmutabilidad
- Tabla/columna/constraint: ninguna de estas tablas tiene un `BEFORE UPDATE/DELETE` que rechace cambios. Las protege solo que `authenticated` no tiene grants de escritura.
  - `crm.usuario_eventos` (0 filas estimadas): no tiene ningún trigger, ni siquiera de auditoría. Su COMMENT dice «Auditoria de usuarios CRM. **Append-only**…», pero nada en la base lo impone.
  - `crm.verificaciones_lead` (1621): el registro «anti-pesca» según su COMMENT. Solo tiene `trg_audit_verificaciones_lead`.
  - `crm.inversionista_gestiones` (502): la bitácora postventa. Solo tiene auditoría, y la escriben 9 funciones.
  - `crm.cartera_lecturas` (16353): el registro de quién leyó cartera. Solo auditoría AFTER INSERT.
  - `crm.correcciones_correo_acceso` (5): solo auditoría. Lo único que debería cambiar después es el sellado de `auth_confirmado_en` (`private.sincronizar_correo_cliente_auth`).
  - `private.agenda_reparto_cambios` (16): historial de cambios de reparto sin ningún trigger, ni de auditoría.
  - `crm.inversion_solicitud_origenes` (1): auditoría en IDU, sin candado.
  - Historiales de vigencia en los que el único UPDATE legítimo es cerrar el tramo: `crm.inversionista_responsables` (789; todas las escrituras por función son `set hasta = …`), `crm.inversionista_leads` (339) y `crm.inversionista_identificadores` (760). Ninguna tiene trigger que limite el UPDATE a cerrar el tramo.
- Evidencia: lista de triggers en el JSON. Las funciones que escriben salen de buscar `update|delete from crm.<tabla>` en los cuerpos del volcado. `inversionista_gestiones`, `inversionista_responsables`, `inversionista_leads`, `inversionista_identificadores` y `cartera_lecturas` solo se borran desde `crm.eliminar_lead_error_carga`.
- Por qué importa: la regla de la casa es que bitácoras y ledgers son inmutables. Aquí esa regla depende del código, cuando en el resto de ledgers (más de 40) la impone la base.
- Qué haría falta: un trigger append-only con la misma excepción `private.borrado_lead_error_autoriza` que ya usan `lead_sla_*`. En los historiales de vigencia, un trigger «solo cerrar tramo»: `hasta` de NULL a una fecha, y nada más.
- SQL de comprobación: `select (select count(*) from crm.usuario_eventos) as usuario_eventos, (select count(*) from crm.verificaciones_lead) as verificaciones, (select count(*) from private.agenda_reparto_cambios) as agenda_cambios, (select count(*) from crm.inversionista_responsables where hasta is not null) as tramos_cerrados;`

### [P2] B-3 · Configuración y constancias con candado incompleto
- Tabla/columna/constraint:
  - `crm.conversion_pesos`: el peso del referido y de la renovación, versionado por mes. Solo tiene `trg_audit_conversion_pesos`. Sus hermanas (`meta_periodos`, `metas_vendedor*`, `sla_politicas`, `politica_rentabilidad`, `politica_gestion_diaria`) llevan todas `trg_config_versionada_inmutable`. La llenan migraciones (`20260811154434…`, `20261007160937…`), y `private.peso_referido_conversion` lanza «crm.conversion_pesos esta vacia» si no hay filas, así que el `n_live_tup = 0` es estadística vieja.
  - `crm.capital_valoracion_politica` (1 fila, singleton): no tiene guarda de DELETE y su auditoría es `AFTER INSERT OR UPDATE`, así que un DELETE ni se registraría.
  - `crm.cuotas_cuenta_pagada` (1408): `trg_cuotas_cuenta_pagada_solo_resello` solo congela `id` y `cuota_id`. `contrato_id`, `cuenta_bancaria_id`, `origen` y `sellada_en` se pueden reescribir, aunque el COMMENT la define como «Constancia… No se borra».
- Por qué importa: si alguien cambia el peso de un mes ya pasado, cambia la conversión «viva» y la de un re-sellado (`reabrir_mes` más volver a sellar) sin que quede una revisión nueva. La constancia de la cuenta a la que se pagó una cuota podría quedar apuntando a otro contrato.
- Qué haría falta: añadir `trg_config_versionada_inmutable` a `conversion_pesos`; un trigger de DELETE y auditoría de DELETE en `capital_valoracion_politica`; y en `cuotas_cuenta_pagada`, congelar también `contrato_id`.
- SQL de comprobación: `select p.periodo, p.ponderacion_referido as peso_sellado, (select cp.peso_referido from crm.conversion_pesos cp where cp.vigente_desde <= p.periodo order by cp.vigente_desde desc limit 1) as peso_que_daria_hoy from crm.periodos_cerrados p order by 1;` (si las dos columnas difieren, la tabla ya cambió después del sello).

### [P2] B-4 · `crm.cierre_mes_vendedor`: «lo que se pagó» sin CHECK en `estado` ni en los contadores
- Tabla/columna/constraint: `estado text NOT NULL` no tiene ningún CHECK. `divisor`, `divisor_aproximado`, `cierres_no_referidos`, `cierres_referidos`, `cierres_de_arrastre`, `referidos_recibidos` y `referidos_dados_de_alta` (`integer`) no tienen CHECK `>= 0`. `conversion_pct` no tiene rango. Los únicos CHECK de la tabla son los `*_finito` y `cartera_objeto_check`.
- Evidencia: `crm.cerrar_periodo` calcula `estado` como `case when divisor > 0 then 'medible' when referidos_recibidos > 0 then 'solo_referidos' when … then 'solo_arrastre' else 'sin_actividad' end`, así que el dominio real son esos 4 valores y la coherencia `(estado='medible') = (divisor>0)` está implícita. COMMENT: «Es el registro de lo que se pago». Tiene 42 filas y es append-only.
- Por qué importa: al ser append-only, un valor malo que entre por un cambio futuro de `cerrar_periodo` queda congelado para siempre y solo sale reabriendo el mes.
- Qué haría falta: `check (estado in ('medible','solo_referidos','solo_arrastre','sin_actividad'))`, `check ((estado='medible') = (divisor>0))` y `>= 0` en los contadores.
- SQL de comprobación: `select estado, count(*) as filas, count(*) filter (where (estado='medible') <> (divisor>0)) as incoherentes, count(*) filter (where least(divisor, divisor_aproximado, cierres_no_referidos, cierres_referidos, cierres_de_arrastre, referidos_recibidos, referidos_dados_de_alta) < 0) as negativos from crm.cierre_mes_vendedor group by estado;`

### [P2] B-5 · Seis códigos `text` del esquema `crm` sin CHECK `in (...)`
- Tabla/columna/constraint:
  - `crm.verificaciones_lead.veredicto text NOT NULL` (1621): se llena con `v_resultado ->> 'estado'` (`crm.verificar_disponibilidad_lead`, `private.toma_asienta_y_devuelve`).
  - `crm.postventa_operaciones.comando text NOT NULL` (162): llega tal cual como `p_comando` en `private.postventa_recibo`.
  - `crm.conversion_acreditaciones.origen text NOT NULL` (306): es una copia de `leads.origen`, que sí tiene CHECK.
  - `crm.lead_asignaciones.origen text NOT NULL` y `categoria_interes text` (5142): copias de `leads`. `trg_lead_asignaciones_inmutables` las congela, pero no las valida al insertar.
  - `crm.inversionista_identificadores.fuente text` (760): los valores que se ven en el código son `'correccion'`, `'fusion'` y `coalesce(p_fuente,'resolver')`.
- Evidencia: barrido de columnas `text` cuyo nombre es estado/tipo/origen/motivo/… y que ningún CHECK de su tabla menciona.
- Por qué importa: en las copias, el valor puede divergir del original sin que nadie se entere (por ejemplo, un origen que `leads` rechazaría). En `veredicto` y `comando`, el informe agrupa por un texto libre.
- Qué haría falta: un CHECK con el mismo dominio que la columna origen (`leads_origen_check` y `leads_categoria_interes_check`) o con la lista de valores que emite el código.
- SQL de comprobación: `select 'verificaciones_lead.veredicto' as columna, veredicto as valor, count(*) from crm.verificaciones_lead group by 2 union all select 'postventa_operaciones.comando', comando, count(*) from crm.postventa_operaciones group by 2 union all select 'conversion_acreditaciones.origen', origen, count(*) from crm.conversion_acreditaciones group by 2 union all select 'lead_asignaciones.origen', origen, count(*) from crm.lead_asignaciones group by 2 union all select 'inversionista_identificadores.fuente', coalesce(fuente,'(null)'), count(*) from crm.inversionista_identificadores group by 2 order by 1, 3 desc;`

### [P2] B-6 · `crm.leads.telefono` (la clave anti-duplicado) sin CHECK de formato: la base solo lo valida en UPDATE
- Tabla/columna/constraint: `telefono text NOT NULL` no tiene CHECK. `telefono_alternativo` sí lo tiene (`leads_telefono_alternativo_formato`).
- Evidencia: `private.trg_leads_disponibilidad_atomica` valida `new.telefono !~ '^\+519[0-9]{8}$' → 'Telefono invalido'`, pero solo dentro de `if tg_op = 'UPDATE'`. Al insertar solo corre `trg_leads_normalizar_tel` → `private.normalizar_telefono`, que no rechaza nada: devuelve `''` tal cual y antepone `+` a cualquier secuencia de dígitos. El candado `uq_leads_telefono_vivo` compara el texto exacto.
- Por qué importa: un alta que entre por una puerta que no valide (n8n, importación) puede guardar un teléfono que la regla de disponibilidad no reconoce. Una vez guardado, editarlo obliga a pasar el formato estricto. **Hipótesis**: no sé si hoy hay filas fuera de formato. Si la consulta devuelve más de 0, sube a P1.
- Qué haría falta: un CHECK de formato (E.164, o el móvil peruano si el negocio lo exige), con el mismo criterio en INSERT y en UPDATE.
- SQL de comprobación: `select count(*) filter (where telefono !~ '^\+519[0-9]{8}$') as fuera_movil_pe, count(*) filter (where telefono !~ '^\+[1-9][0-9]{7,14}$') as fuera_e164, count(*) filter (where activo and etapa not in ('convertido','descartado') and telefono !~ '^\+519[0-9]{8}$') as vivos_fuera_formato from crm.leads;`

### [P2] B-7 · «Una sola primera conversión vigente por persona» solo existe en el código
- Tabla/columna/constraint: `crm.inversiones.es_primera_conversion boolean`. No hay índice único parcial sobre `(inversionista_id) where es_primera_conversion and estado='vigente'`.
- Evidencia: el código la trata como única. Las puertas preguntan `exists(select 1 from crm.inversiones where inversionista_id=v_persona and es_primera_conversion)` (dos sitios) y `private.conversion_lead_con_inversion` exige una inversión inicial vigente. La marca se pone por UPDATE en `confirmar_inversion_revisada_fn` y en el reemplazo de inversión (`update … set es_primera_conversion = true where contrato_id = v_nuevo`). En cambio, `inversiones_contrato_uidx`, `inversiones_cierre_uidx` e `inversion_titulares_principal_uidx` sí están en la base.
- Por qué importa: dos «primeras conversiones» vigentes para la misma persona contarían la venta dos veces. **Hipótesis** (por diseño parece única, pero no hay candado).
- Qué haría falta: `create unique index … on crm.inversiones (inversionista_id) where es_primera_conversion and estado = 'vigente'`, después de comprobar que hoy no hay duplicados.
- SQL de comprobación: `select count(*) as personas_con_2_primeras from (select inversionista_id from crm.inversiones where es_primera_conversion and estado = 'vigente' group by 1 having count(*) > 1) x;`

### [P2] B-8 · Vigencias sin coherencia de fechas ni de estado
- Tabla/columna/constraint:
  - `crm.inversionista_identificadores` (760): ningún CHECK liga `estado='historico'` con `vigente_hasta is not null`, ni exige `vigente_hasta >= vigente_desde`. Una persona puede tener dos documentos vigentes del mismo tipo, porque la unicidad es por documento y no por (persona, tipo).
  - `crm.inversionista_leads` (339): falta `hasta >= desde` y no hay coherencia entre `rol` y `hasta`.
  - `crm.inversionista_responsables` (789): tiene `inv_responsables_rango` y un solo tramo abierto, pero no un EXCLUDE que impida tramos cerrados solapados. `lead_asignaciones` y `celulares_asignaciones` sí lo tienen.
  - `crm.conversion_reservas`: falta `expira_en > reservado_en` y `vence_absoluto_en >= expira_en` (0 filas, tabla cerrada a nuevas reservas).
- Por qué importa: «quién era responsable en tal fecha» y «qué documento valía» se responden con estos rangos. Si se solapan o se invierten, la respuesta deja de ser única.
- Qué haría falta: CHECK de rango y de coherencia estado↔fin, y `exclude using gist (inversionista_id with =, tstzrange(desde, coalesce(hasta,'infinity')) with &&)` en responsables.
- SQL de comprobación: `select (select count(*) from crm.inversionista_identificadores where (estado = 'vigente') <> (vigente_hasta is null) or vigente_hasta < vigente_desde) as identif_incoherentes, (select count(*) from (select inversionista_id, tipo_documento from crm.inversionista_identificadores where estado = 'vigente' group by 1, 2 having count(*) > 1) x) as personas_2_docs_vigentes, (select count(*) from crm.inversionista_leads where hasta < desde) as puente_rango_invertido, (select count(*) from crm.inversionista_responsables a join crm.inversionista_responsables b on a.inversionista_id = b.inversionista_id and a.id < b.id and tstzrange(a.desde, coalesce(a.hasta, 'infinity')) && tstzrange(b.desde, coalesce(b.hasta, 'infinity'))) as tramos_solapados;`

### [P3] B-9 · Dinero y tasas en `numeric` sin precisión ni escala
- Tabla/columna/constraint: dinero en `crm.operaciones_cartera.capital_renovado` y `capital_adicional` (27 filas, el «ledger que congela el desglose económico»), `crm.solicitudes_tasa.capital`, `crm.cierre_mes_vendedor.ajuste_pen` y `ajuste_usd`, y `crm.ajustes_mes_cerrado.capital_*` y `pendiente_*` (0 filas). Tasas en `crm.ledger_rentabilidad.tasa_base`, `tasa_final` y `tasa_recibida`, `crm.solicitudes_tasa.tasa_base` y `crm.politica_rentabilidad.tasa_base_nueva` y `tope_tecnico`. Todas son `numeric` a secas. `leads.monto_estimado` y `cierres_externos.tasa_anual` lo compensan con un CHECK `= trunc(x,2)`, y `solicitudes_tasa.tasa_solicitada` con `scale(...) <= 2`.
- Aclaración: el «monto sin moneda» de `ajustes_mes_cerrado` que marcan los hechos es un **falso positivo**. La tabla separa la moneda por columna (`capital_pen`/`capital_usd`), igual que `cierre_mes_vendedor.ajuste_pen`/`ajuste_usd`, así que PEN y USD nunca se suman. Las precisiones varían (12, 14, 20 o 24) pero la escala es siempre 2, así que eso está bien.
- Por qué importa: con valores de más de 2 decimales, los totales y comparaciones (por ejemplo, la huella de `solicitudes_tasa` frente al contrato) pueden desviarse por un céntimo.
- Qué haría falta: `numeric(14,2)` para dinero (o un CHECK `= round(x,2)`) y una escala fija para las tasas.
- SQL de comprobación: `select (select count(*) from crm.operaciones_cartera where capital_renovado <> round(capital_renovado, 2) or capital_adicional <> round(capital_adicional, 2)) as op_cartera, (select count(*) from crm.solicitudes_tasa where capital <> round(capital, 2)) as sol_tasa, (select count(*) from crm.cierre_mes_vendedor where ajuste_pen <> round(ajuste_pen, 2) or ajuste_usd <> round(ajuste_usd, 2)) as cierre_mes, (select count(*) from crm.ledger_rentabilidad where tasa_final <> round(tasa_final, 2) or tasa_base <> round(tasa_base, 2)) as ledger_tasas;`

### [P3] B-10 · `actualizado_en` mantenido a mano: sin trigger en 10 tablas mutables y una escrita directo desde pantalla
- Tabla/columna/constraint: estas tablas tienen `actualizado_en` pero no un trigger touch (`set_actualizado_en_crm`): `cambio_cuenta_avisos`, `configuracion_reparto`, `conversion_acreditaciones`, `dispositivos_push_tasa`, `enfriamiento_politica`, `inversion_solicitudes`, `inversionista_datos_contacto`, `postventa_retiros`, `recorrido_control` y `private.agenda_reparto_diaria`.
- Evidencia: hoy casi todas las funciones lo ponen a mano, por ejemplo `conversion_acreditaciones` en 7 de 7 updates y `agenda_reparto_diaria` en su upsert. Las excepciones: `crm.bienvenida_inversion_entrega_fn` tiene 3 updates de `inversion_solicitudes.bienvenida` que no lo tocan, y `crm.confirmar_inversion_revisada_fn` 1. `crm.enfriamiento_politica` tiene `GRANT SELECT,INSERT,UPDATE TO authenticated` y una policy `enfriamiento_update` para gerencia, sin trigger, así que `actualizado_en` y `actualizado_por` los pone el cliente. Bien resuelto, para comparar: `solicitudes_tasa` (`trg_solicitudes_tasa_solo_por_puerta` hace `new.actualizado_en := statement_timestamp()`), `politica_abandono` (`politica_abandono_sellar_autoria`) y las tablas `llamadas_celular_*` (sus candados).
- Por qué importa: «cuándo cambió por última vez» deja de ser fiable en cuanto una función nueva olvida la columna. En `enfriamiento_politica`, que fija cuántos días vuelve un lead descartado, el autor visible lo declara el navegador (el audit_log sí guarda el actor real).
- Qué haría falta: el trigger touch estándar en esas tablas y, en `enfriamiento_politica`, sellar el autor en un BEFORE UPDATE igual que `politica_abandono`.
- SQL de comprobación: `select motivo, dias, actualizado_en, (actualizado_por is not null) as con_autor from crm.enfriamiento_politica order by actualizado_en desc;`

### [P3] B-11 · NOT NULL que el negocio implica pero la base no exige
- Tabla/columna/constraint:
  - `crm.inversiones.fecha_comercial date` admite NULL (388 filas). Su COMMENT dice «Fecha comercial propia de la inversion (decision 9)… Validacion… en la puerta», y el capital mensual se imputa por esa fecha.
  - `crm.conversion_acreditaciones.analista_id` admite NULL, aunque siempre sale de `lead_asignaciones.analista_id`, que es NOT NULL.
  - `crm.inversion_eventos.motivo` admite NULL incluso con `tipo in ('correccion','anulacion')` (355 filas).
  - Ledgers cuyo actor admite NULL: `inversionista_fusiones.por`, `inversionista_operaciones.por`, `inversion_eventos.creado_por` e `inversionista_gestiones.creado_por`.
- Por qué importa: una inversión sin fecha comercial no cae en ningún mes, y una corrección o anulación sin motivo ni actor rompe la trazabilidad.
- Qué haría falta: NOT NULL donde los datos lo permitan, o CHECK condicionales (`tipo='registro' or motivo is not null`).
- SQL de comprobación: `select (select count(*) from crm.inversiones where fecha_comercial is null and estado = 'vigente') as inv_vigentes_sin_fecha, (select count(*) from crm.conversion_acreditaciones where analista_id is null) as acred_sin_analista, (select count(*) from crm.inversion_eventos where tipo in ('correccion', 'anulacion') and motivo is null) as eventos_sin_motivo, (select count(*) from crm.inversion_eventos where creado_por is null) as eventos_sin_actor;`

### [P3] B-12 · Formatos sueltos en datos de contacto
- Tabla/columna/constraint: `crm.leads.nombre_completo text NOT NULL` admite `''`, porque no tiene CHECK `btrim <> ''`. Casi todas las demás tablas sí lo tienen (`cierres_externos_nombre_completo_check`, `inversionista_datos_contacto_nombre_completo_check`). `crm.leads.correo` y `crm.correcciones_correo_acceso.correo_anterior` y `correo_nuevo` no tienen CHECK de formato. `crm.inversionista_datos_contacto.telefono` solo valida la longitud (6–32).
- Por qué importa: un lead sin nombre o con un correo mal formado llega a listas, al alta del portal y a los avisos.
- Qué haría falta: CHECK de no vacío y un formato mínimo de correo.
- SQL de comprobación: `select count(*) filter (where btrim(nombre_completo) = '') as nombre_vacio, count(*) filter (where correo is not null and correo !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$') as correo_mal_formado from crm.leads;`

### [P3] B-13 · Al hard-delete solo lo frenan los grants y las FK, no un trigger
- Tabla/columna/constraint: `crm.inversiones` no tiene `BEFORE DELETE`. Su hermana `crm.cierres_externos` sí exige la copia auditada (`private.inversion_eliminacion_autoriza('cierre', …)` en `trg_cierres_externos_inmutables`). Tampoco tienen guarda de DELETE `crm.leads`, `crm.inversionistas`, `crm.tareas` ni `crm.cuentas_bancarias`; esta última se borra en cascada desde `public.perfiles`.
- Evidencia: hoy solo borran rutas auditadas (`contrato_eliminar_auditado`, `eliminar_inversion_cooperativa`, `registrar_inversion_reemplazada_cooperativa`, `eliminar_lead_error_carga`). Lo que protege a `inversiones` es indirecto: la FK desde `inversion_eventos`, que es inmutable. Pero hay 388 inversiones y 355 eventos, así que **hipótesis**: unas 33 inversiones sin evento quedarían sin esa defensa.
- Por qué importa: la regla «soft-delete, nunca hard-delete» depende de que ninguna ruta DEFINER nueva ni ningún SQL manual haga `delete`.
- Qué haría falta: un `BEFORE DELETE` en `inversiones` con la misma llave `inversion_eliminacion_autoriza('inversion', …)`.
- SQL de comprobación: `select count(*) as inversiones_sin_evento from crm.inversiones i where not exists (select 1 from crm.inversion_eventos e where e.inversion_id = i.id);`

### [P3] B-14 · Respaldos de cierre sin PK, sin NOT NULL y sin candado
- Tabla/columna/constraint: `private.respaldo_cierre_septiembre_2026` (169 filas) y `private.respaldo_cierre_agosto_2026` (0, y además sin RLS) tienen `tabla text`, `fila jsonb` y `guardado_en timestamptz`, todas nullable, sin PK ni triggers. El COMMENT de septiembre dice «Se restaura con scripts/reexpresion-septiembre-2026/03-restaurar.sql». Septiembre se sella el 22/10.
- Por qué importa: es la fuente para restaurar un mes que se paga. Si se altera, la restauración devolvería otra cosa. Mitigación: no tienen grants y `crm.reaperturas_mes.respaldo` (append-only) guarda otra copia, si la reapertura pasó por esa tabla.
- Qué haría falta: trigger de solo lectura (o moverlas a `reaperturas_mes` y archivarlas), NOT NULL y RLS en la de agosto.
- SQL de comprobación: `select tabla, count(*) as filas, count(*) filter (where fila is null or guardado_en is null) as incompletas from private.respaldo_cierre_septiembre_2026 group by 1 order by 1;`

### [P3] B-15 · Códigos `text` sin CHECK en el esquema `private`
- Tabla/columna/constraint: `private.vigia_alertas.fase` y `motivo` (24 filas), `private.usuarios_retirados.rol_portal` y `rol_crm`, `private.membresias_purgadas.rol_crm`, y `private.pares_autoridad.rol_portal` y `rol_crm`. Además, `pares_autoridad` no tiene PK (solo `UNIQUE NULLS NOT DISTINCT`).
- Por qué importa: son tablas de control interno. `trg_equipo_par_autoridad` decide con `private.par_autoridad_valido` contra `pares_autoridad`, así que un rol mal escrito ahí puede bloquear un par legítimo o declarar uno que no existe.
- Qué haría falta: CHECK con el dominio de `crm.equipo.rol_crm` (`equipo_rol_crm_check`) y el de roles del portal.
- SQL de comprobación: `select 'pares_autoridad' as t, rol_portal, coalesce(rol_crm, '(null)') as rol_crm, count(*) from private.pares_autoridad group by 2, 3 union all select 'usuarios_retirados', rol_portal, coalesce(rol_crm, '(null)'), count(*) from private.usuarios_retirados group by 2, 3 order by 1, 2;`

## CUBIERTO (claves naturales y ledgers que SÍ están protegidos)

| Regla del negocio | Dónde vive en la base |
|---|---|
| Un cierre por mes | `periodos_cerrados` PK(periodo) + CHECK de primer día + `trg_cierre_mes_append_only` |
| Un cierre por vendedor y mes | `cierre_mes_vendedor` PK(periodo, vendedor_id), FK al mes, append-only |
| Metas por mes, vendedor y dimensión | `meta_periodos` UNIQUE(periodo, revision); `metas_vendedor` UNIQUE(meta_periodo_id, vendedor_id); `metas_vendedor_detalle` UNIQUE(meta_vendedor_id, categoria, moneda); las tres con `trg_config_versionada_inmutable` |
| Tipo de cambio por día | `tipo_cambio_diario` PK(fecha_corte, politica) + `capital_tc_inmutable` |
| Plazo de carga por mes | varias decisiones por mes **por diseño** («vale la última»), con desempate determinista `order by decidido_en desc, id desc` (`private.conversion_plazo_hasta`); UNIQUE(reapertura_id); append-only |
| Documento vigente único | `inversionista_identificadores_vigente_uidx` (tipo, documento) WHERE vigente |
| Un responsable vigente por persona | `inv_responsables_abierto_uidx` WHERE hasta IS NULL + CHECK de rango |
| Una cuenta de pago por contrato | `contrato_cuentas_pago` UNIQUE(contrato_id); el cambio solo con historial (`trg_contrato_cuenta_pago_inmutable`) |
| Una acreditación por lead, episodio y fuente | `conversion_acreditaciones` UNIQUE(lead_id), UNIQUE(episodio_id), UNIQUE(fuente_tipo, fuente_id) |
| Un episodio abierto por lead, sin solapes | `lead_asignaciones` UNIQUE parcial + `EXCLUDE … tstzrange &&` + una conversión por lead |
| Una política vigente | singletons con CHECK + PK (`capital_valoracion_politica`, `conversion_politica`, `politica_abandono`, `llamadas_celular_politica`, `configuracion_reparto`, `recorrido_control`, `sla_operacion_control`); `sla_politicas` y `politica_rentabilidad` UNIQUE(version) y UNIQUE(vigente_desde) |
| Cuenta bancaria única | `cuentas_bancarias_cci_activa_uidx` (cliente_id, moneda, cci) WHERE activa (el CCI contiene banco y número) |
| Una inversión por fuente | `inversiones_contrato_uidx`, `inversiones_cierre_uidx` (parciales), CHECK de exactamente una fuente |
| Idempotencia y dispositivos | `multiempresa_idempotencia` PK(clave); `dispositivos_push_tasa` UNIQUE(endpoint); `agenda_ics` UNIQUE(token) |
| No cobrar dos veces un depósito | `cierres_externos` UNIQUE(upper(btrim(numero_transaccion))) + `depositos_reclamados` UNIQUE(numero_norm), append-only |
| Lead vivo único | `uq_leads_telefono_vivo`, `uq_leads_dni_vivo` (hueco del alternativo ya conocido, no se repite) |
| Ledgers con trigger que rechaza UPDATE/DELETE | `alertas_reconocimientos`, `base_carga_operaciones`, `busquedas_cliente_existente`, `capital_cortes_valorados`, `capital_mes_sellos`, `capital_valoraciones`, `cierre_mes_vendedor`, `cierres_avance_anulados`, `cierres_externos`, `contrato_cuenta_pago_asignaciones`, `contrato_cuenta_pago_cambios`, `contratos_eliminados_auditoria`, `control_citas_*`, `conversion_ventas_recuperadas`, `correcciones_categoria_contrato`, `cuentas_bancarias_retiros`, `depositos_reclamados`, `gestion_diaria_*`, `inversion_ajustes_mes_cerrado`, `inversion_backfill_lotes`, `inversion_cotitular_origenes`, `inversion_eventos`, `inversion_solicitud_correcciones`, `inversion_solicitud_revisiones`, `inversiones_eliminadas`, `inversionista_fusiones`, `inversionista_operaciones`, `lead_asignacion_sla_hitos`, `lead_asignaciones`, `lead_potencial_eventos`, `lead_sla_ciclos`, `lead_sla_etapas`, `lead_sla_etapa_ajustes`, `leads_eliminados`, `ledger_rentabilidad`, `llamadas_celular_*`, `operaciones_cartera`, `periodos_cerrados`, `plazos_carga_mes`, `reaperturas_mes`, `reasignaciones_analista`, `sla_operacion_recibos`, `tarea_sla_contexto`, `actividad_ciclo_contexto`, `tipo_cambio_diario`, `ajustes_mes_cerrado` (solo saldar, y lo pendiente solo baja), `private.usuarios_retirados`, `private.contrato_pdfs`, `private.contrato_pdf_anexo_emisiones` |
| Periodos | todas las columnas `periodo*` son `date`, con CHECK de primer día de mes o FK a `periodos_cerrados` |
| Tipos | sin `float`, `money` ni `timestamp` sin zona; dinero con moneda `CHECK in ('PEN','USD')` en todas las tablas con monto, salvo las que separan la moneda por columna (`*_pen`/`*_usd`) |

Falsos positivos de `hechos-produccion.md`, revisados:
- «Mutables sin `actualizado_en»: `metas_vendedor*`, `meta_periodos`, `sla_politicas`, `politica_rentabilidad` y `tipo_cambio_diario` son inmutables por trigger. `depositos_reclamados` es append-only. `cuentas_bancarias` solo admite la desactivación, sellada con `desactivada_en`. El cambio de `contrato_cuentas_pago` se fecha en `contrato_cuenta_pago_cambios.cambiado_en`.
- «61 tablas sin `creado_en`»: casi todas usan otro sello de alta (`cerrado_en`, `decidido_en`, `reasignado_en`, `anulado_en`, `publicada_en`, `registrado_en`…). Sin ningún sello propio quedan solo `cierre_mes_vendedor` (lo hereda de `periodos_cerrados.cerrado_en`), los hijos de `sla_politicas`, los singletons de configuración, `postventa_escrituras` y los catálogos `private.ayuda_*` y `private.pares_autoridad`. Ninguno es un hallazgo.
- «Booleanos sin default»: los 7 son NOT NULL con valor explícito, o tri-estado a propósito (`incluida_en_sello` lleva un CHECK que lo liga a `sellado_en`).

## CONFIDENCE: media-alta
Alta en todo lo estructural: constraints, índices, triggers y grants salen del volcado de producción del 22/10, y los cuerpos de los triggers de inmutabilidad y de `cerrar_periodo`, `trg_leads_disponibilidad_atomica` y `normalizar_telefono` los leí directamente en ese volcado. Media en el impacto, porque no ejecuté nada contra producción: los conteos de filas son `n_live_tup`, que es estimado (`conversion_pesos` aparece con 0 y tiene filas). B-6, B-7, B-8, B-11 y B-13 son hipótesis sobre los datos hasta que se corra su SQL. Las funciones que escriben cada tabla salen de buscar con expresiones regulares `update/insert/delete` en los cuerpos, así que podría faltar algún SQL dinámico (`execute format(...)`).

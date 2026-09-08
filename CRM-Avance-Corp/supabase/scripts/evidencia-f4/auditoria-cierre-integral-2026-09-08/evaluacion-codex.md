# Evaluación del PRIMARY — revisión integral F4

Codex implementa y decide; Claude solo revisó evidencia saneada, sin herramientas
ni escritura. Esta fue la segunda y última consulta de esta tarea de cierre.
El dictamen exacto fue **CHANGES_REQUESTED**, no PASS. El prompt exacto está en
`entrada-exacta.json`, la respuesta en `review-claude.txt`. La candidata posterior
agrega la guarda de inventario; no cambia los 48 cuerpos SQL revisados. Los
ajustes posteriores de transporte, diagnóstico y compatibilidad frontend fueron
verificados por Codex y no se atribuyen a una aprobación posterior de Claude.

## Decisiones respaldadas por evidencia

| Observación | Evaluación y acción |
|---|---|
| P1: inventario incompleto | **Aceptada como refuerzo de instalación.** Ya existía `inventariar-consumidores.mjs`: clasifica mecánicamente 26 consumidores directos, 18 escritores y 97 transitivos en 546 funciones; falla ante nombres desconocidos. Se añadió `base-inventario-consumidores.json` con los 20 matches del catálogo previo, incluidos comentarios; la migración compara conjunto completo y huellas antes del DDL y rechaza vistas/políticas nuevas. Dos mutantes reales —función y vista— rechazados sin dejar tablas F4; corpus original ahora 12 grupos PASS. |
| Ocho/nueve símbolos supuestamente omitidos | **Hipótesis de duplicación refutada para los símbolos indicados.** Fuente completa en `../revision-integral-catalogo-2026-09-08.json`: `conversion_episodios` toma cierres de `lead_asignaciones` y operaciones elegibles, no de un join 1:N con cierres. `conversion_mensual_por_vendedor` consume ese núcleo. `leads_de_identidades`/`leads_de_personas` son uniones de IDs; `cartera_pagina_fn` lee leads y actividades. Acreditación y contratos afectados usan las fuentes Avance; `registrar_ajuste_si_mes_cerrado` usa el episodio y deja capital cero según ATR-4. Finanzas prueba adicional, anulación inicial y numerador sin duplicación. No se adapta una función solo por aparecer en un comentario o ser wrapper. |
| P1: fecha comercial antigua sin sello | **No se introduce un plazo comercial nuevo.** La regla documentada desde el 07/09 es imputar al mes comercial abierto; si está sellado, imputar al vivo y registrar ajuste. Limitar a N días o exigir Gerencia sería un cambio de negocio sin requisito. Nuevo caso 2001-01 abierto confirma fecha declarada, stock 777, sin nuevos ajustes ficticios ni cambios en sellos junio/julio o el resultado de `cumplimiento_metas_fn` de junio. Finanzas: 13 grupos PASS. La prueba de una comisión pagada fuera del sellado sigue pendiente: no se confunde la decisión temporal con evidencia de pago. |
| P2: triggers de identidad alcanzan otros escritores | **Se conserva el cierre de puertas.** F4 exige identidad canónica antes de crear una fuente; eximir service_role/importadores permitiría una puerta paralela, contraria a F3/F4. Los antecedentes inválidos se tratan por censo/lote con F4 apagada. Demos no eximen validación documental ni autorizan una persona inventada. Altas reales por puerta compartida, corpus F2 conflictivo, multirrol y puertas privadas ensayados. |
| P2: eliminar contratos demo y mensaje opaco | **Mensaje corregido; excepción de borrado rechazada.** Marcar una inversión demo no autoriza borrar su procedencia, especialmente si luego puede volver a real. Se mantiene el rechazo antes de reservar rutas o borrar Storage, incluso para demo. El handler ahora transmite el diagnóstico público de conservación. Nuevo test comprueba HTTP 409, texto correcto y cero llamadas a Storage. |
| P2: teléfono sin responsable | **Fallback rechazado por autorización.** La tenencia histórica de un lead convertido no otorga acceso vivo a la persona. Recuperar teléfono por esa vía reabriría el defecto reproducido tras reasignación. Nuevo caso explícito: responsable NULL oculta teléfono al vendedor anterior; Gerencia mantiene lectura. Permisos: 19 grupos PASS. |
| P2: titulares contractuales inmutables | **Se conserva procedencia documental.** F4 vincula la cotitularidad del snapshot contractual; cambiar/eliminar su fuente histórica no es corregir una solicitud preparada. La corrección versionada de solicitud ocurre antes de crear el contrato/snapshot. `actualizar_contrato` y `_sync` no reciben una excepción para reescribir procedencias congeladas. Los 16 grupos comprueban inmutabilidad con válvula documental, F3 corrige/fusiona identidad sin rehacer la fuente ni PDF. Una rectificación del documento emitido necesitaría un flujo documental distinto, fuera de F4. |
| P2: lectura toma bloqueos de escritura | **Se conserva serialización por persona en F4.** Ambos lectores toman el mismo orden bandera/identidad/persona que los escritores para resolver canónica y permiso vigente consistentemente frente a fusión/reasignación. Cambiar a un chequeo sin candado no es una optimización mecánica. No se afirma capacidad/carga F5; observar latencia real antes de diseñar una variante de lectura. Las carreras actuales terminan y preservan permisos. |
| P2: CORS y mensajes internos Portal | **Corregido.** Se reutiliza la lista de cuatro orígenes productivos del PDF y `Vary: Origin`. Solo diagnósticos SQLSTATE contractuales deliberados (`P0409`, `P0429`, `22023`, `P0002`, `42501`) se muestran; errores Auth/SQL internos reciben texto genérico conservando solicitud/token de recuperación. Ocho tests del handler, preflight y regresiones Portal/Auth/veto/entrypoint Deno reales PASS. CORS complementa, no sustituye, JWT/RPC. |
| P2: saga bloqueada por CHECK perfil | **El ejemplo concreto no existe en este esquema.** Catálogo adjunto: no hay CHECK de teléfono; domicilio usa exactamente `normalizar_domicilio_legal` y sus límites 5..240/sin controles, antes del claim. Esa función es IMMUTABLE. No se añadió compensación destructiva ni cancelación que pueda borrar un Auth cuya respuesta se perdió. Los claims reservados conservan datos y se recuperan desde la misma solicitud; correo ajeno requiere conciliación sin adopción. `cancelada` es un estado reservado, no una RPC prometida. Nuevas restricciones futuras requieren ampliar prevalidación y revisión; no se afirma recuperación automática de una corrupción administrativa arbitraria. |
| P2: bloqueo de Storage y FK | **Riesgo operativo documentado.** No hay aplicación productiva. Instalar en ventana sin escrituras, con copia pareada y timeout corto; si el lock falla, la transacción revierte y se reintenta íntegra tras recapturar. Se conserva FK y políticas para proteger evidencia; no se sustituyen por ETag, que no demuestra igualdad de bytes. |
| P2: cotitular concede acceso | **Hipótesis refutada.** Catálogo adjunto: políticas de inversiones/titulares solo Gerencia y ACL sin SELECT API. Nuevo caso asigna el cotitular al equipo ajeno: SELECT directo denegado 42501, contrato no visible y RPC cotitular denegada. La membresía neutral registra procedencia, no consentimiento ni acceso compartido. No se otorgan permisos por documento. |
| P2: falta DOWN | **No se incorpora un DOWN destructivo.** Reversa operativa: escritor OFF, historia completa retenida. Restauración: 133 tablas + 27 archivos a DB/volumen NUEVOS, datos/ACL/RLS/cuerpos/bytes iguales (6 grupos PASS). F2 global se retira al instalar, incluso con F4 OFF. Tras fuentes 1:N, borrar F4 o recrear UNIQUE(lead_id) perdería operaciones; una restauración histórica exige reconciliar posteriores. El ensayo no se presenta como tercera instalación HTTP ni restauración cron/replicación. |
| Regresión frontend lead_id nullable | **Confirmada y corregida.** `CierresExternosSchema` rechazaba el payload entero cuando una inversión adicional tenía `lead_id:null`: test rojo antes del cambio. Ahora acepta UUID o NULL explícito, sigue rechazando ausencia/UUID inválido; conserva fechas F4 y compatibilidad anterior. Mini-ficha/revisión muestran fecha comercial con fallback histórico. Se retiró el texto falso sobre ausencia de Portal/aporte automático de conversión. Tests de parser y componente PASS; suite completa y build en el manifiesto. |

## Observaciones P3

- **Estado anulado vs Capital:** contrato deliberado ATR-4. `inversiones.estado`
  describe la situación comercial de esa fuente; `capital_episodios` es la
  autoridad del stock. Una anulación comercial no retira dinero ni debe sumarse
  Capital desde `inversiones`. Queda explícito en README y matriz para F5.
- **Evento de anulación inicial:** el cierre inicial conserva su evento/auditoría
  publicados (`crm.actividades`, anulación y auditoría); el trigger adicional
  no duplica ese evento. Se comprueba estado y Capital en ambos canales.
- **Volatilidad:** `normalizar_domicilio_legal` es `IMMUTABLE` (`provolatile=i`),
  confirmado en catálogo; no procede degradar el llamador.
- **Allowlist repetida:** `preparar_inversion_fn` conserva validaciones iniciales
  de forma/identidad antes de contexto; `inversion_validar_datos` centraliza
  validación de negocio compartida con corrección. Oráculo de corrección y
  guardas de cuerpos limitan deriva; no se crea otra función constante.
- **ACL de 30 funciones:** `verificar-estructura.mjs` prueba todas las nuevas,
  roles anon/authenticated/service_role, security definer, owner y search_path;
  no únicamente el auxiliar cotitular. Un GRANT posterior exige repetir el gate.
- **Índice de evidencia:** no se certifica rendimiento a escala F5. La consulta
  actual está acotada a solicitudes del actor; medir planes/carga antes de un
  índice adicional. No se cambia el contrato de evidencia para optimizar.
- **Deadlock cotitular:** se difiere como identidad ocupada y queda conciliable;
  no se oculta éxito financiero ni se inventa titular. El ensayo de contención
  documental prueba recuperación. No se afirma análisis exhaustivo de carga.
- **Solicitud inexistente 404/403:** no concede acceso ni efectos. Se conserva
  respuesta opaca en el proceso Auth; no se equipara un ID desconocido con una
  solicitud visible del actor.
- **Reabrir período:** no se identificó una puerta de reapertura autorizada en
  el catálogo de este paquete. El contrato conserva sellos; la FK no se afloja
  para un flujo hipotético.
- **Cuerpo HTTP sin límite durante lectura:** corregido con límite de 4096 bytes
  mientras se consume el stream; probado sin Content-Length, multibyte, exceso,
  UTF-8 inválido y longitud declarada incorrecta.
- **Producción vs conversión:** contar fuentes cooperativas adicionales como
  producción es correcto; no crea otro episodio de conversión del lead.

## PDF y comisiones

La tanda anterior `cb86e1fd` quedó FAIL tras nueve grupos por WORKER_LIMIT;
se conserva ese resultado. Con la política per_worker predeterminada y leases
reales vencidos se recuperaron los dos pendientes, sin modificar cuotas CPU,
reloj, SQL ni renderer. Readback de los diez confirma job/snapshot/fuente/objeto
únicos y mismos bytes. Otra tanda completa `56c6b388` pasó 12 grupos/10 contratos.
Se inspeccionaron 14 páginas PEN/USD. El único cambio posterior del handler PDF
es el mensaje de prohibición de borrado, con test nuevo; no su generación.

La sugerencia de que metas o ajustes son un registro de comisión pagada es una
**inferencia de Claude, no un hecho del esquema**. `registrar_ajuste_si_mes_cerrado`
registra numerador pendiente y capital cero (ATR-4); no monto de comisión, pago,
fecha de liquidación, tasa de comisión ni comprobante de abono. Se trazaron las
funciones propuestas y se probó conservación de su base sellada. Sigue faltando
identificar con Miguel la fuente de comisiones/liquidaciones para contrastarla.
Por ello **G4 sigue abierto**. No hay aprobación de publicación o dinero real.

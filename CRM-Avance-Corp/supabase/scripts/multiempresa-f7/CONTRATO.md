# F7 — contrato del informe multiempresa en sombra

Estado: **candidata local construida y ensayada; no instalada ni activada en producción**.

## Alcance y acceso

Informe mensual de Gerencia, con Avance, Qorilazo y Prodelco separados y cada
moneda en su propia fila. Solo consulta: no registra inversiones, no modifica
cierres ni activa F4/F5/F6. Comisiones calculadas fuera del CRM.

La bandera nueva `metricas_multiempresa_sombra` nace apagada. Dos RPC nuevas:
`crm.metricas_multiempresa_estado_fn()` y
`crm.metricas_multiempresa_fn(p_mes date)`; Gerencia activa en CRM y Portal,
verificada contra membresía vigente en cada llamada. Directorio no recibe este
informe global de cooperativas. Auxiliares privados sin permisos Data API.

## Producción del mes

- Capital y cantidad proceden de `private.capital_episodios`, exclusivamente
  `medida = 'stock'`. Los desgloses de renovación no se vuelven a sumar.
- Empresa se obtiene de la fuente económica: contrato → Avance; cierre externo
  → su cooperativa. `crm.inversiones` aporta relación, nunca otro importe.
- Fecha de imputación publicada por el núcleo, con límites a medianoche de
  Lima. Mes corriente hasta hoy; un mes futuro es inválido.
- Fuentes sin identidad o con identidad contradictoria conservan su capital y
  se cuentan en la advertencia de cobertura. Nunca fabricar una persona.
- Anulación comercial conserva producción (ATR-4); la elegibilidad comercial
  sigue su regla propia. Se respeta la clasificación demo de los lectores
  publicados, sin deducirla de nombres, correos o teléfonos.
- Atribución por analista del episodio, incluyendo ausentes del roster y sin
  analista; el dueño actual de la relación y el digitador no la sustituyen.

## Personas e inversiones posteriores

- La unidad inversión es una fuente económica, incluso si aún no tiene fila
  relacional. La unidad persona es la identidad canónica coherente.
- «Primera registrada» / «Posterior registrada» compara las fuentes conocidas
  del titular principal en todo el grupo; orden por fecha comercial, registro,
  empresa e ID. No certifica historia desconocida ni determina conversiones.
- Los cotitulares cuentan como personas participantes, una vez por persona y
  empresa; nunca multiplican capital, operaciones o primeras inversiones.
- Distribución de personas con una/dos/tres empresas y oportunidades para una
  empresa faltante: historia conocida hasta hoy, independiente del mes de
  producción seleccionado. Se rotula expresamente como cobertura actual.
- Una oportunidad es una persona ya vinculada a otra empresa sin inversión
  conocida en la empresa destino; es señal para evaluación comercial, no una
  orden ni una oferta automática. No contactar personas con `no_contactar`.

## Conversión y meses sellados

- La conversión global consulta los aportes publicados de
  `private.conversion_episodios(v_ini,v_fin,v_mes,true,'{}',v_factor)`, con
  `v_factor=private.peso_referido_conversion(v_mes)`, igual al informe publicado.
  Se devuelve el factor utilizado. Es el peso mensual versionado disponible
  hoy; no se interpreta como el peso congelado de una foto sellada.
  No hay un divisor
  por empresa inventado: una llegada pertenece al embudo común.
- Renovaciones/upgrades elegibles conservan su aporte y el límite ya aplicado
  por el núcleo, por perfil/mes y lead. No se deduplica esa conversión por la
  nueva identidad. «Posterior registrada» es una clasificación histórica F7;
  no concede ni elimina aportes comerciales del núcleo.
- El informe es una proyección de lectura en sombra, no un nuevo cierre
  contable. No escribe `periodos_cerrados`, fotos ni ajustes, ni sustituye los
  informes sellados. Si el mes está cerrado, se identifica explícitamente que
  el desglose por empresa es una consulta actual y no la foto firmada.
- La conciliación mide por empresa/moneda/analista tanto sumas como cantidad y
  unicidad de fuentes. No presentar ausencia de evidencia como diferencia cero.
  El detalle permite comparar cada grupo; un grupo presente solo en el núcleo
  conserva su diferencia. Las inversiones repetidas se señalan expresamente.

## Vencimientos

Ventana independiente de hoy a 30 días inclusive, por empresa y moneda. Solo
fuentes operativas vigentes: Avance `activo`; cooperativa `vigente` en el núcleo.
Se excluyen
demos, fuentes vencidas antes de hoy y contratos reemplazados. Es capital
contractual próximo a vencer, sin intereses estimados ni cálculo de pago.
Una revisión administrativa de retiro F6 no retira dinero ni modifica este
stock: su finalización financiera no forma parte del contrato vigente.

## G6 y publicación

G6 sigue pendiente hasta la conciliación y firma humana correspondiente. La
aceptación técnica no autoriza el piloto económico F8 ni el encendido de F4/F5/F6.
El SQL exacto, la reversa y sus pruebas se presentan para aprobación antes de
instalar en producción mediante el ciclo de rama Supabase del repositorio.

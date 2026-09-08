# F5.1 — contrato de cartera y ficha multiempresa

Estado: diseño para implementación y aceptación sintética G5. F4 publicada en
`20260908211349_crm_f4_publicacion_compatible_rentabilidad.sql`; F4/F5 apagadas.
La autorización de desarrollo no enciende producción ni autoriza un piloto.

## Identidad y fuentes inventariadas

- Clave de navegación: `crm.inversionistas.id`, resuelta por
  `private.inversionista_canonica`. Los perfiles de identidades fusionadas se
  conservan como enlaces históricos; nunca se reemplaza el dueño contractual.
- Avance: `public.contratos`, `public.cronograma_pagos`,
  `public.contrato_titulares` y archivo PDF publicado. Un contrato cuenta una vez
  por su ID, aunque aparezca en varios enlaces. Perfil y cuenta Auth son opcionales.
- Cooperativas: `crm.cierres_externos`, depósito/referencia, fechas comercial e
  imputación, anulación comercial y comprobante de Storage. El dinero de una
  anulación comercial se conserva según ATR-4; la demo declarada conserva su
  exclusión vigente. No se deriva capital desde `crm.inversiones`.
- Contacto: perfil legítimamente enlazado, lead canónico o antecedente externo.
  Documento vigente: `crm.inversionista_identificadores`; no se deduce identidad
  comparando libremente nombres, correos o documentos durante una lectura.
- Tareas e historial: `crm.tareas`, `crm.actividades` y actividades de cliente.
  Solo hechos vinculados a las identidades/perfiles/leads autorizados, sin extender
  su ámbito por atribución histórica. F5 no crea automatismos de postventa.
- Escritura existente: `preparar_inversion_fn`, `solicitud_inversion_fn`,
  `corregir_solicitud_inversion_fn`, `revisar_solicitud_inversion_fn` y
  `confirmar_inversion_revisada_fn`; acceso Avance mediante `crm-inversion-portal`.

Comprobación productiva de solo lectura del 08/09: 440 identidades, 540 contratos,
14 enlaces de inversión, 13 contratos sin identidad por perfil, 2 cierres sin
identidad y 5 personas sin responsable. Son conteos de un instante, no fixtures.
Por ello NO se puede construir la lista solamente con `crm.inversiones`.

## Puertas y respuestas v1

Todas las RPC nuevas viven en `crm`, son POST, exigen sesión y rol efectivo,
autorizan dentro de la función y fijan `search_path=''`. Tablas y auxiliares
`private` permanecen inaccesibles a `anon`, `authenticated` y `service_role`.

1. `cartera_inversionistas_estado_fn()`: devuelve `version`, `habilitada`,
   `escritura_habilitada` y un motivo genérico. Revalida flags F3/F5 y cobertura
   de fuentes históricas. Si falta una identidad, F5 no sustituye la cartera
   publicada ni presenta totales parciales. No devuelve conteos ni IDs ajenos.
   La conciliación productiva usa los lotes acotados F4 antes del encendido.
2. `cartera_inversionistas_fn(p_pagina, p_tamano, p_texto, p_empresa,
   p_responsable, p_sin_responsable)`: páginas desde 1, tamaños 10/25/50;
   texto normalizado y acotado a 120 caracteres, empresas del catálogo inicial.
   Orden estable por nombre normalizado + identidad canónica. Devuelve
   `version`, `pagina`, `tamano`, `total`, `filas` y `totales` por empresa/moneda.
   Una fila contiene identidad, nombre, documento/contacto permitidos, estado,
   No contactar, responsable y empresas visibles. No contiene banca ni URLs.
3. `inversionista_ficha_fn(p_inversionista)`: devuelve identidad canónica,
   responsable vigente, capacidades, enlaces reales opcionales, inversiones
   agrupables por empresa/moneda y totales del servidor. Cada inversión conserva
   ID de fuente, ID relacional opcional, capital, moneda, estado, vencimiento,
   fechas comercial/imputación, origen comercial y disponibilidad documental.
   Historial y tareas acotados llevan su total para reconocer truncamiento.
4. Las lecturas de banca/documentos se solicitan por separado, después de
   confirmar la ficha, y vuelven a comprobar persona, fuente y capacidad actual.
   No se aceptan como autorización datos del cliente ni un UUID de perfil suelto.

Lista, total y agregados comparten exactamente el conjunto autorizado y filtrado.
Un resultado fuera de ámbito y uno inexistente producen el mismo estado vacío;
buscar un documento ajeno no revela que existe. Parámetros inválidos: `22023`;
sesión/rol revocado: `42501`; bandera/cobertura no lista: `P0409`. La UI distingue
un vacío confirmado de una carga/error; no convierte fallos en cero inversiones.

## Ámbito y capacidades

| Actor | Identidad y fuentes visibles | Acciones |
|---|---|---|
| Analista (`vendedor`) | Responsable actual igual a su usuario | F4 solo si cumple estado, documento y capacidad contractual |
| Supervisor | Responsable actual dentro de `vendedor_ids_visibles`; sin responsable solo con asignación explícita vigente a su supervisión | Mismas comprobaciones F4 |
| Gerencia | Ámbito comercial global, incluidas personas sin responsable | F4 cuando la persona está lista; asignación según puerta vigente |
| Directorio | Lectura Avance permitida actualmente; sin filas privadas cooperativas | Sin escritura, contacto operativo ni consultas bancarias |
| Inactivo, equipo ajeno, cliente Portal, coordinador | Ninguna puerta de cartera neutral fuera de su ámbito | Denegado |

La ficha nunca usa `ce.vendedor_id`, `contrato.analista_cierre_id` o un lead
convertido histórico para devolver contacto al antiguo responsable. La RPC
`cierres_externos_fn` conserva sus resultados/atribución; F5 no la modifica.
Directorio mantiene su límite actual: dicha RPC no entrega filas cooperativas.
F5 no amplía ese permiso bajo la etiqueta «ficha única».

El servidor entrega capacidades positivas, no inferidas por rol en React:
contactar, nueva inversión, cuentas Avance por perfil real, documentos por fuente.
No contactar, documento provisional/faltante, baja o responsable no operativo
bloquean nuevas inversiones con explicación. La corrección documental continúa
reservada a Administración. Cotitulares son información contractual; no generan
identidad comercial, leads, Auth, acceso a la ficha de otro titular ni PDF nuevo.

## Caché, auditoría y recuperación

- Claves TanStack incluyen actor, identidad y filtros. No se usa
  `keepPreviousData` para atravesar ámbitos o personas. Al abrir la ficha se exige
  respuesta posterior al montaje; refetch al recuperar foco y comprobación
  periódica mientras está abierta. Error de autorización vacía datos, cancela
  peticiones y purga la caché sensible. Una respuesta tardía del ámbito anterior
  no puede repoblarla. Cambio de actor desmonta el recorrido.
- Lecturas sensibles registradas en una tabla CRM cerrada con actor, identidad,
  categoría y fecha; su trigger usa `private.log_audit_crm`. No guardar texto de
  búsqueda, documentos, contacto, contenido bancario, URLs ni tokens en logs.
- Una solicitud conserva UUID y contenido; la revisión procede de preparar o
  consultar (empieza en 0, no en 1). Un fallo no genera otra solicitud.
  Corrección y revisión de responsable son explícitas. Confirmación usa
  `confirmar_inversion_revisada_fn`, una inversión por transacción.
- Confirmación económica, alta Auth y PDF tienen estados diferenciados.
  Recuperar Auth/PDF nunca vuelve a crear el contrato ni cambia contenido
  reservado. Avance reutiliza cálculo contractual/cuenta/PDF v8 vigente.
  Cooperativas requieren comprobante válido y depósito único antes de confirmar.

## Diseño que se conserva

Paleta publicada: navy `#111e3d`, acción `#2563eb`, lienzo `#f6f8fc`, blanco
`#ffffff`, texto secundario `#475569`, advertencia `#92400e`. IBM Plex Sans,
pesos 400/500/600/700; misma escala, espaciado y controles de la app vigente.

Mi cartera: título y explicación breve; búsqueda y filtros; resumen por
empresa/moneda; lista de personas con chips; pie Anterior/Siguiente/tamaño.
En móvil las mismas filas se apilan sin tabla horizontal. La ficha reutiliza
cabecera, secciones y Sheet publicados: identidad → próxima tarea/responsable →
inversiones por empresa/moneda → documentos → historial. Banca dentro de Avance.
Nueva inversión abre el diálogo existente con empresa, datos, revisión y resultado.
Foco de retorno, etiquetas explícitas, errores anunciados y acciones alcanzables
con teclado; textos largos parten línea. No se cambia la marca ni el PDF.

## Evidencias para G5 (pendientes hasta ejecutar)

- SQL/HTTP: identidad única, fuentes históricas sin enlace, cobertura incompleta,
  fusiones/multirrol, matriz por rol, búsquedas ajenas, bajas, reasignación viva,
  No contactar, documento faltante, ausencia de Portal y no responsable.
- Dinero: paridad por empresa/moneda, anulación comercial, depósito repetido,
  mes sellado/fechas distintas; Avance PEN/USD y las tres empresas por persona.
- F4 real: cruces entre las tres empresas y repetición en cooperativa, revisión
  obsoleta, corte de red antes/después de confirmar, Auth/PDF pendientes;
  aumento tras fusión conserva perfil/tasa/origen y rechaza otra persona.
- UI: escritorio/móvil, teclado/foco/lector de pantalla, vacío/carga/error,
  recuperación, revocación abierta sin banca/PII residual; revisión visual.
- Gates completos, tipos, revisión Claude evaluada, commits por entregable,
  manifiesto SQL/artefacto, documentación de encendido y reversa sin borrar datos.

F5.2–F5.7 permanecen pendientes. Este contrato no acredita pruebas ni publicación.

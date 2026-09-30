VERDICT: CHANGES_REQUESTED

SUMMARY: La autorización propuesta reutiliza la regla de lectura del PDF y, con la evidencia transcrita, no demuestra una fuga entre carteras ni acceso anónimo. El plan sí tiene problemas accionables en el contenido financiero, la presentación jurídica, la apertura del PDF en el navegador y el orden de publicación. Son hallazgos sobre el diseño; todavía no hay implementación que permita afirmar fallos observados.

FINDINGS:

[P1] **El anexo puede contradecir el cronograma sellado.**  
**Evidencia:** D2 fija la restitución en `fechaVencimiento` y `capital` y acepta un snapshot «sin fila `retorno`»; el borrador anterior tomaba `retorno?.fechaProgramada` y `retorno?.montoProgramado`.  
**Impacto:** El anexo podría imprimir fecha o importe distintos de la fila contractual congelada y ocultar un cronograma incompleto.  
**Recomendación:** Usar la fila `retorno` del snapshot y validar su cardinalidad y coherencia con capital y vencimiento. Si falta o discrepa, fallar con un error de integridad; admitir excepciones solo con una regla de negocio explícita. Validar también las filas `devolucion` del compuesto.

[P1] **El flujo binario no garantiza un anexo visible e imprimible.**  
**Evidencia:** D2 devuelve `application/octet-stream` con `Content-Disposition: inline`; D3 abre `URL.createObjectURL(blob)` y consulta `X-Document-Sha256`.  
**Impacto:** La URL `blob:` conserva el tipo del Blob, pero no la cabecera `Content-Disposition` de la respuesta original: el navegador puede descargar el octet-stream y perder el nombre previsto. Además, `X-Document-Sha256` no será legible desde otro origen si CORS no lo incluye en `Access-Control-Expose-Headers`; el helper CORS no está transcrito, así que esto último es una **hipótesis por verificar**. Abrir la ventana después de esperar la edge también puede activar el bloqueador de ventanas.  
**Recomendación:** Tras verificar los bytes, crear un Blob `application/pdf`, gestionar el nombre de descarga en el front y abrir una ventana durante el clic antes de iniciar la petición. Exponer expresamente la cabecera de hash y comprobar el flujo con un navegador contra la edge real.

[P1] **El aspecto de documento firmado carece de una procedencia verificable.**  
**Evidencia:** El plan reutiliza la «firma impresa de Avance Corp» y `bloqueFirmas`, cierra «en la misma fecha de celebración», y declara: «No se guarda ni se sella». El snapshot transcrito contiene `fechaInicio` y `fechaVencimiento`, pero no una fecha de celebración identificada como tal. La diferencia entre montos fijos y la cláusula 3.9 queda remitida a «abogado».  
**Impacto:** Una impresión posterior puede parecer emitida o firmada junto con el contrato, aunque no exista registro de qué versión se entregó ni respaldo para esa fecha o redacción.  
**Recomendación:** Resolver el carácter del documento antes de publicar. Si es una propuesta para firma posterior, identificarla visiblemente como tal y retirar la firma corporativa preimpresa y la afirmación temporal no sustentada. Si será un anexo contractual emitido, guardar y sellar sus bytes, hash, versión, revisión, actor y fecha. Esto añade almacenamiento, modelo de revisiones, generación idempotente, permisos, migración y pruebas; el hash de una respuesta aislada no sustituye ese registro.

[P1] **El orden de publicación contradice la regla de Main.**  
**Evidencia:** D4 coloca migración, deploy de edge y `/release-crm` en los pasos 1–3, pero «commit en `main` antes de construir, push `avancecorp main`» en el paso 5. Las instrucciones del proyecto exigen verificar que Main local y `avancecorp/main` apuntan al mismo commit y publicar un artefacto construido desde él.  
**Impacto:** Producción podría recibir SQL, edge o front procedentes de un árbol que aún no es el commit verificado.  
**Recomendación:** Integrar remoto, cerrar y verificar el commit, y después aplicar migración, desplegar edge y construir/publicar el front desde ese commit, conservando ese orden entre componentes.

[P2] **La promesa de «mismo snapshot ⇒ mismos bytes» no queda demostrada.**  
**Evidencia:** D2 fija `CreationDate/ModDate` con `generado_en` y afirma que `X-Document-Sha256` «lo acredita»; también cambia renderer, plantilla y assets mediante futuros despliegues.  
**Impacto:** Fijar dos campos de fecha no prueba que el generador sea determinista. El hash solo identifica los bytes de *esa* respuesta; una revisión del renderer o de un recurso puede producir otros bytes para el mismo snapshot conservando el mismo nombre de plantilla.  
**Recomendación:** Probar dos renders independientes, reinicios y el artefacto publicado; versionar de forma inmutable renderer y recursos, o limitar expresamente la promesa a una misma versión desplegada. Si se necesita identidad histórica del anexo, conservar los bytes sellados.

[P2] **La visibilidad del botón no coincide con la elegibilidad declarada.**  
**Evidencia:** D3 muestra el botón para «régimen nuevo o con PDF»; las decisiones limitan el anexo a contratos con snapshot congelado del régimen nuevo. La tabla se describe como «compatible con archivos v1 y jobs server-side v2», mientras la edge exige `validarSnapshotContratoV2`.  
**Impacto:** **Hipótesis:** un PDF v1 visible podría llevar al usuario a un `502 snapshot inválido`, presentado como fallo del servidor en vez de incompatibilidad documental.  
**Recomendación:** Comprobar qué snapshots tienen los PDF v1. Hacer que la RPC distinga explícitamente «sin snapshot v2 apto» y ajustar visibilidad y mensaje a ese resultado.

TEST GAPS:

- **NOT RUN — revisión de plan sin shell.** Probar acceso directo a la RPC como `anon` y `authenticated`, y acceso vía edge con usuarios de otra cartera, lector global, cadena D2, cliente inactivo y contrato en eliminación. La regla propuesta alcanza a quienes ya pueden leer el PDF; si el botón debe ser exclusivo de analistas, hace falta una regla distinta.
- Probar última revisión sellada frente a revisiones anteriores, ausencia de PDF y cronogramas con `retorno` ausente, duplicado o discrepante.
- Probar en navegador real CORS, tipo PDF, nombre de descarga, bloqueador de ventanas, hash y tamaño con 60 cuotas. El e2e con edge simulada no demuestra las cabeceras CORS de producción.
- Conservar los goldens de bytes v9 y ejecutar regresiones de `ensure/status/delete`, además de las pruebas nuevas del anexo.

REGRESSION RISKS:

- La reversión del borrador en `template-v2.ts` y `renderer.ts` debe contrastarse con hashes v9 antes de desplegar; exportar helpers, por sí solo, no demuestra identidad del PDF completo.
- El nombre interpolado en `Content-Disposition` usa número y nombre procedentes del snapshot. El plan no especifica saneamiento de comillas, controles ni caracteres no ASCII; verificarlo antes de construir la cabecera.

RECOMMENDED NEXT ACTIONS:

1. Cerrar la regla financiera del anexo contra las filas selladas y decidir si será propuesta sin firma o documento emitido y sellado.
2. Corregir el flujo Blob/CORS y la elegibilidad de snapshots; añadir las pruebas de autorización y navegador indicadas.
3. Reordenar D4 para publicar exclusivamente desde el commit Main verificado.

CONFIDENCE: HIGH para las contradicciones del plan y del flujo Blob; MEDIUM para CORS y compatibilidad v1, cuyos cuerpos vivos no están completos en la evidencia.

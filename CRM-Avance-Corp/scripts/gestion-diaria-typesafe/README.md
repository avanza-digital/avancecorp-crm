# Arranque de TypeSafe para Gestión Diaria

Ensayo técnico **solo con 20 notas sintéticas**. No es la integración productiva,
no extrae actividades del CRM y no habilita sugerencias a supervisores.

Desde `CRM-Avance-Corp`:

```sh
node --test scripts/gestion-diaria-typesafe/juicio.test.mjs
node scripts/gestion-diaria-typesafe/piloto.mjs
node scripts/gestion-diaria-typesafe/piloto.mjs --vivo
```

## Banco local para ambos supervisores

`npm run gestion-diaria:banco` abre un servidor solo en `127.0.0.1:5274`.
Entrar en `http://127.0.0.1:5274/` y elegir Equipo A o B. Cada supervisor revisa
los mismos veinte ejemplos ficticios, uno a uno y sin soluciones/modelo visibles.
No hay login: A/B separa archivos del ejercicio, **no implementa permisos del CRM**.
No acepta corpus de notas reales, no lee claves ni llama a TypeSafe.

Descargar respuestas antes de cerrar; pueden retomarse desde el JSON del mismo
espacio/versión. Nada se guarda en el servidor ni en almacenamiento persistente
del navegador. La exportación solo lleva IDs, categorías y metadatos del ejercicio.
Una duda sobre la guía se registra aparte de «información insuficiente».

Comparar los dos archivos: `npm run gestion-diaria:comparar -- /ruta/a.json /ruta/b.json`.
La salida mide acuerdo, no precisión del modelo. Siempre mantiene deshabilitada
la muestra real y la producción; tampoco autentica al autor. Los tests usan
respuestas ficticias, no sustituyen el ejercicio de los supervisores.

Guía, privacidad, desacuerdos y criterios **propuestos, pendientes de acuerdo**:
[F4.1-GUIA-REVISION-HUMANA.md](../../docs/gestion-diaria/F4.1-GUIA-REVISION-HUMANA.md).
Ejecutar todos los checks de esta familia con `npm run test:gestion-diaria-typesafe`.

## Ensayo técnico anterior

Sin `--vivo` no hay red ni lectura de clave. El modo vivo realiza 20 peticiones,
una por nota y como máximo cuatro simultáneas, sin reintentos automáticos y
con límite de 15 segundos por petición, utilizando el cliente Jev existente sin
modificarlo. La clave se lee en el proceso servidor/local, nunca se imprime ni
se introduce en el navegador. No se copió su valor al repositorio.

Las etiquetas esperadas son fixtures escritos por Codex, **no etiquetas humanas**.
Se excluyen de la petición. Se cubren seguimiento sin descarte, referencias a
llamadas anteriores, negaciones, notas vacías y una instrucción inyectada en la
nota. Cada petición contiene únicamente su nota y resultado; no ve los otros
casos ni sus etiquetas. El reporte conserva probabilidades, modelos efectivos,
uso y latencia. Separa errores de servicio, respuestas ausentes y respuestas
inválidas de falsas alertas y omisiones del modelo (solo respuestas válidas).
Ninguna confianza decide la activación. Un resultado perfecto aquí no acredita
calidad sobre notas reales, y un desacuerdo no se esconde bajando un umbral.

El siguiente paso del plan F4.1 requiere 100–200 notas redactadas/anonimizadas
y etiquetas revisadas por el supervisor de cada equipo. Hay que medir precisión, falsas alertas,
omisiones, cobertura, coste y latencia antes de implementar/activar la ayuda
visible. Después corresponden cola y caché versionadas, permisos por equipo y
revisión humana de sugerencias; cualquier SQL se presenta antes de instalarla.
Miguel confirmó que participan ambos supervisores, cada uno únicamente con las notas
de su propio equipo. La muestra total representa a ambos equipos; no se espera elegir
un único supervisor ni se habilita revisión cruzada. Se conserva el revisor y el equipo
en la evidencia del piloto y se miden resultados por equipo además del agregado.
El conjunto de validación debe ser independiente de los ejemplos usados para
ajustar las preguntas. Antes de comenzar se acuerdan protocolo de desacuerdos,
criterios de aceptación y tratamiento de datos. No se envían notas reales por
este script, que admite exclusivamente los fixtures sintéticos.

Evidencia del 21/09: [primer ensayo por lote](../../docs/gestion-diaria/typesafe/ensayo-sintetico-2026-09-21.json),
[control aislado](../../docs/gestion-diaria/typesafe/ensayo-aislado-2026-09-21.json)
y [apoyo técnico](../../docs/gestion-diaria/typesafe/apoyo-tecnico-2026-09-21.json).
El control aislado dio 19/20: falsa alerta en la nota genérica «Se gestionó»
(c04, confianza 0,26); no se ajustó el umbral para convertirlo en acierto.
El primer ensayo usa la pregunta v1 con estado compartido y no debe confundirse
con el protocolo v2 de casos aislados. Para conservar otra ejecución, redirigir
la salida JSON a un archivo local nuevo; comprobar también el código de salida.
Un desacuerdo o fallo termina con código 1. `npm run check:scripts` ejecuta
solo tests deterministas, nunca `--vivo`, ni necesita una credencial.

La herramienta de apoyo técnico vive en `scripts/jev/` del taller principal:
sus usos medidos son ordenar contexto, agrupar repetidos y detectar revisiones
estancadas. Este ensayo reutiliza y versiona únicamente su cliente HTTP,
byte a byte; no toma ni modifica los otros archivos pendientes de esa tarea.
Jev no sustituye a Claude como reviewer ni a los tests del proyecto.

Contrato comprobado el 21/09/2026 con la skill `typesafe-ai`, Context7 y las
fuentes oficiales: [API](https://docs.typesafe.ai/api),
[Choice](https://docs.typesafe.ai/primitives/choice) y
[comprobación contra evidencia](https://docs.typesafe.ai/cookbooks/citation_check).

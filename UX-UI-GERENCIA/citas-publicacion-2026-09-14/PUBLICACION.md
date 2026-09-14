# Citas publicado — 14 de septiembre de 2026

Citas está publicado en [crm.miavance.com](https://crm.miavance.com/), con las
reglas comerciales confirmadas y configuración versión 1 vigente desde
septiembre de 2026. Se completó la autorización de Miguel «ok hagamos deploy»,
reanudada después de su pausa.

## Qué está activo

- Meta interna de 1,25 citas por lead, oculta como objetivo numérico en Gerencia.
- Metas del 70% de entrevistas y del 70% de clientes. Cada visita atendida cuenta
  como entrevista; la conversión compara personas distintas. Diez personas,
  quince entrevistas y siete clientes vinculados representan 70%.
- Resultados en el mes en que ocurrieron y para quien los obtuvo. Todos los
  cierres del mes aparecen, incluidos los de entrevistas de otros meses o
  analistas; el detalle distingue los que pertenecen a la base de la tasa.
- Personas y clientes deduplicados por identidad canónica, incluso con varios
  leads/perfiles. El total del equipo reconoce la colaboración entre analistas.
- Manuales incluidos; capital y ticket reales por analista, mes y moneda.
  Los filtros operativos de semana/estado/modalidad conservan la base mensual.

## Artefacto y coordinación

La preparación se hizo en un clon aislado mientras F8 trabajaba. Su acta de
instalación OFF y commits de cierre se integraron sin conflictos. Antes de
publicar, Main local y `avancecorp/main` coincidían exactamente en
`582358883c1a93b9922a0888b90ed06389088d75`, con árbol limpio. El commit de
implementación Citas es `d78b9a3`; el merge también conserva el trabajo F8.

Artefacto: `crm-20260914T173227Z-582358883c1a.zip`, 92 archivos, 2.070.539 bytes.
SHA-256: `24cac39af05d438407c466478df47d2c3240d79aecded8640157b30fd7ee708a`.
ZIP y manifiesto verificados se conservan en `CRM-Avance-Corp/releases/`.
Build público: `build-20260914T173227102Z`.

El hosting confirmó la recepción y el deploy; la lectura HTTP posterior confirmó
el build nuevo. Los commits documentales de cierre pueden avanzar Main sin
reconstruir ni sustituir este artefacto ya verificado.

## Base de datos y activación

Las cinco migraciones canónicas de [migraciones.json](migraciones.json) se
instalaron exclusivamente mediante merge de `citas-validacion-20260912`.
Las 281 entradas previas permanecen idénticas; total productivo 286.
Las 67 sentencias de los cinco archivos conservan contenido literal y orden.
Se contrastaron las 643 funciones, propietarios y permisos contra el banco:
coinciden todas. Frente al padre sólo se modifica el lector de Citas y se
añaden seis funciones de control. Las 19 Edge conservan versiones, paquetes
y configuración JWT.

La aplicación administrativa utilizó las RPC canónicas, el Superadmin activo
existente y nota explícita de ejecución de Codex por autorización de Miguel.
No se creó una cuenta o sesión productiva. Se comprobaron versión inicial cero,
mes abierto y huella del lector; después, las dos entradas de auditoría y la
versión 1 aplicada desde 2026-09. La configuración exacta y la lectura real de
Gerencia constan en [produccion-verificada.json](produccion-verificada.json).
Las cantidades de ese JSON describen el payload del lector, no los indicadores
mensuales después de filtrar en la interfaz.

Capital conserva `c9e58c1da9dd7a5d52991c9e47dc19d5`; lector publicado
`4ad2b90baf96b11b63a626122bd5d64b`. Censo: 34 declarados, 30 sujetos al techo,
cuatro auxiliares y cero sin declarar. F3 permanece ON y F8 instalada OFF.

## Verificación y límites

- **PASS:** gate frontend, 243 archivos / 3519 pruebas, lint, tipos, cobertura,
  build, configuración, bundle y duplicación; nueve E2E afectados repetidos.
  Corrida E2E integral anterior: 179 PASS / 26 SKIP. La última integración F8
  sólo añadió documentación/evidencia; no cambió el código probado.
- **PASS:** pruebas SQL mensuales e identidad con F3 ON/F8 OFF, control local
  y concurrencia, 48 verificaciones Auth/PostgREST y ensayo reversible de
  activación administrativa. Preflights de scripts, seed, RLS y Edge PASS.
- **PASS:** lectura productiva de Gerencia, configuración vigente, paridad de
  schema/historial/ACL y versión HTTP pública.
- **FAIL preexistente:** matriz RLS general, 49 de 1827 casos tanto en referencia
  como en candidato; mismos casos, cero aserciones nuevas. No es un PASS global.
  El A/B antecede a F8; después se repitieron los SQL de dominio y la paridad
  de funciones/permisos. La deuda y su comparación por caso están preservadas.
- **NOT RUN:** inspección manual en navegador autenticado del CRM productivo;
  las verificaciones de interfaz son E2E y la comprobación productiva es HTTP/RPC.

Advisors de Citas: dos INFO de tablas deliberadamente sin acceso directo y tres
WARN de funciones DEFINER que revalidan Superadmin. Sus permisos se probaron
con Auth real; no se abrieron políticas para silenciar los avisos.
Los dos dictámenes de Claude se conservan como CHANGES_REQUESTED. PRIMARY
resolvió y probó los hallazgos; la resolución está en el [README](README.md).

HTTP: 80 recursos devuelven exactamente los bytes del artefacto, incluidos
JavaScript, CSS, HTML y versión. `.htaccess` devuelve el 403 esperado. Once PNG
devuelven HTTP 200 con bytes distintos: seis conservan todos los píxeles RGBA;
cinco logos pasan de 3508×3253 a 1600×1484, conservando proporción. No se declara
igualdad binaria ni de píxeles para esos cinco. Los trece PNG del artefacto
permanecen idénticos a los del release anterior; el cambio no está en Citas.
Hostinger documenta la compresión y redimensión automática de imágenes en su
[optimización CDN](https://www.hostinger.com/support/7935917-hostinger-cdn-website-optimization/).
El cotejo y sus excepciones constan en [http-publicado.json](http-publicado.json).

## Recuperación y cierre

El release público previo comprobado fue
`crm-20260914T150911Z-c22e2ed97248.zip`, SHA-256
`c3927bbb6030206741c0a78587b803220db2efc2202a8aee7deefafb3200a71c`.
No confundirlo con el artefacto F8 construido posteriormente sin deploy.
Se conserva junto a su manifiesto. [rollback-lector.sql](rollback-lector.sql)
restaura únicamente el lector anterior `8b2eeffc547a1c095926ddb76876d262`,
exigiendo la huella publicada exacta y conservando configuración e historial.
La reversión no se ejecutó. Ante deriva posterior se debe revisar de nuevo.

El banco temporal propio `xhgsjtzpmwlqfkninphl`, rama
`07531654-e80e-47ef-ac36-02ce61d93d41`, se eliminó tras guardar la evidencia;
el listado posterior confirma su ausencia. No se tocaron los bancos F7 ni Tasas.
Se preservaron los archivos ajenos y el respaldo scoped del trabajo previo de
Citas; ese stash no debe reaplicarse sobre la implementación publicada.
No se guardan credenciales, sesiones ni datos personales en esta evidencia.

# Hoy del supervisor — implementación y entrega del ZIP para publicar

Plan solicitado por Miguel el 18/10/2026 y ampliado hasta crear y verificar el
ZIP de publicación. Sustituye la versión anterior de cinco fases.

**Estado: ejecución autorizada mediante Goal el 18/10/2026.** Miguel recibió el
plan y activó el objetivo adjunto. El progreso, la revisión de Codex y la
corrección/verificación de cada fase se registran en `PROGRESO-GOAL.md`.

Codex es PRIMARY y el único implementador. Claude es SECONDARY_REVIEWER: analiza
la evidencia, no modifica archivos ni delega. Cada fase sigue el ciclo obligatorio
implementar → revisar por Codex → corregir → verificar → registrar cierre antes
de avanzar. No se pide otra aprobación para decisiones rutinarias de este alcance.

## Objetivo principal propuesto para Goal

Completar e implementar el módulo «Hoy» del supervisor y entregar su ZIP de
publicación verificado, siguiendo las ocho fases de
`docs/diseno/hoy-supervisor-2026-10-18/PLAN-HOY-SUPERVISOR.md`.
Conservar el diseño aprobado y ofrecer indicadores comerciales confiables del
equipo: leads por repartir, llamadas, citas, resultados diarios, avance mensual
y detalle por analista. Aprovechar lo ya construido y resolver las brechas de
datos, actualización y acciones. Codex implementa; Claude revisa las decisiones
relevantes y la implementación; Codex resuelve los hallazgos con evidencia.
Verificar la versión candidata, preparar una revisión identificable conforme a
las reglas de Main y construir con configuración pública de producción.
Entregar el ZIP, manifiesto SHA-256, commit, build ID, evidencia e instrucciones
para publicación y reversión. Mantener excluidos navegador, control del
computador y Docker mientras Miguel no cambie esa instrucción, declarando NOT RUN
las comprobaciones afectadas. Terminar con el paquete local comprobado y los
pendientes explícitos, sin subir archivos, desplegar, aplicar SQL ni modificar
datos reales.

## Punto de partida y alcance

Ya están implementados localmente:

- Aviso ámbar de leads por repartir, cantidad, estado **Por asignar** y botón
  **Repartir leads**. Solo aparece con pendientes confirmados.
- Resumen mensual de capital, meta, brecha, operaciones y conversión.
- Tarjetas **Llamadas de hoy**, **Citas de hoy** y **Resultados de hoy**.
- Equipo con pestañas día/mes, búsqueda, filtro de apoyo y detalle por analista.
- Resultados procedentes de Facturación, con operaciones y capital en PEN/USD
  separados, y desglose por analista.
- Diseño compacto, iconos y textos simplificados según las indicaciones de Miguel.

La última iteración pasó 32 pruebas específicas, lint, compilación y verificación
del bundle. Esa evidencia es un antecedente, no acredita cambios futuros ni
reemplaza las pruebas del paquete final. Ver `ADAPTACION-CRM.md` y
`RESULTADOS-HOY-VERIFICACION.md`.

El árbol compartido contiene otros trabajos. Identificar los cambios propios y
sus dependencias; preservar lo ajeno y no incorporar trabajo incompleto de otros
módulos al ZIP por estar presente en la carpeta local.

## Fase 1 — Definir y contrastar los indicadores

**Objetivo:** que cada cifra tenga una interpretación comercial clara y una fuente
oficial, con el mismo equipo y periodo que su detalle.

**Trabajo de Codex:**

1. Contrastar la implementación con las reglas del vault y las fuentes oficiales.
   Usar CodeGraph primero para localizar lecturas y consumidores.
2. Documentar por indicador: propósito, origen, fecha, población, fórmula, estado
   de disponibilidad y acción que abre.
3. Identificar brechas concretas; conservar lo ya resuelto y evitar nuevas métricas
   o umbrales sin necesidad demostrada.

| Indicador | Regla que se debe comprobar |
| --- | --- |
| Leads por repartir | Abiertos sin analista del ámbito autorizado. Incluye pendientes anteriores; no llamar «nuevos hoy» a toda la bandeja. |
| Llamadas y contacto | Día de Lima y equipo completo. Tasa calculada con sumas de contestadas y útiles, no promedio de porcentajes por analista. |
| Citas de hoy | Fecha prevista y estados oficiales; no fecha de creación. Distinguir cita agendada de asistencia. |
| Resultados de hoy | Día comercial de Facturación, tipos válidos y atribución histórica. Operaciones no equivale a clientes únicos. |
| Capital, metas y brecha | Fuente mensual oficial y población correspondiente. Mantener las reglas de valoración existentes. |
| Conversión | Numerador, denominador y periodo oficiales. No inventar meta ni cumplimiento cuando falta información. |
| Equipo y tareas | Reglas existentes de apoyo y vencimiento, con periodo y detalle coherentes. |

**Claude:** revisión inicial solo si aparecen decisiones materiales nuevas de
fuentes, ámbito, contratos o arquitectura. Recibe la evidencia antes de modificar
esas reglas; no repite revisiones ya resueltas sin nueva evidencia.

**Entregable:** `MATRIZ-INDICADORES.md`, con definiciones y brechas numeradas.
**Cierre:** cada cifra tiene una fuente y un significado comprobables.

## Fase 2 — Completar los datos y su actualización

**Objetivo:** cifras completas, actuales y correspondientes al supervisor conectado.

1. Resolver las brechas reutilizando consultas y agregados autorizados. No sumar
   únicamente una página ni recortar el ámbito completo devuelto por el servidor.
2. Revisar actualización al entrar, pulsar **Actualizar**, regresar al módulo,
   recibir leads y terminar un reparto. Usar invalidación/refresco existentes y
   añadir solo lo que falte; documentar la frecuencia real.
3. Comprobar reparto parcial y total: el aviso actualiza su cantidad y desaparece
   sin reservar espacio cuando el saldo confirmado llega a cero.
4. Manejar cambio de día/mes en Lima y cambio de sesión, evitando respuestas viejas
   y cifras de otro supervisor.
5. Diferenciar carga, cero confirmado, ausencia de datos, error, recorte y corte
   pendiente. Un fallo con caché previa no confirma el total anterior.
6. Mantener PEN y USD separados en resultados diarios; tarjeta y detalle comparten
   el mismo agregado y conservan la atribución histórica.
7. Mantener demo aislada de la red real, sin inventar cierres recientes para rellenar
   tarjetas. No alterar reglas de negocio para producir números más atractivos.

**Entregable:** fuentes y refresco implementados, con pruebas de sus estados.
**Cierre:** no hay cifras incompletas presentadas como confirmadas y el aviso de
reparto responde al saldo real disponible en su fuente.

## Fase 3 — Completar acciones y detalles del supervisor

**Objetivo:** convertir cada indicador en una acción útil y coherente.

| Acción | Comportamiento esperado |
| --- | --- |
| Repartir leads | Abre la bandeja autorizada y refleja su saldo al regresar. |
| Llamadas de hoy | Abre la actividad del equipo o analista para la fecha mostrada. |
| Citas de hoy | Abre las citas y estados del día; no anunciar filtros que el destino no aplica. |
| Resultados de hoy | Desglose por analista con operaciones y montos que cuadran con la tarjeta. |
| Resumen mensual | Detalles y accesos oficiales con periodo y población consistentes. |
| Equipo | Búsqueda, pestañas y filtro de apoyo combinables; conservar contexto al cerrar un detalle. |
| Actualizar / reintentar | Recupera la fuente correspondiente y muestra éxito o error de forma clara. |

Revisar destinos, etiquetas, estados deshabilitados, navegación por teclado,
Escape y devolución del foco. Si falla una fuente con el diálogo abierto,
retirar cifras no confirmadas y conservar una salida usable.

**Entregable:** mapa de acciones y pruebas de interacción. Actualizar el código
del E2E existente cuando cambie el recorrido, aunque su ejecución siga pendiente.
**Cierre:** todas las acciones visibles cumplen lo que anuncian.

## Fase 4 — Consolidar la interfaz aprobada

**Objetivo:** lectura rápida, compacta y comercialmente útil.

1. Mantener el orden: aviso de reparto, resultado mensual, tarjetas diarias y equipo.
2. Conservar títulos e iconos aprobados; no recuperar textos eliminados, el potencial
   estimado ni «Acompañar el cierre».
3. Alinear cifras, importes y botones; reducir huecos sin perjudicar lectura ni
   interacción. Mantener tareas pendientes y atrasadas en lenguaje sencillo.
4. Revisar estilos para anchos pequeños, nombres largos, montos grandes y tablas
   densas; contener el desplazamiento horizontal dentro de la tabla pertinente.
5. Conservar foco visible, nombres accesibles y estados que no dependan solo del
   color. Evitar avisos duplicados entre tarjeta y diálogo.
6. Comprobar estructura y comportamiento con herramientas locales. Los tests DOM
   no sustituyen una inspección visual en navegador.

**Entregable:** interfaz ajustada y criterios de diseño comprobados.
**Cierre:** diseño coherente con lo aprobado. La inspección visual interactiva se
registra como NOT RUN mientras Miguel mantenga la restricción de navegador.

## Fase 5 — Revisión independiente de Claude y correcciones

**Objetivo:** detectar problemas relevantes antes de fijar la versión del paquete.

1. Codex ejecuta las pruebas pertinentes y prepara evidencia saneada: matriz,
   diff, código, contexto CodeGraph, casos de prueba y resultados.
2. Invocar `scripts/claude-review` desde la raíz Git conforme a
   `.ai/REVIEW_PROTOCOL.md`. Claude no dispone de herramientas para abrir archivos:
   la evidencia necesaria se adjunta, sin secretos.
3. Pedir revisión de fórmulas, ámbito, fechas, monedas, cortes, refresco,
   regresiones, acciones, accesibilidad y dependencias para empaquetar.
4. Guardar VERDICT, SUMMARY, hallazgos P0–P3, riesgos, acciones y confianza.
5. Codex acepta, rechaza o adapta cada hallazgo con evidencia, implementa lo
   pertinente y repite las verificaciones afectadas.

Máximo habitual de dos revisiones en la ejecución del plan: la inicial si existe
una decisión material y esta revisión. No consultar para obtener un PASS ni
repetir el review de la iteración anterior sin cambios relevantes.

**Entregables:** `REVISION-FINAL-CLAUDE.txt` y `RESOLUCION-HALLAZGOS.md`.
**Cierre:** sin hallazgos aceptados P0/P1 pendientes ni defectos conocidos de
cifras, ámbito o integridad del paquete; restantes resueltos o justificados.

## Fase 6 — Validación integral de la versión candidata

**Objetivo:** comprobar la integración y registrar exactamente qué se verificó.

Ejecutar `npm run check` en `app/`: lint, tipos, pruebas con cobertura,
configuración de release, service worker, build, bundle y duplicación. Los checks
de backend/dominio se añaden cuando el diff o sus dependencias lo requieran,
conforme a `.ai/VERIFICATION.md`.

| Caso | Resultado esperado |
| --- | --- |
| Día sin actividad/cierres confirmados | Ceros y vacío comprensibles. |
| Error con caché previa o dato ausente | Estado explícito, sin falsos ceros o totales confirmados. |
| Reparto parcial/total | Cantidad correcta y aviso solo con saldo positivo confirmado. |
| Varias operaciones y monedas | Sumas por analista y moneda; no contar filas como operaciones. |
| Cambio de sesión, día o mes | Sin cifras del supervisor ni del periodo anterior. |
| Subárbol autorizado e historia | Sin excluir operaciones válidas con filtros de supervisor directo. |
| Metas ausentes | Ausencia explícita, sin meta ni porcentaje inventados. |
| Diálogos y navegación | Destino correcto, salida usable y retorno del foco. |
| Facturación y otros roles | Sin regresiones en consumidores compartidos ni ampliación de permisos. |

Si existe un entorno ya autorizado para lectura, ejecutar el gate de realidad y
contrastar muestras con los módulos oficiales. Si no está disponible, registrar
NOT RUN con su motivo. Los fixtures no acreditan conciliación productiva.

**Restricción vigente:** no ejecutar navegador, control del computador ni Docker.
El E2E queda **NOT RUN por instrucción de Miguel**. Cuando se autorice, el comando
previsto es `npm run test:e2e:docker` en `app/`, nunca un E2E en GitHub.

El ZIP puede construirse y comprobarse localmente con esos pendientes declarados.
No presentarlo como validado en uso real ni como aprobado para despliegue. La
entrega debe conservar las comprobaciones pendientes para antes de publicar.

**Entregable:** `VERIFICACION-FINAL.md`, con revisión probada, comandos, alcance,
fecha, PASS/FAIL/NOT RUN y evidencia.
**Cierre:** checks locales aplicables en PASS y fallos propios corregidos. Un fallo
no se transforma en NOT RUN ni se oculta como limitación del entorno.

## Fase 7 — Preparar la revisión exacta para el ZIP

**Objetivo:** construir desde una versión identificada y compatible del CRM.

1. Revisar archivos propios y dependencias compartidas. Preservar los cambios
   ajenos; no incluirlos a ciegas ni limpiar masivamente el árbol compartido.
2. Versionar el alcance terminado e integrar cambios remotos sin sobrescribirlos.
   Seguir AGENTS.md: Main local debe seguir `avancecorp/main`, no `origin/main`
   ni `avancecorp/tronco`; no usar push forzado.
3. Comprobar y registrar igualdad del commit local y `avancecorp/main` antes del
   build destinado a publicación. Si la integración cambia código, verificar
   los componentes afectados sobre la revisión resultante.
4. Usar una copia local limpia de esa revisión, conservando el trabajo compartido.
   No crear ramas de release ni worktrees automáticos. No usar `--allow-dirty`
   para el paquete final ni mezclar archivos sin versionar.
5. Verificar la configuración pública de producción disponible. El preview con
   backend ficticio no sirve como build final. No imprimir claves ni incluir
   archivos de entorno en el ZIP.
6. Confirmar compatibilidad con las lecturas del backend de destino. Registrar
   dependencias de SQL/Edge: el inventario de migraciones del manifiesto no prueba
   que estén instaladas. Crear el ZIP no aplica ni autoriza esas dependencias.
7. Registrar build ID y referencia del artefacto anterior para una reversión;
   si no está disponible, dejarlo pendiente sin afirmar que existe un respaldo.

La sincronización Git pertenece a la ejecución futura del plan; esta propuesta
no ejecuta commits, integraciones ni pushes. Si falta acceso o configuración,
registrar el requisito exacto sin fabricar una identidad ni retirar validaciones.

**Entregable:** `PREPARACION-ZIP.md`, con commit, igualdad de Main, alcance,
configuración, dependencias y referencia de reversión.
**Cierre:** revisión limpia identificada, configuración válida y dependencias
conocidas. El build sale de esa revisión, no del preview de diseño.

## Fase 8 — Crear, verificar y entregar el ZIP

**Objetivo:** entregar el archivo de publicación con identidad y contenido comprobados.

### 8.1 Generación

Desde la raíz del CRM en la copia limpia, usar el comando existente:

```bash
npm run release:crm
```

Ejecuta tests de configuración, build, verificación de configuración/bundle y
`scripts/crear-artefacto-release.mjs create`. Produce en `CRM-Avance-Corp/releases/`:

- `crm-<fechaUTC>-<commit12>.zip`.
- `crm-<fechaUTC>-<commit12>.manifest.json`.

El ZIP contiene los archivos estáticos de `app/dist`. No es una copia del código
fuente. El manifiesto queda junto al ZIP y fuera del directorio público.

### 8.2 Comprobación

Usar las rutas reales emitidas por el comando, sustituyendo el marcador:

```bash
npm run release:crm:verify -- releases/<archivo>.manifest.json
unzip -t releases/<archivo>.zip
```

El verificador actual comprueba SHA-256, tamaño, entradas `index.html` y
`.htaccess` en la raíz y ciertas rutas internas prohibidas. Complementarlo sobre
una extracción temporal local, sin navegador:

1. Comparar inventario y hashes de cada archivo con `build.archivos` del
   manifiesto; detectar extras, omisiones y rutas inseguras.
2. Confirmar `version.json` y su build ID, commit del manifiesto igual a la
   revisión fijada y `fuente.worktree_sucio` en falso.
3. Confirmar recursos locales referenciados por la aplicación: JS, CSS, fuentes,
   iconos y archivos PWA requeridos, sin referencias a archivos ausentes.
4. Comprobar configuración pública de destino y ausencia de demo, código fuente,
   `.env*`, dependencias de desarrollo e inventarios internos en el ZIP.
5. Comprobar estructura lista para la raíz del CRM, sin carpeta contenedora
   `dist/` que desplace la entrada un nivel.

El verificador existente no acredita por sí solo todos esos puntos ni el
funcionamiento en producción. Guardar evidencia diferenciada. No editar el ZIP
verificado: un cambio requiere generar un nuevo artefacto y manifiesto.

### 8.3 Entrega

| Archivo o evidencia | Contenido |
| --- | --- |
| ZIP | Enlace, nombre, tamaño y SHA-256. |
| Manifiesto | Enlace, commit completo, fecha, destino e inventario. |
| Identidad | Build ID de `version.json` y revisión probada. |
| Cambios | Resumen comercial de lo nuevo en Hoy del supervisor. |
| Verificación | Checks, revisión de Claude y resolución de hallazgos. |
| Pendientes | E2E, visual, datos reales o dependencias no comprobadas, con motivo. |
| Publicación posterior | Destino, paquete exacto e instrucciones de subida y comprobación. |
| Reversión | Referencia del paquete anterior o pendiente de obtenerlo. |

Guardar `ENTREGA-ZIP.md` con esos datos; no incorporar informes privados al ZIP.
Preparar instrucciones para conservar el artefacto anterior, publicar el contenido
y comprobar después versión, recursos y acceso al módulo. No ejecutar esos pasos.

**Cierre del Goal futuro:** ZIP y manifiesto existen, coinciden, están verificados
y se entregaron sus enlaces. Estado final: **ZIP generado y verificado;
publicación pendiente**, con las limitaciones declaradas.

## Reglas transversales

- Mantener progreso y evidencia por fase, sin repetir trabajo ya acreditado.
- Codex es el único escritor. Claude revisa mediante el wrapper, no implementa
  ni inicia otra cadena de agentes.
- Preservar el diseño y reglas aprobados. No ampliar el alcance con nuevas
  métricas, dependencias, permisos o infraestructura innecesarios.
- Mantener navegador, control del computador y Docker excluidos hasta nueva
  instrucción de Miguel. No afirmar verificación visual por haber compilado.
- Generar el paquete no autoriza desplegar, subir archivos a Hostinger, aplicar
  migraciones, activar funciones ni modificar datos reales.
- La publicación posterior sigue la invocación humana `$release-crm` o
  `/release-crm` de `CLAUDE.md`; no auto-invocar ese flujo.
- Si cambia la aplicación o Main después de construir, comprobar la correspondencia
  del artefacto con la revisión a publicar y reconstruir cuando corresponda.
- Una vez autorizada la ejecución, el objetivo no termina con este documento ni
  con un build suelto: debe llegar al ZIP y manifiesto comprobados.

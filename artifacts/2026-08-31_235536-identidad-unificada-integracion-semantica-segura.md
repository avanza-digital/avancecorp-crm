# Identidad Unificada de Inversionistas — Plan de Integración Semántica y Segura

> **Para Hermes:** usar orquestación supervisada y revisión en dos fases para ejecutar este plan tarea por tarea. Ningún paso autoriza por sí solo SQL, backfill, branch con costo, merge o producción.

**Objetivo:** construir una identidad neutral y única por persona inversionista, con un solo lead total y múltiples inversiones, preservando la historia y haciendo que toda regla de negocio responda al núcleo semántico canónico de su dominio.

**Arquitectura:** hechos crudos → núcleo privado único → ventana de autorización única → RPC/vista consumidora → UI. Identidad incorpora un núcleo propio; conversión, capital, citas, atribución y autorización amplían sus núcleos existentes y nunca crean calculadoras o resolutores paralelos.

**Stack:** PostgreSQL 17 / Supabase, SQL y PL/pgSQL, RLS, Supabase CLI 2.116, Node.js ≥22.12, Deno, React/Vite/TypeScript, Vitest, Playwright y los gates existentes del CRM.

---

## 0. Estado y límite de autorización

Este documento es un plan de implementación mejorado. No autoriza:

- crear una branch con costo;
- ejecutar seeds o pruebas con `service_role`;
- aplicar migraciones;
- ejecutar backfill;
- modificar datos reales;
- desplegar backend o frontend;
- usar `migration repair`, `db push --include-all` o `apply_migration` directo a producción.

Estado vigente:

- **GO:** cerrar semántica, preparar ADR, endurecer herramientas, reconciliar baseline y diseñar F1.
- **NO-GO:** migrar o probar escrituras contra producción.
- **Producción:** solo consultas explícitas `READ ONLY`, agregadas o seudonimizadas, con `ROLLBACK`.

## 1. Resultado comercial

La implementación debe hacer verdadera esta frase:

> **Una persona confirmada, una identidad neutral y un solo lead total; puede tener múltiples perfiles, contratos e inversiones sin compartir permisos ni reescribir la historia.**

Resultado visible:

1. Si la persona vuelve, el CRM reutiliza su lead e historial.
2. Una nueva inversión no crea otro lead.
3. La misma persona puede invertir en Avance y cooperativas sin duplicarse.
4. Sus perfiles de Portal, colaborador o cliente conservan permisos independientes.
5. Gerencia puede resolver excepciones sin borrar ni alterar hechos legales.
6. Capital, conversión, citas, atribución y accesos siguen mostrando una sola versión de la verdad.

## 2. Precedencia documental

Al ejecutar el plan, la autoridad será:

1. reglas del repositorio y del servidor;
2. código y esquema vivo verificados;
3. contrato canónico F0-R aprobado por Miguel;
4. ADR aprobadas;
5. contratos vigentes de núcleos semánticos;
6. este plan;
7. censos fechados;
8. HTML y notas históricas.

El HTML de auditoría y el plan maestro anterior se conservan como evidencia histórica. No se editan para simular que siempre dijeron lo actual.

## 3. Baseline verificado el 2026-08-31

### 3.1 Servidor

- Proyecto linked: `PortalAvanceCorp`.
- Project ref: `dctqcbznekcyxhjujuci`.
- Base principal: activa y saludable.
- Rama `main`: el recurso de branches reporta `MIGRATIONS_FAILED`; el servidor productivo no está caído.
- Deriva observada: 55 versiones solo locales, 78 solo remotas y 113 coincidentes. Debe recalcularse al iniciar P2.
- `supabase/config.toml`: migraciones automáticas y seed automático desactivados.

### 3.2 Datos vivos

La fotografía actual es dinámica y no autoriza backfill:

- 831 leads: 628 vivos, 178 descartados y 25 convertidos;
- 399 perfiles cliente;
- 397 documentos válidos;
- 405 candidatas técnicas A+B antes de exclusiones comerciales;
- 74 operaciones de cartera;
- 493 episodios de capital;
- paridad de capital y conversión sin delta inesperado.

### 3.3 Esquema vivo

Todavía no existen:

- `crm.inversionistas`;
- `crm.inversionista_identificadores`;
- `crm.inversionista_perfiles`;
- `crm.leads.inversionista_id`;
- `crm.cierres_externos.inversionista_id`.

`crm.cierres_externos` conserva `UNIQUE(lead_id)`. Los índices de teléfono y documento en `crm.leads` son parciales para leads vivos y no prueban un lead total por persona.

## 4. Invariantes no negociables

### 4.1 Semántica por núcleos

1. **No nace ninguna calculadora paralela.**
2. **No nace ningún resolutor paralelo.**
3. **El núcleo no autoriza.** Recibe el ámbito ya resuelto y no tiene grants a la API.
4. **La ventana autoriza una sola vez.**
5. **La RPC de pantalla solo da forma.** No decide reglas de negocio.
6. **La UI no recalcula.** Solo presenta el payload semántico.
7. Toda nueva función debe clasificarse como `núcleo`, `ventana`, `adaptador/consumidor` o `operación canónica`. Si no encaja, se rechaza.
8. Los adaptadores de compatibilidad no pueden agregar filtros, fallback o deduplicación propios.

### 4.2 Identidad y datos

9. Documento fuerte normalizado puede identificar automáticamente; nombre, teléfono y correo solo generan candidatos.
10. Una identidad confirmada tiene como máximo un lead total.
11. Una identidad puede tener cero o muchos perfiles; cada perfil pertenece como máximo a una identidad.
12. Una identidad puede tener muchas inversiones.
13. Contratos, PDFs, cierres, actividades, tareas, atribuciones y periodos sellados no se reescriben.
14. No se inventa responsable para completar datos.
15. `no_contactar` prevalece al consolidar fuentes y conserva origen auditable.
16. Datos demo se clasifican técnicamente; no se excluyen por nombre o listas manuales dispersas.

### 4.3 Finanzas y métricas

17. Capital se suma por hechos económicos, no por personas.
18. PEN y USD nunca se suman entre sí.
19. Conversión se decide únicamente en `private.conversion_episodios` y su capa publicada/sellada.
20. Capital se decide únicamente en `private.capital_episodios`.
21. Citas se deciden únicamente en `private.citas_episodios`.
22. Atribución de cadenas de upgrade se decide únicamente en `private.analista_atribuido_cadena`.
23. Una anulación reduce conversión según el contrato ATR-4; no mueve capital.
24. Meses sellados son fotos inmutables.

### 4.4 Seguridad

25. Ninguna identidad concede por sí sola permisos de otro perfil.
26. Banca permanece detrás de sus porteros actuales.
27. Las tablas nuevas nacen con RLS y deny-by-default antes de cualquier grant.
28. Ningún script con `service_role` corre si el destino no está positivamente autenticado como branch no productiva.
29. Cero PII cruda en artefactos, logs, CI o reportes.

## 5. Mapa de núcleos semánticos

| Dominio | Autoridad canónica | Cambio permitido | Prohibido |
|---|---|---|---|
| Identidad | Nuevo núcleo de identidad: hechos canónicos + un resolutor privado + una proyección privada | Añadir `inversionista_id`, resolver documento fuerte, vincular fuentes y registrar decisiones | Matching independiente en cada RPC, edge o pantalla |
| Leads y conversión | `private.conversion_episodios` | Incorporar `inversionista_id` y deduplicación persona/mes aprobada | Crear `conversion_por_inversionista_*` paralelo |
| Capital | `private.capital_episodios` | Añadir dimensión `inversionista_id` sin cambiar aportes económicos | Crear sumadores por ficha o pantalla |
| Citas | `private.citas_episodios` | Propagar identidad vía lead cuando la pregunta lo requiera | Recontar tareas/reuniones en otra función |
| Atribución | `private.analista_atribuido_cadena` + hechos de cierre | Reutilizar atribución efectiva existente | Inferir atribución desde responsable actual |
| Acceso | `private.rol_crm`, vigencia/capacidades y ámbito canónico de cartera | Extender un ámbito canónico para identidades; adaptadores viejos llaman al nuevo | Predicados de rol por pantalla o función |
| Sellado | `crm.cerrar_periodo`, `crm.periodos_cerrados`, `crm.ajustes_mes_cerrado` y núcleos publicados | Consumir la identidad sin reabrir fotos | Recalcular o reescribir meses cerrados |

### 5.1 Forma del nuevo núcleo de identidad

El ADR F1 debe congelar los nombres, pero la forma será:

- **Hechos:** ancla neutral, identificadores fuertes, vínculos a perfiles/leads/inversiones, responsabilidad actual e histórica, exclusiones/demo y mapa de backfill.
- **Operación canónica de escritura:** un único resolutor privado normaliza, bloquea, busca, crea/reutiliza y vincula por documento fuerte. No autoriza y no es ejecutable por la API.
- **Proyección canónica de lectura:** una única salida privada expone identidad y relaciones sin PII innecesaria.
- **Ventana:** un único portero resuelve actor y ámbito; las RPC de Ficha, búsqueda y detalle solo formatean esa salida.

No se crearán helpers semánticos públicos. Los helpers técnicos puros solo se admiten si no deciden reglas y quedan encapsulados dentro del núcleo.

## 6. Decisiones comerciales y ADR

| ID | Regla | Estado | Gate |
|---|---|---|---|
| D1 | Una persona tiene un solo lead total | Confirmada por Miguel | Promover al contrato canónico |
| D2 | Sin documento fuerte no nace identidad automática | Confirmada | ADR de identidad no documental |
| D3 | `no_contactar` se eleva a identidad al confirmarla y prevalece | Recomendación | Aprobar ADR y pruebas |
| D4 | Máximo una conversión acreditada por persona/mes; gana la primera confirmada; una anulación no promueve otra | Pendiente de ratificación | Bloquea modificación de `conversion_episodios` |
| D5 | Identidad sin responsable: solo Gerencia la ve/administra hasta asignación | Pendiente de ratificación de acceso | Bloquea matriz RLS F1 |
| D6 | Demos mediante clasificación durable consumida por todos los núcleos | Requerida | ADR técnico con FKs, sin tabla polimórfica débil |
| D7 | Reinversión externa es postventa 1:N e idempotente; no crea lead | Requerida | ADR y contrato de puerta postventa |

## 7. Estrategia de ambientes

### 7.1 Producción

Solo:

- censos y catálogo en transacción `READ ONLY`;
- conteos agregados o referencias seudonimizadas;
- verificación de objetos y huellas;
- ningún test con fixtures;
- ningún pgTAP con `--linked` sobre producción;
- ningún seed, limpieza, mutante con escritura, repair o push.

### 7.2 Local aislado

No se ejecuta `supabase db reset` sobre el historial completo mientras el baseline sea divergente.

Se usa:

1. proyecto local único y puertos no compartidos;
2. migraciones automáticas desactivadas como hoy;
3. baseline revisado y mínimo/as-built aprobado;
4. migración candidata aplicada explícitamente;
5. pgTAP, pruebas de carrera y mutantes;
6. verificación HTTP, PostgreSQL y contenedores.

El local sirve para velocidad y fallos controlados; no sustituye la branch equivalente a producción.

### 7.3 Branch Supabase desechable

La creación tiene costo y requiere autorización expresa de Miguel.

Comando candidato, sin datos productivos:

```bash
npx supabase branches create identidad-f1-banco \
  --project-ref dctqcbznekcyxhjujuci
```

No usar `--with-data`. La branch debe recibir seed determinista antes de la migración candidata, de acuerdo con el ledger.

## 8. Programa por fases y gates

## P0 — Contrato canónico y semántica

**Objetivo comercial:** que nadie implemente una regla distinta en otra capa.

**Archivos previstos:**

- Crear: `BASE DE CONOCIMINETO/AVANCECORP/Contrato canonico - identidad unificada de inversionistas (F0-R).md`
- Crear: `BASE DE CONOCIMINETO/AVANCECORP/ADR identidad sin documento fuerte.md`
- Crear: `BASE DE CONOCIMINETO/AVANCECORP/ADR no contactar e identidad.md`
- Crear: `BASE DE CONOCIMINETO/AVANCECORP/ADR reinversion externa 1-N.md`
- Crear: `BASE DE CONOCIMINETO/AVANCECORP/ADR clasificacion durable de demos.md`
- Crear: `BASE DE CONOCIMINETO/AVANCECORP/Registro de nucleos semanticos del servidor.md`
- Modificar después de aprobación: `BASE DE CONOCIMINETO/AVANCECORP/Inicio.md`

**Pasos:**

1. Copiar decisiones vigentes sin alterar notas históricas.
2. Ratificar D4 y D5 con Miguel.
3. Resolver D3, D6 y D7 en ADR separadas.
4. Definir fila/hecho, autoridad, ventana y consumidores de Identidad.
5. Registrar los núcleos existentes y declarar qué funciones son adaptadores.
6. Añadir una tabla de precedencia documental.
7. Revisar contradicciones y obtener aprobación G0.

**Gate P0:** cero decisiones ambiguas y cero reglas duplicadas en documentos vigentes.

## P1 — Blindaje del destino y CI

**Objetivo comercial:** impedir que una prueba o migración llegue al servidor real por equivocación.

**Archivos previstos:**

- Crear: `CRM-Avance-Corp/supabase/scripts/lib/validar-destino-supabase.mjs`
- Crear: `CRM-Avance-Corp/supabase/scripts/lib/validar-destino-supabase.test.mjs`
- Modificar: `CRM-Avance-Corp/supabase/scripts/seed-demo.mjs`
- Modificar: `CRM-Avance-Corp/supabase/scripts/test-rls.mjs`
- Modificar: `CRM-Avance-Corp/package.json`
- Modificar: `.github/workflows/crm-rls-preflight.yml`
- Crear, si se aprueba: `.github/workflows/crm-branch-migration-gate.yml`

**TDD:**

1. Escribir tests que demuestren que la guardia actual acepta por error un dominio custom/proxy sin el ref productivo.
2. Ejecutar los tests y observar RED.
3. Implementar validación positiva compartida:
   - `CRM_EXPECTED_BRANCH_REF` obligatorio;
   - host Supabase estándar esperado;
   - ref distinta de producción;
   - custom domains prohibidos para fixtures;
   - `CRM_BANCO_PSQL_URL` debe apuntar a la misma branch;
   - confirmación explícita ligada al ref;
   - salida redacted, nunca claves.
4. Hacer que seed y RLS importen esa única guardia.
5. Añadir `CRM-Avance-Corp/supabase/migrations/**` a los triggers de CI.
6. Mantener preflight estático en PR y exigir evidencia viva de branch para G2.
7. Añadir mutantes: guardia sin comparación exacta, host custom, ref producción, PSQL a otro destino.

**Comandos:**

```bash
cd CRM-Avance-Corp
node --test supabase/scripts/lib/validar-destino-supabase.test.mjs
npm run seed:preflight
npm run test:rls:preflight
npm run check:scripts
```

**Gate P1:** ningún script con capacidad de escritura puede abrir red sin autenticar positivamente una branch no productiva.

## P2 — Reconciliación del baseline

**Objetivo comercial:** saber exactamente qué servidor se está probando y evitar una “migración verde” que solo actualice el ledger.

**Artefactos previstos:**

- Crear: `artifacts/as-built-identidad/<fecha>/migraciones-local-remoto.json`
- Crear: `artifacts/as-built-identidad/<fecha>/objetos-semilla.json`
- Crear: `artifacts/as-built-identidad/<fecha>/huellas-funciones.json`
- Crear: `BASE DE CONOCIMINETO/AVANCECORP/Runbook branch identidad F1.md`

**Pasos:**

1. Recalcular `migration list --linked` y guardar el mapeo, no solo conteos.
2. Clasificar cada diferencia: retimestamp, remoto legítimo, local pendiente, obsoleta o desconocida.
3. Prohibir `migration repair` hasta que todas estén explicadas.
4. Capturar esquema as-built solo como evidencia revisable:

```bash
npx supabase db dump --linked \
  --schema crm,public \
  --file artifacts/as-built-identidad/<fecha>/schema-crm-public.sql
```

5. Revisar que el dump no contenga datos ni secretos.
6. Construir un manifiesto de objetos críticos y huellas:
   - núcleos semánticos;
   - porteros de autorización;
   - puertas de leads y conversión;
   - restricciones e índices;
   - triggers de auditoría;
   - funciones del Portal tocadas indirectamente.
7. Definir el bootstrap local controlado; no replay ciego de 168 migraciones.

**Gate P2:** baseline firmado, cada deriva clasificada y ninguna acción de repair/push pendiente implícita.

## P3 — Banco de branch sin F1

**Objetivo comercial:** demostrar que el laboratorio representa al servidor antes de probar la funcionalidad.

**Pasos:**

1. Solicitar autorización de costo para crear branch.
2. Crear branch sin `--with-data`.
3. Esperar `ACTIVE_HEALTHY`; no creer solo el estado del job.
4. Verificar físicamente objetos y huellas críticas contra el manifiesto P2.
5. Ejecutar `npm run seed:demo` con guardia P1.
6. Ejecutar `npm run test:rls` antes de F1.
7. Ejecutar advisors y guardar baseline.
8. Ejecutar smoke tests de Portal y CRM sobre la branch.
9. Destruir y recrear una segunda vez para probar reproducibilidad.
10. Si falla, detener F1 y corregir el runner/baseline; no parchear producción.

**Gate P3:** dos branches consecutivas reproducibles, RLS verde, objetos reales presentes y cero errores de advisors nuevos.

## F1 — Núcleo de identidad y backfill seguro

### F1-A — ADR y esquema vacío

**Archivos previstos:**

- Crear tras G1: `CRM-Avance-Corp/supabase/migrations/<timestamp>_crm_identidad_inversionistas_f1.sql`
- Crear: `CRM-Avance-Corp/supabase/tests/identidad_inversionistas_test.sql`
- Crear: `CRM-Avance-Corp/supabase/scripts/rollback-identidad-inversionistas-f1.sql`
- Crear: `CRM-Avance-Corp/supabase/scripts/test-identidad-inversionistas-f1.sql`
- Modificar: `CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md`

**Modelo mínimo a congelar en ADR:**

- ancla neutral `crm.inversionistas`;
- identificadores fuertes e historia;
- puente 0:N a perfiles, con unicidad por perfil;
- vínculo 0:1 identidad–lead mediante `crm.leads.inversionista_id` nullable y único si no es null;
- enlaces 1:N a cierres, contratos/operaciones según el modelo aprobado;
- responsable actual nullable + ledger append-only;
- clasificación demo/exclusión con FKs explícitas;
- mapa de backfill/fusión y reversa;
- auditoría de decisiones manuales.

**Regla semántica:** la migración crea un solo núcleo de identidad. Las funciones nuevas permitidas son únicamente su operación privada, proyección privada y ventana autorizada. Las RPC de pantalla o escritura existentes consumen ese núcleo.

### F1-B — Pruebas RED

Antes de implementar:

1. mismo documento fuerte concurrente → exactamente una identidad;
2. mismo perfil no puede enlazarse a dos identidades;
3. una identidad no puede enlazarse a dos leads;
4. lead sin documento continúa sin identidad automática;
5. mismo nombre/teléfono entre dos personas no fusiona;
6. identidad sin responsable queda inaccesible fuera de Gerencia;
7. backfill repetido no duplica;
8. `no_contactar` prevalece y conserva fuentes;
9. demo queda fuera de los núcleos de métricas;
10. rollback desconecta enlaces nuevos sin borrar hechos históricos.

Ejecutar en local/branch, nunca linked a producción:

```bash
npx supabase test db --local supabase/tests/identidad_inversionistas_test.sql
```

### F1-C — RLS y autorización

1. RLS habilitado antes de grants.
2. Tablas de hechos sin acceso API directo salvo necesidad aprobada.
3. Núcleo privado `SECURITY DEFINER`, `search_path=''`, ACL solo dueño.
4. Ventana única reutiliza autoridad y vigencia existentes.
5. El nuevo ámbito de identidades se convierte en autoridad; el ámbito de clientes existente queda como adaptador de compatibilidad, no como segunda regla.
6. Banca no entra en la proyección general.
7. Revisar service-role y edges por acceso directo.

### F1-D — Backfill

**Archivos previstos:**

- Crear: `CRM-Avance-Corp/supabase/scripts/preflight-identidad-f1.sql`
- Crear: `CRM-Avance-Corp/supabase/scripts/backfill-identidad-f1.sql`
- Crear: `CRM-Avance-Corp/supabase/scripts/postflight-identidad-f1.sql`
- Crear: `CRM-Avance-Corp/supabase/scripts/verificar-identidad-f1.mjs`

Secuencia:

1. recenso READ ONLY firmado;
2. excluir demos de forma durable;
3. crear mapa auditable antes de enlaces;
4. automatizar solo documentos fuertes no ambiguos;
5. dejar conflictos en cola manual;
6. procesar lotes pequeños con timeout y fail-closed;
7. reejecución idempotente;
8. comparar conteos, capital, conversión y periodos sellados;
9. no activar escritores F2 aún.

**Gate F1:** cero duplicados fuertes, cero fusiones ambiguas, paridad económica, RLS verde, mutantes cazados y rollback ensayado.

## F2 — Todas las escrituras consumen el núcleo de identidad

**Puertas a adaptar, sin excepción:**

- `crm.crear_lead_si_disponible`;
- `crm.tomar_lead_libre`;
- edición de documento/contacto;
- reapertura y descarte;
- importador `supabase/functions/crm-importar-leads/index.ts`;
- `crm.convertir_lead` y edge de conversión;
- `crm.convertir_lead_externo`;
- futura reinversión externa postventa;
- `public.crear_contrato` y wrappers CRM cuando vinculen perfil/cliente;
- fusiones y correcciones manuales autorizadas.

**Patrón obligatorio de cada puerta:**

1. autorizar mediante portero existente;
2. llamar al núcleo de identidad;
3. normalizar y bloquear identificador fuerte allí;
4. crear/reutilizar identidad allí;
5. crear/reutilizar el único lead allí;
6. escribir el hecho económico sin duplicar semántica;
7. registrar auditoría e idempotencia;
8. devolver códigos de error estables.

No se copia matching en edge, TypeScript o SQL de la RPC. El importador con `service_role` deja de insertar leads por una ruta semántica paralela.

**Tandas:**

1. alta manual + toma de lead;
2. importador;
3. conversión Avance;
4. cierre externo inicial;
5. reinversión externa postventa;
6. vinculación de perfil/contrato;
7. corrección/fusión manual.

Cada tanda lleva RED → implementación mínima → carreras → RLS → mutante → compatibilidad app vieja/nueva → commit revisable.

**Gate F2:** ninguna ruta puede crear una segunda identidad o lead y el trinquete reporta cero escritoras paralelas.

## F3 — Integración con los núcleos semánticos vivos

### F3-A — Conversión

Modificar únicamente `private.conversion_episodios` y sus contratos publicados:

- añadir `inversionista_id` como dimensión;
- aplicar D4 persona/mes en el núcleo, no en consumidores;
- conservar cohorte, pesos, referidos, anulaciones y sellado;
- ninguna anulación promueve otra si D4 se ratifica así;
- consumidores actuales reciben la semántica por transitividad.

Prohibido crear `conversion_inversionistas_fn`, agregar dedup en una pantalla o recontar desde leads crudos.

### F3-B — Capital

Modificar únicamente `private.capital_episodios`:

- propagar `inversionista_id`;
- conservar un episodio por hecho económico;
- no deduplicar capital por persona;
- conservar atribución de `private.analista_atribuido_cadena`;
- PEN/USD separados;
- demos excluidos por clasificación durable;
- meses sellados idénticos.

Prohibido crear un sumador “capital de ficha 360”. La ficha agrupa episodios del núcleo.

### F3-C — Citas

Modificar únicamente `private.citas_episodios` si una pregunta exige persona:

- relación vía lead canónico;
- definición de pactada, realizada, no-show, cancelada y reprogramada intacta;
- ninguna pantalla cuenta tareas crudas.

### F3-D — Trinquete semántico

Crear un gate estructural que falle si fuera de los núcleos autorizados aparece:

- matching automático por documento/identificador;
- agregación directa de capital crudo;
- conteo de conversión desde leads;
- conteo de citas desde tareas;
- lógica propia de atribución;
- filtros de autorización por rol duplicados;
- cálculos TypeScript sobre payloads que ya traen resultado semántico.

El gate debe inspeccionar llamadas/cuerpos, sellar exenciones por huella y llevar topes que solo bajan. Los mutantes deben alterar cada núcleo y demostrar que todos sus consumidores migrados fallan.

**Gate F3:** delta inesperado de capital = 0; delta inesperado de conversión = 0; periodos sellados idénticos; cero funciones semánticas paralelas.

## F4 — Ficha neutral y lecturas

**Objetivo:** una nueva lectura neutral sin convertir la ficha Portal en otro dominio.

**Archivos probables:**

- Migración/RPC consumidora: una sola `crm.inversionista_detalle_fn` o nombre aprobado.
- Adaptar: `crm.clientes_basicos_fn`, `crm.cliente_detalle_fn`, `crm.cartera_pagina_fn` como consumidores/adaptadores.
- Modificar: `CRM-Avance-Corp/app/src/data/crm-api.ts`.
- Modificar tipos: `CRM-Avance-Corp/app/src/lib/tipos.ts` o tipos generados vigentes.
- Tests MSW/componentes existentes.

La RPC de detalle:

- autoriza por la ventana de identidad;
- consume proyección de identidad;
- consume capital/conversión/citas desde sus núcleos;
- no une datos bancarios salvo llamada al portero bancario específico;
- no recalcula totales;
- expone alertas de calidad y no-contactar sin PII innecesaria.

**Gate F4:** pruebas por rol, historia completa, totales idénticos y cero fuga entre perfiles.

## F5 — UI y activación gradual

1. Búsqueda única por identidad.
2. Reutilización visible del lead existente.
3. Flujos separados: primera inversión y nueva inversión.
4. Bandeja de excepciones solo para Gerencia.
5. Asignación/reasignación con ledger.
6. Explicación visible de coincidencia fuerte, débil o bloqueada.
7. App tolera `inversionista_id=null` durante transición.
8. Sin cálculos semánticos en React; el front formatea y presenta.

**Comandos de validación:**

```bash
cd CRM-Avance-Corp
npm --prefix app run test:run
npm --prefix app run lint
npm --prefix app run typecheck
npm --prefix app run build
npm --prefix app run test:e2e
```

**Gate F5:** recorridos críticos por rol en desktop/móvil, compatibilidad con bundle anterior y cero regresiones en cartera, cierres, agenda, ficha o métricas.

## F6 — Transferencias de titularidad, fuera de alcance

No se implementa como cambio de `inversionista_id` en hechos históricos. Requiere contrato legal y técnico separado para titular anterior/nuevo, fecha efectiva, PDFs, obligaciones, capital, atribución, reversa y disputa.

## 9. Gates de autorización

| Gate | Autoriza | No autoriza |
|---|---|---|
| G0 | Aceptar este plan y cerrar D4/D5 | Código, branch o SQL |
| G1 | Congelar ADR, esquema, pruebas y rollback | Producción |
| G1.5 | Crear branch con costo y ejecutar fixtures allí | Producción |
| G2 | Aprobar archivo SQL y hash tras ensayos | Otro archivo o cambios adicionales |
| G3 | Aplicar caparazón F1 exacto | Backfill, F2 o métricas |
| G3.1 | Ejecutar backfill seguro exacto | Casos manuales forzados |
| G4 | Activar cada tanda F2 | F3 automáticamente |
| G5 | Activar integración semántica F3 | UI final automáticamente |
| G6 | Aceptación operativa F4/F5 | F6 |

## 10. Despliegue de producción

Solo después de G2/G3:

1. congelar commit, archivo, tamaño y SHA-256;
2. confirmar ancestro del servidor vivo;
3. backup verificable;
4. recenso READ ONLY final;
5. abortar ante deriva no explicada;
6. aplicar solo caparazón aditivo F1;
7. verificar objetos reales, no solo ledger;
8. verificar RLS, advisors y salud CRM/Portal;
9. autorizar separadamente backfill;
10. procesar automáticos seguros por lotes;
11. dejar manuales en cola;
12. reconciliar núcleos y periodos sellados;
13. observar antes de F2;
14. activar F2/F3/F4/F5 por tandas independientes.

Nunca mezclar schema, backfill, escritores, métricas y UI en una sola migración o ventana.

## 11. Rollback y reversibilidad

Cada tanda debe tener rollback escrito antes de aplicarse.

Principios:

- revocar nuevos consumidores y volver a adaptadores anteriores;
- desconectar enlaces nuevos sin borrar contratos, cierres, perfiles o actividades;
- conservar mapa de backfill y auditoría;
- no deshacer hechos legales;
- no reabrir meses sellados;
- no eliminar identidades si ya recibieron hechos; marcarlas inactivas/corregidas con rastro;
- REVOKE → observar → DROP para retiros posteriores, siempre con aprobación por pieza.

## 12. Observabilidad

Registrar sin PII cruda:

- conflictos de documento fuerte;
- intentos de segundo lead;
- identidad creada/reutilizada/vinculada;
- resoluciones manuales;
- fusiones/correcciones;
- identidades sin responsable;
- casos demo excluidos;
- fallos de idempotencia;
- deltas de paridad;
- hash de migración y censo.

Alertas operativas:

- más de una identidad por identificador vigente;
- más de un lead por identidad;
- writers sin núcleo;
- drift local/remoto nuevo;
- advisors nuevos;
- gate semántico o RLS rojo.

## 13. Pruebas mínimas de aceptación

### Identidad y concurrencia

- 20 altas concurrentes con mismo documento → una identidad y un lead.
- documentos distintos con mismo nombre/teléfono → dos personas.
- reintento con misma idempotency key → mismo resultado.
- cambio de documento autorizado conserva historia.

### Permisos

- analista colaborador/inversionista no hereda acceso de cliente ni viceversa;
- histórico no concede acceso actual;
- sin responsable solo Gerencia;
- banca permanece protegida;
- anon obtiene cero.

### Semántica

- romper núcleo de identidad rompe todas las escritoras migradas;
- romper `conversion_episodios` rompe todos los consumidores de conversión;
- romper `capital_episodios` rompe todos los consumidores de capital;
- romper `citas_episodios` rompe todos los consumidores de citas;
- ningún consumidor puede seguir verde calculando por su cuenta.

### Economía e historia

- capital por fuente/moneda idéntico;
- conversión cambia solo por D4 y con delta explicado;
- meses sellados idénticos;
- contratos/PDF/atribución inmutables;
- demo fuera de métricas, presente en auditoría.

## 14. Condiciones de detención inmediata

Detener si:

- destino no puede autenticarse como branch;
- branch no reproduce objetos reales;
- una función nueva no tiene clasificación semántica;
- aparece matching fuera del núcleo;
- hay una fusión por nombre/teléfono/correo;
- cambia capital sin explicación;
- cambia un periodo sellado;
- falla RLS o se amplía banca;
- una demo entra al universo real;
- el archivo/hash difiere del aprobado;
- el rollback borra hechos históricos;
- una edge/service role puede eludir el núcleo.

## 15. Orden inmediato recomendado

1. Miguel acepta G0 y ratifica D4/D5.
2. Ingeniería redacta contrato canónico y registro de núcleos.
3. Implementar P1 por TDD: guardia de destino + CI de migraciones.
4. Ejecutar P2: baseline local/remoto y manifiesto de objetos.
5. Solicitar autorización de costo G1.5.
6. Probar P3 dos veces sin F1.
7. Diseñar F1 completo, pruebas RED y rollback.
8. Auditoría independiente de semántica, seguridad, datos y concurrencia.
9. Solicitar G1/G2.
10. Ensayar F1 local + branch.
11. Presentar a Miguel archivo, hash, paridad, RLS, advisors y rollback.
12. Solo con G3, ejecutar el caparazón F1 exacto.

## 16. Definición de terminado

La identidad unificada estará terminada únicamente cuando:

1. cada persona confirmada tenga una identidad y un lead total;
2. todas las inversiones 1:N conserven hechos y empresa;
3. ninguna puerta pueda eludir el núcleo de identidad;
4. conversión, capital, citas y atribución sigan teniendo un único núcleo cada uno;
5. ninguna RPC o UI calcule reglas paralelas;
6. permisos, banca y perfiles permanezcan aislados;
7. capital, periodos sellados y hechos legales estén intactos;
8. branch, pruebas, mutantes, RLS, advisors, rollback y observación estén en verde;
9. los trinquetes impidan que la duplicación semántica vuelva a aparecer.

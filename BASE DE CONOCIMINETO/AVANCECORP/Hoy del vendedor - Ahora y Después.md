# Hoy del vendedor — Ahora y Después

Estado: implementado y publicado en producción el 2026-08-23; validación humana con vendedores pendiente.

Relacionado con [[Fundamentos UX del CRM]], [[Plan de mejoras UX-UI del CRM]] y [[Agente de guía comercial para vendedores (plan)]].

## Trabajo que resuelve

La portada del vendedor debe contestar primero: **«¿A quién atiendo ahora y qué hago?»**. Los indicadores de cartera y el cumplimiento mensual sirven como contexto, pero no deben competir con el siguiente movimiento comercial.

## Contrato de experiencia

- La franja **Ahora / Tu siguiente movimiento** reúne agenda y cola en un máximo de tres decisiones ordenadas.
- Se muestra una sola señal dominante por lead. Una prioridad elevada se retira de Agenda, cola e higiene para evitar alertas duplicadas.
- El orden operativo es: speed-to-lead, otras urgencias críticas, agenda vencida, agenda de hoy, seguimiento medio y seguimiento bajo.
- Todo speed-to-lead conserva prioridad, incluso antes de llegar a severidad crítica; su reloj nunca se entierra bajo una tarea vencida del mismo lead.
- **Después en tu agenda** y **Después: mantén el ritmo** contienen solo el remanente accionable.
- Una superficie inferior no puede decir «Al día» si existen intervenciones pendientes en Ahora. En ese caso comunica **Sin trabajo adicional**.
- Los cuatro indicadores pasan a **Tu cartera en contexto**, después del trabajo accionable.
- **Tu cumplimiento del mes** usa divulgación progresiva: el resumen queda visible y el detalle se abre bajo demanda.

## Fundamentos aplicados

- Gestalt: proximidad y región común para unir contexto, urgencia y acción; eliminación de duplicados para evitar competir visualmente consigo mismo.
- Hick: máximo tres decisiones principales.
- Fitts: acciones prioritarias con objetivos de 36 px y la llamada como CTA dominante en speed-to-lead.
- Jakob: patrones conocidos para llamar, WhatsApp, ver ficha y expandir detalle.
- Carga cognitiva y progressive disclosure: primero ejecución, después contexto y finalmente metas.
- Psicología del color: navy para foco y confianza, azul para acción, rojo para criticidad y ámbar para vencimiento; el color nunca sustituye el texto.
- Role-Based UX y Jobs To Be Done: el vendedor ve su jornada y su propia cartera, no un dashboard gerencial reducido.

## Reglas protegidas por pruebas

- Máximo tres prioridades y un solo ítem por lead.
- Las tareas futuras no compiten en el día operable.
- Ninguna tarea vencida desaparece al repartirla entre Ahora, Agenda, cola o higiene.
- El speed-to-lead no queda oculto por una cita vencida.
- La interfaz reacciona al reloj vivo cuando una cita vence.
- PEN y USD se mantienen separados; nunca se suman como si fueran la misma moneda.

Implementación principal: `src/screens/hoy/vendedor.tsx`. Orden puro y testeable: `src/screens/hoy/prioridades-vendedor.ts`.

## Implementación productiva — 2026-08-23

- Implementación original: `04dc37e` (`feat/hoy-vendedor-ahora-v2`). Release productivo combinado: `c79d54a` (`feat/hoy-vendedor-sobre-f3`), construido sobre `fdcd4d1` para conservar también «Hoy, tres cosas» del supervisor.
- No se añadieron tablas, migraciones ni RPC. El cambio no amplía autoridad: el ámbito personal continúa recortado por el store y protegido por RLS.
- El estado remoto ya no se interpreta de forma optimista: carga muestra skeleton; error conserva la agenda y declara que la prioridad es parcial; un viernes con trabajo de higiene nunca dice «al día».
- Los objetivos táctiles de la franja principal miden 44 px en móvil.
- El `Sheet` compartido recupera el control que abrió la ficha al cerrarla, incluso cuando el drawer controlado no tiene un `Dialog.Trigger` declarativo.
- Las tarjetas inferiores admiten encogimiento real (`min-width: 0`), evitando el scroll horizontal interno que solo aparecía a 390 px.

### Evidencia técnica

- 35 pruebas unitarias/de integración específicas de la vista y su priorización: en verde; 80/80 al ejecutar juntas las suites dirigidas de vendedor y supervisor.
- Suite de cobertura combinada: 167 archivos y 2,166 pruebas: en verde.
- Lint, typecheck, build de producción y verificación de bundle: en verde.
- E2E por rol (`demo-roles.spec.ts`): 9/9 en verde sobre el release combinado, incluidos máximo de tres prioridades, no exposición de un lead ajeno, teclado, retorno de foco, primer pantallazo a 390 px, targets de 44 px, ausencia de desborde interno y navegación del supervisor con su F3 presente.
- Revisión en navegador integrado: escritorio y 390 × 844; primera tarjeta completa hasta `y=663`, contenedor central `scrollWidth=clientWidth=316`, sin errores ni avisos de consola.
- La corrida E2E global conserva fallos preexistentes en Contrato/Repartir. Se reprodujeron sobre el release base `71c068f` sin este cambio, por lo que no se atribuyen a la vista Vendedor ni se declaran resueltos aquí.

### Release y reversión

- Artefacto productivo verificado: `releases/crm-20260823T195728Z-c79d54acdcd2.zip`.
- Build vivo: `build-20260823T195727965Z`. SHA-256: `e09b335dd4964bcd84b7d7e45ea7fa134b8875f3f91420fc7c54014b484b04af`.
- Verificación viva: 58/58 archivos públicos no transformados idénticos al manifiesto; el chunk de Hoy contiene las señales de vendedor y supervisor; portada/version/nuevo index 200, indexes anteriores y ZIP 404, `.htaccess` 403. El smoke autenticado recuperó tras un fallo transitorio y terminó con datos reales, F3 visible y sin errores nuevos en la ventana estable.
- Rollback operativo recomendado: `crm-20260823T192043Z-fdcd4d17abdf`; conserva la F3 del supervisor. No usar como rollback el artefacto intermedio `04dc37e`, porque nació en paralelo y elimina esa F3.
- No se considera realizada la validación humana: el benchmark con vendedores reales (primera acción < 5 s, Task Completion Rate, tiempo, errores y clics) comienza después de publicar y se revisa a las dos y cuatro semanas.

## Regresión productiva por despliegue paralelo — 2026-08-24

- Producción dejó de contener esta portada después de un despliegue posterior: `version.json` expuso `build-20260824T155903213Z` (publicado aproximadamente a las 10:59, hora de Lima), en reemplazo del build correcto `build-20260823T195727965Z`.
- El manifiesto local que corresponde exactamente al build vivo es `crm-20260824T155903Z-1dd89bffa9f2`: salió de `1dd89bf` (`feat/hoy-supervisor-sin-ruido`) con el worktree marcado como sucio. Ese commit conserva F4.3 del supervisor, pero no desciende de `c79d54a` ni de `d4a5416`/`9081334`.
- El módulo vivo `assets/hoy-DYWEcfn2.js` conserva «Hoy, tres cosas» y F4.3 del supervisor, pero no contiene «Tu siguiente movimiento», «Después en tu agenda» ni «Tu cartera en contexto» del vendedor. El módulo vivo `assets/derivaciones-BaJuA37j.js` tampoco contiene la paginación de [[Derivar leads del supervisor - paginacion compacta]].
- La secuencia completa fue: `d4a5416` publicó la paginación a las 10:11; `9081334` publicó además el teléfono alternativo a las 10:56; aproximadamente tres minutos después, el release paralelo de `1dd89bf` repuso una base que no contenía ninguna de esas dos ramas ni la portada de `c79d54a`.
- No es un problema de caché ni del rol del usuario: el HTML y `version.json` se sirven sin caché y el artefacto activo carece realmente del código nuevo.
- Restauración publicada aproximadamente a las 13:00 (hora de Lima), tras la invocación humana obligatoria `/release-crm`: `f924b91` integra `1dd89bf`, `9081334`/`d4a5416` y `c79d54a`. Artefacto `crm-20260824T175707Z-f924b91ad677`, build `build-20260824T175706731Z`, SHA-256 `2e6d2f8bdf2593f5c19c0cc84f48d8eb028b72a038ae699055a9d20a029f1b5d`; 2.224 pruebas y 9 E2E en verde. Producción quedó en ese build, 58/58 archivos no transformados coincidieron byte por byte con el manifiesto y el chunk vivo contiene simultáneamente vendedor, F4.3 del supervisor y la paginación de Derivar.

## Segunda regresión el mismo día — 2026-08-24, ~13:27 (hora de Lima)

- El 37.º release (`90b90e2`, F4.4 del supervisor, build `build-20260824T182716934Z`) salió de `feat/hoy-supervisor-sin-ruido` sin descender de la restauración `f924b91` y volvió a pisar la portada del vendedor, la paginación de Derivar (`d4a5416`) y el teléfono alternativo (`9081334`). Verificado en el chunk vivo `hoy-uMcgLjBk.js`: cero señales del vendedor. Segundo episodio en 24 horas de la misma causa: cada release repone el sitio entero y la regla de ascendencia del ledger no se aplicó.
- Arreglo preparado y verificado la misma noche (sin desplegar aún, por orden de Miguel): merge `b3f6e98` = `90b90e2` + `f924b91`, cero archivos solapados, gate 2.243/2.243 + E2E 9/9, artefacto `crm-20260825T005045Z-b3f6e98f9f15` (SHA-256 `402b1d9c7e0c5d0ca8adc86e4b43ae430f3abbb4496e114936a44693b89f47fc`) con todas las señales de vendedor, supervisor F1–F4.4, Derivar y teléfono alternativo dentro del ZIP, conservado en `releases/`. Producción sigue intacta en `90b90e2`. Continuación: código `RETOMAR-55`.
- **CERRADO 2026-08-25 (~10:04, hora de Lima):** ese mismo ZIP se desplegó como **38.º release** sin reconstruir nada. Antes de subir: prod seguía en `build-20260824T182716934Z` (nadie publicó en paralelo) y el SHA-256 y las señales dentro del ZIP se re-verificaron. En vivo: `version.json` = `build-20260825T005045176Z`, 58/64 archivos al byte (las 6 diferencias son los falsos positivos permanentes del método), las 5 señales del vendedor presentes en `hoy-DNJIiTvG.js`, `derivaciones-L48j9Z25.js` 200, ZIP 404. La portada «Ahora y Después», la paginación de Derivar y el teléfono alternativo conviven ya con el supervisor F1–F4.4. Detalle en el ledger de [[Deploy a Hostinger]].

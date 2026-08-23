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

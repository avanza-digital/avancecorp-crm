# Apoyo de Jev al cierre F4 — 22/09/2026

Miguel pidió usar Jev para acelerar decisiones y clasificar pendientes. Se consultó `jev-latest`; respondió `jev-1.13.0` en 2191 ms. Consumo: {'input_tokens': 2747, 'output_tokens': 753}. Solo recibió descripciones técnicas; no datos de clientes, código privado ni secretos.

La clasificación organiza el trabajo. No certifica seguridad, corrección, permisos ni PASS de pruebas. Se mantienen las decisiones explícitas del usuario y la revisión técnica del PRIMARY.

| Pendiente | Grupo propuesto | Confianza |
|---|---|---|
| Agrupar inactividad, tareas vencidas, primer intento y reparto usando núcleos existentes; evitar duplicados entre campana y Gestión Diaria. | construir | 0.94 |
| Mostrar primera llamada y cuántos analistas han llamado, sin inferir feriados. | construir | 0.46 |
| Probar reconocimiento y aplazamiento desde dos sesiones simultáneas reales. | comprobar | 1 |
| Probar permisos HTTP por identidad, equipo ajeno y pérdida de acceso. | comprobar | 0.99 |
| Verificar popup, foco, texto legible y uso móvil con navegador. | comprobar | 1 |
| Comparar tipos generados del servidor y ejecutar gates completos. | comprobar | 0.99 |
| Obtener revisión final de Claude con dictamen recuperado y resolver hallazgos con evidencia. | comprobar | 0.99 |
| Conciliar historial SQL instalado con archivos sin reinstalar migraciones. | entregar | 0.85 |
| Integrar avancecorp/main y preparar artefacto exacto con respaldo y autorización de publicación. | entregar | 0.97 |
| Activar cortes desde jornada futura autorizada y observar esa primera jornada. | entregar | 0.98 |
| Tasa muy baja: Miguel ordenó mantenerla apagada hasta F5; validación y pantalla ya lo imponen. | resuelto_o_fuera | 0.93 |
| F4.1 TypeSafe dentro del producto queda fuera del objetivo actual. | resuelto_o_fuera | 0.99 |
| Dos avisos INFO de índices revisados: no hay necesidad medida; conservar seguimiento. | resuelto_o_fuera | 0.95 |

**Evaluación del PRIMARY:** aceptadas las categorías para ordenar el trabajo. El contexto de primera llamada obtuvo 0,46; se conserva como implementación obligatoria porque el plan lo pide y falta en la pantalla. Los dos INFO de índices quedan en seguimiento, sin convertirlos en solucionados. No se descarta ninguna verificación por el juicio de Jev.

Guía consultada: [API TypeSafe](https://docs.typesafe.ai/api), [clasificación](https://docs.typesafe.ai/primitives/choice). Herramienta reutilizada: `CRM-Avance-Corp/scripts/jev/cliente.mjs`. Estado y probabilidades completos conservados localmente en `/private/tmp/gd-f4-jev-triaje.json`.

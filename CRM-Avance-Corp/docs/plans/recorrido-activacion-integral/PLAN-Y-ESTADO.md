# Puesta en marcha del recorrido: primeras conversiones pendientes

Plan aprobado por Miguel el 19/10/2026: «ok comienza, y dejame este plan en figma, y que pueda ver el progreso».
Continúa el trabajo integrado en PR #331 / Main `3797e6affbed6e97d7ceae00ce0bdc01ae4f2248`. No confundir el Goal previo hasta ZIP con el objetivo comercial operativo.

## Objetivo y alcance aprobado

Impedir toda primera conversión pendiente, de leads nuevos y antiguos, sin asistencia y entrevista con resultado de la misma cita del ciclo vigente. Reutilizar evaluador, cierres, oficina, borradores y controles financieros actuales. Gestión y contacto orientan; no añaden un bloqueo. Cambiar de columna no acredita hechos.

Inversiones confirmadas conservan sus resultados, auditoría y reintentos. Inversiones adicionales, renovación y upgrade de clientes conservan su flujo. No fabricar datos históricos, no backfill de asistencias y no marcar entrevistas en lote. Los registros anteriores sin evidencia suficiente siguen pendientes de comprobación; instalación no los convierte en cumplidos.

El inicio de exigencia es una fecha de activación del control para toda primera conversión pendiente, no una exención según antigüedad del lead. Se conserva el contrato público vigente y la fecha inmutable de primera activación. Una programación futura no bloquea antes de esa fecha. La reversión cambia modo y conserva evidencia.

## Fases

Cada fase tiene 6 subfases. Se cierra tras revisión Codex, corrección y revalidación; los porcentajes representan subfases acreditadas, no tiempo.
1. Alcance y diagnóstico: política → censo → contratos vivos → rutas → dependencias/entorno → revisión documental.
2. Completar regla: migración aditiva → lectura coherente → borradores/reintentos → activación/reversión → permisos/hardening → revisión y correcciones.
3. Pruebas locales: SQL → Auth/HTTP/RLS → UI/E2E Docker → históricos/ausencias → concurrencia/regresión → revisión y correcciones.
4. Ensayo hosted: costo autorizado → rama propia → instalación → matriz RLS → advisors/reversión → revisión y correcciones.
5. Revisión e integración: Claude crítico → PR → CodeRabbit → corregir/revalidar → Main verificado → paquete exacto.
6. Instalación en observación: paquete productivo autorizado → preflight → merge de base → postflight → guía por roles/capacitación → revisión y correcciones.
7. Exigencia: responsable/motivo → control vigente → activar alcance aprobado → rechazos → camino válido/reversión → revisión y correcciones.
8. Aceptación y cierre: negativo sin hechos → positivo misma cita → antiguos cubiertos → reintento sin duplicado → evidencia/capacitación/Figma → revisión final.

## Estado

- Fase 1: PASS documental / 6 de 6. Ver FASE-1-DIAGNOSTICO.md y evidencia.
- Fase 2: PASS local / 6 de 6. Ver FASE-2-REGLA.md.
- Fase 3: PASS local / 6 de 6. SQL, 81 comprobaciones Auth/HTTP/RLS y 42 E2E Docker; ver FASE-3-PRUEBAS.md.
- Fase 4: PASS / 6 de 6. Instalación de 13 migraciones, 81 HTTP/Auth/RLS hosted, reversión y advisors evaluados; ver FASE-4-ENSAYO-HOSTED.md.
- Fase 5: PASS / 6 de 6. Claude entregó CHANGES_REQUESTED; observaciones evaluadas y corregidas, 99 HTTP/Auth/RLS locales y hosted PASS. [PR #332](https://github.com/avanza-digital/avancecorp-crm/pull/332) integrado; CodeRabbit reconoció la corrección, CI PASS y ZIP exacto verificado desde Main `3d5c040d`. FASE-5-REVISION.md conserva la revisión previa al merge.
- Fase 6: PASS / 6 de 6. Autorización exacta recibida; merge Supabase, 15 migraciones e instalación en observación verificados.
- Fase 7: PASS / 6 de 6. Exigencia activa desde 19/10/2026 09:44:22 Lima, revisión 2. Cien rechazos productivos sin escrituras y guía validada por roles; camino positivo/reversión acreditados en banco.
- Fase 8: EN CURSO / 4 de 6. Falta una primera conversión comercial real con cita/entrevista acreditadas y la aceptación del equipo. No se inventan hechos para cerrar el plan.
- Total: **46/48 subfases (95,8 %), 7/8 fases cerradas**. [Acta productiva y límites de la evidencia](FASES-6-8-PRODUCCION.md).
- Producción: **15/15 instaladas, guía disponible, bloqueo activo**, modo `exigir`, revisión 2. Nuevos y antiguos pendientes incluidos.
- Figma: sección comercial 72:190 del mismo archivo, separada del desarrollo técnico 46:190.
- Código integrado: Main `3d5c040d9feac7d15f7c24a037188bb5ac62f148`, copia aislada existente. Taller compartido preservado.
- Banco local propio existente disponible: `supabase_db_avancecorp-recorrido-lead-20261018`.
- Organización confirmada por Miguel: `AVANCECORP- CRM-PORTAL`. Cotización: US$0.01344 por hora. Gasto y creación autorizados: «Sí, hasta 24 horas». Rama `recorrido-integral-20261019` creada el 19/10 a las 06:29 UTC; **eliminada y ausencia verificada el mismo día a las 14:50 UTC**, dentro del plazo. Limpieza programada retirada.
- SQL exacto presentado y autorizado por Miguel: «ok hazlo tienes aprobacion». Instalación y activación ejecutadas; actuación técnica auditada con la cuenta administrativa.

## Aceptación final

No se cierra por PR, ZIP o instalación en observación. Se exige evidencia de: sin asistencia/entrevista no convierte; misma cita/ciclo válido permite continuar; antiguos incluidos; permisos conservados; reintentos sin duplicados; guía operativa y protocolo de reversión probado.


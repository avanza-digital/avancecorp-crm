---
fecha: 2026-09-11
estado: implementado-local-sql-pendiente-de-autorizacion
tags: [crm, citas, gerencia, superadmin, configuracion, metricas]
---

# Citas Gerencia — control de Superadmin en borrador

Miguel pidió un panel en su usuario de Superadmin para configurar las metas y reglas del Excel. Se implementó localmente la pantalla `#/config-citas`, su acceso exclusivo y un candidato SQL de guardado con historial. El alcance comunicado es **guardar borradores**: no activa reglas ni modifica los cálculos actuales de Citas.

## Reglas confirmadas y decisiones pendientes

- Meta inicial interna: **1,25 citas por lead**, sin mostrar ese objetivo al cliente.
- Objetivos iniciales: **70% de entrevistas y 70% de depósitos**.
- La base incluye todos los leads asignados al analista en el mes, incluso sin citas; excluye inicialmente los registrados manualmente por el propio analista. El panel permite configurar esa exclusión.
- Depósito acreditado por conversión a cliente, conservando la definición acordada.

Siete decisiones empiezan sin seleccionar: participación de la actividad de leads manuales, conteo de entrevistas, base del avance de entrevistas, base de depósitos, mes de atribución, analista de atribución y mes de inicio previsto. Se pueden guardar borradores incompletos; una opción propuesta no equivale a una decisión confirmada. La base de depósitos propone personas únicas entrevistadas, pero sigue en «Por definir».

La configuración es global, sin excepciones por analista en esta entrega. El ejemplo de citas usa 100 leads asignados y 20 manuales: 80 válidos × 1,25 = 100 citas. Para este ejemplo operativo se redondea hacia arriba; aún no se ha conectado la proyección de entrevistas o depósitos con datos reales.

## Uso y límites actuales

Vista de prueba: <http://127.0.0.1:4180/prototypes/control-citas.html>. Usa los componentes y estilos existentes del CRM: tres metas horizontales, ejemplo compacto y reglas desplegables. Conserva los borradores solamente en la pestaña del navegador; no utiliza la sesión ni datos reales.

En la aplicación, Superadmin sin Gerencia tiene «Control de Citas» en el menú. Superadmin con Gerencia lo encuentra en Configuración. Otros roles y sesiones demo no pueden leer o guardar mediante los RPC. Si falta instalar el SQL, la pantalla real lo indica; no simula un guardado exitoso.

El editor conserva cambios al recargar la consulta o recibir un conflicto. Cargar otra versión con cambios sin guardar requiere una decisión expresa de descartarlos. El historial muestra las últimas 20 versiones, aunque la tabla conserva todas.

## Candidato de base de datos

Archivo: `CRM-Avance-Corp/supabase/migrations/20260911212756_crm_control_citas_superadmin_borradores.sql`.

Agrega `crm.control_citas_versiones` y dos funciones de lectura/guardado. Incluye verificación de Superadmin activo, validación estricta, bloqueo de concurrencia, auditoría e historial inmutable. No altera tablas operativas, los helpers existentes ni los lectores de Citas. El autor se conserva con referencia al perfil; se permite desactivarlo, pero no borrar físicamente un autor con historial asociado.

**No aplicado en producción ni en una rama remota. No publicado ni comprometido en Git en esta entrega.** Primero debe presentarse el SQL y obtener la confirmación exigida por [[Inicio]]. Después corresponde ensayarlo en una rama autorizada, ejecutar los gates de base de datos, regenerar tipos y seguir la publicación desde Main verificado. La activación de nuevas métricas requiere completar sus definiciones y desarrollar su cálculo; instalar este SQL sólo habilita borradores compartidos.

## Verificación

Evidencia y guía: `UX-UI-GERENCIA/control-citas-superadmin-2026-09-11/README.md`.

- `npm run check` final: **PASS**, 238 archivos y 3.426 pruebas; controles estáticos, cobertura, construcción y gates incluidos por ese comando.
- Banco PostgreSQL 17 aislado: **PASS**, permisos, validación, concurrencia, auditoría, historial y conservación del autor.
- Suite de navegador anterior a los ajustes de revisión: **175 PASS, 26 SKIP**. Después de los ajustes: **5 PASS** en los flujos afectados de Control de Citas y Superadmin.
- Capturas de escritorio y móvil: sin errores de JavaScript, llamadas de autenticación/CRM ni desbordamiento horizontal en la vista de prueba.
- Claude actuó como revisor independiente mediante el wrapper del repositorio. Emitió observaciones; Codex evaluó, corrigió y verificó los cambios. No se atribuye un PASS posterior a Claude.

**NOT RUN:** `gate:realidad` por falta de `SUPABASE_URL` en ese comando; ensayo en rama remota, matriz RLS completa y advisors de esa rama, regeneración completa de tipos desde el catálogo nuevo, instalación y navegador autenticado en producción. El banco local mínimo no sustituye esas verificaciones.

## Aclaraciones posteriores y propuesta de proyección

Miguel confirmó que una cita generada en el CRM pasa a entrevista cuando la persona asiste, y que desea medir la conversión posterior a cliente de los entrevistados como depósito. Pidió ver además el cierre mensual proyectado con las tasas actuales y el ticket de cada analista. La definición de visitas repetidas y las bases de proyección siguen pendientes. Se preparó una visualización sin cambiar los borradores ni el módulo: [[Citas Gerencia - avance y proyeccion mensual por analista 2026-09-11]].

Relacionado: [[Citas Gerencia - analisis del Excel de proyeccion por analista 2026-09-10]], [[Citas Gerencia - cierre de sesion y punto de retoma 2026-09-09]], [[Citas Gerencia - deposito acreditado por conversion a cliente 2026-09-08]].

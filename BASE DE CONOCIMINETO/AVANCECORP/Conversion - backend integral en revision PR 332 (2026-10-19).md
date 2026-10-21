---
tags: [crm, conversion, backend, en-curso]
actualizado: 2026-10-19
---

# Conversión — backend integral preparado para activación

**Actualización posterior: instalado y activo desde 19/10, 09:44 Lima.** Ver [[Conversion - exigencia activa en produccion (2026-10-19)]]. Esta nota conserva el estado anterior a la autorización; la rama temporal ya fue eliminada y su tarea de limpieza retirada.

Miguel aprobó iniciar la puesta en marcha y ver su avance en el mismo Figma. Incluye todas las primeras conversiones pendientes, de leads nuevos y antiguos. Sin asistencia y entrevista con resultado de la misma cita y ciclo vigente no se convierte. No requiere n8n. No inventar visitas históricas ni conceder una excepción a los 78 ambiguos del censo.

**19/10, 08:49 Lima: fases 1–5 cerradas; instalación y activación pendientes de confirmación del SQL exacto. Producción sigue SIN backend del recorrido, guía oculta y bloqueo inactivo (0/15 migraciones), verificado nuevamente mediante preflight de solo lectura.** El frontend del PR #331 está publicado; eso no instaló SQL ni activó la regla.

[PR #332](https://github.com/avanza-digital/avancecorp-crm/pull/332) fusionado por Miguel el 19/10 a las 13:43:22 UTC. Main local aislado = `avancecorp/main` = `3d5c040d9feac7d15f7c24a037188bb5ac62f148`, árbol limpio y contenido idéntico al head probado. CI final y CodeRabbit PASS; observación del postflight corregida y reconocida. [Figma comercial](https://www.figma.com/board/kg289vO84cJjFMCuBJbqhM?node-id=72-190): cierre técnico para 30/48 subfases, 62,5 %, 5/8 fases. Capacitación vigente en `39:190`, con enlaces desde ambos planes.

ZIP exacto de backend: `/Users/usuario/Downloads/CRM-recorrido-backend-20261019/20261019T134726Z-3d5c040d9fea.zip`. SHA256 `def103d06cc162995e64bb3028a56922dfdcc3ced3d0be16dce5e9ba98d0d822`. Contiene 15 migraciones y 27 archivos; integridad y todas las huellas verificadas. No es un ZIP para Hostinger. El directorio homónimo contiene SQL de instalación, activación, reversión, comprobaciones y capacitación. El paquete conserva las notas versionadas previas al merge como historial; este estado y Figma reflejan el cierre posterior.

## Verificación

- 99 comprobaciones Auth/PostgREST/RLS locales y 99 en rama Supabase; 42 E2E Docker. SQL de negocio, concurrencia, reintentos y reversión PASS.
- PostgreSQL local 17.6 igual que producción; rama administrada 17.11. Se conserva el fallo del replay vacío histórico (datos necesarios en migración 86); reconstrucción mediante paridad manual ya acordada y ledger exacto 509. Las 15 candidatas dejan 524 migraciones en la rama.
- Claude entregó CHANGES_REQUESTED. Codex probó que descartar/inactivar un lead con borrador no elude el contexto financiero. Corrigió los conflictos deterministas de acceso a PT409 y la fecha, que solo se fija al exigir. No se cambió el dictamen de Claude a PASS.
- Preflight productivo de solo lectura: seis contratos anteriores e historial coinciden. Sin SQL productivo ejecutado.
- CodeRabbit pidió comprobar identidad completa de las 15 migraciones e índice real, además del conteo. Corregido: versión, nombre, contenido y validez del índice. Cinco regresiones locales PASS. Revisor reconoció la corrección e hilo resuelto.

## Rama temporal y retoma

Miguel autorizó US$0.01344/h hasta 24 h. Rama propia `recorrido-integral-20261019`, id `c42dac35-1185-40b9-9e24-5961e9c29981`, ref `zwnecxkwsxzybefmdrut`. Creada el 19/10 a las 06:29 UTC; eliminar al terminar y antes del 20/10 a las 06:29 UTC. No tocar otras ramas.

Respaldo local de limpieza registrado y validado: LaunchAgent `com.avancecorp.recorrido-temporal-20261019`, script privado `/private/tmp/recorrido-integral-hosted-20261019/limpieza-plazo.py`. Retiro programado el 20/10 a las **05:29 UTC** (23 horas), con tres intentos máximos cada cinco minutos. Identidad exacta de rama/ref/proyecto/nombre verificada; nunca selecciona Main ni otras ramas. Estado en `limpieza-plazo-estado.json`. Este respaldo requiere que el Mac y la conexión estén disponibles; el PRIMARY debe eliminar y verificar al terminar, sin esperar al temporizador. La tarea se retira al comprobar eliminación. No imprimir `launchctl print` completo: puede incluir variables sensibles heredadas.

Implementación aislada: `/private/tmp/hoy-supervisor-goal-20261018/candidato-main`, ahora en `main` verificado. Evidencia versionada en `CRM-Avance-Corp/docs/plans/recorrido-activacion-integral/`. Credenciales y capturas fuente solo en carpeta privada fuera del repo.

Sigue: confirmación productiva del SQL exacto ya presentado → instalar en observación → activar con responsable/motivo → aceptación y limpieza de la rama temporal. No dar por cumplido el objetivo comercial por crear el ZIP. La activación técnica propuesta usa la cuenta administrativa y requiere autorización expresa del paquete y la activación, sin presentarla como login humano. La confirmación está pendiente; ni el merge del PR ni el permiso de costo equivalen a ejecutar este SQL productivo.

Relacionadas: [[Conversion - plan por fases y objetivo goal (2026-10-18)]] · [[Conversion - recorrido obligatorio por hechos (propuesta 2026-10-12)]] · [[Etapas del CRM - mapa de funcionamiento (2026-10-12)]].

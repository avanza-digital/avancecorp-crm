---
tags: [crm, gerencia, metricas, deploy, main]
fecha: 2026-09-04
estado: publicacion-autorizada-en-preparacion
---

# Publicación del frontend de métricas de Gerencia

Relacionado con [[Plan de correccion de metricas de Gerencia - requerimiento vigente]], [[Correccion de pantallas de Gerencia - punto 2 - 2026-09-04]], [[Correccion de Cartera - punto 3 - conciliacion y SQL pendiente 2026-09-04]], [[Main unico - sincronizacion y publicacion 2026-09-04]] y [[Deploy a Hostinger]].

## Autorización y alcance

Miguel pidió «commit a todo y deploy al frontend» después del cierre del punto 3. Se autoriza guardar el trabajo actual, sincronizar Main con `avancecorp/main` y publicar exclusivamente el frontend del CRM en `crm.miavance.com`.

- Incluir las correcciones y pruebas de Gerencia/Cartera, el inventario y requerimiento, y el trabajo concurrente presente en Main, sin sobrescribirlo.
- El SQL del punto 3 ya está aplicado como `20260905034917`; **no reaplicarlo**. Guardar archivos SQL o tipos generados no autoriza ejecutar migraciones adicionales.
- No publicar el portal `miavance.com`, no modificar autenticación, núcleos, permisos, Edge Functions ni datos de negocio.
- No crear ramas ni forzar historia. Confirmar el mismo commit local/remoto antes de construir y publicar un artefacto limpio de ese commit.
- Los puntos 4 y 5 del plan siguen pendientes; esta publicación no los da por resueltos.

## Línea base y reversión

Al comenzar, Main local estaba en `ed2b7ea` y `avancecorp/main` en `c477fec`; la actualización remota no encontró cambios divergentes. Se preserva el commit concurrente «Altas nuevas por analista» y los archivos locales.

El servidor estaba sirviendo `build-20260905T011157779Z`, correspondiente a `b8108ae3f4dca59be3c833ed039ca819235da6dd`.

Reversión frontend disponible fuera del directorio público:
`CRM-Avance-Corp/releases/crm-20260905T011158Z-b8108ae3f4dc.zip`, SHA-256 `c9fdcb382438a9f7d0eac3415942c16cd4075d82d2fcb15b171f6158f151a8a2`, con manifiesto hermano. No se revierte la exclusión SQL de pruebas por revertir el frontend.

## Comprobaciones previas

- La entrega local aprobó 2.741 pruebas y 120 E2E (26 omisiones previas) sobre una huella estable de código; tipos, build, bundle y duplicación aprobados.
- Revisión acotada de secretos en los 66 archivos modificados/no versionados iniciales: ninguna llave privada, token de GitHub, llave secreta Supabase ni JWT `service_role` detectado. No equivale a una auditoría integral de secretos.
- Configuración pública productiva presente y del proyecto correcto; credencial de rol `anon`, sin exponer su valor. La configuración se comprobará nuevamente dentro del artefacto final.
- Context7 confirmó que Vite fija la configuración al construir y que la preview debe usar el `dist` producido. La guía de Supabase orienta la exclusión de llaves privilegiadas; Browser se usa para revisar acceso e interfaz, no para extraer credenciales.

## Resultado

Pendiente: commit y sincronización, gates del commit candidato, artefacto, comprobación de acceso, publicación y verificación remota. Completar este apartado con la evidencia real antes de declarar el deploy terminado.

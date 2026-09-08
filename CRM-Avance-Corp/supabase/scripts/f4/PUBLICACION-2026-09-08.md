# Publicación F4 — 08/09/2026

Miguel autorizó «publica f4 y dame el plan de implementacion para f5». El alcance
es instalar el motor de F4 y entregar el plan de F5. El encendido comercial
conserva las puertas G5/G6/G7 del plan maestro. Las comisiones son externas.

## Artefacto exacto

- Instalar únicamente `20260908211349_crm_f4_publicacion_compatible_rentabilidad.sql`.
- SHA-256: `f0f28b032cfa7c4b65dc6734fb359e263f0feebaf174bf25537a215628a434ae`.
- La candidata técnica `20260907191832_crm_f4_inversiones_base_y_escritores.sql`
  conserva su huella y pruebas históricas; quedó sustituida **sin aplicación
  productiva**. No ejecutar ambas, `db push` ni reparar el historial para fingir
  que la candidata anterior se aplicó.
- `ultima-migracion.json` identifica el banco técnico original. No se reutiliza
  como selector de producción; esta publicación usa el nombre explícito anterior.

## Compatibilidad verificada

El preflight original detectó dos diferencias reales: el wrapper PDF vigente
propaga el origen de los aumentos para Rentabilidad R4, y la corrección documental
se restringió a Administración. `generar-publicacion.mjs` conserva ambas y las
valida contra capturas saneadas. De las 48 funciones, 47 permanecen idénticas a
la candidata técnica. La función documental no se modifica.

```sh
node CRM-Avance-Corp/supabase/scripts/f4/generar-publicacion.mjs CRM-Avance-Corp/supabase/migrations/20260908211349_crm_f4_publicacion_compatible_rentabilidad.sql
F4_BANCO=reconstruccion node CRM-Avance-Corp/supabase/scripts/f4/probar-publicacion.mjs
```

El ensayo crea otra copia sintética PRE-F4, incorpora las migraciones ya
publicadas R3/R4, tasa pendiente y PDF v8, y aplica la revisión completa. Prueba
conservación de fuentes, 48 cuerpos, RLS/ACL de siete tablas, instalación repetida
rechazada, flags apagados, retiro de F2 global, alta y aumento con Rentabilidad
enforcement, reintento sin duplicación y revisión obsoleta rechazada. Ver
[`publicacion-2026-09-08/ensayo.json`](publicacion-2026-09-08/ensayo.json).

## Secuencia de publicación

1. Respaldo privado de esquema y datos de producción, incluidos Auth y metadatos
   de Storage: 122 tablas, huellas verificadas. Conservar el ZIP/manifiesto
   actualmente publicado y el trabajo local no confirmado.
2. Commit del paquete revisado. Integrar Main sin perder cambios ajenos,
   sincronizar solo `avancecorp/main` y comprobar igualdad de commit.
3. Construir desde un checkout limpio de ese commit; validar ZIP, configuración
   pública, manifiesto y ausencia de rutas internas. Publicar el frontend compatible.
4. Aplicar exclusivamente la revisión SQL anterior y desplegar
   `crm-contrato-pdf-v2` y `crm-inversion-portal`, ambos con verificación JWT.
5. Comprobar cuerpos/propietarios/permisos, fuentes económicas, PDF v8,
   Administración, asesores de base y versión/archivos públicos.

F3 queda encendida; `inversiones_escritura` y `ficha_360_neutral` quedan apagadas.
No se ejecuta backfill económico en esta publicación. F2 global se retira incluso
apagada: cualquier completado histórico posterior exige censo vigente y lotes
administrativos de como máximo 100 fuentes.

Recuperación: apagar flags y conservar los datos; nunca una migración DOWN que
borre inversiones. El ZIP anterior se conserva fuera del directorio público.
El respaldo SQL no equivale a una restauración completa de producción ensayada;
la restauración probada en G4 fue sintética.

El resultado real de la publicación se registra después de verificar el servidor.

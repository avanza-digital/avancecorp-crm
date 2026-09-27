# supabase/migrations/ — migraciones del esquema `crm`

## ⚠️ Antes de añadir una clave a un payload: ¿quién envuelve a esta función?

**Pagado el 23/09/2026 con 13 minutos de Metas y Ranking caídos.** Se declaró
`crm.cumplimiento_metas_sin_cartera_fn` tras comprobar que no tiene consumidor
en el front — cierto. Pero `crm.cumplimiento_metas_fn` **construye su payload
sobre el de esa**, y esa sí tiene consumidor, con `v.strictObject`. Cuatro
claves desconocidas y valibot rechazó el paquete entero.

Un `grep` en `app/src` ve quién LLAMA a la RPC; no ve quién HEREDA su forma
dentro de la base. Antes de declarar, correr:

```
supabase db query --linked --file supabase/scripts/conversion/quien-me-envuelve.sql
```

Y para **cada** envoltorio que salga, mirar su esquema del front **en el commit
publicado**, no en el árbol:

```
git show <commit vivo>:CRM-Avance-Corp/app/src/lib/<modulo>.ts
```

`v.object` ignora lo que no conoce; `v.strictObject` tumba el payload entero. El
commit vivo sale de `version.json` → `buildId` → manifiesto en `releases/`.

🔑 **El síntoma que delató el fallo:** en el censo final, una puerta que nadie
había tocado apareció declarando. Una función que cambia sin que la toques es la
señal de que hay herencia.

Contiene el historial versionado del esquema `crm`; `MIGRACIONES.md` registra
la intención, verificación y estado de producción de cada cambio.

Reglas heredadas del plan (§5, condiciones no negociables):

- Formato `AAAAMMDDHHMMSS_nombre.sql` + `MIGRACIONES.md` como ledger documentado (patrón VITANOVA).
- Todas las tablas nuevas en el esquema **`crm`**; helpers de visibilidad en **`private`**.
- **Ninguna migración altera tablas/triggers/policies de `public`** (el portal en producción).
- RLS ON en el mismo statement de creación; deny-by-default; soft-delete `activo=false` sin policy DELETE.
  Excepción ÚNICA documentada: `crm.recordatorios_disponibilidad` (nota personal efímera del vendedor,
  DELETE propio exigido por la spec §5.3 y auditado — justificación completa en `20260818045032`).
- Ciclo: branch de Supabase → aplicar → `supabase/scripts/test-rls.mjs` → advisors → merge. Nunca directo a prod.
- Tras cada bloque funcional: migración de hardening (search_path + revokes).
- Trigger de auditoría sobre toda tabla `crm.*` desde la primera migración: `private.log_audit_crm`, o
  `private.log_audit_sin_secretos` (con las columnas a enmascarar) si la tabla guarda secretos: tokens, claves, contraseñas o credenciales.

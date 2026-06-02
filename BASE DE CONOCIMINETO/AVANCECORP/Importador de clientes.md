---
tags: [feature, admin, excel]
actualizado: 2026-06-01
---

# Importador de clientes (Excel)

**Implementado 2026-05-26.** Alta **masiva** de clientes desde Excel en `/admin/clientes`: botón **Plantilla** (Excel de ejemplo + instrucciones) y **Importar Excel** (sube → preview con validación → crea en bloque).

## Cómo funciona
- Edge **`importar-clientes`** (`service_role`, `verify_jwt:true`): por fila crea `auth.user` + perfil con **todos** los campos (bancarios + asesor) en un solo insert. Clave temporal = DNI ([[Clave temporal = DNI]]), `debe_cambiar_password=true`, **sin correos** (decisión de Miguel).
- **`dry_run`**: valida sin crear (formato + duplicados intra-lote + contra BD, **correo case-insensitive**).
- Bancarios **obligatorios**; asesor **opcional** (match por nombre→id).
- Front `clientes.js`: valida en navegador, llama a la edge en **lotes de 25 en serie** con barra de progreso. **Idempotente** (reimportar omite los ya creados).
- **Probado en producción** (autorizado por Miguel): dry-run + alta real de 2 ficticios + reimport idempotente + limpieza.

## Notas relacionadas
[[Clave temporal = DNI]] · [[Arquitectura del portal]] · [[Inicio]]

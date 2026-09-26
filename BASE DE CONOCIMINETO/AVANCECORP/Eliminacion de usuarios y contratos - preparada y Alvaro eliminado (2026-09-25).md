---
tags: [crm, usuarios, contratos, permisos, auditoria]
fecha: 2026-09-25
estado: backend-instalado-pantallas-pendientes
---

# Eliminación de usuarios y contratos

Miguel solicita que Admin pueda eliminar contratos desde CRM/Portal con autoridad
en backend, y una función para eliminar usuarios del CRM exigiendo transferencia
de pendientes. Confirma expresamente: **conservar el nombre del autor del historial**.

## Operación urgente terminada

**ALVARO LEOMAR CCAHUANA ALHUIRCA fue eliminado de producción el 25/09.** Se verificó
identidad exacta, rol comercial/vendedor, cero seguimientos, actividades, leads,
tareas, clientes, archivos propios y otras referencias de negocio. Se utilizó
`crm.purgar_membresia_crm` existente, con auditoría, y se borró Auth en transacción.
Lectura posterior: Auth/perfil/equipo/sesiones 0; purga 1; cuatro eventos
administrativos previos conservados. No repetir esta operación.

## Backend instalado; pantallas preparadas

1. Contratos: el error de `2026-01-001471` no se debió a retirar el permiso de
   Admin. Un vínculo de cotitular originado en el alta se clasificaba como historial
   posterior. La migración nueva archiva ese origen antes de eliminar y conserva
   identidades/archivos. Se elimina el bloqueo viejo del portal para Admin con pagos.
   No se borró el contrato de la captura. El historial posterior y cierres quedan
   protegidos.
2. Usuarios: botón Eliminar, comprobación de pendientes, acceso a transferencia,
   confirmación del nombre y control de versiones. Vacío: borrado completo auditado.
   Con historia: acceso retirado, nombre/actividades conservados y oculto en el
   directorio. Protege cuentas Portal privilegiadas y la propia cuenta. Bloquea
   asignaciones concurrentes, reactivaciones y cambios del nombre histórico.

SQL: `20260925172955_crm_eliminacion_contrato_cotitular_alta.sql` y
`20260925180145_crm_eliminacion_usuarios_sin_pendientes.sql` en migraciones del CRM.
Ambos **instalados en producción por merge nativo**, tras aprobación «siii».
Lectura final 25/09, 15:34 Lima: 360 migraciones (358 previas intactas), cuerpos y
ACL exactos a la rama ensayada, triggers esperados y 21 Edge Functions idénticas.
El contrato `2026-01-001471` sigue presente; no se solicitó borrarlo en esta fase.

Pruebas: 17 SQL usuarios + 16 SQL contratos PASS, 47 pruebas dirigidas de frontend
PASS, 5 E2E Docker PASS, gate frontend 4.430 pruebas/TypeScript/build PASS. El gate
global de duplicación falla por archivos ajenos (incluye copias ` 2.tsx`/` 2.css`).
Revisiones independientes completadas y observaciones tratadas con pruebas.
Detalle, límites del banco y resultados de preflights:
`CRM-Avance-Corp/supabase/scripts/usuarios-eliminar/VERIFICACION.md`.

Rama remota: 33 SQL y 22 HTTP/PostgREST/Auth PASS. Verificados login/refresh
revocados, permisos del JWT anterior, autores preservados y rechazo de pendientes.
Advisors sin ERROR nuevo; INFO de tabla privada deny-all y dos WARN previstos
de RPC SECURITY DEFINER con Gerencia comprobada. Rama temporal eliminada y
ausencia confirmada; no se tocaron las ramas de otros trabajos.

Falta publicar pantallas; para CRM se requiere invocación humana `$release-crm`
según `CRM-Avance-Corp/CLAUDE.md`. El árbol compartido tiene trabajo simultáneo de
cuentas bancarias/ranking: preservar y no hacer commit global. No repetir las
migraciones instaladas ni la eliminación puntual de Álvaro.

Relacionados: [[Rol Analista]], [[Arquitectura del portal]],
[[Main unico - sincronizacion y publicacion 2026-09-04]],
[[P-0XX - cuentas compartidas CRM portal - S1 en rama (2026-09-25)]].

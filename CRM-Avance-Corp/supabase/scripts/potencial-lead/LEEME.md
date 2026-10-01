# 20260930213647_crm_potencial_lead — scripts de acompañamiento

Fase 1 del plan «Potencial del lead» (Frío · Tibio · Estrella), aprobado por Miguel el 30/09/2026.
Nota del vault: «Potencial del lead - Frio Tibio Estrella (2026-09-30)».

## Orden en producción (lo lanza Miguel con `!`, desde `CRM-Avance-Corp/`)

1. `supabase db query --linked --file supabase/migrations/20260930213647_crm_potencial_lead.sql`
   — aplica, en su propia transacción con `lock_timeout = 5s` (crea FK hacia `crm.leads` y
   `public.perfiles`). Preflight: objetos nuevos inexistentes, ayudantes presentes y huellas de
   `private.rol_crm` (`16960a2a…`) y `private.vendedor_ids_visibles` (`45ae492c…`) por md5 de
   cuerpo + DEFINER + volatilidad + configuración + dueño. Postflight (con `search_path` vacío):
   puerta DEFINER con EXECUTE solo authenticated, 4 privadas sin EXECUTE de la API, tablas y
   secuencia con dueño postgres y ACL solo de postgres (lista blanca) y cero permisos efectivos de
   anon/authenticated/service_role, policies exactas, 5 disparadores exactos
   (`pg_get_triggerdef`) y la bandera `potencial_lead` apagada.
2. `supabase db query --linked --file supabase/scripts/potencial-lead/registrar.sql` — fila en
   `schema_migrations` (statements = el archivo entero, md5 `f4087876…`). Idempotente.
3. `supabase db query --linked --file supabase/scripts/potencial-lead/verificar.sql` — solo
   lectura, termina en raise: marcas 0, eventos 0, bandera false, EXECUTE de la puerta
   `authenticated,postgres`, 0 EXECUTE ajenos en las privadas, 0 permisos API en las tablas,
   registro presente.
4. `supabase db advisors --type all` — ninguna clase nueva.

La bandera se enciende en la fase 3, cuando la pantalla esté publicada.

Reversa: `reversa.sql` (solo con las tablas vacías y la bandera apagada; conserva la fila de
`schema_migrations`: anotarlo en `MIGRACIONES.md`). ⚠️ Toma AccessExclusiveLock sobre `crm.leads` y
`public.perfiles` (lo exige el DROP de las FK; medido en el banco) ANTES de las tablas nuevas, con
`lock_timeout = 3s`: mientras dura nadie lee leads ni perfiles del portal. Correr en horario bajo y
reintentar si salta el timeout.

## Banco

Docker propio `avancecorp-potencial-20260930` (imagen `supabase/postgres:17.6.1.105`, puerto
55470 en loopback), esquema `public,crm,private` volcado de producción el 30/09 con paridad de
huellas: 280 funciones `crm` y 540 `private` idénticas (con el mismo `search_path`; el texto de
`pg_get_functiondef` cambia con él, por eso las huellas fijadas no lo usan).

Ciclo pasado (versión final, tras Codex r1 + r2 y auditor-rls r1): migración → repetida (se niega) →
reversa → reversa repetida (se niega) → migración → registrar ×2 (idempotente) → verificar.

`prueba-sintetica.sql` (como `supabase_admin`, deshecha): **75 de 75**. Roles (analista dueño,
supervisor, sub-supervisor, parqueo solo para supervisor, gerencia, coordinador, directorio, equipo
inactivo, analista desactivado tras marcar, sin sesión), lead ajeno/inactivo/inexistente/
convertido/descartado, bandera apagada y encendida, doble clic sin evento, reconfirmar pasado el
minuto reinicia `marcado_en`, historial en orden, marcar no toca `crm.leads.actualizado_en`
(sembrado en el pasado) ni crea `crm.actividades`, sin grants la API no lee y con un grant de prueba
la RLS filtra, escrituras directas denegadas, historial inmutable (UPDATE, DELETE, TRUNCATE),
reasignación (la marca viaja) y filas de `public.audit_log` con su autor.

`prueba-concurrencia.sh` (dos sesiones de verdad, mundo confirmado y limpiado): **11 de 11**.
A reasignación en vuelo → P0002 sin escribir y V1 esperó ≥ 1,5 s (prueba de que se cruzaron);
B descarte en vuelo → 22023 y esperó; C reversa frente a una marca sin confirmar → espera y se
niega, la marca sobrevive; D reversa frente a una marca a medio camino (FOR SHARE del lead y luego
escribe) → sin interbloqueo, se niega; E lead aún sin confirmar → P0002 sin escribir. Mutantes:
puerta sin `potencial_bloquear_lead` → 3 fallas (escribía con permiso caducado); reversa sin
candados → borra la marca confirmada; reversa con el orden viejo (tablas nuevas antes que
leads/perfiles) → `deadlock detected` y la reversa borra todo.
El caso «FOR SHARE no encontró fila y la fila se confirma antes de autorizar» (Codex r2 R2-1) no es
reproducible de forma determinista (ventana de microsegundos): lo cubre el código (sin fila bloqueada
→ P0002) y el caso E.

Mutantes de la migración, todos rechazados por su pre/postflight: privada sin revoke, SELECT a
authenticated, secuencia abierta, policy `using (true)`, disparador inmutable solo en UPDATE, sin
disparador de TRUNCATE, puerta INVOKER, bandera encendida, `private.rol_crm` alterado.
Mutantes de la lógica cazados por la sintética: cerrado pasa (3), parqueo sin exigir supervisor
(1), token NULL en vez de «ok» (29), sin antirrebote (7), no reinicia el reloj (1), gerencia pasa
en ayudante Y puerta (7). «Gerencia pasa» solo en el ayudante sobrevive porque la puerta vuelve a
exigir el rol (doble candado, a propósito).

⚠️ La imagen del banco trae un `auth.uid()` que solo lee `request.jwt.claim.sub`; el de
producción también lee `request.jwt.claims`. La prueba fija las dos.
⚠️ En este Postgres, llamar a una función SIN EXECUTE bajo `set role` tumba el servidor: los
permisos de las privadas se leen del catálogo, nunca se llaman.
⚠️ Riesgo residual documentado: una baja o un cambio de jerarquía en `crm.equipo` confirmado en el
mismo instante que una marca no se serializa con ella (la marca queda; el actor ya no la usa ni la ve).
⚠️ Fase 2 (caducidad): debe tomar el MISMO candado consultivo que `private.potencial_bloquear_lead`
antes de escribir, o el `nivel_anterior` de sus eventos puede salir falso.

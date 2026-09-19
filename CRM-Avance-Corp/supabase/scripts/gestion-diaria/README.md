# Gestión Diaria · Fase 1 — registro crudo de actividad

Estado: **ensayada en el banco local el 19/09/2026, pendiente de instalar en
producción** (acta en `../../migrations/MIGRACIONES.md`, entrada `20260919211958`).
Plan completo en `../../../docs/gestion-diaria/PLAN-POR-FASES-2026-09-19.md`.

## Qué entrega

`crm.registro_actividad_fn(p_desde, p_hasta, p_analista_ids, p_tipos, p_etapa, p_limite, p_antes_de, p_antes_id)`:
una página keyset `(creado_en desc, id asc)` de `crm.actividades` en una ventana
de días Lima, por analistas, tipos y etapa actual del lead, con `metadata`,
`creado_por`, `autor_nombre`, `metadata` por lista blanca de claves y la **etapa del lead en ese momento** (último
`cambio_etapa` anterior, por `metadata->>'etapa_nueva'`). SECURITY INVOKER: el
alcance lo ponen `actividades_select` y `leads_select`; 42501 explícito si un
analista pedido no está en el roster visible, para el coordinador y para un
analista dado de baja. Sin `count(`: el front pide `limite + 1`.

Índice nuevo `actividades_autor_fecha_idx (creado_por, creado_en desc, id)`.
Gate propio `private.assert_gestion_diaria()` (forma, ACL, índice, huellas de
las dos policies vía `private.assert_actividades_de_lead_base()`) más el md5 del cuerpo del núcleo) y sus 10 mutantes (solo banco: exigen `set gestion_diaria.banco = on`).

## Ensayo local

```bash
node supabase/scripts/gestion-diaria/ensayar.mjs [--historial <ruta a 20260919185718_crm_actividades_de_lead.sql>]
```

Crea la copia `gestion_diaria_20260919` desde `cartera_procedencia_20260919`
(como `supabase_admin`), instala si falta el historial por lead (prerrequisito:
`private.nombre_de_autor` y `private.assert_actividades_de_lead_base`, migración
`20260919185718`, ya en producción; en git llega con la PR #28), mide el censo analítico, instala la migración,
corre el gate, los mutantes y el oráculo por actor (`test-gestion-diaria-registro.sql`:
validaciones 22023, coordinador/inactivo 42501, gerencia = directorio = todo lo
de leads activos, analista solo lo suyo y solo su id, supervisor su subárbol
anidado y nunca otro equipo, cursor sin repetir ni saltar, filtros, etapa en ese
momento coherente con `etapa_anterior` y un caso ESCRITO (una llamada que sube el lead se ve en «nuevo»), metadata por lista blanca, anon sin EXECUTE, sin `count(`),
comprueba el censo intacto, ensaya `reversa.sql` y reinstala. Escribe
`verificacion.json` y genera `../registrar-20260919211958.sql`.

## Publicación y reversa

1. Miguel instala `20260919211958_crm_gestion_diaria_registro.sql` con
   `!npx supabase db query --linked --file …`, luego el registrador, y anota el
   acta. Prerrequisitos en producción: `private.nombre_de_autor(uuid)` y
   `private.assert_actividades_de_lead_base()` (20260919185718, ya están).
2. Front publicado después (RPC nueva: SQL primero).
3. Reversa: retirar el front y ejecutar `reversa.sql` (solo borra objetos nuevos).

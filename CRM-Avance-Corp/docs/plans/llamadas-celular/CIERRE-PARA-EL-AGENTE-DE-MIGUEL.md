# Cerrar «Llamadas desde el celular» — guía ejecutable para el agente de Miguel (05/10/2026)

**Para quién:** el agente que trabaja con Miguel en su máquina (con su banco, sus llaves y Codex). **Qué es:** el orden
exacto para llevar a producción lo que está listo, con los comandos, lo que se espera ver y qué reportar. Todo lo
técnico de detalle ya está escrito en `PUBLICAR-F2-F3.md` (producción) y `supabase/scripts/LEEME-seed.md` (gate); aquí
se ordena en una sola secuencia. **Si algo de esta guía choca con esos dos, mandan ellos y se avisa en el PR.**

## Estado al 05/10, 22:45 UTC

| PR | Qué es | Estado | Bloqueo |
| --- | --- | --- | --- |
| **#190** | Siete migraciones de llamadas, la Edge, el gate y las guías | Tu agente cerró el último P2 (18:46 UTC). Atrás de `main` por #194 y #196, sin conflictos | **Paso 1** de esta guía |
| **#193** | F4-b parte A: el id de la llamada viaja hasta la encuesta (solo pantalla) | Listo. Atrás de `main`, sin conflictos | Tu aprobación (paso 2) |
| **#195** | Octava migración: lecturas de F4-b | Tu revisión (22:00 UTC) pidió paginar y definir «hoy». **Jhosep decidió:** paginar como la bandeja y «hoy» = **lo resuelto hoy**. Va en una **novena** (la octava no se edita) | Espera al #190 y a la novena (paso 3) |
| *(siguiente)* | F4-b: pestaña «Celular» del analista, solo en la demo hasta tener los tipos | Commiteada, apilada sobre el #193 | Los tipos del paso 1.5 |

## Reglas que no cambian

- Ciclo del proyecto: **rama o copia de Supabase → aplicar → gate → advisors → merge → producción.** Nunca
  `apply_migration` directo a producción.
- **Instalar no es activar** (Jhosep, 05/10): en producción se aplican las migraciones y se despliega la Edge, pero **no se
  da de alta ninguna clave ni se cambia la macro de C1** hasta F4-b + F4-d (`PUBLICAR-F2-F3.md` §4–§5).
- **Un solo escritor:** si algo falla, se reporta en el PR con el error y lo corregimos desde nuestra sesión. En nuestras
  ramas tu agente solo hace dos cosas: «Update branch» y el commit de los tipos (paso 1.5).
- Una migración commiteada no se edita: los arreglos van en una migración nueva.

## Paso 1 · #190 (las siete) — hasta producción

**1.1 Poner la rama al día con `main`.** `gh pr update-branch 190` (o «Update branch» en GitHub). Esperado: checks
`verify` y `preflight` en verde. No hay conflictos (comparte con `main` solo `BASE DE CONOCIMINETO/AVANCECORP/Inicio.md`).

**1.2 Banco aislado con el esquema de producción** (rama de Supabase o tu copia Docker). Aplicar las siete, **cada una
seguida de su registrador**, desde `CRM-Avance-Corp/` en un checkout **LF** (los registradores comparan md5):

| # | Migración (`supabase/migrations/`) | Registrador (`supabase/scripts/llamadas-celular/`) |
| --- | --- | --- |
| 1 | `20261001145242_crm_llamadas_celular_datos.sql` | `registrar-datos.sql` |
| 2 | `20261001160219_crm_llamadas_celular_nucleo.sql` | `registrar-nucleo.sql` |
| 3 | `20261001212258_crm_llamadas_celular_ingesta.sql` | `registrar-ingesta.sql` |
| 4 | `20261001222431_crm_llamadas_celular_elegibilidad_dueno.sql` | `registrar-elegibilidad.sql` |
| 5 | `20261005143843_crm_llamadas_celular_correccion.sql` | `registrar-correccion.sql` → `veredicto_registro_20261005143843 = t` |
| 6 | `20261005155914_crm_llamadas_celular_enlace_exacto.sql` | `registrar-enlace-exacto.sql` → `veredicto_registro_20261005155914 = t` |
| 7 | `20261005182227_crm_llamadas_celular_enlace_sin_ciclo.sql` | `registrar-enlace-sin-ciclo.sql` → `veredicto_registro_20261005182227 = t` |

En Docker: `psql "$DB_URL" -v ON_ERROR_STOP=1 -f <archivo>`. En una rama de Supabase: `npx supabase db query --linked
--file <archivo>`. Después, **V1–V5** de `PUBLICAR-F2-F3.md` §3.4 (V1: 7 filas `ok = t`; V2 todo `t`, incluido `sin_ciclo`).

**1.3 Gate.** Variables de `LEEME-seed.md` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`,
`CRM_DEMO_PASSWORD`) más `CRM_BANCO_PSQL_URL` y `CRM_RLS_EXIGE_LLAMADAS=1`. Si el banco es nuevo: `npm run seed:demo` y el
bloque «Baja histórica» de `LEEME-seed.md`. Luego `npm run test:rls`. Entre corridas: `banco/limpiar-entre-corridas.sql`.
- Esperado: el bloque «Llamadas desde el celular (F2 + F3 + quinta + F4-a + séptima)» sin ningún ✗. El tramo de las
  lecturas de F4-b dirá «SALTADAS»: es correcto, la octava no está en este PR.
- **Si falla en llamadas**, mirar primero los tres riesgos que no se pudieron descartar sin el esquema real: `tomar_lead_libre`
  sobre un reutilizable (con `resolver_en_puertas` encendida decide el juicio de reapertura), la v4 real sobre un lead
  creado por inserción de admin, y el descarte vencido fechado fuera de banda en `replica`. Pegar en el #190 las líneas ✗.

**1.4 Advisors** de seguridad y rendimiento del banco: ninguna alerta nueva sobre `crm.llamadas_celular_*`,
`crm.celulares_*`, `private.llamadas_celular_*`, `crm.registrar_llamada_v5` ni las puertas de servicio.

**1.5 Tipos (desbloquean F4-b).** Desde `CRM-Avance-Corp/app/`, con el banco del 1.2:
```bash
npx supabase@2.114.0 gen types typescript --db-url "$CRM_BANCO_PSQL_URL" --schema public,crm > src/lib/database.types.ts.tmp \
  && mv src/lib/database.types.ts.tmp src/lib/database.types.ts
git diff --stat src/lib/database.types.ts
```
El diff debe **solo añadir** las puertas de llamadas. Si cambia algo más, el banco difiere de producción: no subirlo y
generarlos de producción después del paso 1.7. Si sale limpio: **un commit solo con ese archivo** en la rama del #190
(`CRM: tipos de las puertas de llamadas desde el banco con las siete`).

**1.6 Reportar en el #190** con esta tabla:

| Check | Resultado |
| --- | --- |
| Update branch y checks | PASS / FAIL |
| Siete + registradores; V1–V5 | PASS / FAIL (qué V falló) |
| Gate `test-rls.mjs` con `CRM_RLS_EXIGE_LLAMADAS=1` | PASS / FAIL (líneas ✗) |
| Advisors | sin alertas nuevas / cuáles |
| Tipos | sha del commit o «no subidos: el diff tocaba X» |

**1.7 Fusionar el #190 (squash) y producción** según `PUBLICAR-F2-F3.md` §3: las siete **una por mensaje**, cada una con
su registrador, V1–V5, `npm run gen:types` (ahora sí desde producción) y el despliegue de la Edge (§3.6–§3.7). **Sin alta
de claves ni cambio de macro.** Marcar las siete «EN PROD» en `MIGRACIONES.md`.

**1.8 Avisar en el #190**: «fusionado y aplicado (sha, hora)». Con eso nosotros rehacemos el #195 sobre `main` y subimos
la novena.

## Paso 2 · #193 (solo pantalla, riesgo 2)

Independiente del #190: `gh pr update-branch 193`, checks en verde, tu aprobación y squash. Seguro solo: sin id en la
URL nada cambia, y la macro no manda el id hasta F4-d. Si prefieres revisarlo con Codex, mejor una sola ronda junto con
la pestaña (el PR siguiente), que es la que sube el riesgo.

## Paso 3 · #195 (octava) — después del paso 1

1. Esperar nuestra señal en el #195: rama rehecha sobre `main` y **novena** subida (paginada con cursor, `{filas,
   siguiente}`; «hoy» = resuelto hoy en Lima; oráculo con dos páginas y la llamada de ayer resuelta hoy).
2. Revisión: `auditor-rls` y Codex sobre la octava + la novena juntas.
3. Gate en el banco: las siete + octava + novena con sus registradores, y `test-rls.mjs` con
   `CRM_RLS_EXIGE_LLAMADAS=1` **y** `CRM_RLS_EXIGE_LLAMADAS_F4B=1`.
4. Se fusiona y se aplica **con F4-b** (la pestaña), no antes.

## Qué necesitamos de vuelta (una línea cada uno, en el PR)

- [ ] #190: la tabla del 1.6.
- [ ] #190: los tipos (1.5) o por qué no.
- [ ] #190: «fusionado y aplicado» (1.8).
- [ ] #193: aprobado y fusionado, o qué falta.

## En llano

Lo de las llamadas está terminado de nuestro lado. Falta la prueba final en el banco de Miguel, que solo puede hacer él
(tiene las llaves), su visto bueno y subirlo. Esta guía le dice a su agente qué correr, en qué orden y qué contestarnos,
para no ir y venir por comentarios. El celular no se conecta hasta que esté la pantalla de F4-b.

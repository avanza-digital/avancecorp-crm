# Backfill único de conversión · setiembre 2026 — ✅ EJECUTADO EN PRODUCCIÓN el 23/09 a las 18:30 Lima

> ✅ **Hecho** (OK de Miguel a las 16:32; A a las 18:30:36, B a las 18:30:57; verificación a las 18:31):
> - 32 leads convertidos y 0 andamios; las 3 solicitudes previas y las 5 inversiones previas, idénticas;
> - 11 operaciones, 10 elegibles;
> - huellas de funciones, triggers, políticas y permisos IGUALES antes y después;
> - la alarma cuadra y metas-vs-oficial da PASS;
> - conversión de setiembre: 54,8/1.269 = **4,32 % → 86,7/1.269 = 6,83 %**.
> - Pendientes del 01 al 22/09: solo `000670` (excluido) y dos contratos creados el 23/09 a las 18:10 y 18:17,
>   después de la revisión (`001463`, `001467`).
> - Por qué subió 31,9 y no los 34,9 estimados:
>   - los 2 leads con origen `oficina` (`001385`, `001372`) quedan convertidos pero NO suman, porque el núcleo
>     solo cuenta cierres de landing, formulario y referido (`private.metricas_conversiones_implementacion`);
>   - el cliente de `001362` ya tenía otro upgrade elegible en setiembre (`001404`), y cuenta uno por cliente y mes.
> - Mediciones: `_DEV_NO_SUBIR/backfill-conversion-2026-09/ejecucion/{antes,despues}-*.json`.

> Encargo de Miguel: que los contratos «nuevo» de setiembre sin lead ni operación de cartera
> sumen a la conversión. Es de **una sola vez**: sin funciones, sin migraciones, sin apagar
> triggers. **En producción no se ha escrito nada**: todo lo hecho allí fueron lecturas.
> Para retomar: «retomemos backfill de conversión».
> ⚠️ Aquí no hay datos personales. La tabla de casos con DNI y teléfono está SOLO en local:
> `_DEV_NO_SUBIR/backfill-conversion-2026-09/casos-A-para-origen.md` (gitignored).

## 1. La lista (medida en prod el 22/09; guardas repasadas el 23/09)
Hay 44 contratos. El cruce por persona, puente, `leads_de_personas`, DNI y teléfono de 9
dígitos, más el nombre parecido, **no quitó ninguno**.

| Grupo | N | Qué hacer |
|---|---|---|
| A listos | 27 | Cliente nuevo, primer contrato, todas las guardas en verde → lead convertido (falta el ORIGEN) |
| A sin teléfono | 1 | `001420`: sin teléfono no nace el lead |
| A con solicitud previa | 3 | `001377`, `001396`, `001416`: ya tienen una solicitud confirmada SIN lead. Entran: la solicitud se aparta y se repone idéntica (§2) |
| B | 11 | Ya tenía contratos → operación de cartera `upgrade` (`backfill-B-setiembre-2026.sql`) |
| Especial | 1 | `001395` (Nayra): su teléfono coincide con un lead de formulario descartado de ella, con otro nombre. Pasa todas las guardas |
| Excluido | 1 | `000670`: contrato histórico (inicio 12/01/2026); su `fecha_cierre_comercial` es la fecha de carga |

- Varios contratos de una misma persona: se usa la regla de `public.crear_contrato`. Un upgrade
  en el mismo mes del primer contrato del cliente NO es elegible (`001408`, cuyo 1.er contrato
  `001397` es del tipo A).
- `001401` (tipo B) lo cerró un supervisor que no está entre los 18 responsables de la tabla de
  setiembre. Su upgrade es elegible: suma al total de la empresa (y, al sellar, a «fuera de
  ranking»), pero no a ninguna fila. Sigue la regla vendedor = `analista_cierre_id`.
- Estado «solo arrastre» (aviso de la sesión de Metas, 23/09): no aplica. Las 11 analistas del
  tipo A tienen divisor 54–96 en setiembre (estado «medible»).
- Mismo patrón en meses anteriores (sin corregir): dic 2 · ene 3 · feb 5 · mar 9 · abr 11 ·
  may 17 · jun 69 · jul 106 · ago 72.

## 2. Por qué el tipo A no tiene puerta (no es un bug)
- `private.trg_leads_zz_enlaza_identidad`: un lead con el DNI de alguien que ya es cliente no
  nace (`ya_es_cliente`).
- `private.conversion_lead_con_inversion`: para convertir exige una solicitud CONFIRMADA con
  `lead_origen_id` = el lead, cuya inversión sea de la misma persona, `es_primera_conversion` y
  `vigente`. La solicitud Avance siempre CREA un contrato nuevo.
- `trg_leads_guard_tenencia` fija `creado_en = now()`. El cierre cuenta por
  `lead_asignaciones.resultado_en`, así que **el tipo A tiene que correr antes del 01/10 00:00
  Lima**; si no, cae en octubre. El tipo B cuenta por la fecha del contrato.
- **Los 3 con solicitud previa** se registraron por el formulario de solicitud (16 y 18/09), sin
  partir de un lead.
  - Candados: `inversion_solicitudes.inversion_id` es UNIQUE y `private.inversion_origen_inmutable`
    impide darle `lead_origen_id`.
  - Un cierre externo transitorio queda descartado: son ventas reales de las cooperativas.
  - **Solución (Miguel, 23/09: «que cuenten»):** dentro de la misma transacción, la solicitud
    original se APARTA (se borra con copia exacta), entra el andamio, se convierte, se retira el
    andamio y la original se REPONE idéntica (mismo id y datos; se comprueba con `to_jsonb`).
  - Su origen nunca se modifica y ningún trigger se apaga. Solo se admite si está confirmada, sin
    lead y sin revisiones, correcciones ni orígenes (en prod: 0 de cada uno).
  - Ensayado en el banco con `BANCO-A3`: cuenta en setiembre y la solicitud vuelve idéntica. Además
    `contexto_conversion_inversion_fn` da `solicitud_id = null` y el capital no cambia.

## 3. Prueba en el banco Docker (22/09) — condición de Miguel
> «Apruebo A1 solo si la prueba en Docker confirma que la solicitud de respaldo no aparece en
> pantallas ni cambia el capital.»

- **A1 (la solicitud se queda) → NO CUMPLE.** `contexto_conversion_inversion_fn` devuelve su
  `solicitud_id` y el botón «Ver inversión y bienvenida» (`lead-drawer.tsx:332`) la abre,
  mostrando «Solicitud no encontrada». Prueba: `banco/prueba-conservar.sql` (rollback).
- **A1′ (andamio transitorio) → CUMPLE.** La solicitud y la inversión inicial existen solo dentro
  de la transacción y se retiran tras `crm.convertir_lead` (copia en `audit_log`). Capital total
  IDÉNTICO; la pantalla del lead muestra «se registró con el flujo anterior».

## 3b. Segundo banco (23/09) — contra la prod de hoy
Volcado de las 12:38 Lima, ya con `20260923164903` (Metas) y `20260923155859` (peso de la
renovación). **Acreditado por identidad**: 740 funciones por `pg_get_functiondef`, 284 triggers
con su estado, 104 políticas, dueños y permisos de funciones, tablas y columnas IGUALES a prod
(`banco/acreditar.sql`, `banco/acreditar-acl-public.sql`); configuración 27/27.

- **B tenía un fallo, ya corregido.** Si A corría antes (y tiene que correr antes del 01/10), la
  guarda «sin lead» de B contaba 1 de 2 en el banco (en prod habría sido «hay 10» de 11): el
  cliente de `001408` ya tiene el lead que A crea para `001397`. Ahora esa guarda ignora los
  leads del propio backfill (`alta_manual` + `creado_por` ADMIN + nota «Backfill 2026-09 ·
  contrato …»). `banco/backfill-B-banco.sql` se GENERA desde el script real
  (`banco/generar-B-banco.py`): solo cambian los ids y los recuentos.
- **Orden indiferente:** B→A (en rollback) y A→B (confirmado) dan lo mismo: 2 operaciones,
  1 elegible, 3 leads convertidos, 0 solicitudes, inversiones restauradas.
- **Idempotencia:** la 2.ª pasada da «A: 0 convertidos, 3 ya tenían lead» y «B OK» sin insertar;
  entre las dos fotos solo cambian dos marcas de reloj.
- **Capital intacto** (231 llamadas × 5 actores): capital del mes, cartera de clientes e
  inversionistas, pagos, vencimientos, postventa, facturación, altas y fichas de cliente/contrato.
- **Conversión:** la oficial sube lo esperado (2 cierres + 1 referido × 0,15 + 1 upgrade) y el
  divisor no se mueve. `crm.alarma_conversion_fn` cuadra en sus cinco caminos. Metas lo publica
  igual (en el banco, en «fuera del ranking»).
- **Efectos secundarios** (no son capital), para la decisión de Miguel:
  1. Los leads cuentan como «recibidos» el día de la ejecución: Leads recibidos, Reparto y
     Distribución. Los de origen referido suben además «referidos recibidos».
  2. SLA con dos caras (`metricas_sla_fn`): «fuera de objetivo» en primer contacto y primera
     gestión (bloque asignaciones), y «cumplidos» en la etapa «nuevo» (bloque etapas).
  3. Pantalla de Leads (`resumen_cartera_fn`): suben convertidos, vivos, la base de su % y el
     «capital ganado». Citas de Gerencia: aparecen en asignaciones, conversiones y población, y
     su capital se enlaza al lead.
  4. Ficha 360 y registro de actividad: «nuevo → convertido» y «Convertido a cliente».
- **Pasada 2 (23/09, tarde):**
  - `BANCO-A3` (forma de los 3 con solicitud previa): convierte y la solicitud original vuelve
    idéntica; en pantallas cambia solo lo de conversión, sin tocar el capital.
  - Teléfono por caso (columna `telefono` de la lista, solo si la ficha no lo tiene): ensayado en
    rollback con `BANCO-A4`. El lead nace con ese teléfono y la ficha del cliente no se toca.
  - Idempotencia: «0 convertidos, 4 ya tenían lead»; entre fotos solo cambian marcas de reloj.
  - ⚠️ El script de prod lleva UN teléfono (el de `001420`): se genera y guarda en `_DEV_NO_SUBIR/`,
    nunca en el repo.
- **Tercer banco (23/09, ~19 h), contra la prod con `20260923185001` y la ponderación de la renovación
  en `periodos_cerrados`:**
  - funciones, triggers, políticas y permisos iguales a prod; el ACL de public, igual como conjunto;
  - corrida completa: A convierte 4 (incluido A3), B da 2/1 y no quedan andamios;
  - la solicitud de A3 vuelve idéntica y ninguna RPC de capital cambia;
  - la alarma cuadra (0 → 4,15 con divisor 2); la 2.ª pasada no escribe;
  - la prueba del teléfono, OK en rollback.
- **Script A de prod GENERADO** (`banco/generar-A-prod.py` → `_DEV_NO_SUBIR/.../backfill-A-setiembre-2026.sql`):
  - 32 casos: formulario 20, landing 4, referido 6, oficina 2;
  - frente al molde solo cambian la cabecera, el modo fijo, la lista y un recuento final;
  - la sintaxis se validó en el banco: se detiene en el 1.er contrato, que allí no existe.
- **Control previo en prod (solo lectura):**
  - 32/32 A en verde: forma, primer contrato, documento, persona, veto, lead, puente, identidad,
    conversión en curso, tasa pendiente, teléfono y solicitud previa admitida;
  - 11/11 B en verde.
- **Revisión de Codex nº 1 (23/09): CHANGES_REQUESTED, todo aplicado y ensayado.**
  - **P1** — B validaba los contratos sin bloquearlos. Ahora:
    - `for share` antes de validar y condiciones repetidas en el INSERT;
    - comprobación contrato a contrato y la única no elegible = `001408`;
    - una sesión que intenta cambiar un contrato mientras B está abierto recibe lock timeout.
  - **P2** — La repetición aceptaba estados ajenos:
    - A solo salta si el lead es EL de este backfill para ese contrato; si no, se detiene (probado);
    - B verifica cada operación, también si ya existía.
  - **P2** — El generador no garantizaba el conjunto aprobado:
    - exige los 32 aprobados, UUID distintos y formatos;
    - el SQL comprueba número ↔ id (probado).
  - **Menores:**
    - nota nula en la guarda de B;
    - interlock compartido de jerarquía al entrar en A, como `crm.convertir_lead`;
    - `clock_timestamp()`;
    - comentario de `audit_log` corregido.
  - **Aceptados con evidencia:**
    - FKs entrantes NO ACTION, con 0 dependientes;
    - `actualizado_en` de 5 inversiones previas cambia (`trg_inversiones_touch`);
    - un UPDATE concurrente sobre una solicitud apartada: se ejecuta en horario tranquilo.
- **Revisión de Codex nº 2 (23/09):** da por resueltos los 3 hallazgos anteriores y no ve regresiones.
  - Nuevo **P2**: el INSERT de B no repetía todo el predicado del candidato (eliminación, lead ajeno,
    contrato anterior).
  - Aplicado: el predicado COMPLETO está en la validación, el INSERT y la comprobación final.
  - Ensayado: repetición OK; si el lead de A pierde su marca, B se detiene; la inserción nueva, OK
    en rollback.
  - Con esto se cierra la cadena de revisión (máximo 2).
- `supabase/scripts/conversion/metas-vs-oficial.sql` da FAIL en el banco solo por «comparación
  vacía» (el mundo sintético no tiene metas); en prod tiene que dar PASS.
- 🔴 **Lección:** llamar como `authenticated` a una función SIN `EXECUTE` tumba el Postgres local
  (segfault). Las internas (`alarma_conversion_fn`, `*_sin_cartera_fn`) van en
  `banco/medidor-interno.sql` como postgres, y el medidor ya no llama lo que no puede ejecutar.

## 4. Qué falta (en orden)
1. **Miguel decide:** OK a **A1′** (no es lo mismo que A1); los efectos secundarios de §3b; el
   teléfono de `001420` (cargarlo en la ficha del cliente desde
   el CRM, el script lo toma de ahí) o dejarlo fuera; `001395` (¿conversión del lead descartado o
   lead nuevo?); confirmar `000670` fuera; enterado de `001401`.
2. ✅ Orígenes recibidos el 23/09, en `_DEV_NO_SUBIR/backfill-conversion-2026-09/origenes-A.csv` (30
   contratos). WALK IN = `oficina`. Los que su lista marca RENOVACIÓN/UPGRADE (sin contrato anterior en
   el sistema) cuentan como NUEVOS; `001218` (Qorilazo en su lista) entra como Avance.
3. Generar el script A de producción desde `backfill-A-banco.sql` con la lista real: mismo cuerpo,
   modo fijado en `transitorio`, ids leídos de prod por número de contrato.
4. Antes de ejecutar: `banco/acreditar.sql` en prod tiene que dar las huellas del banco del 23/09.
   Si cambiaron (la sesión `[c23759]` tiene 2 migraciones pendientes), volver a volcar y ensayar.
5. Revisión de Codex (`codex exec`, el MCP está caído) sobre los dos scripts finales.
6. Coordinar la ventana con las sesiones de conversión (`crm-avance-corp-98` [ab1e13] y
   [c23759]): nadie escribe en prod mientras otra mide antes/después. **No sellar ningún mes.**
7. Ejecutar con el OK de Miguel: **A antes del 01/10 00:00 Lima**; B después (o antes: da igual).
   Verificar: tabla por analista antes/después (la foto «antes», justo antes), la consulta de
   detección, `crm.alarma_conversion_fn('2026-09-01')` = `cuadra`, `metas-vs-oficial.sql` = PASS
   y `banco/acreditar.sql` igual antes y después (no se creó ni apagó nada).

## 5. Rehacer el banco (~20 min)
```
cd CRM-Avance-Corp
supabase db dump --linked --schema public,crm,private --keep-comments -f <scratch>/esquema.sql
supabase db reset --local --no-seed                 # --local, JAMÁS --linked
psql <banco> <<SQL                                  # roles con la forma de prod
create role crm_metricas_bridge nologin noinherit;
create role crm_gestion_diaria_lector nologin inherit;
grant authenticated to crm_gestion_diaria_lector;
grant crm_metricas_bridge to postgres with inherit true, set true;
grant crm_gestion_diaria_lector to postgres with inherit true, set true;
create extension if not exists btree_gist with schema extensions;
create extension if not exists pg_trgm with schema extensions;
SQL
psql <banco> -f <scratch>/esquema.sql               # 5 errores esperados: los alter owner
psql <banco> -f banco/duenos-funciones.sql          # esos 5, con permisos temporales
banco/generar-paridad-acl.sql                       # en PROD genera el SQL; aplicarlo en el banco
supabase/scripts/backfill-conversion-2026-09/banco/copiar-config.sh
psql <banco> -f supabase/scripts/banco/{siembra-banco,siembra-gerencia,siembra-actor-oraculos}.sql
psql <banco> -f banco/mundo-backfill.sql
psql -f banco/acreditar.sql                         # en banco Y en prod: huellas iguales
psql <banco> -v etapa=E0 -f banco/medidor.sql       # foto; backfill; foto; diferencias.sql
```
`<banco>` = `-h 127.0.0.1 -p 55322 -U postgres -d postgres` (contraseña `postgres`).
El banco es UNO para todas las sesiones: pedir turno antes del `db reset` y avisar al soltarlo.

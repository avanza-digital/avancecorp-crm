# F4 — ensayo remoto autorizado, 22/09/2026

## Permisos y estado productivo

Miguel confirmó la organización `fzxtxnkvslpcsscxqfbr`, autorizó «SQL,
conciliación y banco hasta US$1» sobre la propuesta exacta del PR #73 y luego
invocó `$release-crm`. Las autorizaciones siguen vigentes; no pedirlas otra vez.
Los cuatro SHA-256 de la propuesta no cambian.

La conciliación administrativa de etapa 3 **PASS y confirmada en producción**:
`20260922164159` → `20260921214018`, 33 sentencias y demás campos idénticos;
327 migraciones antes/después, seis gates PASS, v1 OFF conservada. No se reejecutó
SQL de etapa 3. Respaldo privado `gd-f4-ledger-etapa3-respaldo-20260922.json`,
preflight `gd-f4-preprod-autorizado-20260922.json` y readback
`gd-f4-ledger-conciliado-20260922.json`, en `/private/tmp`.

Los cuatro SQL nuevos, merge, frontend y activación productiva: **NOT RUN**.
Los dos dictámenes recuperados de Claude siguen siendo CHANGES_REQUESTED;
resolución del PRIMARY documentada, sin atribuir PASS al reviewer.

## Banco propio y coste

- Rama `gestion-diaria-f4-cierre-20260922`, id
  `5ff71dc3-f44e-49b1-b648-86867231a984`, ref `vqfeicbqhrmiyihpxcsl`.
- Creada `2026-09-22T22:56:25.989974Z`, **with_data=false**.
- US$0,01344/h, tope US$1. Eliminar al terminar y, como máximo,
  `2026-09-23T22:56:25.989974Z`; verificar ausencia y calcular duración real.
- Dos Cron heredados se desactivaron solo en esta rama. Cero activos comprobados.
  Los nueve Cron productivos y la rama ajena `banco-f7` permanecen ajenos al ensayo.
- Directorio privado `/private/tmp/gd-f4-remoto-20260922`; credenciales separadas
  con modo 600. Los scripts fijan destino y vencimiento; no aceptan otro proyecto.

## Reconstrucción y evidencia

El replay histórico se detuvo en migraciones antiguas. Se reconstruyó solo la
rama con esquema y fixtures locales, preservando los servicios Auth/Storage de
Supabase. Las tentativas fallidas se revirtieron completas; se corrigieron el
permiso temporal SET ROLE, el orden users/identities, el conteo real de 17 actores
y las referencias de comprobantes ficticios. No se desactivaron guardas Storage:
se conservaron sus buckets y se agregó el bucket propio del fixture.

Primer respaldo usado: `gd-f4-antes-etapa4-20260922.dump`, SHA-256
`45d000344a7760dd7ab995f25a7e30fdb47bc35710f9523330e637fdb342067f`.
Resultado: 17 usuarios sintéticos, 76 leads, cero Cron activos, v1 OFF.

Producción ya incluía los vigilantes `20260922153708`, `20260922182454` y
`20260922200514`. Se incorporaron en la rama sus definiciones vigentes y
declaraciones técnicas; no se copiaron alertas reales ni se ejecutaron preflights
que dependían de su historia. Se acreditó:

- **721 funciones**: cuerpo, dueño, definer, search_path/configuración y ACL.
- **120 tablas/vistas**: columnas, restricciones, índices, triggers, RLS y ACL;
  solo tres CHECK cambian paréntesis por la normalización de AND de pg_restore.
- Roles y membresías propios, policies Storage y trigger de Auth coincidentes.
- **21 Edge Functions**: versiones, verify_jwt y SHA-256 coincidentes.
- Ledger de la rama: **327 migraciones**, versiones, nombres y sentencias
  idénticos al respaldo productivo. Esta reconstrucción administrativa no
  reejecuta el historial ni introduce migraciones nuevas para fixtures.

Gestión Diaria, SLA, analítica y vigencia PASS. El gate de F7 falla por
`crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)`, huella
`802c0318fd3ec5636e174b4f98b3c965`, **igual en producción y banco antes de F4**.
Es deuda previa de otra tarea; no repararla ni atribuirla a los candidatos.

La matriz general exige siete leads activos exactos. El primer respaldo
conservaba 16 activos de pruebas locales anteriores. Antes de instalar F4 se
prepara la semilla limpia `semilla-base.dump`, SHA-256
`571b82179c858748a6b66f181b9102d01e57234da0d375e554a646af7aaaf26b`:
siete leads y cinco tareas, con el esquema previo a etapa 4 y política v1 OFF.
Respaldo adicional remoto `antes-semilla-limpia.dump`. Auth, Storage e historial
se conservan. Tras resembrar, repetir alineación/cotejo; el primer PASS no basta
para atribuir paridad al estado nuevo.

## Retoma y gates pendientes

1. Terminar semilla limpia y repetir paridad de base. Ejecutar baseline RLS.
2. Aplicar los cuatro archivos exactos en la rama; registrar versiones canónicas
   con contenido comprobado. Nunca un db push general ni DDL directo a producción.
3. SQL/roles/mutantes, Auth/API, matriz completa, concurrencia, carga y advisors.
   Respetar el reloj real: fuera de jornada no inventar un PASS de entrega HTTP.
4. Reconfirmar Main, catálogo productivo, ledger diferencial de solo cuatro
   migraciones y Edge intactas; merge y postflight OFF.
5. Seguir `$release-crm` con respaldo del sitio vigente, artefacto nuevo desde Main
   coincidente, verificación HTTP y registro de la fuente realmente desplegada.
6. Política futura con gerencia, tasa baja NULL hasta F5, primera jornada real.
   Eliminar la rama propia sin esperar esa jornada si ya terminó su uso.

Scripts versionados en `supabase/scripts/gestion-diaria-seguimiento/remoto/`.
Las pruebas locales previas siguen siendo evidencia local, no remota.

# RETOMAR-60 — F2.b «cola del catálogo F0»: E3 (b5) EN PRODUCCIÓN (apagada). F2.b COMPLETA

**Fecha del checkpoint:** 2026-09-05. **Para retomar en otra sesión:** decir «retomemos RETOMAR-60». Sustituye a [[RETOMAR-59 - F2.b cola del catalogo F0, E1+E2 en produccion, sigue E3 (2026-09-05)]].

Enlaza con: [[Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31)]] · [[Catalogo de puertas de escritura - identidad e inversiones (F0, 2026-09-03)]] · [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

## 1. Dónde estamos

| Entrega | Migraciones | Estado |
|---|---|---|
| Lote Contrato-F2 (F3) | `20260903190000` … `20260903260000` | ✅ EN PROD 04/09 |
| F2.b E1 = b1 + b2 | `20260904120000`, `20260904130000` | ✅ EN PROD 04/09 |
| F2.b E2 = b3 + b4 | `20260905100000`, `20260905110000` | ✅ EN PROD 05/09 |
| F2.b **E3 = b5** (fusión, corrección documental, enlace de lead suelto, reasignación) | `20260905120000` | ✅ **EN PROD 05/09**, registrada con `registrar-f2b-e3.sql`, verificada en solo lectura |

Banderas en producción: las tres en `false`. Todo aterriza apagado: con la bandera OFF las 5 RPC nuevas responden `P0409` antes de leer argumentos y las 7 funciones vivas transformadas son byte a byte las de hoy (reversa real ×2 con md5 de producción).

Git: fusionada a `main` (`2742bf8`) y subida el mismo día a `avancecorp/tronco` y a `avancecorp/main` (`ecbb7b9`). El worktree `../AVANCECORP-f3` puede borrarse (`git worktree remove`). Ojo: otra sesión unificó `main` local con `avancecorp/main` el 04/09 (nota [[Main unico - sincronizacion y publicacion 2026-09-04]]); CLAUDE.md sigue diciendo «tronco»: Miguel decide cuál manda.

## 2. Qué hace b5 (idioma de negocio)

- **Previsualizar y fusionar** dos fichas de la misma persona: Gerencia ve antes qué pasará (bloqueos con diagnóstico, advertencias, huella) y la fusión se niega si algo cambió en medio. La perdedora nunca se borra; documentos, perfil, lead, cierres, inversiones, titularidades, reservas, veto y responsable pasan a la canónica. Como máximo un lead y un perfil entre las dos; lo demás queda en la cola de revisión hasta F5.
- **Corregir el documento** de una persona: el viejo queda histórico, el nuevo vigente; el perfil del Portal y el lead se realinean SOLO si llevaban el documento equivocado; un documento de otra persona, de otro cliente del Portal o de otro lead vivo se rechaza.
- **Enlazar un lead suelto** a una persona reconocida (la revisión humana de la clase E): solo con el DNI exacto, validando perfil y cierre por documento.
- **Reasignar el responsable de relación**: cierra y abre tramo; no mueve atribuciones ni el vendedor del lead.
- Libro append-only `crm.inversionista_operaciones` (correcciones y enlaces); la fusión tiene su libro `inversionista_fusiones`.

## 3. Cómo se construyó y qué evidencia hay

- Diseño v1 → Codex NO-GO (14 bloqueantes) → v2 → Codex NO-GO (10 puntos) → **v3 aplicada en el código** (`DISEÑO-F2B-COLA-CATALOGO.md`, sección E3 v3).
- Generada desde el texto vivo de producción: `supabase/scripts/f2b/gen-b5.py` + `b5-nuevos.sql` + `vivas/e3/` + `huellas-e3-prod.txt`.
- `auditor-rls`: sin bloqueantes de seguridad; medios corregidos el mismo día.
- Oráculo `scripts/oraculo-f2b-b5.sh` **VERDE 87/87**; arnés viejo (F3 + b1..b4) VERDE encima; reversa real ×2; suite RLS **1360/1361** con el bloque b5 (88 aserciones nuevas: grants OFF/ON de las 5 RPC para anon/service_role/no-Gerencia, tabla sin grants, helpers sin EXECUTE, gates de Gerencia; el único rojo es el «tercer estado» conocido de `HALLAZGOS-SUITE.md`); Codex sobre lo construido: **GO técnico para aplicar APAGADA** («no encontré un bloqueante técnico para aplicarlo en producción apagada»); 4 bloqueantes para ACTIVAR, todos cerrados el mismo día en el código y con caso en el oráculo (B1 perfiles = unión de los directos y los del lead, con coherencia documental; B2 «un solo lead» cuenta el puente también en las dos conversiones; B3 un vigente propio reutilizado queda verificado; B4 el motivo se contrasta con TODOS los documentos de la persona), más N2 (jerarquía antes del documento en `reclamar`), N4 (el propio puente histórico no bloquea el enlace) y N9 (guardas EXACTAS: md5 de prod o md5 del texto de b5, existencia obligatoria; postflight byte a byte de las 7 — lección: `pg_get_functiondef` termina en un salto que el generador recorta). Oráculo final **92/92**.
- Ledger: `MIGRACIONES.md` → `## 20260905120000`. Plan: `PLAN-MAESTRO-MULTIEMPRESA.html`.

## 4. Decisiones que esperan a Miguel

1. ✅ **Decidido por Miguel el 05/09: OK** a que la corrección de documento ESCRIBA `public.perfiles.dni/tipo_documento` del perfil enlazado (es lo que ya hace el código en producción). Riesgos aceptados y anotados: clave temporal derivada del documento viejo (avisar o resetear), conciliación de depósitos por el DNI nuevo, «Ver PDF» regenera con el dato actual, puerta trasera del Portal hasta el candado de la decisión 2.
2. ✅ **Decidido por Miguel el 05/09: SÍ** al parche de `public.crear_contrato` (crear un contrato reconoce a la persona) y al candado en `public.perfiles` (el documento de una persona reconocida solo cambia por la corrección de Gerencia); **colaboradores y registros del Portal FUERA** de la identidad. Se construye como E4 de F2.b (migración aparte, aterriza apagada).
3. ¿Qué manda: CLAUDE.md (tronco = `avancecorp/tronco`) o la nota «Main único» (upstream `avancecorp/main`)?

## 5. Publicado el 05/09

Aplicada y registrada por Miguel con los dos `!`; verificada en solo lectura: 7 funciones con el md5 exacto de b5, 5 RPC + 10 helpers, tabla con RLS y sin grants, banderas en `false`, registro con el texto íntegro. Ledger «✅ PRODUCCIÓN».

## 6. Después de E3

F2.b queda COMPLETA. Sigue la lista de prerrequisitos de ACTIVACIÓN `[D-1..D-11]` (ledger de b3/b4/b5) y encender `resolver_en_puertas` como paso aparte, con edges y front.

## 7. Recursos

banco-f7 `cwkiejoaqadcnaieghnf` vivo con E1+E2+E3 (credenciales en el scratchpad de la sesión `b415a35b`, `banco-pooler.txt`/`banco.json`; nunca imprimirlas). Ciclo de la suite: `scripts/f2b/LEEME.md`.

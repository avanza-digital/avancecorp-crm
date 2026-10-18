# Revisión independiente y resolución

LEVEL 3. Codex PRIMARY, único escritor. Dos consultas mediante `scripts/claude-review`,
Claude SECONDARY_REVIEWER sin herramientas, MCP ni delegación. Dictamen final recibido:
**CHANGES_REQUESTED, confianza MEDIA**. No se solicitó otra opinión para obtener PASS;
el PRIMARY resolvió los puntos con código y comprobaciones reales.

| Hallazgo | Resolución y evidencia |
|---|---|
| P1: proyección excluía operaciones sin contrato o demo, aun sin corrección | Aceptado. LEFT JOIN sin filtro demo para la rama original; sin auditoría devuelve exactamente los campos originales. Paridad bidireccional JSON en `prueba.sql`, incluye demo y categoría histórica NULL. |
| P1: consumidores de visibilidad sin inventario | Investigado; ver inventario abajo. Helpers de escritura y roles no ampliados. Negativas de contacto, cooperativa, agenda, veto, retiro y gestión SLA, además de UPDATE/INSERT directos, bancos y documentos. |
| P1 hipótesis: ID comercial sintético incompatible con sello | Refutado por `sello.py`: ejecuta `crm.cerrar_periodo` real para septiembre con las seis transiciones y dos eventos sintéticos, compara foto contra conversiones, conteos y capital vivos. PASS con constraints inmediatas. No cambia reloj ni función del sello. |
| P2: desglose cambiaba históricos sin corrección | Aceptado. `capital_episodios` usa categoría del contrato solo si existe auditoría; sin ella conserva `o.tipo`. Prueba categorías e importes antes/después. |
| P2: anclaje replace podía no coincidir en otra variante | Aceptado como defensa adicional. Postcondición md5 exacta del cuerpo resultante. Aplicación/reversa/reaplicación y 87 checks en variantes anterior y F3: PASS; ampliación final F3 a 93 checks: PASS. El generador ya comprobaba anclaje único en ambas. |
| P2: identidad ya acreditada impedía corregir clasificación | Aceptado. Permite la clasificación y conserva estado sin crédito `operacion_cartera` con motivo específico; no duplica captación. Prueba explícita PASS. |
| P2 hipótesis: puedeEscribir bloqueaba Repartir | No usa ese helper: el reparto usa sus capacidades/RPC propias. El listado de usos está en roles/store y formularios de gestión. E2E de reparto conservado y oráculos de navegación actualizados. Suite final Docker: 422 PASS, 26 omitidos, cero fallos. |
| P2 hipótesis: ficha parcialmente vacía por otras tablas RLS | Las lecturas directas del drawer pasan por leads, actividades, tareas; estados/potencial/identidad/conversión usan RPC contempladas. No lee directamente lead_asignaciones, citas ni derivaciones. |
| P3: copy de meses cerrados | Aceptado: “Los meses sellados no se pueden corregir.” |
| P3: nueva inversión deshabilitada vs ausente | Aceptado: callbacks de alta/operación ausentes para Coordinación; test unitario y E2E verifican ausencia. |
| P3: rendimiento de proyección | Medido con 3.000 contratos/operaciones adicionales: ranking 110,425 ms; conversión 7,265 ms. `rendimiento.sql`, EXPLAIN ANALYZE, banco local; no es benchmark de producción. |
| P3: snapshot admitía cualquier corrección anterior | Aceptado: compara última corrección ordenada por creado_en/id; el trigger de categoría sigue exigiendo marcador de la transacción actual. |
| P3: cache ranking | `crmQueryKeys.rankingOrigenesPrefijo`, cumplimiento y conversión cuelgan de `metricas()` en `data/crm-queries.ts:197–218`; la mutación invalida ese prefijo y el ámbito. |

## Inventario de visibilidad F5

Consulta del catálogo `pg_proc` por referencias exactas a `cartera_f5_personas_visibles`.
Los consumidores son:

- `crm.inversionista_cuentas_fn(uuid,uuid,text)`
- `crm.inversionista_ficha_fn(uuid,integer,integer)`
- `crm.inversionista_documento_fn(uuid,uuid,uuid)`
- `crm.inversionista_gestion_fn(uuid,uuid)`
- `crm.postventa_perfil_fn(uuid)`
- `crm.postventa_vencimientos_fn(text,integer)`
- `private.cartera_f5_listar(integer,integer,text,text,uuid,boolean,text,text,text,text,boolean,boolean)`
- `private.cartera_f5_personas_visibles()`
- `private.gestiones_clientes_identidades(jsonb)`

El overload sin argumentos delega al de uuid. `cartera_f5_listar` y ficha son lecturas;
ficha enmascara capacidades. `inversionista_gestion_fn`, documento y cuentas reciben
veto explícito de Coordinación. `postventa_perfil_fn`/vencimientos verifican
`postventa_estado_fn`, que admite solo vendedor/supervisor/gerencia. `gestiones_clientes_identidades`
llama `gestiones_validar`, con la misma lista. No se modificó ninguno de esos guards de escritura.

Corrección de contacto llama `postventa_persona` y gestión; corrección Coopac exige Gerencia.
Agenda, veto y retiro llaman `postventa_persona`, que rechaza Coordinación antes de validar
payload o tocar datos. Negativas ejecutadas sobre esas puertas. Gestión de actividad v2
entra por `private.sla_ejecutar_comando`; la ampliación de `sla_operacion_autorizada` afecta
lecturas (avisos, cola y estados), no ese comando.

Las policies nuevas son exclusivamente SELECT. Se consolidan en una tercera migración
mediante el OR exacto de las dos expresiones, con huella y roles/permisividad verificados;
conserva policies restrictivas. Los helpers `es_lector_global` y `vendedor_ids_visibles`
permanecen iguales. Un SECURITY DEFINER que leía leads antes no gana ámbito por cambiar
la RLS del caller. Un invoker sigue sujeto a las policies de INSERT/UPDATE, que no se amplían.

## Límites que permanecen explícitos

La matriz HTTP/Auth general y el gate de realidad no se ejecutaron contra Supabase:
el banco de ensayo ofrece PostgreSQL, no Auth/PostgREST. Las pruebas UI usan transporte simulado;
las pruebas SQL usan los roles reales authenticated y los guards del esquema local. El banco
no equivale a una reproducción completa de producción. Publicación y aplicación quedan pendientes.

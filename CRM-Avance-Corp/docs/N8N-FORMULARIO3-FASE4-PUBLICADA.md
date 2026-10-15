# Formulario 3 — fase 4 publicada y verificada

Publicación verificada: 14/10/2026, 23:17 Lima (15/10, 04:17 UTC). [CRM publicado](https://crm.miavance.com/). **Fase 4 publicada y verificada; primera fila real y activación de n8n pendientes.**

Tras la pausa intermedia, Miguel reanudó el objetivo. Se volvió a comprobar la versión web, las dos migraciones, los permisos, la firma de cartera y los ocho archivos del importador. El ledger, el plan del vault y Figma reflejan el estado publicado. Esta acta sustituye los puntos de pausa y las fotografías previas al despliegue; no repetir los despliegues ya realizados.

Los leads nuevos de esta campaña pueden guardar y mostrar **Formulario 3**, y filtrarse en Cartera. Conservan el canal FORMULARIO, su turno de reparto y reglas de conversión. Las coincidencias mantienen responsable e historial; no se reclasificaron los 3.687 leads existentes. Coordinación conserva su circuito habitual de reparto.

## Publicación comprobada

- Fuente: Main limpio e igual a `avancecorp/main`, commit `0fa4a39892c1b38946d06b7a0e03d57b83b013c9`, [PR 280](https://github.com/avanza-digital/avancecorp-crm/pull/280). Miguel fusionó la PR; todos los checks fueron SUCCESS. El árbol es idéntico al candidato probado `6beebac9`.
- Base: versiones exactas `20261014210146` y `20261014215453`, aplicadas en ese orden. SHA256 SQL: `fe0ea0f266aa6e43b5bf71b61cef24b4ab5c4c164c189485180d7736e31b8711` y `e49913e30471ceccf1493926078b949b66c7f365be0b8fc627271cb112fbb891`. Simulación previa: solo esas dos, sin seeds, roles ni cambios de Vault.
- Importador: `crm-importar-leads` versión **24**, JWT exigido, ocho archivos descargados tras publicar idénticos al código probado. Huella de despliegue `a7cb4515e2bc103c9fb0b5e6e3e18a079640e69df05b2607884bb3ab0f36a198`.
- Frontend: `build-20261015T041350920Z`; ZIP `crm-20261015T041351Z-0fa4a39892c1.zip`; SHA256 `b5bb96c18b339b0aeff0610115b2eb5c7797aea32903d56314d078487c8855eb`. Build, manifiesto y preflight obligatorio PASS; Hostinger aceptó el despliegue. **124 archivos HTTP (portada, versión y JS/CSS) con bytes y SHA256 exactos**, más login público en Chromium/Docker sin errores JS.
- Orden cumplido: SQL → verificar contrato y caché → Edge → frontend. La rama autorizada de fase 4 ya se había retirado al pausar; tras reanudar se revalidaron las siete huellas vivas y el historial de 476 migraciones antes de aplicar únicamente las candidatas desde un workspace aislado. No se recreó otro recurso de pago.

## Evidencia que cubre el objetivo

| Requisito | Evidencia |
|---|---|
| Alta con campaña y compatibilidad anterior | 98 SQL y 18 HTTP/Auth repetidos en rama; casos integrados de fase 3; mismos 44 hashes de producto |
| Reparto, conversión, duplicados e historial | Ensayos integrados de fase 3 y anclas de las funciones; 3.687 históricos sin campaña tras publicar |
| Etiqueta y filtro, paginación y cifras | 43 SQL de cartera, tests de app y E2E Docker; bundle publicado coincide con el probado |
| Permisos | SELECT de campaña permitido; INSERT/UPDATE humano y anónimo denegados; RLS activo; firma de cartera única de 15 argumentos |
| Transición compatible | ZIP anterior exacto contra base nueva: Vendedor y Gerencia, Cartera/ficha/Pipeline, 2 E2E PASS |
| Lecturas en producción | Cuatro transacciones READ ONLY con rol PostgreSQL authenticated e identidad existente: Coordinación, Supervisor, Vendedor y Gerencia; consulta antigua y filtro nuevo sin errores |
| Frontera HTTP | PostgREST reconoce consultas antigua/nueva y rechaza anon con 401/42501; Edge rechaza petición vacía sin secreto con 401 |
| Publicación | Release limpio, preflight, 124 archivos comparados y login público PASS |
| Operación y limpieza | Flujo real apagado, aviso manual 52 enviado a Miguel, rama y credenciales temporales retiradas |

Checks locales: 420 archivos / 6.707 tests; lint, tipos, build, scripts, preflights; 3 E2E de campaña; 25 tests de n8n; 6 del verificador SQL. Checks GitHub de PR 280: preflight y verify SUCCESS. Los E2E se ejecutaron localmente en Docker, no en GitHub.

Claude hizo una revisión de fase 4 mediante el wrapper, con resultado inicial CHANGES_REQUESTED, sin P0/P1. Sus observaciones se resolvieron con evidencia; no se afirma una aprobación nueva de Claude. Véase [resolución](../supabase/scripts/formulario3-fase4/revision-resolucion.md). Los documentos LEEME/verificacion de esa carpeta son la fotografía previa a publicar; **esta acta y el ledger contienen el estado posterior**.

Advisors productivos: se mantienen los mismos cinco tipos/niveles de seguridad y seis de rendimiento. El verificador de realidad completó diez mediciones; sin modo estricto retorna 0. Persisten dos advertencias históricas documentadas (45 ventas de analistas inactivos y 273 clientes sin domicilio). No se alteraron esos datos para forzar un verde.

## Límites y siguiente fase

No se importaron filas reales de Formulario 3: campaña en producción = 0, resultado esperado antes de fase 5. Las pruebas HTTP con inicio de sesión real se hicieron en la rama aislada; la verificación de cuatro roles en producción fue SQL bajo authenticated dentro de READ ONLY, y el smoke web público no inició una sesión humana. No se mintieron tokens ni se crearon usuarios de prueba en producción.

n8n `BjI5m1PKVWhO0NDb` sigue inactivo, sin versión publicada, `enviar_crm=false` e `Importar en CRM` deshabilitado. Fotografía posterior al despliegue: versión `29940eb5-d36c-49c7-bf7f-686b66cc3f76`. Revalidación a las 04:22 UTC: versión `2f432b16-c6c3-42aa-b936-26d0dc245d8b`, mismos frenos, cero ejecuciones nuevas/en curso/en espera. Credencial original conservada. El aviso manual productivo 52 confirmó envío a Miguel; no sustituye la prueba automática de fallo, ya realizada en fase 3.

Antes de la primera fila real: verificar la poda de contenido fallido del VPS (política definida: máximo siete días) o desactivar su almacenamiento. Esa configuración del VPS sigue NOT RUN y no se presenta como establecida. La fase 5 limitará explícitamente a una fila, comprobará campaña/reparto/recibo y repetición segura; la carga y el cron quedan para fase 6.

Recuperación: se conserva ZIP/manifiesto anterior `crm-20261014T031547Z-e791502ff696` fuera de la web. Mantener el esquema aditivo y el historial. Si fuese necesario volver al frontend anterior, Miguel decide el rollback conforme al procedimiento; no se elimina SQL ni datos automáticamente.

[Plan en Figma](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34).

## Resultados posteriores a la publicación

```json
{
  "sql": {
    "rls": true,
    "cartera": [
      {
        "acl": "{postgres=X/postgres,authenticated=X/postgres}",
        "firma": "crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text,text)",
        "huella": "37e4e2a13b50c757ffc7a8fdcb3c37b0",
        "argumentos": 15
      }
    ],
    "campania": {
      "insert_anon": false,
      "update_anon": false,
      "insert_authenticated": false,
      "select_authenticated": true,
      "update_authenticated": false
    },
    "migraciones": [
      {
        "name": "crm_formulario3_campania_origen",
        "version": "20261014210146"
      },
      {
        "name": "crm_formulario3_cartera",
        "version": "20261014215453"
      }
    ],
    "total_leads": 3687,
    "cron_activos": 11,
    "leads_con_campania": 0
  },
  "edge": {
    "count": 8,
    "version": 24,
    "verify_jwt": true,
    "hash": "a7cb4515e2bc103c9fb0b5e6e3e18a079640e69df05b2607884bb3ab0f36a198"
  },
  "lecturas_sql_produccion": [
    {
      "rol": "coordinador",
      "ejecutor": "authenticated",
      "identidad": true,
      "lectura_anterior": 0,
      "lectura_campania": 0
    },
    {
      "rol": "supervisor",
      "ejecutor": "authenticated",
      "identidad": true,
      "lectura_anterior": 1,
      "lectura_campania": 0
    },
    {
      "rol": "vendedor",
      "ejecutor": "authenticated",
      "identidad": true,
      "lectura_anterior": 1,
      "lectura_campania": 0
    },
    {
      "rol": "gerencia",
      "ejecutor": "authenticated",
      "identidad": true,
      "lectura_anterior": 1,
      "lectura_campania": 0
    }
  ],
  "advisors": [
    {
      "tipo": "security",
      "anteriores": 5,
      "actuales": 5,
      "identicos": true,
      "lints": [
        {
          "name": "rls_enabled_no_policy",
          "level": "INFO",
          "cache_key": null
        },
        {
          "name": "extension_in_public",
          "level": "WARN",
          "cache_key": null
        },
        {
          "name": "anon_security_definer_function_executable",
          "level": "WARN",
          "cache_key": null
        },
        {
          "name": "authenticated_security_definer_function_executable",
          "level": "WARN",
          "cache_key": null
        },
        {
          "name": "auth_leaked_password_protection",
          "level": "WARN",
          "cache_key": null
        }
      ]
    },
    {
      "tipo": "performance",
      "anteriores": 6,
      "actuales": 6,
      "identicos": true,
      "lints": [
        {
          "name": "unindexed_foreign_keys",
          "level": "INFO",
          "cache_key": null
        },
        {
          "name": "auth_rls_initplan",
          "level": "WARN",
          "cache_key": null
        },
        {
          "name": "no_primary_key",
          "level": "INFO",
          "cache_key": null
        },
        {
          "name": "unused_index",
          "level": "INFO",
          "cache_key": null
        },
        {
          "name": "multiple_permissive_policies",
          "level": "WARN",
          "cache_key": null
        },
        {
          "name": "auth_db_connections_absolute",
          "level": "INFO",
          "cache_key": null
        }
      ]
    }
  ],
  "n8n": {
    "id": "BjI5m1PKVWhO0NDb",
    "version": "29940eb5-d36c-49c7-bf7f-686b66cc3f76",
    "active": false,
    "activeVersionId": null,
    "importDisabled": true,
    "control": "={{ JSON.stringify({enviar_crm:false,simular_registro:false,inicio_ms:$now.toMillis()}) }}"
  },
  "rama_temporal": "Eliminada al pausar; no recreada ni facturando",
  "smoke_publico": {
    "estado": "PASS",
    "portada": 200,
    "login": true,
    "erroresJS": 0,
    "autenticacionReal": false
  },
  "http": {
    "estado": "PASS",
    "comprobado": "2026-10-15T04:17:02.707Z",
    "commit": "0fa4a39892c1b38946d06b7a0e03d57b83b013c9",
    "release": "crm-20261015T041351Z-0fa4a39892c1",
    "zip_sha256": "b5bb96c18b339b0aeff0610115b2eb5c7797aea32903d56314d078487c8855eb",
    "version": {
      "schema": 1,
      "buildId": "build-20261015T041350920Z"
    },
    "archivos": [
      {
        "ruta": "assets/acciones-reconocer-alerta-DcS35ImZ.js",
        "status": 200,
        "sha256": "ee1b777b4969f2b2eaf3eca462e955e6106e2d8bf9e2feaf695bd8451d3e8422"
      },
      {
        "ruta": "assets/actividad-visual-C0YkG7hH.js",
        "status": 200,
        "sha256": "290c94b5be858da21a158971e85ea074a3199528a4cf2e8dd8eaea67c1b6e9f4"
      },
      {
        "ruta": "assets/agenda-DNnuatmQ.js",
        "status": 200,
        "sha256": "28a77647fd0881da1648c24764dde87a7e05f94e80c1a2a3d3470a605ba320ed"
      },
      {
        "ruta": "assets/alertas-C0W4FAbO.css",
        "status": 200,
        "sha256": "57a1788d95fc70d210f3c9877496dda2c5d4457188b885521ba1abbff989ea94"
      },
      {
        "ruta": "assets/alertas-D8L0Qjt1.js",
        "status": 200,
        "sha256": "3f1341cd4f8aab47f0c055efe985b0fd20d13517fcf65d10034260a3293903e3"
      },
      {
        "ruta": "assets/alertas-presentacion-B4NsBEfD.js",
        "status": 200,
        "sha256": "3791c57c923a5a527771c91630615d3582ef5031afba468e2bb3e4e3adec4e85"
      },
      {
        "ruta": "assets/animated-value-CxWwuyas.js",
        "status": 200,
        "sha256": "18d958c2ff460396a0c0d4c31c414874a61452722022b4b1111f99fa5f3e7258"
      },
      {
        "ruta": "assets/argumentos-rpc-CZnLpNy5.js",
        "status": 200,
        "sha256": "b6464d4e979016d87b1285d5694a793601cee73e4744bbca24941b03071d6d06"
      },
      {
        "ruta": "assets/avatar-D5jCzPHt.js",
        "status": 200,
        "sha256": "a1c10f3991aa254bf44bb09a53442beaa70394333dfe1a79e4924543f8932b74"
      },
      {
        "ruta": "assets/aviso-degradacion-aW5Jo4xN.js",
        "status": 200,
        "sha256": "2f2bcda7591b9f679ae6735455ab818692ea751f45550fc5c19259673bd3f016"
      },
      {
        "ruta": "assets/badge-ypeLoRxr.js",
        "status": 200,
        "sha256": "a23f0347e1d37f3d95142f52861331c7992eeefac43c1d4f5935fe72eabfd0e8"
      },
      {
        "ruta": "assets/bases-BVKZrVWB.js",
        "status": 200,
        "sha256": "7ba940f0dfad73206730ab3fb87a45b5d462495cb95b0eb3a309199566b4b86a"
      },
      {
        "ruta": "assets/button-CmyU_qcq.js",
        "status": 200,
        "sha256": "db1791b1e3d2caf251b8f51cbc09c5f242f0e1ef13dd7ea11dfbbfbd4fc226b1"
      },
      {
        "ruta": "assets/card-CDou0iii.js",
        "status": 200,
        "sha256": "a1e04b4844ee810e8be74863df481787bea865957af0a319f64c0e88d8a90d2b"
      },
      {
        "ruta": "assets/cargar-base-B-obJic_.js",
        "status": 200,
        "sha256": "671e846cef891bfe88e3c79d37230335cf33fc615edacd1dbdc97adc8c865731"
      },
      {
        "ruta": "assets/cartera-DraBkahY.js",
        "status": 200,
        "sha256": "b4868d452c3f4bbadad5e128ae55407f3e5aea3de919fb518f60a3bce45ecc19"
      },
      {
        "ruta": "assets/cierres-externos-seccion-DKhC0vQ6.js",
        "status": 200,
        "sha256": "188ad314f3071254639b4b71f862ce781c2cc254033e12be1288c55096497fad"
      },
      {
        "ruta": "assets/cliente-detalle-BuhPmfxP.js",
        "status": 200,
        "sha256": "cb11cfacb2a037ea2d317aa579411ea652ccfbfbd9006a72dbcbc9e749c5ee6a"
      },
      {
        "ruta": "assets/cola-seguimiento-CWiR7Vkq.js",
        "status": 200,
        "sha256": "65949349d394820de8e3e39641a867718da8b5b8bf46b2260c8a00e3ef6b3778"
      },
      {
        "ruta": "assets/config-celulares-BanwBxYX.js",
        "status": 200,
        "sha256": "2baf49b549c45481c2ccf74dd9e0b23743cb8ad1e4c499dde12f6da9aa2ee40f"
      },
      {
        "ruta": "assets/config-citas-fNBvY2Kw.js",
        "status": 200,
        "sha256": "4fbbc2a0dc6748fcef41e1db4c999afd22511238f2c1901763d7f8655cc55c1b"
      },
      {
        "ruta": "assets/config-gestion-diaria-dKHhotq6.js",
        "status": 200,
        "sha256": "bcfd2facfb6123ee8726b4c32d85ec8f026f832bbf59c0f984f26b083a9f188d"
      },
      {
        "ruta": "assets/config-kooC2faQ.js",
        "status": 200,
        "sha256": "883e9862b6808ea0bf146a8a61efcb63b61467ec20563152e470805d806c624e"
      },
      {
        "ruta": "assets/config-metas-Dt8EBQDC.js",
        "status": 200,
        "sha256": "92ff9d2b9da16746f50b5366931c62099e673c891a8f1c5c1f210c60b9f7e65a"
      },
      {
        "ruta": "assets/config-productos-CyPGrCPK.js",
        "status": 200,
        "sha256": "fd0ffd31f15fbfd12fb86e3d3f1ea90560077cb13b124ea4a7e2a2a285a56dce"
      },
      {
        "ruta": "assets/config-rentabilidad-CqS79_W4.js",
        "status": 200,
        "sha256": "a6b9eb6972b8f1cb9d530f5bbdf36d711197f772405b2d4d14e4ea8ef7763d1d"
      },
      {
        "ruta": "assets/config-sla-DcijPSSY.js",
        "status": 200,
        "sha256": "b8bb74cd2db8c7d8d433b2e371c7086c561f98223de8e6259eebe0733de75778"
      },
      {
        "ruta": "assets/config-usuarios-pd_hkd6X.js",
        "status": 200,
        "sha256": "a0f102d57305fcfc4f9e342d00abb4c58ca46142770a8169a31fdf2bf3c16753"
      },
      {
        "ruta": "assets/configuracion-shell-Dm5V6vfJ.js",
        "status": 200,
        "sha256": "9d9139b58c4b22d7d2b70d5807d563467257ddbfb1e7951f1ca9c82b13627f02"
      },
      {
        "ruta": "assets/control-citas-Lzrn_JzW.js",
        "status": 200,
        "sha256": "0434ef3410b2a53c3e09218000364abe2dfd7c147b713cc11a220e71e50856e6"
      },
      {
        "ruta": "assets/controles-periodo-derivaciones-CKCG2Avm.js",
        "status": 200,
        "sha256": "6b985aad554f4e6952c6b60632028f6ee51b71140973a83508375deb48c78ced"
      },
      {
        "ruta": "assets/crm-api-BnB2tsZz.js",
        "status": 200,
        "sha256": "c7a03cf4761167642873f718786c041c18ca317e33117871a16c334fb36f661b"
      },
      {
        "ruta": "assets/crm-queries-1RzZ-6ce.js",
        "status": 200,
        "sha256": "0f19361194027b82f062b73cd6e9f0bbfd8e592b49cc51e8d02d42a8be9a04bb"
      },
      {
        "ruta": "assets/data-vendor-hxr3O6zl.js",
        "status": 200,
        "sha256": "32460896bd4d259fbcae9279756ae62767cd3ae5d370fbb16361ce5f6ceb353a"
      },
      {
        "ruta": "assets/demo-config-DCXcf92E.js",
        "status": 200,
        "sha256": "9037ec53848e0c2a1110884093c86e38ef098892eb15507554aa4af43c6ca815"
      },
      {
        "ruta": "assets/derivaciones-C-Kz-UYY.js",
        "status": 200,
        "sha256": "d802272233cd864f378ce8f06f4f0d95dfeed93e231aa1ae46e4afcfd6ae3e9a"
      },
      {
        "ruta": "assets/desglose-monedas-BggCoJQQ.js",
        "status": 200,
        "sha256": "806f82b5abe28cf10d76931b7e1b709117f972086fa16e360b2b7540be7e79d7"
      },
      {
        "ruta": "assets/dialog-C7hUQ8p9.js",
        "status": 200,
        "sha256": "cf6f54c68cb7db9bd87e42e8cc5281fa1357859600b5e8f36644b30cd1a3e439"
      },
      {
        "ruta": "assets/dist-DAse8jiX.js",
        "status": 200,
        "sha256": "1770acebf7adfedbf9dec1c4d53e718cf21d9543fbafb02991de59ddfd3dd3de"
      },
      {
        "ruta": "assets/distribucion-lecturas-CSPaRIJU.js",
        "status": 200,
        "sha256": "43da337e8696e5fbef9da787f65e2b84f8b2bd44ce6d86ff32b5b1c34443722a"
      },
      {
        "ruta": "assets/dropdown-menu-D5cVgrVY.js",
        "status": 200,
        "sha256": "5272b40bb33b62a034fb341d4a002a97fa055622f4e9aca10f8e1a93c1cef419"
      },
      {
        "ruta": "assets/echart-bar-v-fhrASN.js",
        "status": 200,
        "sha256": "df714bdd5a2e955ef5f192b0179e257baf79e0b2df9dc28cb9e385d08ea29513"
      },
      {
        "ruta": "assets/echart-Bg5TfA8m.js",
        "status": 200,
        "sha256": "04f00b9d4d7d8d5389cb9127424195463c76b50362721abcd5f21465c24064dc"
      },
      {
        "ruta": "assets/echart-line-CEd5-ImO.js",
        "status": 200,
        "sha256": "ed5e11ae6349d3966df448fbf09d8b3213432ecfbaad70e9b113ac39b91c4cd0"
      },
      {
        "ruta": "assets/equipo-D_b_b4Zl.js",
        "status": 200,
        "sha256": "27d7cba24dbc38780d1ff32b0a0a83c37ea99a447437a526c8285e1f38b69f28"
      },
      {
        "ruta": "assets/escape-dialogo-D5GnlN_m.js",
        "status": 200,
        "sha256": "812fbe53a6bdc36db000561d7b14d25e5ebc4f4053ddadb50f6f6e2ce0cb3b35"
      },
      {
        "ruta": "assets/esm-BofDk75c.js",
        "status": 200,
        "sha256": "83896dae0e387ac3d002482a822d03dda90b01bbf82fba06bd017cdb635cd722"
      },
      {
        "ruta": "assets/estado-panel-BqUVt-7q.js",
        "status": 200,
        "sha256": "8fb637a7d189cdf100af1dc7f499bcc2ce22838eff1b2de4630a3fe0ecd7d4d1"
      },
      {
        "ruta": "assets/estilos-gestion-tVVTyUGz.js",
        "status": 200,
        "sha256": "85beb20352401ca6f717e7e6f73d102b692082cdd7d977fb18552784c8895d25"
      },
      {
        "ruta": "assets/estilos-hoja-BJjnbNbT.js",
        "status": 200,
        "sha256": "b8ec0136bac870e7b95596e7a5b30ac0e2186bd2110cc530911610bd81a29424"
      },
      {
        "ruta": "assets/exportar-csv-CWrqHuXK.js",
        "status": 200,
        "sha256": "5dad92517ca837dd671afffc5acaccae693f52c656516734127a02679c2e3d31"
      },
      {
        "ruta": "assets/facturacion-BpD46X4W.css",
        "status": 200,
        "sha256": "c185a386ed643e815a1e743d2a983fa8ec0ad9819198c3e88fa98a9cb934a350"
      },
      {
        "ruta": "assets/facturacion-BRJVmqVe.js",
        "status": 200,
        "sha256": "daea1a164e1755309292a1712a7d47c4f6b5b5f4ddb32fa455c086eb425d742d"
      },
      {
        "ruta": "assets/foco-Dos0YiNm.js",
        "status": 200,
        "sha256": "60b738f1dd770eb487eb5a4f1814473aa72464a60987dca2fce82158d51af70b"
      },
      {
        "ruta": "assets/gerencia-BaLUQF8y.css",
        "status": 200,
        "sha256": "5152a3e3ccda9418f840b3d987f460aeee0699e9dfd09e53101d04a10028d293"
      },
      {
        "ruta": "assets/gerencia-Cxu0rW1H.css",
        "status": 200,
        "sha256": "4eaf2093dea2e8949441234ec0d3bd039bedd90653f0c6be3f5e06d91fee5eec"
      },
      {
        "ruta": "assets/gerencia-D8CnbXyw.js",
        "status": 200,
        "sha256": "1fe0a3e725f854fdf2eaeb2f4189c5d0ee5612be2caa796e9a2a2ee1957de2f8"
      },
      {
        "ruta": "assets/gerencia-DCiYWdJD.js",
        "status": 200,
        "sha256": "593eabdae62cd98a6b24b3446cf5116205e2d411c47b72a0744438c965fa3dfa"
      },
      {
        "ruta": "assets/gestion-diaria-9kIysyJT.js",
        "status": 200,
        "sha256": "7b4bc399d6dcbabc2ea0f935b3f32f9e1cb7dc4c2e30a6e52ef4b405bcb9cff1"
      },
      {
        "ruta": "assets/gestion-diaria-api-a1awND_R.js",
        "status": 200,
        "sha256": "cf6e36907d523f6299915eabc7dca2ccce72117dcf8e5c50cf602b4cefa4fcf0"
      },
      {
        "ruta": "assets/gestion-diaria-avisos-BboW1n30.js",
        "status": 200,
        "sha256": "af06da2480d88541840ac97ecccfc34c9e53795330a6e1192cf299604f6cb72e"
      },
      {
        "ruta": "assets/gestion-diaria-DKGVjwXy.css",
        "status": 200,
        "sha256": "16a767f5340ddc9408707d6c0318b4d9a2336bf70a1e1f36b700fed8d530bf6f"
      },
      {
        "ruta": "assets/gestion-diaria-queries-BD42h3bD.js",
        "status": 200,
        "sha256": "7d3cc9936acb00dad91d37370cc15fd2b393d53617843cc95d34a95d33560c59"
      },
      {
        "ruta": "assets/historial-decisiones-tasa-gerencia-Bd2fAaEo.js",
        "status": 200,
        "sha256": "f6e67a5ed2ed270b95db91bd3d541248bcbfd1f2b7e1296afa3c6b89f156a87a"
      },
      {
        "ruta": "assets/hoja-base-BE8IGVKy.js",
        "status": 200,
        "sha256": "bc69a32fee6b043ac2fea5e85b1050666a9e5a2bb0f9394bd03d6a60d085ebf7"
      },
      {
        "ruta": "assets/hoy-BY9QBCS8.css",
        "status": 200,
        "sha256": "896aad491c208a1bca1dbb5a1d53fcc9ca7e5c45778dd4ee2d16d630ab3c6357"
      },
      {
        "ruta": "assets/hoy-I7xk3peX.js",
        "status": 200,
        "sha256": "608041469c0cbf5f8088219c30f1cd635b6a04575ad478b9781af518d7b1a676"
      },
      {
        "ruta": "assets/index-BnrdhjO-.css",
        "status": 200,
        "sha256": "8a667a0c1c0fd592f9a160e51e4b0b6d6a45c0c876acff8b1cab8af3178b57b8"
      },
      {
        "ruta": "assets/index-BQ07McZB.js",
        "status": 200,
        "sha256": "7e42de1e98efc0110814084b8af42b5d442d01fc7e4796be4ea51e9e2fce5e60"
      },
      {
        "ruta": "assets/input-BZ2lxz2k.js",
        "status": 200,
        "sha256": "46dd3d83f6f095ce5d2409d067bfe0ff329d8a35cd578168b70e656880e9f9df"
      },
      {
        "ruta": "assets/inversionistas-api-DWj9Bvyh.js",
        "status": 200,
        "sha256": "eaa78f900163605eabfedc6b15028ccaf85a21c2681e89477db5f56e0a56a6ad"
      },
      {
        "ruta": "assets/kpi-card-BPBxi-z5.js",
        "status": 200,
        "sha256": "5ca19221b170844833271186f7a97829389a45fee93008d08c47f52992ae3221"
      },
      {
        "ruta": "assets/label-DUVWJb6O.js",
        "status": 200,
        "sha256": "e49805879caffc9ce09d2352af89fc00f8a33ed78dd6f32f4dd023094a330152"
      },
      {
        "ruta": "assets/lead-hover-card-Ce7F9AHz.js",
        "status": 200,
        "sha256": "61f35ee2a55f65e8c49207b81fc97f8188d143384b23f94b2922cb69cde8cdb8"
      },
      {
        "ruta": "assets/llamadas-celular-DjTgh_WO.js",
        "status": 200,
        "sha256": "b99aaffce41c034372d0c877f53d5e0080ca24bc88cd8811237ffcaced1deacb"
      },
      {
        "ruta": "assets/media-DQ7wMsg1.js",
        "status": 200,
        "sha256": "d16a53384c51481a0c4f7024c2f8b988009fdbcecd79039b513f50a7e9412d49"
      },
      {
        "ruta": "assets/metricas-multiempresa-BKCK6QhP.js",
        "status": 200,
        "sha256": "de50857f0ceadd66f6c2ba6eb440745cfdd87ba28cac811b7597c4df9d28607a"
      },
      {
        "ruta": "assets/mi-cartera-Cw37kBu6.js",
        "status": 200,
        "sha256": "c591a1078fa39217fcf100e0a143b0b110114bec719ba9d99572bd3bcc7bd149"
      },
      {
        "ruta": "assets/notificaciones-tasa-BE-chswS.js",
        "status": 200,
        "sha256": "c156e367fd1a489f1c7fb413b1731ad5de91a716aeac045fea11933b4112666a"
      },
      {
        "ruta": "assets/paginacion-D8GbO-wY.js",
        "status": 200,
        "sha256": "fac40124ffca31ebdfeffe996f0eb0f7e288021e6c8f8b8990b54ab97e7bef07"
      },
      {
        "ruta": "assets/pastilla-D08i_QPx.js",
        "status": 200,
        "sha256": "9b6e80c90c168c8596ed248ff739132cd574182055e4ccd1a4dabcfb1c38f4d0"
      },
      {
        "ruta": "assets/periodo-BbVxqwYT.js",
        "status": 200,
        "sha256": "6e10bb4ffc79bba6d674b3eb0e07d8a4fbbdba39ce19136331deb1529a7868c1"
      },
      {
        "ruta": "assets/piezas-base-1XnVEBk2.js",
        "status": 200,
        "sha256": "589c0c767b837fb4b216adcd0a93d2f733960b37a3c8b4f3023bfa0fe887e89b"
      },
      {
        "ruta": "assets/piezas-bases-BO0tVGkm.js",
        "status": 200,
        "sha256": "5cafde4d735050da54a4099e56262de4a394f391db6cc0c61008750af008fe4c"
      },
      {
        "ruta": "assets/pipeline-Cb9azJ8v.js",
        "status": 200,
        "sha256": "d940c62788573a26501a98a37f1a65ee579a2aaf7432a36a8036f5a423098945"
      },
      {
        "ruta": "assets/pipeline-columnas-DafJ0TPM.js",
        "status": 200,
        "sha256": "15ae25e7ac70efad393d8a6a6e64f6a9a4d0a9a0e2d5f453b02347735406f90a"
      },
      {
        "ruta": "assets/postventa-api-TjkBceXa.js",
        "status": 200,
        "sha256": "5f6f6b17aa6257b727806d49286c1ae20c37934870b43f54f9c5b2aa236bb68f"
      },
      {
        "ruta": "assets/potencial-demo-DqXlOhK4.js",
        "status": 200,
        "sha256": "2d45e57784a486845671520c79a4c1773ba4498f560f457a05163e8bcf56a18a"
      },
      {
        "ruta": "assets/progress-DSdwG13c.js",
        "status": 200,
        "sha256": "a56245f415b9410955ee479fa53b3c441a5f6c5f184d0c7ffc303a157d7f092d"
      },
      {
        "ruta": "assets/query-client-F7qUvsfC.js",
        "status": 200,
        "sha256": "3fa23bcf8ea7958932aaeb6ac03464a78153ac2d3e1c37aabca22b76f79b2596"
      },
      {
        "ruta": "assets/radio-group-D3vq8pgV.js",
        "status": 200,
        "sha256": "540897bce9629a9ace26fcb025c75f4f0813a0ebde86d4a3a606f58efc79ae88"
      },
      {
        "ruta": "assets/ranking-vendedores-DH68QZQE.js",
        "status": 200,
        "sha256": "b7fa7c6af50beb56ed98c1c40ac3cd12b9376118400e96671ae1ec02d6fe3601"
      },
      {
        "ruta": "assets/react-vendor-BXy-oECh.js",
        "status": 200,
        "sha256": "b2afb358dc57c4cf68025302de03ee54bff6694c93558199ea6e8fbc312b0f18"
      },
      {
        "ruta": "assets/registrar-resultado-X9pwELF0.js",
        "status": 200,
        "sha256": "8194125698c6b1133bed516939ecde39e062a2f4b0c501ba329563710911de35"
      },
      {
        "ruta": "assets/repartir-D2ld-pTD.js",
        "status": 200,
        "sha256": "d7467898e27880662e94f0f23a899f6302c135b25ca37ab67cbc35ebc9cb1a13"
      },
      {
        "ruta": "assets/rescate-carpeta-Mt6D81lA.js",
        "status": 200,
        "sha256": "a6ef79c3f2f59d7ea8d6293629a9e3712c2c8b559df38603ced6ff0f675c4582"
      },
      {
        "ruta": "assets/rescate-descartados-CcWEQXn-.js",
        "status": 200,
        "sha256": "bd8ff39cecd32e7ebc3137b85ab679a67980b314cbb9ce7fe73347ddd135c5fa"
      },
      {
        "ruta": "assets/rescate-Rh_H2FUP.js",
        "status": 200,
        "sha256": "dcd5c8fcb64d99cf85f864e61c073c4d4953b87e6e10fde60c8138785dc4eee1"
      },
      {
        "ruta": "assets/resumen-gestiones-Dly4DXAH.js",
        "status": 200,
        "sha256": "4cbe3943aa7d230711ed6dfd3a03fb68e881ce6dbf09e3f7c15731f539add68b"
      },
      {
        "ruta": "assets/roles-DSGicJjX.js",
        "status": 200,
        "sha256": "cd8ac091be816d377b47b2581ff285157bb2ff07b69d3fe42943d0418037c9d4"
      },
      {
        "ruta": "assets/rolldown-runtime-QTnfLwEv.js",
        "status": 200,
        "sha256": "5db5ba82eef00d1dee7e86e663098c9427d01183a88d357437daff295aec3e75"
      },
      {
        "ruta": "assets/section-head-DDent87j.js",
        "status": 200,
        "sha256": "a51f90ae6057f23d65be9649140eab2d9a18cbb32da1be6fd0a7cb5d360d1461"
      },
      {
        "ruta": "assets/seguimiento-BBpPQ1yt.js",
        "status": 200,
        "sha256": "f4fafebde3b9ee61e40a8f79cf5213bc8a32662b8676e3f1ca0589688ab233fb"
      },
      {
        "ruta": "assets/segundo-numero-BoiASF5P.js",
        "status": 200,
        "sha256": "fb1c60a456ce289eb44078c0a668c460f14ad1f4683778078d9378fc08a3ca4d"
      },
      {
        "ruta": "assets/select-C6WWNPwG.js",
        "status": 200,
        "sha256": "4a3f1fce1a3f1cf887077ef5b2e122dbb9bac57a134b9e8665069425afed5841"
      },
      {
        "ruta": "assets/sla-operacion-DZLgT1nB.js",
        "status": 200,
        "sha256": "73309c8f62216968ef61af5d0108209393f8508683aba1e3cd705a7417655087"
      },
      {
        "ruta": "assets/sla-operacion-queries-CZP6rdM6.js",
        "status": 200,
        "sha256": "130a42f8999a84369250b52e952ab20f763a92495d5c4519985121ae0e9c6535"
      },
      {
        "ruta": "assets/stat-strip-BbVQaOfU.js",
        "status": 200,
        "sha256": "48e02b3205e47b69116a5f6f9b5884c5216d205c67888fd4db9f5403227ece22"
      },
      {
        "ruta": "assets/store-context-8oahbTda.js",
        "status": 200,
        "sha256": "3484103a074f0a67c81b8aeddc548d58cf9438f0e70308ff69f187474eb4da53"
      },
      {
        "ruta": "assets/tabla-CqKusG7y.js",
        "status": 200,
        "sha256": "b5b027509abc97ecafa2d1110b96963031a3c1a21fbeea32cb3310cb513c3d4e"
      },
      {
        "ruta": "assets/telefono-9z_U36Kc.js",
        "status": 200,
        "sha256": "cb38928a6ac895395d4bc22f7167618287db7c687ce801deac5a04db703f2e13"
      },
      {
        "ruta": "assets/textarea-dw7KXCos.js",
        "status": 200,
        "sha256": "03467467f0657d97c8550a8c228d7f1402f2e99dbfd5e88f6e5fc09bbb59a73f"
      },
      {
        "ruta": "assets/ui-vendor-lrcbir9p.js",
        "status": 200,
        "sha256": "0dbf7adcca66d35cf1a62c26617bc1fdc8599aa18b757cf4c968a1c17efe290d"
      },
      {
        "ruta": "assets/universal-DwCjmUkO.js",
        "status": 200,
        "sha256": "178778fd03056b4203b2b41fea7263fa8b1da87f1f485c3572f48cb2844aac09"
      },
      {
        "ruta": "assets/use-cartera-paginada-CScb_V7U.js",
        "status": 200,
        "sha256": "eb0afca271fb6f97b2733ba8e72fa328c2dc2f0f0c7c52280fffba1e5d7cad56"
      },
      {
        "ruta": "assets/use-etapa-visible-B-gArSZY.js",
        "status": 200,
        "sha256": "713d4df8a2c566724d96acd2cd567bfd6c3abad6a0fe86214d5ac89162069bb5"
      },
      {
        "ruta": "assets/use-metricas-vendedores-operativas-zuXjTHXf.js",
        "status": 200,
        "sha256": "a4c5a20bc0d81e9433f9220451e0428858d867e2f75c0d4eb48ebc3b2efaa537"
      },
      {
        "ruta": "assets/use-periodo-gerencia-PPPpzerT.js",
        "status": 200,
        "sha256": "9b76316b61c5ec0c8a70a87ce237eb532b2648516800ab309160900690ec427a"
      },
      {
        "ruta": "assets/use-resumen-cartera-operativo-BHuI_R_w.js",
        "status": 200,
        "sha256": "3952cf538fbbc964beec1905dcf6195f766995b8e0f4697632c97354222289f8"
      },
      {
        "ruta": "assets/use-valor-diferido-C5pSPdfy.js",
        "status": 200,
        "sha256": "affc968124d89af3f59bc58884f81e3e3101efe1a22d65e3f55ef0350cf5099f"
      },
      {
        "ruta": "assets/utils-Bcl_2xCf.js",
        "status": 200,
        "sha256": "6f093887f675066c079b2271c3bba27cfbf1e81dc20a7f121b7c64b9063e8e43"
      },
      {
        "ruta": "index.html",
        "status": 200,
        "sha256": "63d5d2f1988de214f715ce9e2bff80a8ffc6759f229de225baba48a41da5008c"
      },
      {
        "ruta": "sw-crm.js",
        "status": 200,
        "sha256": "bb8b17431e6f05e609b09d9b111a1182830ec745c9d376a4a62a9bbff20e35e6"
      },
      {
        "ruta": "version.json",
        "status": 200,
        "sha256": "fee7bdbced06eb156b4b5c6c989e9e817ce4471ceb15586e889c25917b9e5851"
      }
    ]
  }
}
```

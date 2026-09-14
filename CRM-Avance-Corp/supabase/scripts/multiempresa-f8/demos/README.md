# F8 — exclusión consistente de fuentes demo

Estado: candidata local preparada el 13/09/2026 (14/09 UTC), **sin aplicar en
producción**. Los diez enlaces reales autorizados anteriormente ya están
aplicados; este paquete no los vuelve a ejecutar.

## Resultado previsto

En el corte de 598 fuentes, las 593 reales ya tienen identidad coherente. Las
cinco demo se conservan como historia; los cuatro huecos demo dejan de bloquear
el piloto. No se inventan documentos ni se crean personas para las pruebas.

La cobertura de F5/F8, lista, inversiones de la ficha, cantidades, empresas,
documentos y fuentes de postventa usan el mismo lector de fuentes reales. Una
persona con inversiones reales y demo conserva sus fuentes reales. Una persona
con solo fuentes demo no reaparece por tener un perfil cliente. Los perfiles
cliente sin ninguna fuente económica siguen disponibles para su responsable.

El lector administrativo `private.cartera_f5_fuentes()` y los cálculos F7 siguen
intactos. Las actividades/historial de una persona real se conservan. La marca
Avance continúa bajo la puerta existente de Gerencia, con motivo, auditoría y
rechazo de meses sellados; Qorilazo conserva su único fixture técnico reconocido.
La migración no reclasifica registros ni cambia cuentas, permisos o banderas.

## SQL exacto y orden

1. [Control F8 apagado](../../../migrations/20260913215240_crm_f8_piloto_controlado.sql),
   candidato anterior, todavía no instalado en producción.
2. [Exclusión demo](../../../migrations/20260914025926_crm_f8_excluir_fuentes_demo.sql),
   objeto de esta entrega. Requiere el control anterior instalado OFF y F4–F7 OFF.
3. Verificar firmas, ACL, cobertura real/demo y banderas después de instalar.
   El encendido nominal del piloto pertenece a otro paso autorizado del plan.

Son dos migraciones separadas, cada una transaccional. La primera instala
control y membresías vacías; la segunda crea un helper privado INVOKER y ajusta
ocho definiciones exactas, sin modificar tablas de negocio. Las huellas previas
y posteriores abortan frente a deriva. No ejecutar la segunda aislada sobre
producción ni alterar las migraciones ya versionadas.

La instalación requiere presentar este SQL y aprobación de Miguel, además del
ciclo de rama, verificación y merge del proyecto. La deuda del replay remoto
anterior sigue abierta: el ensayo remoto del control F8 original no prueba esta
corrección ni habilita un merge de una rama restaurada manualmente.

## Verificación

Desde `CRM-Avance-Corp`: `npm run test:multiempresa:f8`.
Se ejecutan secuencialmente dos archivos sobre la copia sintética cerrada; el
reinicio rehúsa conexiones de clientes existentes y no termina procesos ajenos.

- 31 pruebas SQL PASS: 20 de demos y 11 del control F8, incluidas cinco carreras
  de encendido. El fixture reproduce 598 fuentes: 593 reales, cinco demo y cuatro
  huecos exclusivamente demo. Se demuestra el fallo anterior y su corrección.
- Huecos reales y marca NULL bloquean; F5 global y F8 nominal conservan ese gate.
  En producción `contratos.es_demo` es NOT NULL; el NULL es solo un mutante.
- Persona mixta, perfil solo demo, perfil sin fuentes, enlaces contradictorios,
  cierre vinculado por lead vivo/histórico, aislamiento entre vendedores y
  Directorio. Fuentes demo rechazadas como documentos/origen de postventa.
- Huellas idénticas de fuentes, contratos, cierres, inversiones, personas,
  titulares, períodos, Auth y salida F7. Firmas/ACL públicas y CRM idénticas.
- Instalación/reversa rechazadas con piloto o cualquiera de F4–F7 ON; deriva,
  consumidor nuevo en `public` o vista dependiente abortan con rollback.
- `check:scripts`, `check:multiempresa:f8`, `test:edge-preflight`, `seed:preflight`
  y `test:rls:preflight` PASS. Los dos últimos usan valores ficticios de entorno
  y no conectan: no sustituyen a una matriz real.
- [Revisión independiente y decisiones](REVISION-CLAUDE.md).

**NOT RUN para esta corrección:** replay/rama Supabase, advisors de la candidata
remota y Auth/Data API remoto, pendientes del ciclo autorizado. Tampoco se
ejecutaron build/frontend ni regeneración de tipos: no cambia interfaz,
tabla/firma expuesta o código cliente; se comprobó paridad del contrato SQL.
Las comprobaciones focalizadas con roles SQL sí ejecutan las funciones reales
en PostgreSQL. No equivalen a una prueba de nueva venta real o al cierre G7.

## Reversa

[Reversa exacta](reversa.sql): con F8 y F4–F7 OFF, restaura las ocho definiciones
anteriores y retira exclusivamente el helper nuevo. Rechaza deriva/dependencias
adicionales y conserva todas las filas. Se aplicó realmente en el banco y se
comprobó que los cuatro demos vuelven a bloquear antes de reinstalar allí.

El script no modifica `supabase_migrations.schema_migrations`. Después de una
publicación, registrar la compensación y cualquier reinstalación como nuevas
migraciones en el ciclo autorizado. `db push` no repite una versión ya aplicada;
no corregir el ledger ni reinstalar de forma automática.

Los nuevos consumidores de estas funciones deben revisar conjuntamente las
huellas de instalación/reversa. El barrido detecta referencias textuales y
dependencias del catálogo; no pretende analizar SQL construido dinámicamente.

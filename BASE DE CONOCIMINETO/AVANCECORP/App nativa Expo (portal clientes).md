# App nativa Expo (portal clientes)

> F0 arrancado el 2026-07-29. Parte de la [[Visión fintech — app nativa y transferencias]].

> ⚠️ **Directiva de Miguel (2026-07-30): la app REEMPLAZA al portal de clientes.**
> Cuando la app esté publicada y adoptada, **miavance.com (portal cliente) se APAGA** —
> no van a convivir para siempre. Consecuencias: el portal queda CONGELADO en features
> durante la transición (nada de fórmulas nuevas en dos lugares); el núcleo de cálculos
> se construye EN el proyecto de la app (no se refactoriza el portal); y el apagado es
> GRADUAL: antes hay que verificar adopción, clientes con equipos viejos (iOS < 16.4 no
> instala la app: iPhone 7/6s/SE 1ª gen) y el destino del panel admin (candidato: CRM).
> Detalle operativo en `avancecorp-app/00_GESTION/` (plan maestro + registro de decisiones).

## Dónde vive

**FUERA de este repo**, carpeta hermana: `DESARROLLO/avancecorp-app/`
(mismo patrón que el ui-playground). Repos/deploys separados del CRM y del portal web.

⚠️ **Desde 2026-07-29 (noche)** el proyecto/repo git vive un nivel más adentro
(reorganización de Miguel en Finder): `avancecorp-app/APP CODIGO Y COMPONENTES/`
— TODOS los comandos (`npx expo start`, git, etc.) se corren desde ESA subcarpeta
(la ruta lleva comillas por los espacios). `avancecorp-app/` es la carpeta paraguas
donde Miguel agrupará también guías de desarrollo y material del app.

## Stack

- **Expo SDK 57** (React Native 0.86.2, React 19.2.3, expo-router, TypeScript estricto).
  Historia: se bajó a 54 (commit `e7668ac`) por el Expo Go del iPhone; el 2026-07-30 se
  VOLVIÓ a 57 (commit `ac605bd`, versiones exactas del commit `18b7b15`; expo-doctor 20/20)
  porque Miguel ya tiene **Expo Go 57 en su Android**. Trampa npm 12 sigue viva: versiones
  a mano + `npm install --legacy-peer-deps` (nunca `expo install --fix`).
- **Mismo backend que el portal**: Supabase `dctqcbznekcyxhjujuci`, misma llave publicable,
  mismo login (`signInWithPassword` + tabla `perfiles`) y misma RLS. La app NO tiene backend propio.
- Sesión en AsyncStorage con auto-refresh solo en primer plano (patrón oficial Supabase RN).
- Paleta espejo del portal (navy `#111e3d` + gold `#c8922a`) en `src/constants/brand.ts`.

## Qué está construido (2026-07-29)

- **Login** de marca con las MISMAS reglas de `auth.js` del portal: solo rol `cliente`,
  activo, sin clave temporal pendiente (`debe_cambiar_password` → lo manda a miavance.com);
  cualquier otro caso cierra sesión (sin limbo autenticado).
- **5 pestañas**: Inicio (real: hero con capital activo POR MONEDA —PEN/USD jamás sumados—
  + tarjetas de contratos vía RLS), Inversión / Documentos / Novedades (placeholders de
  marca, F3/F4) y Perfil (datos + cerrar sesión).
- Reglas del portal respetadas: cliente NUNCA ve "Vencido" (mapa `ESTADO_LABEL` → "Finalizado");
  fechas `YYYY-MM-DD` parseadas como fecha LOCAL (bug UTC-5 documentado del portal).
- `npx tsc --noEmit` limpio; bundle Android exporta OK.
- IDs de tienda ya fijados: `com.avancecorp.app` (Android e iOS).

## Núcleo de cálculos con paridad al centavo (2026-07-30, fase B1 del plan)

- **`src/core/`** (fechas, formato, cálculos): transcripción EXACTA de las fórmulas de
  `public_html/js/dashboard.js` — la versión **autoritativa** (la copia de `inversion.js`
  es una versión simple divergente; hallazgo de auditoría, NO usarla).
- **Suite de paridad** (`src/core/__tests__/paridad-portal.test.ts`): carga el JS REAL del
  portal como oráculo y compara — 19 contratos reales + 600 aleatorios con semilla +
  820 casos de formato + valores dorados de interés compuesto. **12/12 en verde.**
- Ya se pagó sola: detectó que `toFixed` redondea `1.005 → 1.00` mientras la web (Intl)
  muestra `1.01`. Corregido con redondeo por notación exponencial. Sin la suite, la app
  habría mostrado centavos distintos que la web.
- Correr con `npm run test:core` (usa `node --test` con TZ=America/Lima; se salta la
  paridad si el portal no está en el disco). Typecheck: `npm run typecheck`.
- La app ya consume `@/core` (el viejo `src/utils/formato.ts` fue absorbido); el tipo
  `Contrato` ganó `tipo_interes` y `cerrado_en` y el select de contratos los trae.

## Barrera de pruebas unitarias (2026-07-31)

- Infraestructura Jest compatible con Expo SDK 57 (`jest-expo` + React Native Testing
  Library), separada de la suite Node de paridad del portal.
- **52/52 pruebas en verde, 12 suites**: cálculos/fechas/formato, autenticación completa,
  cliente Supabase móvil, servicios, redirecciones, tabs, login, Inicio, Perfil y
  placeholders.
- Cobertura sobre TODO `src/`: **100% líneas, 100% funciones, 99.16% sentencias y
  96.87% ramas**. Gate mínimo global: 85% líneas/sentencias, 85% funciones y 80% ramas;
  umbrales más estrictos para `core/`, `lib/` y `services/`.
- Comando único: `npm run verify` (typecheck app + typecheck tests + paridad del portal +
  cobertura). GitHub Actions replica el gate con `npm ci --legacy-peer-deps`.
- Alcance deliberado: solo pruebas, configuración de desarrollo, documentación y CI;
  **ningún cambio funcional**, de Supabase, diseño o despliegue.

## Cómo probarla

```
cd "DESARROLLO/avancecorp-app/APP CODIGO Y COMPONENTES" && npx expo start --tunnel
```
`--tunnel` evita los problemas de wifi/router (funciona hasta con datos móviles).
**Equipo de preview: el Android de Miguel** (su Expo Go es 57, compatible). En el celular:
app **Expo Go** → escanear el QR (o generar un QR del exp:// con
`npx qrcode -o qr.png -w 600 "exp://…"` y abrirlo en pantalla para escanearlo).
**iPhone**: su Expo Go quedó en 54 → la vía es el simulador de Xcode
(`npx expo start` + tecla `i`) o TestFlight cuando existan las cuentas.
**Simuladores de la Mac (listos desde 2026-07-30):** Xcode completo instalado y
`xcode-select` apuntándole (iPhone 17, iOS 26.5) + emuladores Android `Pixel_8_A15`
(API 35, el de uso diario) y `Pixel_8` (API 36), con **Expo Go 57.0.2 instalado a
mano por APK** (los releases 57.0.3+ de github.com/expo/expo-go-releases son SOLO iOS;
el CLI de Expo solo auto-instala en iOS). Arranque típico:
`npx expo start` + `adb reverse tcp:8081 tcp:8081` + abrir `exp://localhost:8081`.
Login con una cuenta de cliente real → ve SUS contratos (solo lectura, RLS).
El código está organizado por subcarpetas con reglas escritas en su **README.md**
(pantallas solo componen; toda query de Supabase vive en `src/services/`).

## Trampas conocidas

- ⚠️ **reanimated/worklets PINNEADOS — no subir hasta nuevo Expo Go Android** (2026-07-30):
  el `package.json` fija `react-native-reanimated@4.5.0` + `react-native-worklets@0.10.0`
  (exactas) A PROPÓSITO, aunque `npx expo install --check` pida 4.5.1/0.10.1. Los binarios
  de Expo Go vigentes (Android 57.0.2, iOS 57.0.5) llevan 4.5.0/0.10.0 **compilado nativo**;
  Expo bumpeó las recomendadas a 4.5.1 el 27-jul sin publicar clientes nuevos. Con 4.5.1 en
  JS, **Android crashea al arrancar** con SIGSEGV nativo en `libhermesvm.so` (hilo
  `mqt_v_js`, addr fija `0x193020489040003`) — iOS tolera el descalce de casualidad.
  Diagnóstico por bisección (2h): app vacía OK → +reanimated crashea → 4.5.3/0.10.3 igual →
  imagen Android 35 vs 36 igual → bytecode on/off igual → **pin a 4.5.0/0.10.0 = arreglado
  en ambos**. Para des-pinnear: esperar release Android >57.0.2 en expo-go-releases y
  cotejar `apps/expo-go/package.json` del repo expo al commit del release.
- El **npm 12** de la Mac rompe `create-expo-app` ("Could not parse JSON…"):
  la plantilla se montó a mano con `npm pack expo-template-default` + tar.
- `web.output` va en `"single"` (SPA): el modo `"static"` pre-renderiza en Node
  y Supabase/AsyncStorage revienta ahí. La web real sigue siendo miavance.com.

## Pendiente (según el plan aprobado — ver `avancecorp-app/00_GESTION/`)

- **🎨 DISEÑO RECIBIDO 2026-07-30** en `avancecorp-app/DISE;O APP/` (handoff de Claude
  Design "Tres prototipos fintech" → doc "Avance Corp - 3 Niveles": prototipos Empresas A
  "Solo tarjeta" y Empresas B "Sin tarjeta" + design system avanza). ⛔ Antes de construir:
  faltan 2 respuestas de Miguel — (1) ¿el 3er prototipo quedó sin exportar o el alcance son
  estos 2?; (2) ¿implementar directo o plan de pantallas con aprobación una por una (F4)?
  Al implementar: leer el `.dc.html` ENTERO (regla del README del handoff) y cruzar con la
  Guía Expo V2 (disclaimers, accesibilidad, exigencias de Apple en pantalla).
- **Vía A (trámites, disparan solos):** credenciales de `desarrollo@corp-avance.com` →
  ese mismo día: cambiar clave + 2FA → cuentas Apple org (D-U-N-S 759379947, razón social
  exacta, pedir Unlisted) + Google Play org (US$25) + cuenta Expo. Observaciones de Jorge
  (abogado) → corregir política → encargo web fase 2 (/privacidad + /eliminar-cuenta).
  Su opinión legal = gate del envío a Apple. Verificar URLs de fase 1 al publicarse.
- Fases técnicas siguientes (tras el diseño): F4 pantallas (aprobación visual de Miguel
  una por una) → F5/F6 seguridad + BFF (necesitan cuentas) → build/assets/compliance →
  TestFlight/closed testing → envío (Google primero, Apple después con la opinión legal).
- Push nativo (expo-notifications + tokens) llega con los development builds.
- Ícono/splash: siguen los de la plantilla; falta el logo real de AVANCE CORP en `assets/images/`.
- Regla permanente: `public_html/` (portal) NO se toca; ningún gasto sin confirmación de Miguel.

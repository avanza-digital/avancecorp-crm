# Stack React Native recomendado — CRM Avance Corp S.A.C.

Informe técnico crudo (subagente de stack). Fuentes: documentación actual vía Context7 (julio 2026), repo GitHub `avanzadigitald/cliente-belysh-app` (leído vía gh CLI, solo lectura), y repo VITANOVA en `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/CLINICA-ALVAREZ-desktop/crm-vitanova-vite/` (solo lectura).

## 1. Resumen ejecutivo

Stack recomendado: **Expo SDK 57 (RN 0.86.0, React 19.2.3) + expo-router, app UNIVERSAL (iOS/Android + web vía react-native-web) con NativeWind v5 (Tailwind v4) + react-native-reusables como librería de componentes, supabase-js con AsyncStorage, Victory Native XL (Skia) para charts, FlashList v2 para listas, expo-notifications para push, expo-print para PDF móvil, expo-linking para wa.me/tel:, EAS Build + EAS Update para distribución.**

Razón dominante: es casi exactamente el stack que el equipo YA opera en producción con la app Belysh (mismo owner EAS `avancecorp`), y el modelo mental de UI (shadcn: tokens CSS + cva + clsx + tailwind-merge) es el mismo que VITANOVA usa en web, lo que maximiza la transferencia del esqueleto arquitectónico.

## 2. Stack que el equipo ya domina (evidencia: repo belysh)

`avanzadigitald/cliente-belysh-app` (actualizado 2026-07-03, `app.json` → `"owner": "avancecorp"`, EAS projectId propio). Su `package.json` (raíz del repo):

- `expo ^57.0.0` — SDK 57, el actual (Context7/docs.expo.dev confirma SDK 57 = react-native 0.86.0 + react 19.2.3 en el diff de upgrade 56→57).
- `expo-router ~57.0.3` con `"main": "expo-router/entry"`, `typedRoutes: true` y `reactCompiler: true` en `app.json`.
- `@supabase/supabase-js ^2.110.0` + `@react-native-async-storage/async-storage 2.2.0` + `react-native-url-polyfill ^3.0.0`.
- `react-native-web ~0.21.0` + `react-dom` + script `"web": "expo start --web"` + bloque `"web": { "output": "single" }` — **el equipo ya compila target web desde Expo**.
- `react-native-reanimated 4.5.0`, `react-native-worklets 0.10.0`, `react-native-gesture-handler ~2.32.0`, `react-native-screens 4.25.2`, `react-native-safe-area-context ~5.7.0`, `react-native-svg 15.15.4`.
- `@expo-google-fonts/cormorant-garamond` / `@expo-google-fonts/mulish` + `expo-font` — ya conocen el patrón de fuentes Google en Expo.
- `expo-linking ~57.0.1` — ya usan deep links.
- Testing: `jest-expo ~57.0.1` + `@testing-library/react-native ^14.0.1`; TypeScript `~6.0.3`; `eslint-config-expo`.
- `eas.json`: EAS CLI `>= 16.0.0`, `appVersionSource: remote`, perfiles `development`/`preview`/`production` con canales `preview`/`production` y `autoIncrement` — plantilla lista para copiar.
- Cliente Supabase del equipo (`src/belysh/api/supabase.ts` del repo belysh), transcripción textual:

```ts
export const supabase = createClient<Database>(SUPABASE_URL, SUPABASE_KEY, {
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
    flowType: 'pkce', // necesario para OAuth (Google) en móvil
  },
});
```

Esto coincide con el patrón oficial actual de Supabase para Expo (Context7 `/websites/supabase`, quickstart React Native), que además recomienda `lock: processLock`, condicionar `storage` a `Platform.OS !== 'web'` (en web usa localStorage por defecto — clave para la app universal) y el listener de `AppState` con `startAutoRefresh()/stopAutoRefresh()`.

Lo ÚNICO nuevo para el equipo respecto a belysh: NativeWind, react-native-reusables, victory-native, FlashList, expo-notifications, expo-print. Todo lo demás es repetición de stack conocido.

## 3. Decisión: ¿RN pura o Expo + react-native-web (universal)?

**Recomendación: UNIVERSAL (Expo + react-native-web), una sola base de código con tres targets: Android, iOS y web estático.**

Sustento:
1. **Usuarios**: vendedores/supervisores en campo → app nativa móvil (push, arranque rápido, wa.me/tel: nativos). Gerencia/directorio → escritorio; con `react-native-web` la MISMA app corre en navegador sin segundo frontend. Mantener dos frontends (RN + web separado) duplicaría cada módulo del CRM.
2. **El equipo ya lo hace**: belysh incluye `react-native-web ~0.21.0` y config web en `app.json`. Cero curva nueva.
3. **Toda la cadena elegida es universal**: expo-router soporta web (output `single`/`static`); NativeWind v5 es explícitamente multiplataforma ("consistent styling across all platforms", docs nativewind.dev/v5); react-native-reusables se define como "universal component library" y trae utilidades específicas para web (p. ej. `NativeOnlyAnimatedView` en `packages/registry/src/nativewind/components/ui/native-only-animated-view.tsx`, que en `Platform.OS === 'web'` omite animaciones Reanimated); Skia corre en web vía CanvasKit WASM (docs shopify.github.io/react-native-skia/docs/getting-started/web: `LoadSkiaWeb()` en `index.web.tsx` con `expo-router/build/qualified-entry`, o script `setup-skia-web` en postinstall).
4. **Despliegue web**: el bundle web estático se puede subir al mismo Hostinger que hoy sirve el portal (método MCP ya documentado en la memoria del proyecto) o a EAS Hosting.

Caveats del target web (asumidos y manejables):
- Charts Skia en web cargan ~canvaskit.wasm (unos MB) asíncrono — aceptable para dashboard de gerencia; configurar `LoadSkiaWeb` solo en `index.web.tsx`.
- `expo-print` en web NO convierte el HTML dado a PDF (imprime la página actual, docs expo-print) → los PDF formales (contratos AeP, estados de cuenta) deben generarse server-side en una Supabase Edge Function con plantilla HTML; `expo-print` queda para comprobantes ad-hoc en móvil.
- Push web: `expo-notifications` es nativo; para web reutilizar la infraestructura Web Push que Avance ya tiene en el portal (`_supabase_functions/functions/notificar-pagos`, `diagnostico-push`) si se necesitara.

## 4. Stack detallado por capa (versiones a julio 2026)

| Capa | Librería / versión | Notas de docs actuales |
|---|---|---|
| Framework | `expo ~57.0.0` (RN 0.86.0, React 19.2.3) | SDK actual; belysh ya está en 57 |
| Navegación | `expo-router ~57.0.3` | Versiona con el SDK; file-based, typed routes; grupos de rutas por rol (`(vendedor)/`, `(gerencia)/`) mapean la jerarquía de 4 niveles |
| Backend client | `@supabase/supabase-js ^2.110.0` + `@react-native-async-storage/async-storage 2.2.0` + `react-native-url-polyfill ^3.0.0` | Patrón oficial: `storage: AsyncStorage` solo si `Platform.OS !== 'web'`, `detectSessionInUrl: false`, `lock: processLock`, `flowType: 'pkce'`, AppState → start/stopAutoRefresh. Realtime funciona igual que en web (websocket) |
| Secretos | `expo-secure-store ~57.x` | Opcional: guardar clave de cifrado de sesión (adapter aes-js) si auditoría lo exige; AsyncStorage basta para MVP (es lo que belysh usa en prod) |
| Estilos | `nativewind` v5 + `tailwindcss` v4 (`npx expo install --dev tailwindcss @tailwindcss/postcss postcss`) | v5 usa directiva `@theme` en CSS (ya no `tailwind.config.js`) — EXACTAMENTE el sistema de tokens que VITANOVA-vite ya usa con Tailwind `^4.3.1`. Tema: `@theme { --color-primary: #111e3d; --color-accent: #2563eb; }`, tema claro fijo (sin `dark:`). Si v5 aún estuviera en RC al kickoff, plan B: NativeWind 4.2 + Tailwind 3 |
| Componentes UI | **react-native-reusables** (CLI `rnr add`, componentes copiados al repo) + `@rn-primitives/*` | RECOMENDADA sobre Tamagui/gluestack. Justificación: (a) es shadcn/ui para RN — mismo ADN que VITANOVA (radix→rn-primitives, cva, clsx, tailwind-merge, tokens CSS), la migración de cada componente web es 1:1 conceptual; (b) código copiado = ownership total para imponer navy/blanco sin pelear con un theme-engine; (c) universal (web incluido); (d) 30 componentes cubren el CRM: button, card, dialog, alert-dialog, dropdown-menu, input, select, tabs, badge, checkbox, radio-group, switch, skeleton, tooltip, progress, etc. Tamagui se descarta (sistema de estilos propio, curva alta, beneficios de perf irrelevantes para un CRM de formularios); gluestack-ui v3 es plan B válido (también NativeWind) pero con menor paridad shadcn |
| Utilidades UI | `class-variance-authority ^0.7.1`, `clsx ^2.1.1`, `tailwind-merge ^3.6.0` | JS puro; VITANOVA ya las usa (su `package.json`); transfieren sin cambios |
| Charts | `victory-native` (XL, ~v41) + `@shopify/react-native-skia` | Peer deps: reanimated + gesture-handler + skia (belysh ya tiene las dos primeras). `CartesianChart` + `Bar`/`Line` (+ `Pie`) con animación Reanimated; fuentes de ejes vía `useFont` de Skia. Sustituye a recharts. En web: CanvasKit WASM (`LoadSkiaWeb`) |
| Listas | `@shopify/flash-list` v2 (~2.3.1) | Para los ~5,000 clientes. v2: drop-in de FlatList, SIN `estimatedItemSize`, REQUIERE New Architecture (lanza error en old arch — SDK 57 ya es new-arch por defecto, sin riesgo) |
| Push | `expo-notifications ~57.x` | `getExpoPushTokenAsync({ projectId })` (projectId EAS de `Constants.expoConfig.extra.eas.projectId`), canal Android obligatorio (`setNotificationChannelAsync`), `setNotificationHandler`, listeners received/response, `addPushTokenListener` para re-sync del token. Envío desde Supabase Edge Functions al Expo Push Service — encaja con las edge functions de notificación que Avance ya opera (`notificar-pagos`, `diagnostico-push`) |
| PDF | `expo-print ~57.x` + `expo-sharing` | `Print.printToFileAsync({ html })` → URI → `shareAsync(uri, { UTI: '.pdf', mimeType: 'application/pdf' })`. Solo móvil; documentos formales → edge function |
| Deep links | `expo-linking ~57.0.1` | `Linking.openURL(waLink(...))` y `Linking.openURL('tel:...')`; belysh ya lo incluye |
| Fuentes | `@expo-google-fonts/plus-jakarta-sans` + `expo-font` | Mismo patrón que belysh (cormorant/mulish); en NativeWind se registra como fontFamily del `@theme` |
| Íconos | `lucide-react-native` (+ `react-native-svg 15.15.4`) | Mismos nombres de íconos que `lucide-react ^1.20.0` de VITANOVA — búsqueda/reemplazo del import |
| Toasts | `sonner-native` | Port RN de sonner (VITANOVA usa `sonner ^2.0.7` para el patrón notify() del store) |
| Fechas | `date-fns ^4.4.0` (transfiere) + `@react-native-community/datetimepicker` | `react-day-picker` de VITANOVA es DOM-only |
| Animación | `react-native-reanimated 4.5.0` + `react-native-worklets 0.10.0` + `react-native-gesture-handler ~2.32.0` | Peer deps de router-drawer, charts y reusables; belysh ya las tiene |
| Build/OTA | EAS Build + EAS Update (eas-cli >= 16) | Copiar `eas.json` de belysh: canales `preview`/`production`, `runtimeVersion: { policy: 'appVersion' }`, `autoIncrement`. OTA para iterar el CRM sin re-publicar en tiendas |
| Testing | `jest-expo ~57.0.1` + `@testing-library/react-native ^14` | Ya en uso en belysh |

## 5. Compatibilidad de patrones VITANOVA con RN (citas)

Base VITANOVA: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/CLINICA-ALVAREZ-desktop/crm-vitanova-vite/`

1. **Store `useSyncExternalStore` — TRANSFIERE.** `src/lib/store.ts:11` importa `useSyncExternalStore`; `src/lib/store.ts:139-186` implementa pub/sub + snapshot estable (`subscribe` en :172, `getSnapshot` en :182, `useStore()` en :185-186: `return useSyncExternalStore(subscribe, getSnapshot, getSnapshot)`). Es API de React 19 sin dependencia del DOM — funciona idéntico en RN 0.86/React 19.2. El export agregado (store.ts:2148: `subscribe, notifyAll, suscribirRealtime, getSnapshot, ...`) y el patrón realtime (`.subscribe()` en store.ts:730, cleanup del canal auth en :254) también corren en RN tal cual (supabase realtime es websocket).
2. **wa.me — lógica TRANSFIERE, apertura ADAPTA.** `src/lib/store.ts:668-673`, transcripción textual:
```ts
function waLink(telefono: string | number | null | undefined, texto?: string): string {
  let d = String(telefono == null ? '' : telefono).replace(/[^0-9]/g, '')
  if (d.indexOf('51') !== 0 && d.length === 9) d = '51' + d
  const base = 'https://wa.me/' + d
  return texto ? base + '?text=' + encodeURIComponent(texto) : base
}
```
Lógica pura de strings con prefijo Perú +51 — se copia sin cambios. Lo que cambia es la apertura: `src/components/gestion/gestion-provider.tsx:34` usa `window.open(store.waLink(a.telefono, a.mensaje), '_blank', 'noopener')` y `:36` usa `window.location.href = 'tel:' + a.telefono` → en RN ambos pasan a `Linking.openURL(...)` (en el target web de la app universal, `Linking.openURL` de react-native-web hace window.open — no hace falta bifurcar). El patrón "abrir deep link → preguntar '¿Lograste contacto?'" (gestion-provider.tsx:2) transfiere; nota: en móvil el retorno a la app tras WhatsApp dispara `AppState` 'active', que puede usarse para mostrar el prompt. `plantillaBucket` (store.ts:675-687, placeholders `{nombre}`/`{clinica}`) transfiere adaptando textos al dominio inversiones. La normalización de teléfono también está en `src/components/ficha/ficha-provider.tsx:289`.
3. **Fuente — ADAPTA.** VITANOVA usa Figtree por CDN (`index.html:9`: `fonts.googleapis.com/css2?family=Figtree...`; `src/index.css:112`: `--font-sans: 'Figtree', ...`). El destino manda Plus Jakarta Sans → `@expo-google-fonts/plus-jakarta-sans` empaquetada en el binario (sin CDN, funciona offline en campo); mismo patrón que belysh ya usa con expo-font.
4. **Tema — ADAPTA (mismo sistema de tokens, otros valores).** `src/index.css:8`: `--brand: #9c1a84; /* magenta médico (default) */` con `--primary: var(--brand)` (:29) y `--ring: var(--brand)` (:44), tokens estilo shadcn (`--color-primary: var(--primary)` etc., :118-129). En NativeWind v5 el mismo sistema se declara con `@theme { --color-primary: #111e3d; --color-accent: #2563eb; --color-background: #ffffff; }` — tema claro único (se descarta `next-themes` y el bloque dark de index.css:78-104; prohibido verde).
5. **Cliente Supabase — ADAPTA.** `src/lib/supabase.ts:7`: `export const sb = createClient(CONFIG.SUPABASE_URL, CONFIG.SUPABASE_ANON_KEY)` sin opciones (localStorage implícito, web-only) → en RN requiere el bloque de auth con AsyncStorage/pkce/AppState (sección 2; belysh ya lo tiene resuelto en producción).
6. **UI Radix/Tailwind-CSS del web — NO transfiere como código.** `crm-vitanova-vite/package.json`: `radix-ui ^1.6.0`, `recharts ^3.8.0`, `cmdk`, `react-day-picker`, `next-themes`, `tw-animate-css` son DOM-only → se DESCARTAN y sus roles los cubren react-native-reusables (+@rn-primitives), victory-native, y datetimepicker RN. En cambio `class-variance-authority`, `clsx`, `tailwind-merge`, `date-fns` son JS puro y TRANSFIEREN.

## 6. Riesgos y decisiones abiertas

- **NativeWind v5**: las docs actuales (nativewind.dev/v5) la presentan como la línea activa con Tailwind v4 y scaffold oficial (`npx rn-new@next --nativewind`), pero verificar en el kickoff si ya salió de pre-release; plan B sin impacto arquitectónico: NativeWind 4.2 + Tailwind 3 (tokens en `tailwind.config.js` en vez de `@theme`).
- **FlashList v2 exige New Architecture**: no usar librerías legacy que fuercen old-arch (SDK 57 es new-arch por defecto; belysh corre así con reactCompiler activado).
- **PDF formales (contratos AeP)**: `expo-print` es best-effort por plataforma; para documentos con validez uniforme generar el PDF en Supabase Edge Function y entregarlo por Storage/URL firmada (patrón que el equipo ya conoce por las edge functions del portal).
- **Charts en web**: requiere `index.web.tsx` con `LoadSkiaWeb` + `canvaskit-wasm` versionado (docs de Skia muestran integración exacta con expo-router `qualified-entry`); si se quisiera evitar WASM, alternativa sólo-web sería renderizar los dashboards con víctory en native y tablas en web, pero no se recomienda bifurcar.
- **iOS**: los vendedores en Perú son mayoritariamente Android; iOS vía EAS `preview` (internal) puede bastar al inicio; cuenta Apple Developer necesaria para producción/push iOS.

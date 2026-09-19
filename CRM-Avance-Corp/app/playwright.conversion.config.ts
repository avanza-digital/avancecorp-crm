import {defineConfig,devices} from '@playwright/test'
import {execFileSync} from 'node:child_process'
import assert from 'node:assert/strict'

// Exclusivamente contra los servicios locales creados por http-banco.mjs.
const contenedor=JSON.parse(execFileSync('docker',['inspect','conversion_inversion_20260918_storage'],{encoding:'utf8'}))[0]
assert.equal(contenedor.Config.Labels['avancecorp.ensayo'],'conversion_inversion_20260918')
const anon=contenedor.Config.Env.find((x:string)=>x.startsWith('ANON_KEY=')).slice('ANON_KEY='.length)
export default defineConfig({
  testDir:'./e2e-integration',testMatch:'conversion-inversion.spec.ts',workers:1,timeout:90_000,
  reporter:'list',outputDir:'/private/tmp/avancecorp-conversion-inversion/playwright',
  use:{baseURL:'http://127.0.0.1:5299',trace:'retain-on-failure',screenshot:'only-on-failure'},
  projects:[{name:'conversion-local',use:{...devices['Desktop Chrome']}}],
  webServer:{command:'npm run dev -- --port 5299 --host 127.0.0.1',url:'http://127.0.0.1:5299',reuseExistingServer:false,
    env:{VITE_ENABLE_DEMO:'false',VITE_SUPABASE_URL:'http://127.0.0.1:59321',VITE_SUPABASE_ANON_KEY:anon}},
})

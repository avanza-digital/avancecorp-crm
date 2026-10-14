const {defineConfig} = require('../../../app/node_modules/@playwright/test')
module.exports = defineConfig({
  testDir: __dirname, testMatch: 'portal.spec.cjs', workers: 1, retries: 0,
  outputDir: '../../../app/test-results/atencion-portal', reporter: 'list',
  use: {browserName: 'chromium', serviceWorkers: 'block'},
})

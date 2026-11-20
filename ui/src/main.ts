import './Tailwind.css'

import { initLocale } from './utils/i18n'

const app = initLocale().then(async()=>{const {default:App}=await import('./App.svelte');return new App({
    target: document.getElementById('app')
  })})

export default app

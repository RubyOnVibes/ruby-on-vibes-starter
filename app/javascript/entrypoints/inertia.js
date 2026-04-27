import { createInertiaApp } from '@inertiajs/react'
import { createElement } from 'react'
import { createRoot, hydrateRoot } from 'react-dom/client'
import InertiaLayout from '../layouts/InertiaLayout'

createInertiaApp({
  // Set default page title
  // see https://inertia-rails.dev/guide/title-and-meta
  //
  // title: title => title ? `${title} - App` : 'App',

  // Disable progress bar
  //
  // see https://inertia-rails.dev/guide/progress-indicators
  // progress: false,

  resolve: (name) => {
    const jsxPages = import.meta.glob('../pages/**/*.jsx', { eager: true })
    const tsxPages = import.meta.glob('../pages/**/*.tsx', { eager: true })

    const page = jsxPages[`../pages/${name}.jsx`] || tsxPages[`../pages/${name}.tsx`]
    if (!page) {
      console.error(`Missing Inertia page component: '${name}.jsx' or '${name}.tsx'`)
    }

    // Use default layout that includes ToasterProvider
    // see https://inertia-rails.dev/guide/pages#default-layouts
    page.default.layout ||= (page) => createElement(InertiaLayout, null, page)

    return page
  },

  setup({ el, App, props }) {
    if (el) {
      const tree = createElement(App, props)
      const hasSSRMarkup = el.firstElementChild != null
      if (hasSSRMarkup) hydrateRoot(el, tree)
      else createRoot(el).render(tree)
    } else {
      console.error(
        'Missing root element.\n\n' +
          'If you see this error, it probably means you load Inertia.js on non-Inertia pages.\n' +
          'Consider moving <%= vite_javascript_tag "inertia" %> to the Inertia-specific layout instead.',
      )
    }
  },
})

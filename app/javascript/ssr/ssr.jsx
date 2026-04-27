import React from 'react'
import { createElement } from 'react'
import { createInertiaApp } from '@inertiajs/react'
import createServer from '@inertiajs/react/server'
import ReactDOMServer from 'react-dom/server'
import InertiaLayout from '../layouts/InertiaLayout'

createServer((page) =>
  createInertiaApp({
    page,
    render: ReactDOMServer.renderToString,
    resolve: (name) => {
      const jsxPages = import.meta.glob('../pages/**/*.jsx', { eager: true })
      const tsxPages = import.meta.glob('../pages/**/*.tsx', { eager: true })

      const found = jsxPages[`../pages/${name}.jsx`] || tsxPages[`../pages/${name}.tsx`]

      if (!found) {
        console.error(`Missing Inertia page component: '${name}.jsx' or '${name}.tsx'`)
      }

      // Apply the same default layout on the server as in the browser
      if (found && found.default) {
        const mod = found
        mod.default.layout ||= (pageNode) =>
          createElement(InertiaLayout, null, pageNode)
        return mod
      }

      return found
    },
    setup: ({ App, props }) => <App {...props} />,
  }),
)

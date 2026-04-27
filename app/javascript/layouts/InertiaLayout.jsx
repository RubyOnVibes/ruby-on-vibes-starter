import React from 'react';
import ToasterProvider from '../pages/components/ToasterProvider';

/**
 * InertiaLayout - Default layout for Inertia pages
 *
 * Wraps all Inertia pages with the ToasterProvider to enable
 * automatic flash message display and manual toast calls.
 *
 * This layout is automatically applied to all Inertia pages
 * unless they specify their own layout.
 */
export default function InertiaLayout({ children }) {
  return (
    <>
      <ToasterProvider />
      {children}
    </>
  );
}

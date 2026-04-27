import React, { useEffect, useState } from 'react';
import { Toaster, toast } from 'sonner';
import { usePage } from '@inertiajs/react';

/**
 * ToasterProvider - Provides toast notifications for Inertia pages
 *
 * Automatically displays flash messages from Inertia and provides
 * the Sonner Toaster component with proper theme support.
 *
 * NOTE: This component uses @inertiajs/react and is Inertia-only.
 * For ERB pages, use ToastIsland instead.
 *
 * Usage in Inertia layout:
 *   import ToasterProvider from './ToasterProvider';
 *   <ToasterProvider />
 */
export default function ToasterProvider() {
  const [isClient, setIsClient] = useState(false);
  const { props } = usePage();
  const flash = props.flash;

  // Only render Toaster on client side (after hydration)
  useEffect(() => {
    setIsClient(true);
  }, []);

  // Display flash messages AFTER Toaster is mounted
  useEffect(() => {
    if (!isClient || !flash) return;

    // Small delay to ensure Toaster DOM is ready
    const timer = setTimeout(() => {
      Object.entries(flash).forEach(([type, message]) => {
        const messages = Array.isArray(message) ? message : [message];

        messages.forEach((msg) => {
          if (!msg) return;

          // Map Rails flash types to toast types
          switch (type) {
            case 'success':
              toast.success(msg, { duration: 5000 });
              break;
            case 'error':
              toast.error(msg, { duration: 7000 });
              break;
            case 'alert':
            case 'warning':
              toast.warning(msg, { duration: 6000 });
              break;
            case 'notice':
            case 'info':
            default:
              toast.info(msg, { duration: 5000 });
              break;
          }
        });
      });
    }, 100);

    return () => clearTimeout(timer);
  }, [isClient, flash]);

  // Don't render Toaster during SSR to avoid hydration mismatch
  if (!isClient) {
    return null;
  }

  return (
    <Toaster
      position="bottom-right"
      expand={false}
      richColors
      closeButton
      toastOptions={{
        style: {
          background: 'var(--color-surface-1)',
          border: '1px solid var(--color-border)',
          color: 'var(--color-foreground)',
        },
      }}
    />
  );
}

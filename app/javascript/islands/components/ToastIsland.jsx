import React, { useEffect, useState } from 'react';
import { toast, Toaster } from 'sonner';
import { useTurboProps } from '../utils/turbo';

/**
 * ToastIsland - A React toast component for islandjs-rails
 *
 * Displays Rails flash messages as toasts using Sonner.
 * Works with Turbo navigation and flash messages.
 *
 * Usage in ERB:
 *   <%= react_component('ToastIsland', { flash: flash.to_hash }) %>
 */
function ToastIsland({ containerId }) {
  const initialProps = useTurboProps(containerId);
  const [processedFlash, setProcessedFlash] = useState(new Set());

  // Display flash messages
  useEffect(() => {
    if (!initialProps.flash) return;

    Object.entries(initialProps.flash).forEach(([type, message]) => {
      const messages = Array.isArray(message) ? message : [message];

      messages.forEach((msg) => {
        if (!msg) return; // Skip empty messages

        const flashId = `${type}-${msg}`;

        // Skip if already shown
        if (processedFlash.has(flashId)) return;

        // Mark as processed
        setProcessedFlash(prev => new Set(prev).add(flashId));

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
  }, [initialProps.flash, processedFlash]);

  // Listen for Turbo navigation to clear processed flash
  useEffect(() => {
    const handleTurboRender = () => {
      // Reset processed flash on navigation
      setProcessedFlash(new Set());
    };

    document.addEventListener('turbo:render', handleTurboRender);
    return () => document.removeEventListener('turbo:render', handleTurboRender);
  }, []);

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

export default ToastIsland;

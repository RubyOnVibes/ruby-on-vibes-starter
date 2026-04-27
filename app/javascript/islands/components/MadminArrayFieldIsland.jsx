import React, { useState, useEffect, useRef } from 'react';
import { useTurboProps, useTurboCache } from '../utils/turbo';

function MadminArrayFieldIsland({ containerId }) {
  const initialProps = useTurboProps(containerId);

  const [items, setItems] = useState(initialProps.items || []);
  const [newItem, setNewItem] = useState('');
  const [draggedIndex, setDraggedIndex] = useState(null);
  const inputRef = useRef(null);

  // Read fieldName and placeholder from DOM data attributes (not cached state)
  const [fieldName, setFieldName] = useState('items[]');
  const [placeholder, setPlaceholder] = useState('Enter value...');

  useEffect(() => {
    const container = document.getElementById(containerId);
    if (container) {
      const fieldNameAttr = container.getAttribute('data-field-name');
      const placeholderAttr = container.getAttribute('data-placeholder');
      if (fieldNameAttr) setFieldName(fieldNameAttr);
      if (placeholderAttr) setPlaceholder(placeholderAttr);
    }
  }, [containerId]);

  // Setup turbo cache persistence
  useEffect(() => {
    const cleanup = useTurboCache(containerId, { items }, true);
    return cleanup;
  }, [containerId, items]);

  const handleAdd = () => {
    if (newItem.trim()) {
      setItems([...items, newItem.trim()]);
      setNewItem('');
      inputRef.current?.focus();
    }
  };

  const handleRemove = (index) => {
    setItems(items.filter((_, i) => i !== index));
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      handleAdd();
    }
  };

  const handleDragStart = (index) => {
    setDraggedIndex(index);
  };

  const handleDragOver = (e, index) => {
    e.preventDefault();

    if (draggedIndex === null || draggedIndex === index) return;

    const newItems = [...items];
    const draggedItem = newItems[draggedIndex];

    // Remove from old position
    newItems.splice(draggedIndex, 1);
    // Insert at new position
    newItems.splice(index, 0, draggedItem);

    setItems(newItems);
    setDraggedIndex(index);
  };

  const handleDragEnd = () => {
    setDraggedIndex(null);
  };

  return (
    <div style={{
      fontFamily: 'system-ui, -apple-system, sans-serif',
      width: '100%'
    }}>
      {/* Items list with actual input fields that Rails can serialize */}
      <div style={{ marginBottom: '12px' }}>
        {items.length === 0 ? (
          <div style={{
            padding: '16px',
            textAlign: 'center',
            color: 'var(--color-muted-foreground)',
            fontSize: '14px',
            fontStyle: 'italic',
            backgroundColor: 'var(--color-surface-1)',
            borderRadius: '6px',
            border: '1px dashed var(--color-border)'
          }}>
            No items yet. Add your first item below.
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
            {items.map((item, index) => (
              <div
                key={index}
                draggable
                onDragStart={() => handleDragStart(index)}
                onDragOver={(e) => handleDragOver(e, index)}
                onDragEnd={handleDragEnd}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px',
                  padding: '10px 12px',
                  backgroundColor: draggedIndex === index ? 'color-mix(in srgb, var(--color-primary) 10%, transparent)' : 'var(--color-background)',
                  border: '1px solid var(--color-border)',
                  borderRadius: '6px',
                  cursor: 'grab',
                  transition: 'all 0.2s',
                  boxShadow: draggedIndex === index ? '0 4px 12px rgba(0,0,0,0.1)' : 'none'
                }}
              >
                <div style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  width: '20px',
                  height: '20px',
                  color: 'var(--color-muted-foreground)',
                  cursor: 'grab',
                  fontSize: '16px'
                }}>
                  ⋮⋮
                </div>

                {/* Actual hidden input that Rails will serialize */}
                <input
                  type="hidden"
                  name={fieldName}
                  value={item}
                />

                <div style={{
                  flex: 1,
                  fontSize: '14px',
                  color: 'var(--color-foreground)',
                  userSelect: 'none'
                }}>
                  {item}
                </div>

                <button
                  type="button"
                  onClick={() => handleRemove(index)}
                  style={{
                    padding: '4px 10px',
                    backgroundColor: 'color-mix(in srgb, var(--color-destructive) 10%, transparent)',
                    color: 'var(--color-destructive)',
                    border: '1px solid color-mix(in srgb, var(--color-destructive) 20%, transparent)',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontSize: '12px',
                    fontWeight: '500',
                    transition: 'all 0.2s'
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.backgroundColor = 'color-mix(in srgb, var(--color-destructive) 20%, transparent)';
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.backgroundColor = 'color-mix(in srgb, var(--color-destructive) 10%, transparent)';
                  }}
                >
                  Remove
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Add new item */}
      <div style={{
        display: 'flex',
        gap: '8px',
        padding: '12px',
        backgroundColor: 'var(--color-surface-1)',
        borderRadius: '6px',
        border: '1px solid var(--color-border)'
      }}>
        <input
          ref={inputRef}
          type="text"
          value={newItem}
          onChange={(e) => setNewItem(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={placeholder}
          style={{
            flex: 1,
            padding: '8px 12px',
            border: '1px solid var(--color-input)',
            borderRadius: '6px',
            fontSize: '14px',
            outline: 'none',
            transition: 'border-color 0.2s',
            backgroundColor: 'var(--color-background)',
            color: 'var(--color-foreground)'
          }}
          onFocus={(e) => {
            e.currentTarget.style.borderColor = 'var(--color-primary)';
          }}
          onBlur={(e) => {
            e.currentTarget.style.borderColor = 'var(--color-input)';
          }}
        />
        <button
          type="button"
          onClick={handleAdd}
          style={{
            padding: '8px 16px',
            backgroundColor: 'var(--color-primary)',
            color: 'var(--color-primary-foreground)',
            border: 'none',
            borderRadius: '6px',
            cursor: 'pointer',
            fontSize: '14px',
            fontWeight: '500',
            transition: 'all 0.2s',
            whiteSpace: 'nowrap'
          }}
          onMouseEnter={(e) => {
            e.currentTarget.style.opacity = '0.9';
            e.currentTarget.style.transform = 'translateY(-1px)';
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.opacity = '1';
            e.currentTarget.style.transform = 'translateY(0)';
          }}
        >
          + Add
        </button>
      </div>

      {items.length > 0 && (
        <div style={{
          marginTop: '8px',
          fontSize: '12px',
          color: 'var(--color-muted-foreground)',
          fontStyle: 'italic'
        }}>
          💡 Drag items to reorder
        </div>
      )}
    </div>
  );
}

export default MadminArrayFieldIsland;
